# Remediation Script for Event ID 8004: AppLocker blocked DLL
# Conservative remediation: ensure AppIDSvc is running and refresh policy.

param()

$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')
$LOG_NAME = 'Application'
$SOURCE = 'AutoRemediationDemo'
$RESOLVE_ID = 7036
$message = $env:RM_MESSAGE
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$LOG_FILE = 'C:\Temp\Event8004_Remediation.log'

if (-not (Test-Path 'C:\Temp')) { New-Item -ItemType Directory -Path 'C:\Temp' -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    Add-Content -Path $LOG_FILE -Value "[$timestamp] $Message" -Force
}

function Get-BlockedPath {
    param([string]$Message)

    if ($Message -match '([A-Za-z]:\\[^,\r\n]+\.dll)') { return $matches[1].Trim() }
    if ($Message -match 'DLL\s+([^,\r\n]+\.dll)') { return $matches[1].Trim() }
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

Write-Log 'Event 8004 received: AppLocker blocked DLL.'
Write-Log ("Message: {0}" -f $message)

$blockedPath = Get-BlockedPath -Message $message
$action = 'none'

if ($SIMULATION_MODE) {
    Write-Log ("[SIMULATION] Would review blocked DLL and refresh AppLocker policy: {0}" -f $blockedPath)
    $action = 'simulated-review'
}
else {
    try {
        $appIdSvc = Get-Service -Name 'AppIDSvc' -ErrorAction SilentlyContinue
        if ($appIdSvc -and $appIdSvc.Status -ne 'Running') {
            Start-Service -Name 'AppIDSvc' -ErrorAction SilentlyContinue
            Set-Service -Name 'AppIDSvc' -StartupType 'Automatic' -ErrorAction SilentlyContinue
        }

        gpupdate /force | Out-Null
        $action = 'refreshed-policy'
    }
    catch {
        Write-Log ("AppLocker DLL remediation failed: {0}" -f $_.Exception.Message)
        $action = 'partial'
    }
}

$status = if ($action -in @('simulated-review','refreshed-policy')) { 'SUCCESS' } else { 'PARTIAL' }
$resolutionMessage = "Auto-remediation $status for Event 8004. BlockedPath=$blockedPath Action=$action Time=$timestamp"
if ($SIMULATION_MODE) { $resolutionMessage = "[SIMULATION] $resolutionMessage" }
Write-ResolutionEvent -EventId $RESOLVE_ID -Message $resolutionMessage
Write-Log ("Remediation complete with action: {0}" -f $action)
exit 0
