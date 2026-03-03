<#
.SYNOPSIS
    Windows Event Monitor with JSON configuration support.

.DESCRIPTION
    Reads configuration from monitor_config.json and monitors Windows Event Logs.

.PARAMETER ConfigFile
    Path to the JSON configuration file (default: monitor_config.json)

.EXAMPLE
    .\event_monitor_config.ps1

.EXAMPLE
    .\event_monitor_config.ps1 -ConfigFile "custom_config.json"
#>

param(
    [string]$ConfigFile = "$PSScriptRoot\monitor_config.json"
)

# Load configuration
if (-not (Test-Path $ConfigFile)) {
    Write-Host "Configuration file not found: $ConfigFile" -ForegroundColor Red
    Write-Host "Creating default configuration..." -ForegroundColor Yellow
    
    $defaultConfig = @{
        api_url = "http://localhost:5000"
        poll_interval_seconds = 10
        max_events_per_poll = 50
        log_names = @("System", "Application")
        event_ids_to_monitor = @()
        description = "Configuration for Windows Event Monitor"
    }
    
    $defaultConfig | ConvertTo-Json -Depth 10 | Out-File $ConfigFile -Encoding UTF8
    Write-Host "Default configuration created at: $ConfigFile" -ForegroundColor Green
}

try {
    $config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
}
catch {
    Write-Host "Failed to parse configuration file: $_" -ForegroundColor Red
    exit 1
}

# Extract configuration
$ApiUrl = $config.api_url
$PollIntervalSeconds = $config.poll_interval_seconds
$MaxEventsPerPoll = if ($config.max_events_per_poll) { $config.max_events_per_poll } else { 100 }
$HistoricalDays = if ($config.historical_days) { $config.historical_days } else { 30 }
$MaxHistoricalEvents = if ($config.max_historical_events) { $config.max_historical_events } else { 10000 }
$LogNames = $config.log_names -join ','
$EventIds = if ($config.event_ids_to_monitor -and $config.event_ids_to_monitor.Count -gt 0) {
    $config.event_ids_to_monitor -join ','
} else {
    ""
}

