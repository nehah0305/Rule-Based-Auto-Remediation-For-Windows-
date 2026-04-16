# Remediation Script for Event ID 5152: Packet dropped by Windows Filtering Platform
# Conservative remediation: verify firewall service, refresh networking, and record the incident.

param()

$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')
$LOG_NAME = 'Application'
$SOURCE = 'AutoRemediationDemo'
$RESOLVE_ID = 7036
$message = $env:RM_MESSAGE
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$LOG_FILE = 'C:\Temp\Event5152_Remediation.log'

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

Write-Log 'Event 5152 received: Packet dropped by Windows Filtering Platform.'
Write-Log ("Message: {0}" -f $message)

$action = 'none'

if ($SIMULATION_MODE) {
    Write-Log '[SIMULATION] Would verify firewall service state and refresh DNS/network configuration.'
    $action = 'simulated-check'
}
else {
    try {
        $firewallService = Get-Service -Name 'mpssvc' -ErrorAction SilentlyContinue
        if ($firewallService -and $firewallService.Status -ne 'Running') {
            Start-Service -Name 'mpssvc' -ErrorAction SilentlyContinue
            Set-Service -Name 'mpssvc' -StartupType 'Automatic' -ErrorAction SilentlyContinue
            Write-Log 'Windows Defender Firewall service was started or repaired.'
        }

        ipconfig /flushdns | Out-Null
        ipconfig /registerdns | Out-Null
        $action = 'refreshed-network'
    }
    catch {
        Write-Log ("Firewall packet-drop remediation failed: {0}" -f $_.Exception.Message)
        $action = 'partial'
    }
}

$status = if ($action -in @('simulated-check','refreshed-network')) { 'SUCCESS' } else { 'PARTIAL' }
$resolutionMessage = "Auto-remediation $status for Event 5152. Action=$action Time=$timestamp"
if ($SIMULATION_MODE) { $resolutionMessage = "[SIMULATION] $resolutionMessage" }
Write-ResolutionEvent -EventId $RESOLVE_ID -Message $resolutionMessage
Write-Log ("Remediation complete with action: {0}" -f $action)
exit 0
