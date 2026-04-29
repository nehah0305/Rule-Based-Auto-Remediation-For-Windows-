# Remediation Script for Event ID 10016: DCOM permission denied
# Conservative remediation: ensure RPC/DCOM services are running and collect DCOM context.

param()

$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')
$LOG_NAME = 'Application'
$SOURCE = 'AutoRemediationDemo'
$RESOLVE_ID = 7036
$message = $env:RM_MESSAGE
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$LOG_FILE = 'C:\Temp\Event10016_Remediation.log'

if (-not (Test-Path 'C:\Temp')) { New-Item -ItemType Directory -Path 'C:\Temp' -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    Add-Content -Path $LOG_FILE -Value "[$timestamp] $Message" -Force
}

function Get-ContextValue {
    param([string]$Message, [string]$Label)

    $pattern = ('{0}:\\s*([^`r`n]+)' -f $Label)
    if ($Message -match $pattern) { return $matches[1].Trim() }
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

Write-Log 'Event 10016 received: DCOM permission denied.'
Write-Log ("Message: {0}" -f $message)

$clsid = Get-ContextValue -Message $message -Label 'CLSID'
$appId = Get-ContextValue -Message $message -Label 'APPID'
$action = 'none'

if ($SIMULATION_MODE) {
    Write-Log ("[SIMULATION] Would verify RPC/DCOM services and review CLSID={0} APPID={1}" -f $clsid, $appId)
    $action = 'simulated-review'
}
else {
    try {
        foreach ($svcName in @('RpcSs', 'DcomLaunch', 'PlugPlay')) {
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -ne 'Running') {
                Start-Service -Name $svcName -ErrorAction SilentlyContinue
                Write-Log ("Started service: {0}" -f $svcName)
            }
        }
        gpupdate /force | Out-Null
        $action = 'services-checked'
    }
    catch {
        Write-Log ("DCOM permission remediation failed: {0}" -f $_.Exception.Message)
        $action = 'partial'
    }
}

$status = if ($action -in @('simulated-review','services-checked')) { 'SUCCESS' } else { 'PARTIAL' }
$resolutionMessage = "Auto-remediation $status for Event 10016. CLSID=$clsid APPID=$appId Action=$action Time=$timestamp"
if ($SIMULATION_MODE) { $resolutionMessage = "[SIMULATION] $resolutionMessage" }
Write-ResolutionEvent -EventId $RESOLVE_ID -Message $resolutionMessage
Write-Log ("Remediation complete with action: {0}" -f $action)
exit 0
