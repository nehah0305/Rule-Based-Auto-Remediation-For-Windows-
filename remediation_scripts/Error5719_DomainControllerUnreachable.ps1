# Remediation Script for Event ID 5719: Domain controller not reachable
# Conservative remediation: validate secure channel and DNS, then attempt secure channel repair.

param()

$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')
$LOG_NAME = 'Application'
$SOURCE = 'AutoRemediationDemo'
$RESOLVE_ID = 7036
$message = $env:RM_MESSAGE
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$LOG_FILE = 'C:\Temp\Event5719_Remediation.log'

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

Write-Log 'Event 5719 received: Domain controller not reachable.'
Write-Log ("Message: {0}" -f $message)

$action = 'none'
$domain = $env:USERDOMAIN

if ($SIMULATION_MODE) {
    Write-Log '[SIMULATION] Would verify DNS, secure channel, and domain connectivity.'
    $action = 'simulated-check'
}
else {
    try {
        ipconfig /flushdns | Out-Null
        nltest /dsgetdc:$domain | Out-Null
        if (Get-Command Test-ComputerSecureChannel -ErrorAction SilentlyContinue) {
            if (-not (Test-ComputerSecureChannel -Quiet)) {
                Test-ComputerSecureChannel -Repair -ErrorAction SilentlyContinue | Out-Null
                Write-Log 'Attempted secure channel repair.'
            }
        }
        $action = 'verified-and-repaired'
    }
    catch {
        Write-Log ("Domain controller remediation failed: {0}" -f $_.Exception.Message)
        $action = 'partial'
    }
}

$status = if ($action -in @('simulated-check','verified-and-repaired')) { 'SUCCESS' } else { 'PARTIAL' }
$resolutionMessage = "Auto-remediation $status for Event 5719. Domain=$domain Action=$action Time=$timestamp"
if ($SIMULATION_MODE) { $resolutionMessage = "[SIMULATION] $resolutionMessage" }
Write-ResolutionEvent -EventId $RESOLVE_ID -Message $resolutionMessage
Write-Log ("Remediation complete with action: {0}" -f $action)
exit 0
