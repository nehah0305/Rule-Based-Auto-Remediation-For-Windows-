# Remediation Script for Event ID 5025: Windows Firewall service stopped
# Conservative remediation: start the firewall service and restore automatic startup.

param()

$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')
$LOG_NAME = 'Application'
$SOURCE = 'AutoRemediationDemo'
$RESOLVE_ID = 7036
$message = $env:RM_MESSAGE
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$LOG_FILE = 'C:\Temp\Event5025_Remediation.log'

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

Write-Log 'Event 5025 received: Windows Firewall service stopped.'
Write-Log ("Message: {0}" -f $message)

$action = 'none'
$service = Get-Service -Name 'mpssvc' -ErrorAction SilentlyContinue

if ($SIMULATION_MODE) {
    Write-Log '[SIMULATION] Would start Windows Defender Firewall service and set it to Automatic.'
    $action = 'simulated-start'
}
else {
    try {
        if ($service) {
            if ($service.Status -ne 'Running') {
                Start-Service -Name 'mpssvc' -ErrorAction Stop
                Write-Log 'Windows Defender Firewall service started.'
            }
            Set-Service -Name 'mpssvc' -StartupType 'Automatic' -ErrorAction SilentlyContinue
            $action = 'started'
        }
        else {
            Write-Log 'Firewall service not found.'
            $action = 'service-not-found'
        }
    }
    catch {
        Write-Log ("Firewall service remediation failed: {0}" -f $_.Exception.Message)
        $action = 'partial'
    }
}

$status = if ($action -in @('simulated-start','started')) { 'SUCCESS' } else { 'PARTIAL' }
$resolutionMessage = "Auto-remediation $status for Event 5025. Action=$action Time=$timestamp"
if ($SIMULATION_MODE) { $resolutionMessage = "[SIMULATION] $resolutionMessage" }
Write-ResolutionEvent -EventId $RESOLVE_ID -Message $resolutionMessage
Write-Log ("Remediation complete with action: {0}" -f $action)
exit 0
