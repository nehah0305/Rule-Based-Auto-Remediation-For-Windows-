# Remediation Script for Event ID 7034: Service terminated unexpectedly (per-user/session)
# This script handles Windows Service Control Manager 7034 crashes using dynamic service detection.

param()

$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')
$EVENT_ID = $env:RM_EVENT_ID
$LOG_NAME = 'Application'
$SOURCE = 'AutoRemediationDemo'
$RESOLVE_ID = 7036
$message = $env:RM_MESSAGE
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$LOG_FILE = "C:\Temp\Event7034_Remediation.log"

if (-not (Test-Path 'C:\Temp')) { New-Item -ItemType Directory -Path 'C:\Temp' -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    $msg = "[$timestamp] $Message"
    Add-Content -Path $LOG_FILE -Value $msg -Force
}

function Get-ServiceNameFromMessage {
    param([string]$Message)

    if (-not $Message) { return $null }

    # Pattern: "The <service> service terminated unexpectedly"
    if ($Message -match "The\s+(.+?)\s+service\s+terminated\s+unexpectedly") {
        return $matches[1]
    }

    # Pattern: "service '<name>'"
    if ($Message -match "service\s+'([^']+)'") {
        return $matches[1]
    }

    # Pattern: "Service Name: <name>"
    if ($Message -match "Service\s*Name\s*:\s*([^\r\n]+)") {
        return $matches[1].Trim()
    }

    # Optional caller override
    if ($env:RM_TARGET_SERVICE) {
        return $env:RM_TARGET_SERVICE
    }

    return $null
}

function Get-ServiceObject {
    param([string]$ServiceName)

    if (-not $ServiceName) { return $null }

    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service) { return $service }

    $service = Get-Service -DisplayName $ServiceName -ErrorAction SilentlyContinue
    return $service
}

function Write-ResolutionEvent {
    param(
        [int]$EventId,
        [string]$Message
    )

    try {
        Write-EventLog -LogName $LOG_NAME `
                       -Source $SOURCE `
                       -EventId $EventId `
                       -EntryType 'Information' `
                       -Message $Message `
                       -ErrorAction Stop
    }
    catch {
        Write-Log ("Error writing event: {0}" -f $_.Exception.Message)
    }
}

Write-Log "Event 7034 received: Service terminated unexpectedly"
Write-Log "Injected Event ID: $EVENT_ID"
Write-Log "Message: $message"

$serviceName = Get-ServiceNameFromMessage -Message $message
Write-Log "Extracted service name: $serviceName"

$service = $null
$remediationSucceeded = $false

if ($serviceName) {
    $service = Get-ServiceObject -ServiceName $serviceName

    if ($service) {
        Write-Log "Service found: $($service.Name) (Display: $($service.DisplayName), Status: $($service.Status))"

        if ($SIMULATION_MODE) {
            Write-Log "[SIMULATION] Would restart service: $($service.Name)"
            $remediationSucceeded = $true
        }
        else {
            try {
                if ($service.Status -eq 'Running') {
                    Restart-Service -Name $service.Name -Force -ErrorAction Stop
                    Write-Log "Restarted running service: $($service.Name)"
                }
                else {
                    Start-Service -Name $service.Name -ErrorAction Stop
                    Write-Log "Started stopped service: $($service.Name)"
                }

                Set-Service -Name $service.Name -StartupType 'Automatic' -ErrorAction SilentlyContinue
                Write-Log "Ensured startup type Automatic for: $($service.Name)"

                $service.Refresh()
                if ($service.Status -eq 'Running') {
                    $remediationSucceeded = $true
                    Write-Log "Service confirmed running after remediation."
                }
            }
            catch {
                Write-Log ("Service restart/start failed: {0}" -f $_.Exception.Message)
            }
        }
    }
    else {
        Write-Log "Service not found for parsed name: $serviceName"
    }
}
else {
    Write-Log "Could not parse service name from event message."
}

if (-not $remediationSucceeded) {
    Write-Log "Applying fallback diagnostics."

    if ($SIMULATION_MODE) {
        Write-Log "[SIMULATION] Would run: sfc /scannow"
        Write-Log "[SIMULATION] Would run: DISM /Online /Cleanup-Image /RestoreHealth"
    }
    else {
        & cmd.exe /c "sfc /scannow" 2>&1 | Out-Null
        & cmd.exe /c "DISM /Online /Cleanup-Image /RestoreHealth" 2>&1 | Out-Null
        Write-Log "Fallback diagnostics executed."
    }
}

$statusText = if ($remediationSucceeded) { 'SUCCESS' } else { 'PARTIAL' }
$resolvedService = if ($service -and $service.Name) { $service.Name } elseif ($serviceName) { $serviceName } else { 'UnknownService' }

$resolutionMessage = "Auto-remediation $statusText for Event 7034. Service=$resolvedService. Completed at $timestamp."
if ($SIMULATION_MODE) {
    $resolutionMessage = "[SIMULATION] $resolutionMessage"
}

Write-ResolutionEvent -EventId $RESOLVE_ID -Message $resolutionMessage
Write-Log "Remediation complete with status: $statusText"

exit 0
