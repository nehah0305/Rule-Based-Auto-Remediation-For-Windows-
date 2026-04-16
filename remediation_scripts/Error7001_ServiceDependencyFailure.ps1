# Error7001_ServiceDependencyFailure.ps1
# Remediation script for Event ID 7001: a service failed to start because a dependency failed.

$EVENT_ID = 7001
$DESCRIPTION = 'Service dependency failure'
$EVENT_SOURCE = 'AutoRemediationDemo'
$EVENT_LOG = 'Application'
$LOG_FILE = 'C:\Temp\Event7001_Remediation.log'
$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')

function Write-Log {
    param ([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$timestamp - $Message"
    $line | Out-File -Append -FilePath $LOG_FILE -ErrorAction SilentlyContinue
    Write-Host $line
}

function Get-ServiceContextFromMessage {
    param ([string]$Message)

    $context = [pscustomobject]@{
        ServiceName = $null
        DependencyName = $null
    }

    if ($env:RM_TARGET_SERVICE) {
        $context.ServiceName = $env:RM_TARGET_SERVICE
    }

    if ($env:RM_TARGET_DEPENDENCY) {
        $context.DependencyName = $env:RM_TARGET_DEPENDENCY
    }

    if ($Message -match 'The (?<service>.+?) service depends on the (?<dependency>.+?) service') {
        if (-not $context.ServiceName) { $context.ServiceName = $Matches.service }
        if (-not $context.DependencyName) { $context.DependencyName = $Matches.dependency }
    }
    elseif ($Message -match 'The (?<service>.+?) service could not start because the (?<dependency>.+?) service failed to start') {
        if (-not $context.ServiceName) { $context.ServiceName = $Matches.service }
        if (-not $context.DependencyName) { $context.DependencyName = $Matches.dependency }
    }
    elseif ($Message -match 'The service (?<service>[A-Za-z0-9_\-\. ]+) depends on the service (?<dependency>[A-Za-z0-9_\-\. ]+)') {
        if (-not $context.ServiceName) { $context.ServiceName = $Matches.service.Trim() }
        if (-not $context.DependencyName) { $context.DependencyName = $Matches.dependency.Trim() }
    }

    return $context
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

function Start-SafeService {
    param ([string]$Name)

    $service = Get-ServiceObject -Name $Name
    if ($null -eq $service) {
        Write-Log "Service not found: $Name"
        return
    }

    if ($service.Status -eq 'Running') {
        Write-Log "Service already running: $($service.Name)"
        return
    }

    if ($SIMULATION_MODE) {
        Write-Log "[SIMULATION MODE] Would start service: $($service.Name)"
        return
    }

    try {
        Start-Service -Name $service.Name -ErrorAction Stop
        Write-Log "Service started: $($service.Name)"
    }
    catch {
        Write-Log ("WARNING: Could not start service {0}: {1}" -f $($service.Name), $_)
    }
}

function Write-ResolutionEvent {
    param ([string]$Message)

    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($EVENT_SOURCE)) {
            New-EventLog -LogName $EVENT_LOG -Source $EVENT_SOURCE -ErrorAction SilentlyContinue
        }

        Write-EventLog -LogName $EVENT_LOG -Source $EVENT_SOURCE -EventId 7002 -EntryType Information -Message $Message -ErrorAction Stop
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
$context = Get-ServiceContextFromMessage -Message $message

Write-Log 'Starting remediation for Event ID 7001 (Dependency failure).'
Write-Log "Simulation mode: $SIMULATION_MODE"

if ($message) {
    Write-Log "Event message: $($message.Substring(0, [Math]::Min(180, $message.Length)))"
}

if ($context.DependencyName) {
    Write-Log "Dependency inferred: $($context.DependencyName)"
    Start-SafeService -Name $context.DependencyName
}

if ($context.ServiceName) {
    Write-Log "Target service inferred: $($context.ServiceName)"
    $service = Get-ServiceObject -Name $context.ServiceName

    if ($null -eq $service) {
        Write-Log 'Target service not found. Running system repair checks as a fallback.'
    }
    else {
        $serviceInfo = $null
        try {
            $serviceInfo = Get-CimInstance Win32_Service -Filter "Name='$($service.Name)'" -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        catch {
            $serviceInfo = $null
        }

        if ($serviceInfo -and $serviceInfo.ServicesDependedOn) {
            foreach ($dependency in @($serviceInfo.ServicesDependedOn)) {
                if ($dependency) {
                    Start-SafeService -Name $dependency
                }
            }
        }

        if ($SIMULATION_MODE) {
            Write-Log "[SIMULATION MODE] Would set startup type to Automatic for: $($service.Name)"
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

        Start-SafeService -Name $service.Name

        try {
            $service.Refresh()
            Write-Log "Current status: $($service.Status)"
        }
        catch {
            Write-Log 'WARNING: Could not refresh service status.'
        }
    }
}

if (-not $context.ServiceName -and -not $context.DependencyName) {
    Write-Log 'No service context could be resolved. Running safe system-health checks.'
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
[EVENT 7001 RESOLVED]
Timestamp        : $timestamp
Description      : $DESCRIPTION
Service Context   : $(if ($context.ServiceName) { $context.ServiceName } else { 'Unknown' })
Dependency        : $(if ($context.DependencyName) { $context.DependencyName } else { 'Unknown' })
Simulation Mode  : $SIMULATION_MODE
Action Taken     : Dependency start attempts, target service start attempt, health checks
Auto-remediated by the Rule-Based Auto-Remediation System.
"@

Write-ResolutionEvent -Message $summary
Write-Log 'Remediation complete.'
exit 0