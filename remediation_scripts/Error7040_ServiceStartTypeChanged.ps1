# Remediation Script for Event ID 7040: Service start type changed
# This script restores safe service startup configuration when a target service
# is switched to an unavailable startup mode.

param()

$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')
$LOG_NAME = 'Application'
$SOURCE = 'AutoRemediationDemo'
$RESOLVE_ID = 7036
$message = $env:RM_MESSAGE
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$LOG_FILE = 'C:\Temp\Event7040_Remediation.log'

if (-not (Test-Path 'C:\Temp')) { New-Item -ItemType Directory -Path 'C:\Temp' -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    Add-Content -Path $LOG_FILE -Value "[$timestamp] $Message" -Force
}

function Get-StartTypeContext {
    param([string]$Message)

    $name = $null
    $newType = $null

    if (-not $Message) {
        return [PSCustomObject]@{ ServiceName = $null; NewType = $null }
    }

    if ($Message -match "The\s+start\s+type\s+of\s+the\s+(.+?)\s+service\s+was\s+changed\s+from\s+.+?\s+to\s+(.+?)\.") {
        $name = $matches[1].Trim()
        $newType = $matches[2].Trim().ToLowerInvariant()
    }

    if (-not $name -and $Message -match "service\s+'([^']+)'") {
        $name = $matches[1].Trim()
    }

    if (-not $newType -and $Message -match "to\s+(disabled|manual|auto start|automatic)\b") {
        $newType = $matches[1].Trim().ToLowerInvariant()
    }

    return [PSCustomObject]@{ ServiceName = $name; NewType = $newType }
}

function Convert-ToStartupType {
    param([string]$TypeText)

    if (-not $TypeText) { return 'Automatic' }

    switch -Regex ($TypeText) {
        'disabled' { return 'Disabled' }
        'manual' { return 'Manual' }
        'auto\s*start|automatic' { return 'Automatic' }
        default { return 'Automatic' }
    }
}

function Get-ServiceObject {
    param([string]$ServiceName)

    if (-not $ServiceName) { return $null }

    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc) { return $svc }

    $svc = Get-Service -DisplayName $ServiceName -ErrorAction SilentlyContinue
    return $svc
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

Write-Log 'Event 7040 received: Service start type changed.'
Write-Log ("Message: {0}" -f $message)

$ctx = Get-StartTypeContext -Message $message
$serviceName = $ctx.ServiceName
$detectedType = $ctx.NewType
$service = Get-ServiceObject -ServiceName $serviceName
$action = 'none'

if ($service) {
    Write-Log ("Service found: {0} (Status: {1})" -f $service.Name, $service.Status)

    $unsafeType = ($detectedType -eq 'disabled')

    if ($unsafeType) {
        if ($SIMULATION_MODE) {
            Write-Log ("[SIMULATION] Would set startup type to Automatic for: {0}" -f $service.Name)
            Write-Log ("[SIMULATION] Would start service if not running.")
            $action = 'simulated-corrected-startup'
        }
        else {
            try {
                Set-Service -Name $service.Name -StartupType 'Automatic' -ErrorAction Stop
                if ($service.Status -ne 'Running') {
                    Start-Service -Name $service.Name -ErrorAction SilentlyContinue
                }
                $action = 'corrected-startup'
                Write-Log ("Startup type corrected for: {0}" -f $service.Name)
            }
            catch {
                Write-Log ("Failed to correct startup type: {0}" -f $_.Exception.Message)
                $action = 'failed-correction'
            }
        }
    }
    else {
        Write-Log ("Detected start type appears safe: {0}" -f $detectedType)
        $action = 'no-change-needed'
    }
}
else {
    Write-Log ("Service not found from message parse: {0}" -f $serviceName)
    $action = 'service-not-found'
}

$status = if ($action -in @('corrected-startup','simulated-corrected-startup','no-change-needed')) { 'SUCCESS' } else { 'PARTIAL' }
$resolutionMessage = "Auto-remediation $status for Event 7040. Service=$serviceName NewType=$detectedType Action=$action Time=$timestamp"
if ($SIMULATION_MODE) { $resolutionMessage = "[SIMULATION] $resolutionMessage" }

Write-ResolutionEvent -EventId $RESOLVE_ID -Message $resolutionMessage
Write-Log ("Remediation complete with action: {0}" -f $action)

exit 0
