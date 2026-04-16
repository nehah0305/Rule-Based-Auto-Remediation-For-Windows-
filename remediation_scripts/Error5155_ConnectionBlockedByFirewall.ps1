# Remediation Script for Event ID 5155: Connection blocked by firewall
# Conservative remediation: verify the firewall service and record the blocked connection context.

param()

$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')
$LOG_NAME = 'Application'
$SOURCE = 'AutoRemediationDemo'
$RESOLVE_ID = 7036
$message = $env:RM_MESSAGE
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$LOG_FILE = 'C:\Temp\Event5155_Remediation.log'

if (-not (Test-Path 'C:\Temp')) { New-Item -ItemType Directory -Path 'C:\Temp' -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    Add-Content -Path $LOG_FILE -Value "[$timestamp] $Message" -Force
}

function Get-BlockedAppName {
    param([string]$Message)

    if ($Message -match "application\s+'([^']+)'") { return $matches[1] }
    if ($Message -match '([A-Za-z0-9_.-]+\.exe)') { return $matches[1] }
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

Write-Log 'Event 5155 received: Connection blocked by firewall.'
Write-Log ("Message: {0}" -f $message)

$appName = Get-BlockedAppName -Message $message
$action = 'none'

if ($SIMULATION_MODE) {
    Write-Log ("[SIMULATION] Would verify firewall service and review blocked app: {0}" -f $appName)
    $action = 'simulated-check'
}
else {
    try {
        $firewallService = Get-Service -Name 'mpssvc' -ErrorAction SilentlyContinue
        if ($firewallService -and $firewallService.Status -ne 'Running') {
            Start-Service -Name 'mpssvc' -ErrorAction SilentlyContinue
            Set-Service -Name 'mpssvc' -StartupType 'Automatic' -ErrorAction SilentlyContinue
        }
        $action = 'firewall-checked'
    }
    catch {
        Write-Log ("Firewall blocked-connection remediation failed: {0}" -f $_.Exception.Message)
        $action = 'partial'
    }
}

$status = if ($action -in @('simulated-check','firewall-checked')) { 'SUCCESS' } else { 'PARTIAL' }
$resolutionMessage = "Auto-remediation $status for Event 5155. App=$appName Action=$action Time=$timestamp"
if ($SIMULATION_MODE) { $resolutionMessage = "[SIMULATION] $resolutionMessage" }
Write-ResolutionEvent -EventId $RESOLVE_ID -Message $resolutionMessage
Write-Log ("Remediation complete with action: {0}" -f $action)
exit 0
