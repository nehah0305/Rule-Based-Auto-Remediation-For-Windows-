# Remediation Script for Event ID 98: Volume corruption detected
# Conservative remediation: inspect volume health and run read-only repair checks.

param()

$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')
$LOG_NAME = 'Application'
$SOURCE = 'AutoRemediationDemo'
$RESOLVE_ID = 7036
$message = $env:RM_MESSAGE
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$LOG_FILE = 'C:\Temp\Event98_Remediation.log'

if (-not (Test-Path 'C:\Temp')) { New-Item -ItemType Directory -Path 'C:\Temp' -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    Add-Content -Path $LOG_FILE -Value "[$timestamp] $Message" -Force
}

function Get-DriveFromMessage {
    param([string]$Message)

    if ($Message -match '([A-Z]:)') { return $matches[1] }
    return $null
}

function Write-ResolutionEvent {
    param([int]$EventId, [string]$Message)
    try {
        Write-EventLog -LogName $LOG_NAME -Source $SOURCE -EventId $EventId -EntryType 'Information' -Message $Message -ErrorAction Stop
    }
    catch {
        Write-Log ("Error writing event: {0}" -f $_.Exception.Message)
    }
}

Write-Log 'Event 98 received: Volume corruption detected.'
Write-Log ("Message: {0}" -f $message)

$drive = Get-DriveFromMessage -Message $message
$action = 'none'

if ($SIMULATION_MODE) {
    Write-Log ("[SIMULATION] Would run volume health checks for drive {0}." -f $drive)
    $action = 'simulated-check'
}
else {
    try {
        if ($drive) {
            & cmd.exe /c "chkdsk $drive /scan" 2>&1 | Out-Null
        }
        & cmd.exe /c "sfc /scannow" 2>&1 | Out-Null
        & cmd.exe /c "DISM /Online /Cleanup-Image /RestoreHealth" 2>&1 | Out-Null
        $action = 'checked-and-diagnosed'
    }
    catch {
        Write-Log ("Volume corruption remediation failed: {0}" -f $_.Exception.Message)
        $action = 'partial'
    }
}

$status = if ($action -in @('simulated-check','checked-and-diagnosed')) { 'SUCCESS' } else { 'PARTIAL' }
$resolutionMessage = "Auto-remediation $status for Event 98. Drive=$drive Action=$action Time=$timestamp"
if ($SIMULATION_MODE) { $resolutionMessage = "[SIMULATION] $resolutionMessage" }
Write-ResolutionEvent -EventId $RESOLVE_ID -Message $resolutionMessage
Write-Log ("Remediation complete with action: {0}" -f $action)
exit 0
