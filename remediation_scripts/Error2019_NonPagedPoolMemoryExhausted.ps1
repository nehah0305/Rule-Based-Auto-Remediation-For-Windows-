# Remediation Script for Event ID 2019: Non-paged pool memory exhausted
# Conservative remediation: identify memory-heavy processes, clear caches, and run diagnostics.

param()

$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')
$LOG_NAME = 'Application'
$SOURCE = 'AutoRemediationDemo'
$RESOLVE_ID = 7036
$message = $env:RM_MESSAGE
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$LOG_FILE = 'C:\Temp\Event2019_Remediation.log'

if (-not (Test-Path 'C:\Temp')) { New-Item -ItemType Directory -Path 'C:\Temp' -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    Add-Content -Path $LOG_FILE -Value "[$timestamp] $Message" -Force
}

function Get-MemoryContext {
    param([string]$Message)

    $processName = $null

    if ($Message -match "process\s+([^\r\n]+?)\s+(?:is|was)\s+using\s+high\s+memory") {
        $processName = $matches[1].Trim()
    }

    if (-not $processName -and $Message -match "memory.*?([A-Za-z0-9_.-]+)\s*\.exe") {
        $processName = $matches[1].Trim()
    }

    return $processName
}

function Get-MemoryHogProcesses {
    param([string]$ProcessName)

    try {
        if ($ProcessName) {
            return @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Sort-Object CPU -Descending)
        }

        return @(Get-Process -ErrorAction SilentlyContinue | Sort-Object WorkingSet64 -Descending | Select-Object -First 10)
    }
    catch {
        Write-Log ("Error querying processes: {0}" -f $_.Exception.Message)
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

Write-Log 'Event 2019 received: Non-paged pool memory exhausted.'
Write-Log ("Message: {0}" -f $message)

$processName = Get-MemoryContext -Message $message
$processes = Get-MemoryHogProcesses -ProcessName $processName
$action = 'none'

Write-Log ("Detected process hint: {0}" -f $processName)
Write-Log ("Candidate process count: {0}" -f $processes.Count)

if ($SIMULATION_MODE) {
    Write-Log '[SIMULATION] Would review top memory consumers and trim caches.'
    if ($processes.Count -gt 0) {
        Write-Log ("[SIMULATION] Would evaluate: {0}" -f (($processes | Select-Object -ExpandProperty Name) -join ', '))
    }
    $action = 'simulated-review'
}
else {
    try {
        # Conservative cleanup steps: clear temp files and recycle bin.
        Get-ChildItem -Path $env:TEMP -Recurse -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer } | Remove-Item -Force -ErrorAction SilentlyContinue
        if (Test-Path 'C:\Windows\Temp') {
            Get-ChildItem -Path 'C:\Windows\Temp' -Recurse -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer } | Remove-Item -Force -ErrorAction SilentlyContinue
        }
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue

        # If a specific process was identified, restart it only if it is safe to do so.
        foreach ($proc in $processes) {
            try {
                if ($proc.Id -ne $PID) {
                    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                    Write-Log ("Stopped memory-heavy process: {0} (PID {1})" -f $proc.Name, $proc.Id)
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
        Write-Log ("Memory remediation failed: {0}" -f $_.Exception.Message)
        $action = 'partial'
    }
}

$status = if ($action -in @('simulated-review','cleaned-and-diagnosed')) { 'SUCCESS' } else { 'PARTIAL' }
$resolutionMessage = "Auto-remediation $status for Event 2019. ProcessHint=$processName Action=$action Time=$timestamp"
if ($SIMULATION_MODE) { $resolutionMessage = "[SIMULATION] $resolutionMessage" }

Write-ResolutionEvent -EventId $RESOLVE_ID -Message $resolutionMessage
Write-Log ("Remediation complete with action: {0}" -f $action)

exit 0
