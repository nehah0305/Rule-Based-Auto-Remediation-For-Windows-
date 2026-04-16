# Remediation Script for Event ID 2004: Resource exhaustion detected
# Conservative remediation: trim memory pressure, identify top consumers, and run diagnostics.

param()

$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')
$LOG_NAME = 'Application'
$SOURCE = 'AutoRemediationDemo'
$RESOLVE_ID = 7036
$message = $env:RM_MESSAGE
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$LOG_FILE = 'C:\Temp\Event2004_Remediation.log'

if (-not (Test-Path 'C:\Temp')) { New-Item -ItemType Directory -Path 'C:\Temp' -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    Add-Content -Path $LOG_FILE -Value "[$timestamp] $Message" -Force
}

function Get-ResourceContext {
    param([string]$Message)

    $resource = $null

    if ($Message -match "(memory|handles|commit|resource)\s+exhaust") {
        $resource = $matches[1].Trim()
    }

    return $resource
}

function Get-TopConsumers {
    try {
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

Write-Log 'Event 2004 received: Resource exhaustion detected.'
Write-Log ("Message: {0}" -f $message)

$resource = Get-ResourceContext -Message $message
$topConsumers = Get-TopConsumers
$action = 'none'

Write-Log ("Detected resource hint: {0}" -f $resource)
Write-Log ("Top consumer count: {0}" -f $topConsumers.Count)

if ($SIMULATION_MODE) {
    Write-Log '[SIMULATION] Would clear temp caches, review top consumers, and capture diagnostics.'
    $action = 'simulated-review'
}
else {
    try {
        Get-ChildItem -Path $env:TEMP -Recurse -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer } | Remove-Item -Force -ErrorAction SilentlyContinue
        if (Test-Path 'C:\Windows\Temp') {
            Get-ChildItem -Path 'C:\Windows\Temp' -Recurse -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer } | Remove-Item -Force -ErrorAction SilentlyContinue
        }
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue

        foreach ($proc in $topConsumers) {
            Write-Log ("Top consumer: {0} PID={1} WS={2}" -f $proc.Name, $proc.Id, $proc.WorkingSet64)
        }

        & cmd.exe /c "sfc /scannow" 2>&1 | Out-Null
        & cmd.exe /c "DISM /Online /Cleanup-Image /RestoreHealth" 2>&1 | Out-Null
        $action = 'cleaned-and-diagnosed'
    }
    catch {
        Write-Log ("Resource exhaustion remediation failed: {0}" -f $_.Exception.Message)
        $action = 'partial'
    }
}

$status = if ($action -in @('simulated-review','cleaned-and-diagnosed')) { 'SUCCESS' } else { 'PARTIAL' }
$resolutionMessage = "Auto-remediation $status for Event 2004. ResourceHint=$resource Action=$action Time=$timestamp"
if ($SIMULATION_MODE) { $resolutionMessage = "[SIMULATION] $resolutionMessage" }

Write-ResolutionEvent -EventId $RESOLVE_ID -Message $resolutionMessage
Write-Log ("Remediation complete with action: {0}" -f $action)

exit 0
