# Remediation Script for Event ID 1129: Secure channel failure
# Conservative remediation: verify and repair the machine secure channel.

param()

$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')
$LOG_NAME = 'Application'
$SOURCE = 'AutoRemediationDemo'
$RESOLVE_ID = 7036
$message = $env:RM_MESSAGE
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$LOG_FILE = 'C:\Temp\Event1129_Remediation.log'

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

Write-Log 'Event 1129 received: Secure channel failure.'
Write-Log ("Message: {0}" -f $message)

$action = 'none'
$domain = $env:USERDOMAIN

if ($SIMULATION_MODE) {
    Write-Log '[SIMULATION] Would test and repair secure channel if needed.'
    $action = 'simulated-repair'
}
else {
    try {
        if (Get-Command Test-ComputerSecureChannel -ErrorAction SilentlyContinue) {
            if (-not (Test-ComputerSecureChannel -Quiet)) {
                Test-ComputerSecureChannel -Repair -ErrorAction SilentlyContinue | Out-Null
                Write-Log 'Secure channel repair attempted.'
                $action = 'repaired'
            }
            else {
                Write-Log 'Secure channel already healthy.'
                $action = 'healthy'
            }
        }
        else {
            nltest /sc_reset:$domain | Out-Null
            Write-Log 'Fallback secure channel reset attempted with nltest.'
            $action = 'reset-with-nltest'
        }
    }
    catch {
        Write-Log ("Secure channel remediation failed: {0}" -f $_.Exception.Message)
        $action = 'partial'
    }
}

$status = if ($action -in @('simulated-repair','repaired','healthy','reset-with-nltest')) { 'SUCCESS' } else { 'PARTIAL' }
$resolutionMessage = "Auto-remediation $status for Event 1129. Domain=$domain Action=$action Time=$timestamp"
if ($SIMULATION_MODE) { $resolutionMessage = "[SIMULATION] $resolutionMessage" }
Write-ResolutionEvent -EventId $RESOLVE_ID -Message $resolutionMessage
Write-Log ("Remediation complete with action: {0}" -f $action)
exit 0
