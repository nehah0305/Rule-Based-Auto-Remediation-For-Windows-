# Error1026_DotNetRuntimeCrash.ps1
# Remediation script for Event ID 1026: a .NET application terminated due to an unhandled exception.

$EVENT_ID = 1026
$DESCRIPTION = '.NET runtime crash'
$EVENT_SOURCE = 'AutoRemediationDemo'
$EVENT_LOG = 'Application'
$LOG_FILE = 'C:\Temp\Event1026_Remediation.log'
$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')

function Write-Log {
    param ([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$timestamp - $Message"
    $line | Out-File -Append -FilePath $LOG_FILE -ErrorAction SilentlyContinue
    Write-Host $line
}

function Get-AppNameFromMessage {
    param ([string]$Message)

    if ($env:RM_TARGET_PROCESS) {
        return [System.IO.Path]::GetFileNameWithoutExtension($env:RM_TARGET_PROCESS)
    }

    if ($Message -match '(?:Application|Faulting application) name:\s*(?<app>[^,\r\n]+)') {
        return [System.IO.Path]::GetFileNameWithoutExtension($Matches.app.Trim())
    }

    if ($Message -match 'Process:\s*(?<app>[^,\r\n]+)') {
        return [System.IO.Path]::GetFileNameWithoutExtension($Matches.app.Trim())
    }

    return $null
}

function Get-DotNetEvents {
    param ([int]$Count = 10)

    try {
        return Get-WinEvent -LogName Application -FilterHashTable @{ Id = $EVENT_ID } -MaxEvents $Count -ErrorAction SilentlyContinue |
            Sort-Object TimeCreated -Descending
    }
    catch {
        return @()
    }
}

function Write-ResolutionEvent {
    param ([string]$Message)

    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($EVENT_SOURCE)) {
            New-EventLog -LogName $EVENT_LOG -Source $EVENT_SOURCE -ErrorAction SilentlyContinue
        }

        Write-EventLog -LogName $EVENT_LOG -Source $EVENT_SOURCE -EventId 1027 -EntryType Information -Message $Message -ErrorAction Stop
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
$appName = Get-AppNameFromMessage -Message $message

Write-Log 'Starting remediation for Event ID 1026 (.NET runtime crash).'
Write-Log "Simulation mode: $SIMULATION_MODE"

if ($message) {
    Write-Log "Event message: $($message.Substring(0, [Math]::Min(180, $message.Length)))"
}

if ($appName) {
    Write-Log "Application inferred: $appName"
}

$recentEvents = Get-DotNetEvents -Count 5
if ($recentEvents.Count -gt 0) {
    Write-Log "Found $($recentEvents.Count) recent .NET Runtime event(s) for review."
}

if ($SIMULATION_MODE) {
    Write-Log '[SIMULATION MODE] Would run: sfc /scannow'
    Write-Log '[SIMULATION MODE] Would run: DISM /Online /Cleanup-Image /RestoreHealth'
}
else {
    try {
        sfc /scannow | Out-File -Append -FilePath $LOG_FILE
    }
    catch {
        Write-Log ("WARNING: SFC failed: {0}" -f $_)
    }

    try {
        DISM /Online /Cleanup-Image /RestoreHealth | Out-File -Append -FilePath $LOG_FILE
    }
    catch {
        Write-Log ("WARNING: DISM failed: {0}" -f $_)
    }
}

if ($appName) {
    $runningProcess = $null
    try {
        $runningProcess = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -ieq $appName } | Select-Object -First 1
    }
    catch {
        $runningProcess = $null
    }

    if ($runningProcess) {
        Write-Log "Process is still running: $($runningProcess.ProcessName)"
        if ($SIMULATION_MODE) {
            Write-Log "[SIMULATION MODE] Would restart process: $($runningProcess.ProcessName)"
        }
        else {
            $restartPath = $null
            try {
                $restartPath = $runningProcess.Path
            }
            catch {
                $restartPath = $null
            }

            try {
                Stop-Process -Id $runningProcess.Id -Force -ErrorAction Stop
                Write-Log "Stopped process: $($runningProcess.ProcessName)"
            }
            catch {
                Write-Log ("WARNING: Could not stop process {0}: {1}" -f $($runningProcess.ProcessName), $_)
            }

            if ($restartPath -and (Test-Path $restartPath)) {
                try {
                    Start-Process -FilePath $restartPath -ErrorAction Stop | Out-Null
                    Write-Log "Restarted application from path: $restartPath"
                }
                catch {
                    Write-Log ("WARNING: Could not restart application from {0}: {1}" -f $restartPath, $_)
                }
            }
        }
    }
}

$timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'
$summary = @"
[EVENT 1026 RESOLVED]
Timestamp        : $timestamp
Description      : $DESCRIPTION
Application      : $(if ($appName) { $appName } else { 'Unknown' })
Simulation Mode  : $SIMULATION_MODE
Action Taken     : .NET crash review, system integrity checks, optional process restart
Auto-remediated by the Rule-Based Auto-Remediation System.
"@

Write-ResolutionEvent -Message $summary
Write-Log 'Remediation complete.'
exit 0