<#
.SYNOPSIS
    Real-time Windows Event Log watcher that monitors events and sends them to the remediation backend.

.DESCRIPTION
    This script subscribes to Windows Event Logs and monitors events in real-time.
    When new events occur, they are automatically sent to the Flask backend API.
    Supports filtering by event IDs, sources, and severity levels.

.PARAMETER ApiUrl
    The URL of the Flask backend API (default: http://localhost:5000)

.PARAMETER LogNames
    Comma-separated list of event log names to monitor (default: System,Application)

.PARAMETER EventIds
    Optional comma-separated list of specific event IDs to monitor (monitors all if not specified)

.PARAMETER MinSeverityLevel
    Minimum severity level to monitor: Critical, Error, Warning, Information, Verbose (default: Warning)

.PARAMETER ThrottleSeconds
    Minimum seconds between sending duplicate events (default: 60)

.EXAMPLE
    .\event_watcher.ps1 -LogNames "System,Application" -MinSeverityLevel "Error"

.EXAMPLE
    .\event_watcher.ps1 -EventIds "7031,7034,1000,1001" -ApiUrl "http://localhost:5000"
#>

param(
    [string]$ApiUrl = "http://localhost:5000",
    [string]$LogNames = "System,Application",
    [string]$EventIds = "",
    [ValidateSet("Critical", "Error", "Warning", "Information", "Verbose")]
    [string]$MinSeverityLevel = "Warning",
    [int]$ThrottleSeconds = 60
)

# Configuration
$script:ApiEndpoint = "$ApiUrl/api/events"
$script:LogNamesArray = $LogNames -split ','
$script:EventIdsArray = if ($EventIds) { ($EventIds -split ',') | ForEach-Object { [int]$_ } } else { @() }
$script:RecentEvents = @{}  # Track recent events to avoid duplicates
$script:SeverityMap = @{
    "Critical" = 1
    "Error" = 2
    "Warning" = 3
    "Information" = 4
    "Verbose" = 5
}
$script:MinSeverity = $script:SeverityMap[$MinSeverityLevel]

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Windows Event Watcher - Real-Time Monitor" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "API Endpoint: $script:ApiEndpoint" -ForegroundColor Green
Write-Host "Monitoring Logs: $LogNames" -ForegroundColor Green
Write-Host "Min Severity: $MinSeverityLevel" -ForegroundColor Green
if ($script:EventIdsArray.Count -gt 0) {
    Write-Host "Filtering Event IDs: $EventIds" -ForegroundColor Green
}
Write-Host "Throttle: $ThrottleSeconds seconds" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan

# Function to send event to API
function Send-EventToApi {
    param($Event)
    
    try {
        $eventData = @{
            event_id = $Event.Id
            log_name = $Event.LogName
            source = $Event.ProviderName
            message = $Event.Message
            timestamp = $Event.TimeCreated.ToString("yyyy-MM-ddTHH:mm:ss")
        }
        
        $json = $eventData | ConvertTo-Json -Compress
        $response = Invoke-RestMethod -Uri $script:ApiEndpoint -Method Post -Body $json -ContentType "application/json" -ErrorAction Stop
        
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] " -NoNewline -ForegroundColor Gray
        Write-Host "✓ " -NoNewline -ForegroundColor Green
        Write-Host "Event $($Event.Id) from $($Event.ProviderName) sent successfully" -ForegroundColor White
        
        return $true
    }
    catch {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] " -NoNewline -ForegroundColor Gray
        Write-Host "✗ " -NoNewline -ForegroundColor Red
        Write-Host "Failed to send event: $_" -ForegroundColor Red
        return $false
    }
}

# Function to check if event should be processed
function Should-ProcessEvent {
    param($Event)
    
    # Check severity level
    $eventLevel = switch ($Event.Level) {
        1 { "Critical" }
        2 { "Error" }
        3 { "Warning" }
        4 { "Information" }
        5 { "Verbose" }
        default { "Information" }
    }
    
    $eventSeverity = $script:SeverityMap[$eventLevel]
    if ($eventSeverity -gt $script:MinSeverity) {
        return $false
    }
    
    # Check event ID filter
    if ($script:EventIdsArray.Count -gt 0 -and $Event.Id -notin $script:EventIdsArray) {
        return $false
    }
    
    # Check throttling (avoid duplicate events within throttle period)
    $eventKey = "$($Event.LogName)-$($Event.Id)-$($Event.ProviderName)"
    $now = Get-Date
    
    if ($script:RecentEvents.ContainsKey($eventKey)) {
        $lastSent = $script:RecentEvents[$eventKey]
        $timeDiff = ($now - $lastSent).TotalSeconds
        
        if ($timeDiff -lt $ThrottleSeconds) {
            return $false
        }
    }
    
    # Update last sent time
    $script:RecentEvents[$eventKey] = $now
    
    return $true
}

# Function to create event watcher for a log
function Start-EventWatcher {
    param([string]$LogName)
    
    Write-Host "Starting watcher for log: $LogName" -ForegroundColor Yellow
    
    # Create event query
    $query = "*[System]"

    try {
        # Create event watcher
        $watcher = New-Object System.Diagnostics.Eventing.Reader.EventLogWatcher($LogName, $query)

        # Register event handler
        Register-ObjectEvent -InputObject $watcher -EventName "EventRecordWritten" -Action {
            param($sender, $eventArgs)

            try {
                $event = $eventArgs.EventRecord

                if ($null -eq $event) {
                    return
                }

                # Check if event should be processed
                if (Should-ProcessEvent -Event $event) {
                    # Send to API
                    Send-EventToApi -Event $event | Out-Null
                }
            }
            catch {
                Write-Host "Error processing event: $_" -ForegroundColor Red
            }
        } | Out-Null

        # Enable the watcher
        $watcher.Enabled = $true

        Write-Host "✓ Watcher started for $LogName" -ForegroundColor Green

        return $watcher
    }
    catch {
        Write-Host "✗ Failed to start watcher for $LogName : $_" -ForegroundColor Red
        return $null
    }
}

# Main execution
Write-Host "Initializing event watchers...`n" -ForegroundColor Cyan

$watchers = @()
foreach ($logName in $script:LogNamesArray) {
    $watcher = Start-EventWatcher -LogName $logName.Trim()
    if ($null -ne $watcher) {
        $watchers += $watcher
    }
}

if ($watchers.Count -eq 0) {
    Write-Host "`nNo watchers started. Exiting." -ForegroundColor Red
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Monitoring started successfully!" -ForegroundColor Green
Write-Host "Press Ctrl+C to stop monitoring" -ForegroundColor Yellow
Write-Host "========================================`n" -ForegroundColor Cyan

# Keep script running
try {
    while ($true) {
        Start-Sleep -Seconds 1

        # Clean up old entries from recent events cache (older than 5 minutes)
        $cutoffTime = (Get-Date).AddMinutes(-5)
        $keysToRemove = @()

        foreach ($key in $script:RecentEvents.Keys) {
            if ($script:RecentEvents[$key] -lt $cutoffTime) {
                $keysToRemove += $key
            }
        }

        foreach ($key in $keysToRemove) {
            $script:RecentEvents.Remove($key)
        }
    }
}
finally {
    Write-Host "`n`nStopping event watchers..." -ForegroundColor Yellow

    foreach ($watcher in $watchers) {
        if ($null -ne $watcher) {
            $watcher.Enabled = $false
            $watcher.Dispose()
        }
    }

    # Unregister all event handlers
    Get-EventSubscriber | Unregister-Event

    Write-Host "Event watchers stopped." -ForegroundColor Green
}

