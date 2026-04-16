# Remediation Script for Event ID 7045: New service installed
# This script performs a conservative safety response for newly installed services.
# It validates service binary location and disables only clearly suspicious installs.

param()

$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')
$LOG_NAME = 'Application'
$SOURCE = 'AutoRemediationDemo'
$RESOLVE_ID = 7036
$message = $env:RM_MESSAGE
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$LOG_FILE = 'C:\Temp\Event7045_Remediation.log'

if (-not (Test-Path 'C:\Temp')) { New-Item -ItemType Directory -Path 'C:\Temp' -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    Add-Content -Path $LOG_FILE -Value "[$timestamp] $Message" -Force
}

function Get-NewServiceContext {
    param([string]$Message)

    $name = $null

    if (-not $Message) {
        return [PSCustomObject]@{ ServiceName = $null }
    }

    if ($Message -match "Service\s+Name\s*:\s*([^\r\n]+)") {
        $name = $matches[1].Trim()
    }

    if (-not $name -and $Message -match "A\s+service\s+was\s+installed\s+in\s+the\s+system\.?\s*Service\s+Name\s*:\s*([^\r\n]+)") {
        $name = $matches[1].Trim()
    }

    if (-not $name -and $Message -match "service\s+'([^']+)'") {
        $name = $matches[1].Trim()
    }

    return [PSCustomObject]@{ ServiceName = $name }
}

function Get-ServiceBinaryPath {
    param([string]$ServiceName)

    if (-not $ServiceName) { return $null }

    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
        $raw = (Get-ItemProperty -Path $regPath -Name 'ImagePath' -ErrorAction Stop).ImagePath
        if (-not $raw) { return $null }

        $clean = $raw.Trim()
        if ($clean.StartsWith('"')) {
            $first = $clean.IndexOf('"', 1)
            if ($first -gt 1) { return $clean.Substring(1, $first - 1) }
        }

        return ($clean -split '\s+')[0]
    }
    catch {
        Write-Log ("Could not read ImagePath for service {0}: {1}" -f $ServiceName, $_.Exception.Message)
        return $null
    }
}

function Is-SuspiciousPath {
    param([string]$Path)

    if (-not $Path) { return $true }

    $p = $Path.ToLowerInvariant()

    if ($p -like '*\appdata\local\temp\*') { return $true }
    if ($p -like '*\users\*\downloads\*') { return $true }
    if ($p -like '*\temp\*') { return $true }

    return $false
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

Write-Log 'Event 7045 received: New service installed.'
Write-Log ("Message: {0}" -f $message)

$ctx = Get-NewServiceContext -Message $message
$serviceName = $ctx.ServiceName
$action = 'none'
$binaryPath = $null

if ($serviceName) {
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($svc) {
        $binaryPath = Get-ServiceBinaryPath -ServiceName $serviceName
        Write-Log ("Service found: {0} (Status: {1})" -f $svc.Name, $svc.Status)
        Write-Log ("ImagePath: {0}" -f $binaryPath)

        $suspicious = Is-SuspiciousPath -Path $binaryPath

        if ($suspicious) {
            if ($SIMULATION_MODE) {
                Write-Log ("[SIMULATION] Would stop and disable suspicious service: {0}" -f $svc.Name)
                $action = 'simulated-disabled-suspicious'
            }
            else {
                try {
                    if ($svc.Status -eq 'Running') {
                        Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
                    }
                    Set-Service -Name $svc.Name -StartupType 'Disabled' -ErrorAction Stop
                    Write-Log ("Suspicious service disabled: {0}" -f $svc.Name)
                    $action = 'disabled-suspicious'
                }
                catch {
                    Write-Log ("Failed to disable suspicious service: {0}" -f $_.Exception.Message)
                    $action = 'failed-disable'
                }
            }
        }
        else {
            Write-Log 'Service path appears non-suspicious; audit only.'
            $action = 'audited-safe-install'
        }
    }
    else {
        Write-Log ("Service not found by name after install event: {0}" -f $serviceName)
        $action = 'service-not-found'
    }
}
else {
    Write-Log 'Could not parse service name from event message.'
    $action = 'parse-failed'
}

$status = if ($action -in @('audited-safe-install','disabled-suspicious','simulated-disabled-suspicious')) { 'SUCCESS' } else { 'PARTIAL' }
$resolutionMessage = "Auto-remediation $status for Event 7045. Service=$serviceName ImagePath=$binaryPath Action=$action Time=$timestamp"
if ($SIMULATION_MODE) { $resolutionMessage = "[SIMULATION] $resolutionMessage" }

Write-ResolutionEvent -EventId $RESOLVE_ID -Message $resolutionMessage
Write-Log ("Remediation complete with action: {0}" -f $action)

exit 0
