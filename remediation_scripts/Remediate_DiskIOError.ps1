# Remediate_DiskIOError.ps1
# ═════════════════════════════════════════════════════════════════════════════
# Compound Root Cause Remediation: Disk I/O Error
#
# WHEN INVOKED:
#   When multiple disk-related errors co-occur (e.g., Event 11 Disk Controller
#   Error + Event 51 Disk Paging Error, or Event 55 NTFS Corruption).
#   This indicates potential hardware failure or filesystem corruption.
#
# WHAT THIS SCRIPT DOES:
#   1. Checks disk health status via Windows Storage diagnostics
#   2. Runs CHKDSK on affected volumes to detect filesystem corruption
#   3. Schedules CHKDSK to run at next boot if corruption found
#   4. Monitors disk queue length and I/O latency
#
# ENVIRONMENT VARIABLES (from correlation engine):
#   RM_COMPOUND_CAUSE        - 'disk_io_error' or 'ntfs_corruption'
#   RM_CO_EVENT_IDS          - Related disk event IDs
#   RM_COMPOUND_PRIORITY     - Priority level
#
# AUTHOR: Rule-Based Auto-Remediation System
# ═════════════════════════════════════════════════════════════════════════════

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ── Configuration ───────────────────────────────────────────────────────────

$CHKDSK_TARGET_DRIVE = 'C:'
$IO_LATENCY_THRESHOLD_MS = 100

# ── Helper Functions ────────────────────────────────────────────────────────

function Write-RemediationLog {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $prefix = "[DISK-IO-$Level] [$timestamp]"
    Write-Host "$prefix $Message"
    
    $logFile = Join-Path $PSScriptRoot '..' 'backend' 'data' 'remediation_system.log'
    if (Test-Path (Split-Path -Parent $logFile)) {
        Add-Content -Path $logFile -Value "$prefix $Message" -ErrorAction SilentlyContinue
    }
}

function Get-DiskHealthStatus {
    try {
        $disks = Get-WmiObject Win32_DiskDrive -ErrorAction Stop
        $results = @()
        
        foreach ($disk in $disks) {
            $results += @{
                Name = $disk.Name
                Status = $disk.Status
                Availability = $disk.Availability
            }
        }
        return $results
    } catch {
        Write-RemediationLog "Could not query disk health: $_" 'WARN'
        return @()
    }
}

function Get-DiskIOMetrics {
    try {
        # Get Physical Disk performance counters
        $disks = Get-WmiObject Win32_PerfFormattedData_PerfDisk_PhysicalDisk -ErrorAction Stop |
            Where-Object { $_.Name -notmatch '_total' } |
            Select-Object Name, @{Name="QueueLength"; Expression={$_.CurrentDiskQueueLength}}, 
                          @{Name="AvgResponseTime_ms"; Expression={[math]::Round($_.AvgDiskSecPerRead * 1000, 2)}}
        return $disks
    } catch {
        Write-RemediationLog "Could not query I/O metrics: $_" 'WARN'
        return @()
    }
}

function Test-DiskVolume {
    param([string]$DriveLetter = 'C:')
    
    Write-RemediationLog "Running CHKDSK scan on $DriveLetter..." 'INFO'
    
    try {
        # Try read-only check first
        $result = cmd /c chkdsk $DriveLetter 2>&1
        
        if ($result -match 'corruption|error|problem' -or $result -match 'Status: FAILED') {
            Write-RemediationLog "CHKDSK found potential issues — scheduling repair at next boot" 'WARN'
            
            # Schedule repair for next boot
            cmd /c chkdsk $DriveLetter /f /sched /scan 2>&1 | Out-Null
            Write-RemediationLog "Disk check scheduled for next system restart" 'INFO'
            
            return $false  # Issues found
        } else {
            Write-RemediationLog "CHKDSK completed — no corruption detected" 'INFO'
            return $true  # No issues
        }
    } catch {
        Write-RemediationLog "Error running CHKDSK: $_" 'WARN'
        return $false
    }
}

