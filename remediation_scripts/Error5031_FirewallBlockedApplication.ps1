# Remediation Script for Event ID 5031: Firewall blocked application
# Conservative remediation: verify firewall service and optionally create a scoped allow rule.

param()

$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')
$ALLOW_FIREWALL_RULES = ($env:RM_ALLOW_FIREWALL_RULES -eq '1')
$LOG_NAME = 'Application'
$SOURCE = 'AutoRemediationDemo'
$RESOLVE_ID = 7036
$message = $env:RM_MESSAGE
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$LOG_FILE = 'C:\Temp\Event5031_Remediation.log'

if (-not (Test-Path 'C:\Temp')) { New-Item -ItemType Directory -Path 'C:\Temp' -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    Add-Content -Path $LOG_FILE -Value "[$timestamp] $Message" -Force
}

function Get-BlockedAppPath {
    param([string]$Message)

    if ($Message -match 'Executable path\s+([^,]+)') { return $matches[1].Trim() }
    if ($Message -match '([A-Za-z]:\\[^,]+\.exe)') { return $matches[1].Trim() }
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

Write-Log 'Event 5031 received: Firewall blocked application.'
Write-Log ("Message: {0}" -f $message)

$appPath = Get-BlockedAppPath -Message $message
$action = 'none'

if ($SIMULATION_MODE) {
    Write-Log ("[SIMULATION] Would evaluate a scoped allow rule for: {0}" -f $appPath)
    $action = 'simulated-evaluate'
}
else {
    try {
        $firewallService = Get-Service -Name 'mpssvc' -ErrorAction SilentlyContinue
        if ($firewallService -and $firewallService.Status -ne 'Running') {
            Start-Service -Name 'mpssvc' -ErrorAction SilentlyContinue
            Set-Service -Name 'mpssvc' -StartupType 'Automatic' -ErrorAction SilentlyContinue
        }

        if ($ALLOW_FIREWALL_RULES -and $appPath) {
            $ruleName = "AutoAllow-Block-$([System.IO.Path]::GetFileNameWithoutExtension($appPath))"
            $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
            if (-not $existing) {
                New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow -Program $appPath -Profile Any -ErrorAction SilentlyContinue | Out-Null
                Write-Log ("Created scoped allow rule: {0}" -f $ruleName)
            }
            $action = 'allow-rule-evaluated'
        }
        else {
            $action = 'firewall-checked'
        }
    }
    catch {
        Write-Log ("Firewall blocked-application remediation failed: {0}" -f $_.Exception.Message)
        $action = 'partial'
    }
}

$status = if ($action -in @('simulated-evaluate','allow-rule-evaluated','firewall-checked')) { 'SUCCESS' } else { 'PARTIAL' }
$resolutionMessage = "Auto-remediation $status for Event 5031. AppPath=$appPath Action=$action Time=$timestamp"
if ($SIMULATION_MODE) { $resolutionMessage = "[SIMULATION] $resolutionMessage" }
Write-ResolutionEvent -EventId $RESOLVE_ID -Message $resolutionMessage
Write-Log ("Remediation complete with action: {0}" -f $action)
exit 0
