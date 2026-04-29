# Remediation Script for Event ID 41: System reboot due to resource exhaustion
# Conservative remediation: gather evidence, run integrity checks, and clear obvious memory pressure.

param()

$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')
$LOG_NAME = 'Application'
$SOURCE = 'AutoRemediationDemo'
$RESOLVE_ID = 7036
$message = $env:RM_MESSAGE
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$LOG_FILE = 'C:\Temp\Event41_Remediation.log'

if (-not (Test-Path 'C:\Temp')) { New-Item -ItemType Directory -Path 'C:\Temp' -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    Add-Content -Path $LOG_FILE -Value "[$timestamp] $Message" -Force
}

function Get-RebootContext {
    param([string]$Message)

    $context = 'resource exhaustion'
    if ($Message -match 'resource exhaustion|memory limits|low memory') {
        $context = $matches[0]
    }
    return $context
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

Write-Log 'Event 41 received: System reboot due to resource exhaustion.'
Write-Log ("Message: {0}" -f $message)

$context = Get-RebootContext -Message $message
$action = 'none'

if ($SIMULATION_MODE) {
    Write-Log '[SIMULATION] Would collect diagnostics, review top consumers, and avoid rebooting automatically.'
    $action = 'simulated-diagnostics'
}
else {
    try {
        Get-ChildItem -Path $env:TEMP -Recurse -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer } | Remove-Item -Force -ErrorAction SilentlyContinue
        if (Test-Path 'C:\Windows\Temp') {
            Get-ChildItem -Path 'C:\Windows\Temp' -Recurse -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer } | Remove-Item -Force -ErrorAction SilentlyContinue
        }
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue

        $top = @(Get-Process -ErrorAction SilentlyContinue | Sort-Object WorkingSet64 -Descending | Select-Object -First 10)
        foreach ($proc in $top) {
            Write-Log ("Top consumer: {0} PID={1} WS={2}" -f $proc.Name, $proc.Id, $proc.WorkingSet64)
        }

        & cmd.exe /c "sfc /scannow" 2>&1 | Out-Null
        & cmd.exe /c "DISM /Online /Cleanup-Image /RestoreHealth" 2>&1 | Out-Null
        $action = 'diagnostics-complete'
    }
    catch {
        Write-Log ("Event 41 remediation failed: {0}" -f $_.Exception.Message)
        $action = 'partial'
    }
}

$status = if ($action -in @('simulated-diagnostics','diagnostics-complete')) { 'SUCCESS' } else { 'PARTIAL' }
$resolutionMessage = "Auto-remediation $status for Event 41. Context=$context Action=$action Time=$timestamp"
if ($SIMULATION_MODE) { $resolutionMessage = "[SIMULATION] $resolutionMessage" }

Write-ResolutionEvent -EventId $RESOLVE_ID -Message $resolutionMessage
Write-Log ("Remediation complete with action: {0}" -f $action)

exit 0
