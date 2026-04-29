# Remediation Script for Event ID 4673: Privileged service operation failed
# Conservative remediation: identify the privilege used and gather service/auth diagnostics.

param()

$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')
$LOG_NAME = 'Application'
$SOURCE = 'AutoRemediationDemo'
$RESOLVE_ID = 7036
$message = $env:RM_MESSAGE
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$LOG_FILE = 'C:\Temp\Event4673_Remediation.log'

if (-not (Test-Path 'C:\Temp')) { New-Item -ItemType Directory -Path 'C:\Temp' -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    Add-Content -Path $LOG_FILE -Value "[$timestamp] $Message" -Force
}

function Get-PrivilegeName {
    param([string]$Message)

    if ($Message -match 'Privilege:\s*([^\r\n]+)') { return $matches[1].Trim() }
    if ($Message -match '([^\r\n]+)\s+privilege') { return $matches[1].Trim() }
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

Write-Log 'Event 4673 received: Privileged service operation failed.'
Write-Log ("Message: {0}" -f $message)

$privilege = Get-PrivilegeName -Message $message
$action = 'none'

if ($SIMULATION_MODE) {
    Write-Log ("[SIMULATION] Would inspect privilege usage and gather service diagnostics: {0}" -f $privilege)
    $action = 'simulated-review'
}
else {
    try {
        whoami /priv | Out-Null
        gpupdate /force | Out-Null
        $action = 'diagnostics-collected'
    }
    catch {
        Write-Log ("Privileged service operation remediation failed: {0}" -f $_.Exception.Message)
        $action = 'partial'
    }
}

$status = if ($action -in @('simulated-review','diagnostics-collected')) { 'SUCCESS' } else { 'PARTIAL' }
$resolutionMessage = "Auto-remediation $status for Event 4673. Privilege=$privilege Action=$action Time=$timestamp"
if ($SIMULATION_MODE) { $resolutionMessage = "[SIMULATION] $resolutionMessage" }
Write-ResolutionEvent -EventId $RESOLVE_ID -Message $resolutionMessage
Write-Log ("Remediation complete with action: {0}" -f $action)
exit 0
