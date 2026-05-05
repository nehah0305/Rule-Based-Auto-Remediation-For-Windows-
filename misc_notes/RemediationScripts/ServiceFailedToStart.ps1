# Error7000_ServiceFailedToStart.ps1
# PowerShell script for analyzing and fixing Windows Event ID 7000: Service Failed to Start
# Run as Administrator if needed for fixes.
# WARNING: Review and test in a safe environment.

$EVENT_ID = 7000
$DESCRIPTION = 'Service Failed to Start'
$FIX_SCRIPT = 'Write-Host "Check services.msc manually or restart the service."'

function Fetch-RecentErrors {
    param (
        [int]$Count = 10
    )
    $events = Get-WinEvent -LogName System -MaxEvents $Count -FilterHashTable @{Id = $EVENT_ID; Level = 1,2} -ErrorAction SilentlyContinue | Sort-Object TimeCreated -Descending
    return $events
}

function Analyze-AndFixError {
    param (
        [object]$Event
    )
    $eventID = $Event.Id
    $message = $Event.Message
    $time = $Event.TimeCreated
    
    Write-Host "Event ID: $eventID at $time"
    Write-Host "Message: $($message.Substring(0, [Math]::Min(100, $message.Length)))..."
    Write-Host "Classified as: $DESCRIPTION"
    Write-Host "Executing Fix: $FIX_SCRIPT"
    
    Invoke-Expression $FIX_SCRIPT
    Write-Host "-------------------"
}

function Main {
    Write-Host "Fetching recent errors for Event ID $EVENT_ID..."
    $errors = Fetch-RecentErrors -Count 5
    
    if ($errors.Count -eq 0) {
        Write-Host "No recent errors found for Event ID $EVENT_ID."
        return
    }
    
    foreach ($event in $errors) {
        Analyze-AndFixError -Event $event
    }
    
    Write-Host "Analysis and fixes complete."
}

Main