# Configuration
$script:ApiEndpoint = "$ApiUrl/api/events"
$script:LogNamesArray = $LogNames -split ','
$script:EventIdsArray = if ($EventIds) { ($EventIds -split ',') | ForEach-Object { [int]$_ } } else { @() }
$script:LastCheckTime = @{}
$script:ProcessedEvents = @{}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Windows Event Monitor - Config Mode" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Config File: $ConfigFile" -ForegroundColor Green
Write-Host "API Endpoint: $script:ApiEndpoint" -ForegroundColor Green
Write-Host "Monitoring Logs: $LogNames" -ForegroundColor Green
Write-Host "Poll Interval: $PollIntervalSeconds seconds" -ForegroundColor Green
Write-Host "Max Events/Poll: $MaxEventsPerPoll" -ForegroundColor Green
if ($script:EventIdsArray.Count -gt 0) {
    Write-Host "Filtering Event IDs: $($script:EventIdsArray.Count) IDs" -ForegroundColor Green
} else {
    Write-Host "Monitoring: ALL event IDs" -ForegroundColor Yellow
}
if ($HistoricalDays -gt 0) {
    Write-Host "Historical Import: Last $HistoricalDays days" -ForegroundColor Green
}
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Initialize last check times to now (we'll do historical import separately)
foreach ($logName in $script:LogNamesArray) {
    $script:LastCheckTime[$logName.Trim()] = Get-Date
}

# Function to send event to API
function Send-EventToApi {
    param($Event)
    
    try {
        $eventData = @{
            event_id = $Event.Id
            log_name = $Event.LogName
            source = $Event.ProviderName
            message = if ($Event.Message) { $Event.Message } else { "No message available" }
            timestamp = $Event.TimeCreated.ToString("yyyy-MM-ddTHH:mm:ss")
            level = $Event.LevelDisplayName  # Error or Warning
        }
        
        $json = $eventData | ConvertTo-Json -Compress
        $response = Invoke-RestMethod -Uri $script:ApiEndpoint -Method Post -Body $json -ContentType "application/json" -ErrorAction Stop
        
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] " -NoNewline -ForegroundColor Gray
        Write-Host "[OK] " -NoNewline -ForegroundColor Green
        Write-Host "Event $($Event.Id) from $($Event.ProviderName)" -ForegroundColor White
        
        return $true
    }
    catch {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] " -NoNewline -ForegroundColor Gray
        Write-Host "[FAIL] " -NoNewline -ForegroundColor Red
        Write-Host "Failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to check for new events
function Check-LogForNewEvents {
    param([string]$LogName)
    
    $lastCheck = $script:LastCheckTime[$LogName]
    $currentTime = Get-Date
    
    try {
        # Only capture Error (Level 2) and Warning (Level 3) events
        $filterHashtable = @{
            LogName = $LogName
            StartTime = $lastCheck
            Level = @(2, 3)  # 2 = Error, 3 = Warning (Administrative Events)
        }

        if ($script:EventIdsArray.Count -gt 0) {
            $filterHashtable['ID'] = $script:EventIdsArray
        }

        $events = Get-WinEvent -FilterHashtable $filterHashtable -MaxEvents $MaxEventsPerPoll -ErrorAction SilentlyContinue
        
        if ($null -eq $events) {
            return 0
        }
        
        if ($events -isnot [Array]) {
            $events = @($events)
        }
        
        $newEventCount = 0
        [array]::Reverse($events)
        
        foreach ($evt in $events) {
            $eventKey = "$($evt.LogName)-$($evt.RecordId)"
            
            if ($script:ProcessedEvents.ContainsKey($eventKey)) {
                continue
            }
            
            if (Send-EventToApi -Event $evt) {
                $script:ProcessedEvents[$eventKey] = $true
                $newEventCount++
            }
        }
        
        $script:LastCheckTime[$LogName] = $currentTime
        return $newEventCount
    }
    catch {
        if ($_.Exception.Message -notlike "*No events were found*") {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Error: $($_.Exception.Message)" -ForegroundColor Red
        }
        return 0
    }
}

# Function to import historical events
function Import-HistoricalEvents {
    if ($HistoricalDays -eq 0) {
        Write-Host "Skipping historical import - monitoring new events only" -ForegroundColor Yellow
        Write-Host ""
        return
    }

    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "HISTORICAL IMPORT - Last $HistoricalDays days" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    $startTime = (Get-Date).AddDays(-$HistoricalDays)
    $totalImported = 0

    foreach ($logName in $script:LogNamesArray) {
        $logNameTrimmed = $logName.Trim()
        Write-Host "Importing from $logNameTrimmed..." -ForegroundColor Yellow

        try {
            # Only import Error (Level 2) and Warning (Level 3) events
            $filterHashtable = @{
                LogName = $logNameTrimmed
                StartTime = $startTime
                Level = @(2, 3)  # 2 = Error, 3 = Warning (Administrative Events)
            }

            if ($script:EventIdsArray.Count -gt 0) {
                $filterHashtable['ID'] = $script:EventIdsArray
            }

            $events = Get-WinEvent -FilterHashtable $filterHashtable -MaxEvents $MaxHistoricalEvents -ErrorAction SilentlyContinue

            if ($null -eq $events) {
                Write-Host "  No events found in $logNameTrimmed" -ForegroundColor Gray
                continue
            }

            if ($events -isnot [Array]) {
                $events = @($events)
            }

            Write-Host "  Found $($events.Count) events, importing..." -ForegroundColor Cyan

            [array]::Reverse($events)

            $imported = 0
            foreach ($evt in $events) {
                $eventKey = "$($evt.LogName)-$($evt.RecordId)"

                if ($script:ProcessedEvents.ContainsKey($eventKey)) {
                    continue
                }

                if (Send-EventToApi -Event $evt) {
                    $script:ProcessedEvents[$eventKey] = $true
                    $imported++
                    $totalImported++

                    if ($imported % 50 -eq 0) {
                        Write-Host "  Progress: $imported events imported..." -ForegroundColor Gray
                    }
                }
            }

            Write-Host "  [OK] Imported $imported events from $logNameTrimmed" -ForegroundColor Green
        }
        catch {
            if ($_.Exception.Message -notlike "*No events were found*") {
                Write-Host "  [FAIL] Error importing from $logNameTrimmed : $($_.Exception.Message)" -ForegroundColor Red
            } else {
                Write-Host "  No matching events in $logNameTrimmed" -ForegroundColor Gray
            }
        }
    }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "HISTORICAL IMPORT COMPLETE" -ForegroundColor Green
    Write-Host "Total events imported: $totalImported" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

# Import historical events before starting monitoring
Import-HistoricalEvents

# Main loop
Write-Host "Starting real-time monitoring..." -ForegroundColor Green
Write-Host ""
Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow
Write-Host ""

$pollCount = 0

try {
    while ($true) {
        $pollCount++
        $totalNewEvents = 0
        
        foreach ($logName in $script:LogNamesArray) {
            $totalNewEvents += Check-LogForNewEvents -LogName $logName.Trim()
        }
        
        if ($totalNewEvents -eq 0 -and $pollCount % 6 -eq 0) {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ♥ Monitoring active" -ForegroundColor DarkGray
        }
        
        if ($script:ProcessedEvents.Count -gt 1000) {
            $keysToKeep = $script:ProcessedEvents.Keys | Select-Object -Last 500
            $newDict = @{}
            foreach ($key in $keysToKeep) {
                $newDict[$key] = $true
            }
            $script:ProcessedEvents = $newDict
        }
        
        Start-Sleep -Seconds $PollIntervalSeconds
    }
}
finally {
    Write-Host "`n`nMonitoring stopped." -ForegroundColor Yellow
}

