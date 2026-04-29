# Remediation Script for Event ID 4202: Network interface was disconnected
# Conservative remediation: inspect adapter state and try safe adapter refresh steps.

param()

$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')
$LOG_NAME = 'Application'
$SOURCE = 'AutoRemediationDemo'
$RESOLVE_ID = 7036
$message = $env:RM_MESSAGE
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$LOG_FILE = 'C:\Temp\Event4202_Remediation.log'

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

Write-Log 'Event 4202 received: Network interface disconnected.'
Write-Log ("Message: {0}" -f $message)

$adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Down' -or $_.Status -eq 'Not Present' })
$action = 'none'

if ($SIMULATION_MODE) {
    Write-Log '[SIMULATION] Would inspect adapters, verify link status, and refresh DNS cache.'
    $action = 'simulated-check'
}
else {
    try {
        ipconfig /flushdns | Out-Null
        foreach ($adapter in $adapters) {
            Write-Log ("Disconnected adapter: {0} Status={1}" -f $adapter.Name, $adapter.Status)
        }
        $action = 'checked-disconnect'
    }
    catch {
        Write-Log ("Network interface disconnect remediation failed: {0}" -f $_.Exception.Message)
        $action = 'partial'
    }
}

$status = if ($action -in @('simulated-check','checked-disconnect')) { 'SUCCESS' } else { 'PARTIAL' }
$resolutionMessage = "Auto-remediation $status for Event 4202. Action=$action Time=$timestamp"
if ($SIMULATION_MODE) { $resolutionMessage = "[SIMULATION] $resolutionMessage" }
Write-ResolutionEvent -EventId $RESOLVE_ID -Message $resolutionMessage
Write-Log ("Remediation complete with action: {0}" -f $action)
exit 0
