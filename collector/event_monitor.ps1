<#
.SYNOPSIS
    Windows Event Log monitor for Errors and Warnings (Administrative Events).

.DESCRIPTION
    This script monitors Windows Event Logs for Error (Level 2) and Warning (Level 3) events only,
    matching the "Administrative Events" view in Event Viewer. Sends events to the Flask backend.

    Configuration is loaded from .env file in the project root. Command-line parameters override .env values.

.PARAMETER ApiUrl
    The URL of the Flask backend API (overrides .env if specified)

.PARAMETER LogNames
    Comma-separated list of event log names to monitor (overrides .env if specified)

.PARAMETER PollIntervalSeconds
    How often to check for new events in seconds (overrides .env if specified)

.PARAMETER EventIds
    Optional comma-separated list of specific event IDs to monitor (overrides .env if specified)

.PARAMETER MaxEventsPerPoll
    Maximum number of events to retrieve per poll (overrides .env if specified)

.EXAMPLE
    .\event_monitor.ps1

.EXAMPLE
    .\event_monitor.ps1 -LogNames "System,Application" -PollIntervalSeconds 5

.EXAMPLE
    .\event_monitor.ps1 -EventIds "7031,7034,1000,1001" -MaxEventsPerPoll 100
#>

param(
    [string]$ApiUrl = "",
    [string]$LogNames = "",
    [int]$PollIntervalSeconds = 0,
    [string]$EventIds = "",
    [int]$MaxEventsPerPoll = 0,
    [int]$HistoricalDays = 0,
    [int]$MaxHistoricalEvents = 0,
    [switch]$SkipHistorical
)

# Load configuration from .env file
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigScript = Join-Path $ScriptDir "Load-Config.ps1"

if (Test-Path $ConfigScript) {
    $envConfig = & $ConfigScript

    # Use .env values as defaults, allow command-line parameters to override
    if ([string]::IsNullOrWhiteSpace($ApiUrl)) {
        $ApiUrl = $envConfig.API_BASE_URL
    }
    if ([string]::IsNullOrWhiteSpace($LogNames)) {
        $LogNames = $envConfig.LOG_NAMES
    }
    if ($PollIntervalSeconds -eq 0) {
        $PollIntervalSeconds = [int]$envConfig.POLL_INTERVAL_SECONDS
    }
    if ($MaxEventsPerPoll -eq 0) {
        $MaxEventsPerPoll = [int]$envConfig.MAX_EVENTS_PER_POLL
    }
    if ($HistoricalDays -eq 0) {
        $HistoricalDays = [int]$envConfig.HISTORICAL_DAYS
    }
    if ($MaxHistoricalEvents -eq 0) {
        $MaxHistoricalEvents = [int]$envConfig.MAX_HISTORICAL_EVENTS
    }
    if ([string]::IsNullOrWhiteSpace($EventIds)) {
        $EventIds = $envConfig.EVENT_IDS_TO_MONITOR
    }
} else {
    Write-Warning "Configuration loader not found. Using default values."
    # Set defaults if not specified
    if ([string]::IsNullOrWhiteSpace($ApiUrl)) { $ApiUrl = "http://localhost:5000" }
    if ([string]::IsNullOrWhiteSpace($LogNames)) { $LogNames = "System,Application" }
    if ($PollIntervalSeconds -eq 0) { $PollIntervalSeconds = 10 }
    if ($MaxEventsPerPoll -eq 0) { $MaxEventsPerPoll = 100 }
    if ($HistoricalDays -eq 0) { $HistoricalDays = 30 }
    if ($MaxHistoricalEvents -eq 0) { $MaxHistoricalEvents = 10000 }
}

# Configuration
$script:ApiEndpoint = "$ApiUrl/api/events"
$script:LogNamesArray = $LogNames -split ','
$script:EventIdsArray = if ($EventIds) { ($EventIds -split ',') | ForEach-Object { [int]$_ } } else { @() }
$script:LastCheckTime = @{}  # Track last check time for each log
$script:ProcessedEvents = @{}  # Track processed events to avoid duplicates

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Windows Event Monitor - Administrative Events" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "API Endpoint: $script:ApiEndpoint" -ForegroundColor Green
Write-Host "Monitoring Logs: $LogNames" -ForegroundColor Green
Write-Host "Event Levels: Error (2) + Warning (3)" -ForegroundColor Yellow
Write-Host "Poll Interval: $PollIntervalSeconds seconds" -ForegroundColor Green
Write-Host "Max Events/Poll: $MaxEventsPerPoll" -ForegroundColor Green
if ($script:EventIdsArray.Count -gt 0) {
    Write-Host "Filtering Event IDs: $EventIds" -ForegroundColor Green
}
if (-not $SkipHistorical) {
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
        Write-Host "Event $($Event.Id) from $($Event.ProviderName) sent" -ForegroundColor White
        
        return $true
    }
    catch {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] " -NoNewline -ForegroundColor Gray
        Write-Host "[FAIL] " -NoNewline -ForegroundColor Red
        Write-Host "Failed to send event $($Event.Id): $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to check for new events in a log
