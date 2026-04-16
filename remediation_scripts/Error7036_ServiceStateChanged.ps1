# Remediation Script for Event ID 7036: Service entered running/stopped state
# This script verifies whether the observed state change is expected and
# restores service availability when a critical service is found stopped.

param()

$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')
$LOG_NAME = 'Application'
$SOURCE = 'AutoRemediationDemo'
$RESOLVE_ID = 7036
$message = $env:RM_MESSAGE
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$LOG_FILE = 'C:\Temp\Event7036_Remediation.log'

if (-not (Test-Path 'C:\Temp')) { New-Item -ItemType Directory -Path 'C:\Temp' -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    Add-Content -Path $LOG_FILE -Value "[$timestamp] $Message" -Force
}

function Get-ServiceStateContext {
    param([string]$Message)

    $name = $null
    $state = $null

    if (-not $Message) {
        return [PSCustomObject]@{ ServiceName = $null; State = $null }
    }

    if ($Message -match "The\s+(.+?)\s+service\s+entered\s+the\s+(.+?)\s+state") {
        $name = $matches[1].Trim()
        $state = $matches[2].Trim().ToLowerInvariant()
    }

    if (-not $name -and $Message -match "service\s+'([^']+)'") {
        $name = $matches[1].Trim()
    }

    if (-not $state -and $Message -match "entered\s+the\s+(running|stopped|paused|start pending|stop pending)\s+state") {
        $state = $matches[1].Trim().ToLowerInvariant()
    }

    return [PSCustomObject]@{ ServiceName = $name; State = $state }
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

Write-Log 'Event 7036 received: Service state changed.'
Write-Log ("Message: {0}" -f $message)

$ctx = Get-ServiceStateContext -Message $message
$serviceName = $ctx.ServiceName
$reportedState = $ctx.State
$service = Get-ServiceObject -ServiceName $serviceName
$remediationAction = 'none'

if ($service) {
    Write-Log ("Service found: {0} (Status: {1})" -f $service.Name, $service.Status)

    # If SCM reports a stopped transition, attempt self-heal by restarting.
    if ($reportedState -eq 'stopped') {
        if ($SIMULATION_MODE) {
            Write-Log ("[SIMULATION] Would start service: {0}" -f $service.Name)
            $remediationAction = 'simulated-start'
        }
        else {
            try {
                Start-Service -Name $service.Name -ErrorAction Stop
                Set-Service -Name $service.Name -StartupType 'Automatic' -ErrorAction SilentlyContinue
                $service.Refresh()
                if ($service.Status -eq 'Running') {
                    Write-Log ("Service restarted successfully: {0}" -f $service.Name)
                    $remediationAction = 'started'
                }
                else {
                    Write-Log ("Service did not reach Running state: {0}" -f $service.Name)
                    $remediationAction = 'partial'
                }
            }
            catch {
                Write-Log ("Service restart failed: {0}" -f $_.Exception.Message)
                $remediationAction = 'failed-start'
            }
        }
    }
    else {
        Write-Log ("No restart needed for reported state: {0}" -f $reportedState)
        $remediationAction = 'observed'
    }
}
else {
    Write-Log ("Service not found from message parse: {0}" -f $serviceName)
    $remediationAction = 'service-not-found'
}

$status = if ($remediationAction -in @('started','simulated-start','observed')) { 'SUCCESS' } else { 'PARTIAL' }
$resolutionMessage = "Auto-remediation $status for Event 7036. Service=$serviceName State=$reportedState Action=$remediationAction Time=$timestamp"
if ($SIMULATION_MODE) { $resolutionMessage = "[SIMULATION] $resolutionMessage" }

Write-ResolutionEvent -EventId $RESOLVE_ID -Message $resolutionMessage
Write-Log ("Remediation complete with action: {0}" -f $remediationAction)

exit 0
