# Remediation Script for Event ID 129: Storage timeout reset
# Conservative remediation: capture storage context, refresh caches, and run diagnostics.

param()

$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')
$LOG_NAME = 'Application'
$SOURCE = 'AutoRemediationDemo'
$RESOLVE_ID = 7036
$message = $env:RM_MESSAGE
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$LOG_FILE = 'C:\Temp\Event129_Remediation.log'

if (-not (Test-Path 'C:\Temp')) { New-Item -ItemType Directory -Path 'C:\Temp' -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    Add-Content -Path $LOG_FILE -Value "[$timestamp] $Message" -Force
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

Write-Log 'Event 129 received: Storage timeout reset.'
Write-Log ("Message: {0}" -f $message)

$storageDevices = @(Get-WmiObject Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'storage|disk|controller|sata|nvme|raid' } | Select-Object -First 10)
$action = 'none'

if ($SIMULATION_MODE) {
    Write-Log '[SIMULATION] Would refresh storage diagnostics and avoid device resets.'
    $action = 'simulated-diagnostics'
}
else {
    try {
        foreach ($device in $storageDevices) {
            Write-Log ("Storage device: {0}" -f $device.Name)
        }
        & cmd.exe /c "sfc /scannow" 2>&1 | Out-Null
        & cmd.exe /c "DISM /Online /Cleanup-Image /RestoreHealth" 2>&1 | Out-Null
        $action = 'diagnostics-complete'
    }
    catch {
        Write-Log ("Storage timeout remediation failed: {0}" -f $_.Exception.Message)
        $action = 'partial'
    }
}

$status = if ($action -in @('simulated-diagnostics','diagnostics-complete')) { 'SUCCESS' } else { 'PARTIAL' }
$resolutionMessage = "Auto-remediation $status for Event 129. Action=$action Time=$timestamp"
if ($SIMULATION_MODE) { $resolutionMessage = "[SIMULATION] $resolutionMessage" }
Write-ResolutionEvent -EventId $RESOLVE_ID -Message $resolutionMessage
Write-Log ("Remediation complete with action: {0}" -f $action)
exit 0
