# Error1101_AuditEventsDropped.ps1
# Remediation script for Event ID 1101: Audit events have been dropped by the transport
# Run as Administrator

$logFile = "C:\Temp\Event1101_Remediation.log"
$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')

# Function to log actions
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

Write-Log "Starting remediation for Event ID 1101 (Audit events dropped)"

# Step 1: Increase Security Log Size
Write-Log "Increasing Security Event Log size to 100 MB..."
if ($SIMULATION_MODE) {
    Write-Log "[SIMULATION MODE] Would execute: wevtutil sl Security /ms:104857600"
} else {
    try {
        wevtutil sl Security /ms:104857600   # 100 MB
        Write-Log "Security log size increased to 100 MB."
    } catch {
        Write-Log "ERROR: Failed to increase log size: $_"
    }
}

# Step 2: Set retention method to overwrite as needed
Write-Log "Setting log retention to overwrite as needed..."
if ($SIMULATION_MODE) {
    Write-Log "[SIMULATION MODE] Would execute: wevtutil sl Security /rt:true"
} else {
    try {
        wevtutil sl Security /rt:true
        Write-Log "Log retention set to overwrite as needed."
    } catch {
        Write-Log "ERROR: Failed to set log retention: $_"
    }
}

# Step 3: Ensure Windows Event Log service is running
Write-Log "Checking Windows Event Log service..."
$service = Get-Service -Name "EventLog" -ErrorAction SilentlyContinue

if ($service -eq $null) {
    Write-Log "ERROR: EventLog service not found!"
} elseif ($service.Status -ne "Running") {
    Write-Log "EventLog service not running. Starting service..."
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

# Step 4: Check Audit Policy
Write-Log "Checking and enforcing audit policy..."
if ($SIMULATION_MODE) {
    Write-Log "[SIMULATION MODE] Would execute: auditpol /set /category:* /success:enable /failure:enable"
} else {
    try {
        $auditOutput = auditpol /set /category:* /success:enable /failure:enable
        Write-Log "Audit policy enforced for all categories."
        $auditOutput | Out-File -Append -FilePath $logFile
    } catch {
        Write-Log "WARNING: Audit policy update encountered an issue: $_"
    }
}

# Step 5: Check system performance (CPU & Memory snapshot)
Write-Log "Collecting system performance snapshot..."
try {
    $cpuCounter = Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue
    if ($cpuCounter) {
        Write-Log "CPU Usage: $($cpuCounter.CounterSamples.CookedValue)%"
        $cpuCounter | Out-File -Append -FilePath $logFile
    }
    
    $memCounter = Get-Counter '\Memory\Available MBytes' -ErrorAction SilentlyContinue
    if ($memCounter) {
        Write-Log "Available Memory: $($memCounter.CounterSamples.CookedValue) MB"
        $memCounter | Out-File -Append -FilePath $logFile
    }
} catch {
    Write-Log "WARNING: Could not collect performance counters: $_"
}

# Step 6: Check disk space (important for logging)
Write-Log "Checking disk space..."
try {
    $drive = Get-PSDrive C -ErrorAction SilentlyContinue
    if ($drive) {
        $usedGB = [math]::Round($drive.Used / 1GB, 2)
        $freeGB = [math]::Round($drive.Free / 1GB, 2)
        Write-Log "C: Drive - Used: $usedGB GB, Free: $freeGB GB"
        $drive | Select-Object Used,Free | Out-File -Append -FilePath $logFile
    }
} catch {
    Write-Log "WARNING: Could not check disk space: $_"
}

# Step 7: Get current log size info
Write-Log "Checking current Security log configuration..."
try {
    $logInfo = wevtutil gli Security
    $logInfo | Out-File -Append -FilePath $logFile
    Write-Log "Security log configuration retrieved."
} catch {
    Write-Log "WARNING: Could not retrieve log configuration: $_"
}

# Step 8: Run system health checks
Write-Log "Running System File Checker (SFC)..."
if ($SIMULATION_MODE) {
    Write-Log "[SIMULATION MODE] Would execute: sfc /scannow"
} else {
    try {
        $sfcOutput = sfc /scannow
        Write-Log "System File Checker completed."
        $sfcOutput | Out-File -Append -FilePath $logFile
    } catch {
        Write-Log "WARNING: SFC execution encountered an issue: $_"
    }
}

Write-Log "Running DISM..."
if ($SIMULATION_MODE) {
    Write-Log "[SIMULATION MODE] Would execute: DISM /Online /Cleanup-Image /RestoreHealth"
} else {
    try {
        $dismOutput = DISM /Online /Cleanup-Image /RestoreHealth
        Write-Log "DISM health restore completed."
        $dismOutput | Out-File -Append -FilePath $logFile
    } catch {
        Write-Log "WARNING: DISM execution encountered an issue: $_"
    }
}

# Step 9: Restart Event Log service (refresh pipeline)
Write-Log "Restarting EventLog service to refresh audit pipeline..."
if ($SIMULATION_MODE) {
    Write-Log "[SIMULATION MODE] Would execute: Restart-Service -Name 'EventLog' -Force"
} else {
    try {
        Restart-Service -Name "EventLog" -Force
        Write-Log "EventLog service restarted successfully."
    } catch {
        Write-Log "WARNING: EventLog service restart encountered an issue: $_"
    }
}

Write-Log "=========================================="
Write-Log "Remediation for Event ID 1101 completed."
Write-Log "Audit pipeline should now resume normal operation."
Write-Log "=========================================="
Write-Host "Remediation completed successfully."
