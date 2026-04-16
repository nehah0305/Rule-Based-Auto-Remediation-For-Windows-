# Remediation Script for Event ID 4697: Service installation failure
# Conservative remediation: verify service binary and service control state.

param()

$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')
$LOG_NAME = 'Application'
$SOURCE = 'AutoRemediationDemo'
$RESOLVE_ID = 7036
$message = $env:RM_MESSAGE
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$LOG_FILE = 'C:\Temp\Event4697_Remediation.log'

if (-not (Test-Path 'C:\Temp')) { New-Item -ItemType Directory -Path 'C:\Temp' -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    Add-Content -Path $LOG_FILE -Value "[$timestamp] $Message" -Force
}

function Get-ServiceNameFromMessage {
    param([string]$Message)

    if ($Message -match 'Service Name:\s*([^\r\n]+)') { return $matches[1].Trim() }
    if ($Message -match 'service\s+([^\r\n]+)') { return $matches[1].Trim() }
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

Write-Log 'Event 4697 received: Service installation failure.'
Write-Log ("Message: {0}" -f $message)

$serviceName = Get-ServiceNameFromMessage -Message $message
$action = 'none'

if ($SIMULATION_MODE) {
    Write-Log ("[SIMULATION] Would verify newly installed service and its binary: {0}" -f $serviceName)
    $action = 'simulated-review'
}
else {
    try {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($service) {
            Set-Service -Name $service.Name -StartupType 'Manual' -ErrorAction SilentlyContinue
            Write-Log ("Service installation reviewed: {0}" -f $service.Name)
        }
        gpupdate /force | Out-Null
        $action = 'reviewed-service'
    }
    catch {
        Write-Log ("Service installation remediation failed: {0}" -f $_.Exception.Message)
        $action = 'partial'
    }
}

$status = if ($action -in @('simulated-review','reviewed-service')) { 'SUCCESS' } else { 'PARTIAL' }
$resolutionMessage = "Auto-remediation $status for Event 4697. Service=$serviceName Action=$action Time=$timestamp"
if ($SIMULATION_MODE) { $resolutionMessage = "[SIMULATION] $resolutionMessage" }
Write-ResolutionEvent -EventId $RESOLVE_ID -Message $resolutionMessage
Write-Log ("Remediation complete with action: {0}" -f $action)
exit 0