function Restart-StorageServices {
    param([bool]$Simulation = $false)
    
    Write-RemediationLog "Restarting storage-related services..." 'INFO'
    
    $services = @('Disk', 'spaceport', 'storvsp')  # Storage driver/filter services
    
    foreach ($svc in $services) {
        try {
            $serviceObj = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($serviceObj) {
                if ($Simulation) {
                    Write-RemediationLog "[SIMULATION] Would restart service: $svc" 'INFO'
                } else {
                    Write-RemediationLog "Restarting service: $svc" 'INFO'
                    Restart-Service -Name $svc -Force -ErrorAction SilentlyContinue
                }
            }
        } catch {
            Write-RemediationLog "Could not restart $svc service: $_" 'WARN'
        }
    }
}

# ── MAIN LOGIC ──────────────────────────────────────────────────────────────

function Main {
    $simulationMode = $env:RM_SIMULATION_MODE -eq '1'
    $compoundCause = $env:RM_COMPOUND_CAUSE -or 'disk_io_error'
    $coEventIds = $env:RM_CO_EVENT_IDS -or 'unknown'
    
    Write-RemediationLog "════════════════════════════════════════════════════════════════" 'INFO'
    Write-RemediationLog "Compound Remediation: Disk I/O Error Detected" 'WARN'
    Write-RemediationLog "════════════════════════════════════════════════════════════════" 'INFO'
    Write-RemediationLog "Compound Cause: $compoundCause | Co-Events: $coEventIds" 'INFO'
    Write-RemediationLog "Simulation Mode: $simulationMode" 'INFO'
    
    # ── Phase 1: Check disk health status ────────────────────────────────────
    Write-RemediationLog "PHASE 1: Checking disk health status" 'INFO'
    $healthStatus = Get-DiskHealthStatus
    
    foreach ($disk in $healthStatus) {
        $status = $disk.Status -eq 'OK' ? 'HEALTHY' : 'ERROR'
        Write-RemediationLog "Disk $($disk.Name): $status" 'INFO'
    }
    
    # ── Phase 2: Monitor I/O metrics ─────────────────────────────────────────
    Write-RemediationLog "PHASE 2: Monitoring I/O performance metrics" 'INFO'
    $ioMetrics = Get-DiskIOMetrics
    
    foreach ($disk in $ioMetrics) {
        Write-RemediationLog "$($disk.Name): Queue=$($disk.QueueLength), Latency=$($disk.AvgResponseTime_ms)ms" 'INFO'
    }
    
    # ── Phase 3: Test disk volume integrity ──────────────────────────────────
    Write-RemediationLog "PHASE 3: Testing disk volume integrity" 'INFO'
    $volumeOK = Test-DiskVolume -DriveLetter $CHKDSK_TARGET_DRIVE
    
    # ── Phase 4: Restart storage services ────────────────────────────────────
    Write-RemediationLog "PHASE 4: Restarting storage services for recovery" 'INFO'
    Restart-StorageServices -Simulation $simulationMode
    
    Write-RemediationLog "════════════════════════════════════════════════════════════════" 'INFO'
    Write-RemediationLog "Disk I/O remediation complete" 'INFO'
    
    if ($volumeOK) {
        Write-RemediationLog "Disk appears healthy — no immediate action required" 'INFO'
        return 0
    } else {
        Write-RemediationLog "Disk issues detected — check scheduled for next reboot" 'WARN'
        Write-RemediationLog "Recommend: Restart system at earliest convenience for deep repair" 'WARN'
        return 0
    }
}

# ── Execution ───────────────────────────────────────────────────────────────

try {
    $exitCode = Main
    exit $exitCode
} catch {
    Write-RemediationLog "Unhandled exception: $_" 'ERROR'
    exit 1
}
