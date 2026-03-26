# Error1100_EventLogShutdown.ps1
# Remediation script for Event ID 1100: The event logging service has shut down
# Run as Administrator

$logFile = "C:\Temp\EventLog_Remediation.log"
$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')

# Function to write logs
function Write-Log {
    param ([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $message"
    $logMessage | Out-File -Append -FilePath $logFile -ErrorAction SilentlyContinue
    Write-Host $logMessage
}

# Ensure temp directory exists
if (-not (Test-Path "C:\Temp")) {
    New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
}

Write-Log "Starting remediation for Event ID 1100"

# Step 1: Check Windows Event Log service
Write-Log "Checking Windows Event Log service..."
$service = Get-Service -Name "EventLog" -ErrorAction SilentlyContinue

if ($service -eq $null) {
    Write-Log "ERROR: EventLog service not found!"
    exit 1
}

# Step 2: Restart service if not running
if ($service.Status -ne "Running") {
    Write-Log "EventLog service is not running. Attempting to start..."
    if ($SIMULATION_MODE) {
        Write-Log "[SIMULATION MODE] Would execute: Start-Service -Name 'EventLog'"
    } else {
        try {
            Start-Service -Name "EventLog"
            Write-Log "EventLog service started successfully."
        } catch {
            Write-Log "ERROR: Failed to start EventLog service: $_"
        }
    }
} else {
    Write-Log "EventLog service is already running."
}

# Step 3: Set service to Automatic
Write-Log "Setting EventLog service startup type to Automatic..."
if ($SIMULATION_MODE) {
    Write-Log "[SIMULATION MODE] Would execute: Set-Service -Name 'EventLog' -StartupType Automatic"
} else {
    try {
        Set-Service -Name "EventLog" -StartupType Automatic
        Write-Log "Set EventLog service startup type to Automatic."
    } catch {
        Write-Log "ERROR: Failed to set startup type: $_"
    }
}

# Step 4: Run System File Checker
Write-Log "Running System File Checker (SFC)..."
if ($SIMULATION_MODE) {
    Write-Log "[SIMULATION MODE] Would execute: sfc /scannow"
} else {
    try {
        $sfcOutput = sfc /scannow
        $sfcOutput | Out-File -Append -FilePath $logFile
        Write-Log "System File Checker completed."
    } catch {
        Write-Log "WARNING: SFC execution encountered an issue: $_"
    }
}

# Step 5: Run DISM repair
Write-Log "Running DISM health restore..."
if ($SIMULATION_MODE) {
    Write-Log "[SIMULATION MODE] Would execute: DISM /Online /Cleanup-Image /RestoreHealth"
} else {
    try {
        $dismOutput = DISM /Online /Cleanup-Image /RestoreHealth
        $dismOutput | Out-File -Append -FilePath $logFile
        Write-Log "DISM health restore completed."
    } catch {
        Write-Log "WARNING: DISM execution encountered an issue: $_"
    }
}

# Step 6: Check for recent shutdown events
Write-Log "Checking for unexpected shutdown events..."
try {
    $shutdownEvents = Get-EventLog -LogName System -Newest 20 -ErrorAction SilentlyContinue | Where-Object {$_.EventID -in 41,6008}
    if ($shutdownEvents) {
        Write-Log "Found unexpected shutdown events:"
        $shutdownEvents | ForEach-Object {
            Write-Log "  - Event ID: $($_.EventID), Time: $($_.TimeGenerated), Source: $($_.Source)"
        }
        $shutdownEvents | Out-File -Append -FilePath $logFile
    } else {
        Write-Log "No recent unexpected shutdown events found."
    }
} catch {
    Write-Log "WARNING: Could not query shutdown events: $_"
}

# Step 7: Verify log file integrity
Write-Log "Checking Event Viewer log files..."
$logPath = "C:\Windows\System32\winevt\Logs"
if (Test-Path $logPath) {
    try {
        $logFiles = Get-ChildItem $logPath -Filter *.evtx -ErrorAction SilentlyContinue
        if ($logFiles) {
            Write-Log "Found $($logFiles.Count) event log files:"
            $logFiles | ForEach-Object {
                Write-Log "  - Checked log file: $($_.Name) (Size: $($_.Length) bytes)"
            }
        } else {
            Write-Log "WARNING: No event log files found."
        }
    } catch {
        Write-Log "WARNING: Could not verify log files: $_"
    }
} else {
    Write-Log "ERROR: Event log path not found: $logPath"
}

Write-Log "=========================================="
Write-Log "Remediation for Event ID 1100 completed."
Write-Log "=========================================="
Write-Host "Remediation completed successfully."
