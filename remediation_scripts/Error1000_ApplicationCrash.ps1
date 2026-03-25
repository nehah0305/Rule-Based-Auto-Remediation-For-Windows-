# Error1000_ApplicationCrash.ps1
# PowerShell script for analyzing and fixing Windows Event ID 1000: Application Crash
# Run as Administrator if needed for fixes.
# WARNING: Review and test in a safe environment.

$EVENT_ID = 1000
$DESCRIPTION = 'Application Crash'
$FIX_SCRIPT = 'sfc /scannow'
$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')

function Fetch-RecentErrors {
    param (
        [int]$Count = 10
    )

    $events = Get-WinEvent -LogName System -MaxEvents $Count -FilterHashTable @{ Id = $EVENT_ID; Level = 1,2 } -ErrorAction SilentlyContinue |
        Sort-Object TimeCreated -Descending

    return $events
}

function Analyze-AndFixError {
    param (
        [object]$Event
    )

    if (-not $Event) {
        Write-Host "Skipping empty event object"
        return
    }

    $eventID = $Event.Id
    $message = $Event.Message
    $time = $Event.TimeCreated

    if (-not $message) {
        $message = 'No event message available.'
    }

    Write-Host "Event ID: $eventID at $time"
    Write-Host "Message: $($message.Substring(0, [Math]::Min(100, $message.Length)))..."
    Write-Host "Classified as: $DESCRIPTION"
    Write-Host "Executing Fix: $FIX_SCRIPT"

    if ($SIMULATION_MODE) {
        Write-Host "[SIMULATION MODE] Skipping real command execution for safety."
        Write-Host "[SIMULATION MODE] Would run: $FIX_SCRIPT"
    }
    else {
        Invoke-Expression $FIX_SCRIPT
    }
    Write-Host "-------------------"
}

function Main {
    Write-Host "Fetching recent errors for Event ID $EVENT_ID..."
    $errors = Fetch-RecentErrors -Count 5

    if (-not $errors -or $errors.Count -eq 0) {
        Write-Host "No recent errors found for Event ID $EVENT_ID."
        return
    }

    foreach ($event in $errors) {
        Analyze-AndFixError -Event $event
    }

    Write-Host "Analysis and fixes complete."
}

Main
