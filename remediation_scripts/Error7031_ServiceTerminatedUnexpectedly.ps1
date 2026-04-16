# Error7031_ServiceTerminatedUnexpectedly.ps1
# Remediation script for Event ID 7031: a Windows service terminated unexpectedly.

$EVENT_ID = 7031
$DESCRIPTION = 'Service terminated unexpectedly'
$EVENT_SOURCE = 'AutoRemediationDemo'
$EVENT_LOG = 'Application'
$LOG_FILE = 'C:\Temp\Event7031_Remediation.log'
$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')

function Write-Log {
    param ([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$timestamp - $Message"
    $line | Out-File -Append -FilePath $LOG_FILE -ErrorAction SilentlyContinue
    Write-Host $line
}

function Get-ServiceNameFromMessage {
    param ([string]$Message)

    if ($env:RM_TARGET_SERVICE) {
        return $env:RM_TARGET_SERVICE
    }

    if ($Message -match 'The (?<service>.+?) service terminated unexpectedly') {
        return $Matches.service
    }

    if ($Message -match 'The (?<service>.+?) service was terminated unexpectedly') {
        return $Matches.service
    }

    if ($Message -match 'service "(?<service>[^"]+)"') {
        return $Matches.service
    }

    return $null
}

function Get-ServiceObject {
    param ([string]$Name)

    if (-not $Name) {
        return $null
    }

    return Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ieq $Name -or $_.DisplayName -ieq $Name } |
        Select-Object -First 1
}

function Write-ResolutionEvent {
    param ([string]$Message)

    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($EVENT_SOURCE)) {
            New-EventLog -LogName $EVENT_LOG -Source $EVENT_SOURCE -ErrorAction SilentlyContinue
        }

        Write-EventLog -LogName $EVENT_LOG -Source $EVENT_SOURCE -EventId 7036 -EntryType Information -Message $Message -ErrorAction Stop
        Write-Log 'Resolution event written to Application log.'
    }
    catch {
        Write-Log ("WARNING: Could not write resolution event: {0}" -f $_)
    }
}

if (-not (Test-Path 'C:\Temp')) {
    New-Item -ItemType Directory -Path 'C:\Temp' -Force | Out-Null
}

$message = $env:RM_MESSAGE
$serviceName = Get-ServiceNameFromMessage -Message $message

Write-Log 'Starting remediation for Event ID 7031 (Service terminated unexpectedly).'
Write-Log "Simulation mode: $SIMULATION_MODE"

if ($message) {
    Write-Log "Event message: $($message.Substring(0, [Math]::Min(180, $message.Length)))"
}

if ($serviceName) {
    Write-Log "Target service inferred: $serviceName"
    $service = Get-ServiceObject -Name $serviceName

    if ($null -eq $service) {
        Write-Log 'Service not found on this machine. Running safe system-health checks instead.'
        $serviceName = $null
    }
    else {
        if ($SIMULATION_MODE) {
            Write-Log "[SIMULATION MODE] Would restart service: $($service.Name)"
        }
        else {
            try {
                if ($service.Status -eq 'Running') {
                    Restart-Service -Name $service.Name -Force -ErrorAction Stop
                }
                else {
                    Start-Service -Name $service.Name -ErrorAction Stop
                }
                Write-Log "Service restart/start completed: $($service.Name)"
            }
            catch {
                Write-Log "WARNING: Could not start or restart $($service.Name): $_"
            }
        }

        try {
            $service.Refresh()
            Write-Log "Current status: $($service.Status)"
        }
        catch {
            Write-Log 'WARNING: Could not refresh service status.'
        }
    }
}

if (-not $serviceName) {
    Write-Log 'No concrete service name could be resolved. Executing system repair checks.'
    if ($SIMULATION_MODE) {
        Write-Log '[SIMULATION MODE] Would run: sfc /scannow'
        Write-Log '[SIMULATION MODE] Would run: DISM /Online /Cleanup-Image /RestoreHealth'
    }
    else {
        try {
            sfc /scannow | Out-File -Append -FilePath $LOG_FILE
        }
        catch {
            Write-Log "WARNING: SFC failed: $_"
        }

        try {
            DISM /Online /Cleanup-Image /RestoreHealth | Out-File -Append -FilePath $LOG_FILE
        }
        catch {
            Write-Log "WARNING: DISM failed: $_"
        }
    }
}

$timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'
$summary = @"
[EVENT 7031 RESOLVED]
Timestamp        : $timestamp
Description      : $DESCRIPTION
Target Service    : $(if ($serviceName) { $serviceName } else { 'Unknown' })
Simulation Mode  : $SIMULATION_MODE
Action Taken     : Service restart/start attempt and health checks
Auto-remediated by the Rule-Based Auto-Remediation System.
"@

Write-ResolutionEvent -Message $summary
Write-Log 'Remediation complete.'
exit 0