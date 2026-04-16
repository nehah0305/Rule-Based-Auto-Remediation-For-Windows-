# Remediation Script for Event ID 4625: Logon failure
# Conservative remediation: inspect failed logon context, refresh time sync, and collect auth diagnostics.

param()

$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')
$LOG_NAME = 'Application'
$SOURCE = 'AutoRemediationDemo'
$RESOLVE_ID = 7036
$message = $env:RM_MESSAGE
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$LOG_FILE = 'C:\Temp\Event4625_Remediation.log'

if (-not (Test-Path 'C:\Temp')) { New-Item -ItemType Directory -Path 'C:\Temp' -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    Add-Content -Path $LOG_FILE -Value "[$timestamp] $Message" -Force
}

function Get-UserFromMessage {
    param([string]$Message)

    if ($Message -match 'Account Name:\s*([^\r\n]+)') { return $matches[1].Trim() }
    if ($Message -match 'User Name:\s*([^\r\n]+)') { return $matches[1].Trim() }
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

Write-Log 'Event 4625 received: Logon failure.'
Write-Log ("Message: {0}" -f $message)

$userName = Get-UserFromMessage -Message $message
$action = 'none'

if ($SIMULATION_MODE) {
    Write-Log ("[SIMULATION] Would inspect failed logon context and sync time for user: {0}" -f $userName)
    $action = 'simulated-review'
}
else {
    try {
        w32tm /resync /force | Out-Null
        $action = 'time-synced'

        if ($env:USERDOMAIN) {
            nltest /dsgetdc:$env:USERDOMAIN | Out-Null
            Write-Log 'Domain controller check attempted.'
        }
    }
    catch {
        Write-Log ("Logon failure remediation failed: {0}" -f $_.Exception.Message)
        $action = 'partial'
    }
}

$status = if ($action -in @('simulated-review','time-synced')) { 'SUCCESS' } else { 'PARTIAL' }
$resolutionMessage = "Auto-remediation $status for Event 4625. User=$userName Action=$action Time=$timestamp"
if ($SIMULATION_MODE) { $resolutionMessage = "[SIMULATION] $resolutionMessage" }
Write-ResolutionEvent -EventId $RESOLVE_ID -Message $resolutionMessage
Write-Log ("Remediation complete with action: {0}" -f $action)
exit 0
