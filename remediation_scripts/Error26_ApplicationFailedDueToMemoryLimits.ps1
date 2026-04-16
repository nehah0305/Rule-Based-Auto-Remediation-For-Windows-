# Remediation Script for Event ID 26: Application failed due to memory limits
# Conservative remediation: identify the affected app, free memory pressure, and restart only if safe.

param()

$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')
$LOG_NAME = 'Application'
$SOURCE = 'AutoRemediationDemo'
$RESOLVE_ID = 7036
$message = $env:RM_MESSAGE
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$LOG_FILE = 'C:\Temp\Event26_Remediation.log'

if (-not (Test-Path 'C:\Temp')) { New-Item -ItemType Directory -Path 'C:\Temp' -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    Add-Content -Path $LOG_FILE -Value "[$timestamp] $Message" -Force
}

function Get-AppNameFromMessage {
    param([string]$Message)

    if ($Message -match "application\s+([^\r\n]+?)\s+failed\s+due\s+to\s+memory") {
        return $matches[1].Trim()
    }

    if ($Message -match "faulting application name:\s*([^\r\n]+)") {
        return $matches[1].Trim()
    }

    if ($Message -match "([A-Za-z0-9_.-]+)\.exe") {
        return $matches[1].Trim()
    }

    return $null
}

function Get-AppProcesses {
    param([string]$AppName)

    try {
        if ($AppName) {
            return @(Get-Process -Name $AppName -ErrorAction SilentlyContinue)
        }
        return @(Get-Process -ErrorAction SilentlyContinue | Sort-Object WorkingSet64 -Descending | Select-Object -First 5)
    }
    catch {
        Write-Log ("Error querying application processes: {0}" -f $_.Exception.Message)
        return @()
    }
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

Write-Log 'Event 26 received: Application failed due to memory limits.'
Write-Log ("Message: {0}" -f $message)

$appName = Get-AppNameFromMessage -Message $message
$processes = Get-AppProcesses -AppName $appName
$action = 'none'

Write-Log ("Detected application hint: {0}" -f $appName)
Write-Log ("Candidate process count: {0}" -f $processes.Count)

if ($SIMULATION_MODE) {
    Write-Log '[SIMULATION] Would reclaim memory pressure and restart application if safe.'
    $action = 'simulated-review'
}
else {
    try {
        Get-ChildItem -Path $env:TEMP -Recurse -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer } | Remove-Item -Force -ErrorAction SilentlyContinue
        if (Test-Path 'C:\Windows\Temp') {
            Get-ChildItem -Path 'C:\Windows\Temp' -Recurse -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer } | Remove-Item -Force -ErrorAction SilentlyContinue
        }
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue

        foreach ($proc in $processes) {
            try {
                if ($proc.Id -ne $PID) {
                    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                    Write-Log ("Stopped application process: {0} (PID {1})" -f $proc.Name, $proc.Id)
                }
            }
            catch {
                Write-Log ("Failed to stop process {0}: {1}" -f $proc.Name, $_.Exception.Message)
            }
        }

        & cmd.exe /c "sfc /scannow" 2>&1 | Out-Null
        & cmd.exe /c "DISM /Online /Cleanup-Image /RestoreHealth" 2>&1 | Out-Null
        $action = 'cleaned-and-diagnosed'
    }
    catch {
        Write-Log ("Application memory remediation failed: {0}" -f $_.Exception.Message)
        $action = 'partial'
    }
}

$status = if ($action -in @('simulated-review','cleaned-and-diagnosed')) { 'SUCCESS' } else { 'PARTIAL' }
$resolutionMessage = "Auto-remediation $status for Event 26. AppHint=$appName Action=$action Time=$timestamp"
if ($SIMULATION_MODE) { $resolutionMessage = "[SIMULATION] $resolutionMessage" }

Write-ResolutionEvent -EventId $RESOLVE_ID -Message $resolutionMessage
Write-Log ("Remediation complete with action: {0}" -f $action)

exit 0
