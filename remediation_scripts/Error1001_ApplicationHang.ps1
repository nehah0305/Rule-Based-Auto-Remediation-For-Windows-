# Error1001_ApplicationHang.ps1
# Remediation script for Event ID 1001: an application has stopped responding.

$EVENT_ID = 1001
$DESCRIPTION = 'Application hang'
$EVENT_SOURCE = 'AutoRemediationDemo'
$EVENT_LOG = 'Application'
$LOG_FILE = 'C:\Temp\Event1001_Remediation.log'
$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')

function Write-Log {
    param ([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$timestamp - $Message"
    $line | Out-File -Append -FilePath $LOG_FILE -ErrorAction SilentlyContinue
    Write-Host $line
}

function Get-ProcessNameFromMessage {
    param ([string]$Message)

    if ($env:RM_TARGET_PROCESS) {
        return [System.IO.Path]::GetFileNameWithoutExtension($env:RM_TARGET_PROCESS)
    }

    if ($Message -match '(?:Faulting application name|Application Name):\s*(?<app>[^,\r\n]+)') {
        return [System.IO.Path]::GetFileNameWithoutExtension($Matches.app.Trim())
    }

    if ($Message -match 'Process Name:\s*(?<app>[^,\r\n]+)') {
        return [System.IO.Path]::GetFileNameWithoutExtension($Matches.app.Trim())
    }

    return $null
}

function Get-HungProcesses {
    param ([string]$ProcessName)

    $processes = @()

    try {
        $processes = Get-Process -ErrorAction SilentlyContinue |
            Where-Object { $_.Responding -eq $false }
    }
    catch {
        $processes = @()
    }

    if ($ProcessName) {
        $processes = $processes | Where-Object { $_.ProcessName -ieq $ProcessName -or $_.MainWindowTitle -like "*$ProcessName*" }
    }

    return @($processes)
}

function Write-ResolutionEvent {
    param ([string]$Message)

    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($EVENT_SOURCE)) {
            New-EventLog -LogName $EVENT_LOG -Source $EVENT_SOURCE -ErrorAction SilentlyContinue
        }

        Write-EventLog -LogName $EVENT_LOG -Source $EVENT_SOURCE -EventId 1002 -EntryType Information -Message $Message -ErrorAction Stop
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
$processName = Get-ProcessNameFromMessage -Message $message

Write-Log 'Starting remediation for Event ID 1001 (Application hang).'
Write-Log "Simulation mode: $SIMULATION_MODE"

if ($message) {
    Write-Log "Event message: $($message.Substring(0, [Math]::Min(180, $message.Length)))"
}

if ($processName) {
    Write-Log "Target process inferred: $processName"
}

$hungProcesses = Get-HungProcesses -ProcessName $processName

if ($hungProcesses.Count -gt 0) {
    foreach ($process in $hungProcesses) {
        $displayName = if ($process.ProcessName) { $process.ProcessName } else { $process.Name }
        Write-Log "Hung process detected: $displayName (PID $($process.Id))"

        if ($SIMULATION_MODE) {
            Write-Log "[SIMULATION MODE] Would stop process: $displayName (PID $($process.Id))"
            continue
        }

        $restartPath = $null
        try {
            $restartPath = $process.Path
        }
        catch {
            $restartPath = $null
        }

        try {
            Stop-Process -Id $process.Id -Force -ErrorAction Stop
            Write-Log "Stopped hung process: $displayName"
        }
        catch {
            Write-Log ("WARNING: Could not stop process {0}: {1}" -f $displayName, $_)
        }

        if ($restartPath -and (Test-Path $restartPath)) {
            try {
                Start-Process -FilePath $restartPath -ErrorAction Stop | Out-Null
                Write-Log "Restarted process from path: $restartPath"
            }
            catch {
                Write-Log ("WARNING: Could not restart process from {0}: {1}" -f $restartPath, $_)
            }
        }
        else {
            Write-Log 'Restart path unavailable; manual restart may be required.'
        }
    }
}
else {
    Write-Log 'No hung processes were detected. Running a brief system health check as a fallback.'
    if ($SIMULATION_MODE) {
        Write-Log '[SIMULATION MODE] Would run: sfc /scannow'
    }
    else {
        try {
            sfc /scannow | Out-File -Append -FilePath $LOG_FILE
        }
        catch {
            Write-Log ("WARNING: SFC failed: {0}" -f $_)
        }
    }
}

$timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'
$summary = @"
[EVENT 1001 RESOLVED]
Timestamp        : $timestamp
Description      : $DESCRIPTION
Target Process   : $(if ($processName) { $processName } else { 'Unknown' })
Simulation Mode  : $SIMULATION_MODE
Action Taken     : Hung process termination attempt and optional restart
Auto-remediated by the Rule-Based Auto-Remediation System.
"@

Write-ResolutionEvent -Message $summary
Write-Log 'Remediation complete.'
exit 0