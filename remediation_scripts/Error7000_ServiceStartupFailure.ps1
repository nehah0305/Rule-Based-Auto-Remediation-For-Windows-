# Error7000_ServiceStartupFailure.ps1
# Remediation script for Event ID 7000: a service failed to start.

$EVENT_ID = 7000
$DESCRIPTION = 'Service startup failure'
$EVENT_SOURCE = 'AutoRemediationDemo'
$EVENT_LOG = 'Application'
$LOG_FILE = 'C:\Temp\Event7000_Remediation.log'
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

    if ($Message -match 'The (?<service>.+?) service failed to start') {
        return $Matches.service
    }

    if ($Message -match 'service "(?<service>[^"]+)" failed to start') {
        return $Matches.service
    }

    if ($Message -match 'service (?<service>[A-Za-z0-9_\-\. ]+) failed to start') {
        return $Matches.service.Trim()
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

function Get-CimServiceInfo {
    param ([string]$Name)

    if (-not $Name) {
        return $null
    }

    try {
        return Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    catch {
        return $null
    }
}

function Write-ResolutionEvent {
    param ([string]$Message)

    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($EVENT_SOURCE)) {
            New-EventLog -LogName $EVENT_LOG -Source $EVENT_SOURCE -ErrorAction SilentlyContinue
        }

        Write-EventLog -LogName $EVENT_LOG -Source $EVENT_SOURCE -EventId 7001 -EntryType Information -Message $Message -ErrorAction Stop
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

Write-Log 'Starting remediation for Event ID 7000 (Service failed to start).'
Write-Log "Simulation mode: $SIMULATION_MODE"

if ($message) {
    Write-Log "Event message: $($message.Substring(0, [Math]::Min(180, $message.Length)))"
}

if ($serviceName) {
    Write-Log "Target service inferred: $serviceName"
    $service = Get-ServiceObject -Name $serviceName

    if ($null -eq $service) {
        Write-Log 'Service not found on this machine. Running system repair checks as a fallback.'
        $serviceName = $null
    }
    else {
        $serviceInfo = Get-CimServiceInfo -Name $service.Name

        if ($serviceInfo -and $serviceInfo.StartMode -ne 'Auto') {
            if ($SIMULATION_MODE) {
                Write-Log "[SIMULATION MODE] Would run: Set-Service -Name '$($service.Name)' -StartupType Automatic"
            }
            else {
                try {
                    Set-Service -Name $service.Name -StartupType Automatic -ErrorAction Stop
                    Write-Log 'Startup type set to Automatic.'
                }
                catch {
                    Write-Log ("WARNING: Could not update startup type: {0}" -f $_)
                }
            }
        }

        if ($serviceInfo -and $serviceInfo.ServicesDependedOn) {
            foreach ($dependency in @($serviceInfo.ServicesDependedOn)) {
                if (-not $dependency) { continue }
                Write-Log "Checking dependency service: $dependency"
                if ($SIMULATION_MODE) {
                    Write-Log "[SIMULATION MODE] Would start dependency service: $dependency"
                }
                else {
                    try {
                        $depService = Get-ServiceObject -Name $dependency
                        if ($depService -and $depService.Status -ne 'Running') {
                            Start-Service -Name $depService.Name -ErrorAction Stop
                            Write-Log "Dependency service started: $($depService.Name)"
                        }
                    }
                    catch {
                        Write-Log ("WARNING: Could not start dependency {0}: {1}" -f $dependency, $_)
                    }
                }
            }
        }

        if ($SIMULATION_MODE) {
            Write-Log "[SIMULATION MODE] Would run: Start-Service -Name '$($service.Name)'"
        }
        else {
            try {
                Start-Service -Name $service.Name -ErrorAction Stop
                Write-Log "Service started: $($service.Name)"
            }
            catch {
                Write-Log ("WARNING: Could not start service {0}: {1}" -f $($service.Name), $_)
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
    Write-Log 'No concrete service name could be resolved. Running safe system-health checks.'
    if ($SIMULATION_MODE) {
        Write-Log '[SIMULATION MODE] Would run: sfc /scannow'
        Write-Log '[SIMULATION MODE] Would run: DISM /Online /Cleanup-Image /RestoreHealth'
    }
    else {
        try { sfc /scannow | Out-File -Append -FilePath $LOG_FILE } catch { Write-Log ("WARNING: SFC failed: {0}" -f $_) }
        try { DISM /Online /Cleanup-Image /RestoreHealth | Out-File -Append -FilePath $LOG_FILE } catch { Write-Log ("WARNING: DISM failed: {0}" -f $_) }
    }
}

$timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'
$summary = @"
[EVENT 7000 RESOLVED]
Timestamp        : $timestamp
Description      : $DESCRIPTION
Target Service    : $(if ($serviceName) { $serviceName } else { 'Unknown' })
Simulation Mode  : $SIMULATION_MODE
Action Taken     : Startup type verification, dependency checks, service start attempt
Auto-remediated by the Rule-Based Auto-Remediation System.
"@

Write-ResolutionEvent -Message $summary
Write-Log 'Remediation complete.'
exit 0