function Check-LogForNewEvents {
    param([string]$LogName)
    
    $lastCheck = $script:LastCheckTime[$LogName]
    $currentTime = Get-Date
    
    try {
        # Build filter - Only capture Error (Level 2) and Warning (Level 3) events
        $filterHashtable = @{
            LogName = $LogName
            StartTime = $lastCheck
            Level = @(2, 3)  # 2 = Error, 3 = Warning (Administrative Events)
        }

        if ($script:EventIdsArray.Count -gt 0) {
            $filterHashtable['ID'] = $script:EventIdsArray
        }

        # Get events since last check
        $events = Get-WinEvent -FilterHashtable $filterHashtable -MaxEvents $MaxEventsPerPoll -ErrorAction SilentlyContinue
        
        if ($null -eq $events) {
            return 0
        }
        
        # Ensure $events is an array
        if ($events -isnot [Array]) {
            $events = @($events)
        }
        
        $newEventCount = 0
        
        # Process events (newest first, so reverse to send oldest first)
        [array]::Reverse($events)
        
        foreach ($evt in $events) {
            # Create unique event key
            $eventKey = "$($evt.LogName)-$($evt.RecordId)"
            
            # Skip if already processed
            if ($script:ProcessedEvents.ContainsKey($eventKey)) {
                continue
            }
            
            # Send to API
            if (Send-EventToApi -Event $evt) {
                $script:ProcessedEvents[$eventKey] = $true
                $newEventCount++
            }
        }
        
        # Update last check time
        $script:LastCheckTime[$LogName] = $currentTime
        
        return $newEventCount
    }
    catch {
        if ($_.Exception.Message -notlike "*No events were found*") {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Error checking $LogName : $($_.Exception.Message)" -ForegroundColor Red
        }
        return 0
    }
}

# Function to import historical events
function Import-HistoricalEvents {
    if ($SkipHistorical) {
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
            # Build filter for historical events - Only Error (Level 2) and Warning (Level 3)
            $filterHashtable = @{
                LogName = $logNameTrimmed
                StartTime = $startTime
                Level = @(2, 3)  # 2 = Error, 3 = Warning (Administrative Events)
            }

            if ($script:EventIdsArray.Count -gt 0) {
                $filterHashtable['ID'] = $script:EventIdsArray
            }

            # Get ALL historical errors/warnings (up to MaxHistoricalEvents)
            $events = Get-WinEvent -FilterHashtable $filterHashtable -MaxEvents $MaxHistoricalEvents -ErrorAction SilentlyContinue

            if ($null -eq $events) {
                Write-Host "  No events found in $logNameTrimmed" -ForegroundColor Gray
                continue
            }

            # Ensure $events is an array
            if ($events -isnot [Array]) {
                $events = @($events)
            }

            Write-Host "  Found $($events.Count) events, importing..." -ForegroundColor Cyan

            # Process events (newest first, so reverse to send oldest first)
            [array]::Reverse($events)

            $imported = 0
            foreach ($evt in $events) {
                # Create unique event key
                $eventKey = "$($evt.LogName)-$($evt.RecordId)"

                # Skip if already processed
                if ($script:ProcessedEvents.ContainsKey($eventKey)) {
                    continue
                }

                # Send to API
                if (Send-EventToApi -Event $evt) {
                    $script:ProcessedEvents[$eventKey] = $true
                    $imported++
                    $totalImported++

                    # Show progress every 50 events
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

# Main monitoring loop
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
            $logNameTrimmed = $logName.Trim()
            $newEvents = Check-LogForNewEvents -LogName $logNameTrimmed
            $totalNewEvents += $newEvents
        }
        
        if ($totalNewEvents -eq 0 -and $pollCount % 6 -eq 0) {
            # Show heartbeat every minute (6 polls at 10 seconds each)
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ♥ Monitoring active - no new events" -ForegroundColor DarkGray
        }
        
        # Clean up old processed events (keep last 1000)
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
    Write-Host ""
    Write-Host ""
    Write-Host "Monitoring stopped." -ForegroundColor Yellow
}

