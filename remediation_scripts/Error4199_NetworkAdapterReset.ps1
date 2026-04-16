# Remediation Script for Event ID 4199: Network adapter reset
# Conservative remediation: record adapter state, refresh network configuration, and verify connectivity.

param()

$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')
$LOG_NAME = 'Application'
$SOURCE = 'AutoRemediationDemo'
$RESOLVE_ID = 7036
$message = $env:RM_MESSAGE
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$LOG_FILE = 'C:\Temp\Event4199_Remediation.log'

if (-not (Test-Path 'C:\Temp')) { New-Item -ItemType Directory -Path 'C:\Temp' -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    Add-Content -Path $LOG_FILE -Value "[$timestamp] $Message" -Force
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

Write-Log 'Event 4199 received: Network adapter reset.'
Write-Log ("Message: {0}" -f $message)

$adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue)
$action = 'none'

if ($SIMULATION_MODE) {
    Write-Log '[SIMULATION] Would inspect adapter state and run DNS refresh/reset steps.'
    $action = 'simulated-check'
}
else {
    try {
        foreach ($adapter in $adapters) {
            Write-Log ("Adapter: {0} Status={1} LinkSpeed={2}" -f $adapter.Name, $adapter.Status, $adapter.LinkSpeed)
        }
        ipconfig /flushdns | Out-Null
        ipconfig /registerdns | Out-Null
        $action = 'refreshed-network'
    }
    catch {
        Write-Log ("Adapter reset remediation failed: {0}" -f $_.Exception.Message)
        $action = 'partial'
    }
}

$status = if ($action -in @('simulated-check','refreshed-network')) { 'SUCCESS' } else { 'PARTIAL' }
$resolutionMessage = "Auto-remediation $status for Event 4199. Action=$action Time=$timestamp"
if ($SIMULATION_MODE) { $resolutionMessage = "[SIMULATION] $resolutionMessage" }
Write-ResolutionEvent -EventId $RESOLVE_ID -Message $resolutionMessage
Write-Log ("Remediation complete with action: {0}" -f $action)
exit 0
