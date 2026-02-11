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
$MaxEventsPerPoll = $config.max_events_per_poll
$HistoricalDays = if ($config.historical_days) { $config.historical_days } else { 7 }
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

# Initialize last check times
if ($HistoricalDays -eq 0) {
    # Start from now - only capture new events
    foreach ($logName in $script:LogNamesArray) {
        $script:LastCheckTime[$logName.Trim()] = Get-Date
    }
    Write-Host "Skipping historical events - monitoring new events only" -ForegroundColor Yellow
    Write-Host ""
} else {
    # Start from X days ago to capture historical events
    $startTime = (Get-Date).AddDays(-$HistoricalDays)
    foreach ($logName in $script:LogNamesArray) {
        $script:LastCheckTime[$logName.Trim()] = $startTime
    }
    Write-Host "Importing historical events from last $HistoricalDays days..." -ForegroundColor Yellow
    Write-Host "This may take a moment..." -ForegroundColor Gray
    Write-Host ""
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
        $filterHashtable = @{
            LogName = $LogName
            StartTime = $lastCheck
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

# Main loop
Write-Host "Starting monitoring...`n" -ForegroundColor Green
Write-Host "Press Ctrl+C to stop`n" -ForegroundColor Yellow

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

