# Remediate_SystemRepair_Fallback.ps1
# ═════════════════════════════════════════════════════════════════════════════
# Deep System Repair Fallback for Corrupted Core Windows DLL
#
# WHEN TO USE THIS SCRIPT:
#   When an application crashes due to a faulting module that is a core
#   Windows system DLL (ntdll.dll, kernel32.dll, etc.). In this case,
#   simply restarting the application will create an infinite loop. The
#   problem is not the application — it's the OS itself.
#
# WHAT THIS SCRIPT DOES:
#   1. Logs the event details and faulting module
#   2. Runs sfc /scannow to repair system file corruption
#   3. If sfc fails or detects corruption it can't fix, escalates to DISM
#   4. Provides detailed output and triggers system reboot if needed
#
# ENVIRONMENT VARIABLES (injected by event_log_monitor.py):
#   RM_FAULTING_MODULE          - e.g., "ntdll.dll"
#   RM_ESCALATION_REASON        - Description of why fallback was triggered
#   RM_EVENT_ROW_ID             - Database row ID of the event
#   RM_EVENT_ID                 - Windows Event ID (should be 1000)
#   RM_SOURCE                   - Event source/provider name
#   RM_MESSAGE                  - Event message excerpt
#   RM_SIMULATION_MODE          - Set to '1' to skip actual repairs (test mode)
#
# OUTPUT:
#   Returns exit code 0 if repair successful or system will reboot
#   Returns exit code 1 if repair failed
#
# AUTHOR: Rule-Based Auto-Remediation System
# ═════════════════════════════════════════════════════════════════════════════

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Helper Functions ────────────────────────────────────────────────────────

function Write-RemediationLog {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $prefix = "[SYSREPAIR-$Level] [$timestamp]"
    Write-Host "$prefix $Message"
    
    # Also write to unified log if accessible
    $logFile = Join-Path $PSScriptRoot '..' 'backend' 'data' 'remediation_system.log'
    if (Test-Path (Split-Path -Parent $logFile)) {
        Add-Content -Path $logFile -Value "$prefix $Message" -ErrorAction SilentlyContinue
    }
}

function Test-IsAdministrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Invoke-SFCScannow {
    param([bool]$Simulation = $false)
    
    Write-RemediationLog "Starting System File Checker (sfc /scannow)..." 'INFO'
    
    if ($Simulation) {
        Write-RemediationLog "[SIMULATION] Would run: sfc /scannow /offbootdir=C:\ /offwindir=C:\Windows" 'WARN'
        Start-Sleep -Seconds 2
        Write-RemediationLog "[SIMULATION] sfc scan completed (simulated)" 'INFO'
        return $true
    }
    
    try {
        $proc = Start-Process -FilePath 'sfc.exe' `
            -ArgumentList '/scannow', '/offbootdir=C:\', '/offwindir=C:\Windows' `
            -Wait -PassThru -NoNewWindow
        
        if ($proc.ExitCode -eq 0) {
            Write-RemediationLog "SFC scan completed successfully — no corruption found or corruption repaired" 'INFO'
            return $true
        } elseif ($proc.ExitCode -eq 1) {
            Write-RemediationLog "SFC scan found corruption but was unable to repair all of it" 'WARN'
            return $false  # Escalate to DISM
        } else {
            Write-RemediationLog "SFC scan failed with exit code $($proc.ExitCode)" 'ERROR'
            return $false  # Escalate to DISM
        }
    } catch {
        Write-RemediationLog "Exception running SFC: $_" 'ERROR'
        return $false
    }
}

function Invoke-DISM {
    param([bool]$Simulation = $false)
    
    Write-RemediationLog "Starting DISM Repair..." 'WARN'
    
    if ($Simulation) {
        Write-RemediationLog "[SIMULATION] Would run: DISM /Online /Cleanup-Image /RestoreHealth" 'WARN'
        Start-Sleep -Seconds 3
        Write-RemediationLog "[SIMULATION] DISM repair completed (simulated)" 'INFO'
        return $true
    }
    
    try {
        # First attempt: online repair
        Write-RemediationLog "Running DISM online image repair..." 'INFO'
        $proc1 = Start-Process -FilePath 'DISM.exe' `
            -ArgumentList '/Online', '/Cleanup-Image', '/RestoreHealth' `
            -Wait -PassThru -NoNewWindow
        
        if ($proc1.ExitCode -eq 0) {
            Write-RemediationLog "DISM online repair succeeded" 'INFO'
            return $true
        } else {
            Write-RemediationLog "DISM online repair exit code: $($proc1.ExitCode) — attempting startcomponent repair" 'WARN'
            
            # Second attempt: start component repair
            $proc2 = Start-Process -FilePath 'DISM.exe' `
                -ArgumentList '/Online', '/Cleanup-Image', '/StartComponentCleanup' `
                -Wait -PassThru -NoNewWindow
            
            Write-RemediationLog "DISM component cleanup exit code: $($proc2.ExitCode)" 'INFO'
            return ($proc2.ExitCode -eq 0)
        }
    } catch {
        Write-RemediationLog "Exception running DISM: $_" 'ERROR'
        return $false
    }
}

function Request-SystemReboot {
    param([string]$Reason = 'System repair completed')
    
    Write-RemediationLog "System reboot required for changes to take effect: $Reason" 'WARN'
    Write-RemediationLog "Initiating system reboot in 30 seconds..." 'WARN'
    Write-RemediationLog "To cancel: shutdown /a" 'INFO'
    
    # Graceful reboot with 30-second delay to allow cleanup
    Start-Process -FilePath 'shutdown.exe' `
        -ArgumentList '/r', '/t', '30', '/c', $Reason `
        -WindowStyle Hidden
    
    return $true
}

# ── MAIN LOGIC ──────────────────────────────────────────────────────────────

function Main {
    # Extract environment variables
    $simulationMode = $env:RM_SIMULATION_MODE -eq '1'
    $faultingModule = $env:RM_FAULTING_MODULE -or 'unknown'
    $escalationReason = $env:RM_ESCALATION_REASON -or 'Core OS module crash'
    $eventRowId = $env:RM_EVENT_ROW_ID -or 'N/A'
    $eventId = $env:RM_EVENT_ID -or '1000'
    $source = $env:RM_SOURCE -or 'Unknown'
    
    Write-RemediationLog "════════════════════════════════════════════════════════════════" 'INFO'
    Write-RemediationLog "Deep System Repair Fallback Initiated" 'WARN'
    Write-RemediationLog "════════════════════════════════════════════════════════════════" 'INFO'
    Write-RemediationLog "Event ID: $eventId | Row ID: $eventRowId" 'INFO'
    Write-RemediationLog "Source: $source | Faulting Module: $faultingModule" 'INFO'
    Write-RemediationLog "Reason: $escalationReason" 'INFO'
    Write-RemediationLog "Simulation Mode: $simulationMode" 'INFO'
    
    # Check administrator privileges
    if (-not (Test-IsAdministrator)) {
        Write-RemediationLog "ERROR: This script requires Administrator privileges" 'ERROR'
        return 1
    }
    
    # ── PHASE 1: System File Check (sfc /scannow) ────────────────────────────
    Write-RemediationLog "PHASE 1: System File Check (sfc /scannow)" 'INFO'
    $sfcSuccess = Invoke-SFCScannow -Simulation $simulationMode
    
    if ($sfcSuccess) {
        Write-RemediationLog "SFC repair successful — system integrity restored" 'INFO'
        Write-RemediationLog "════════════════════════════════════════════════════════════════" 'INFO'
        
        # If SFC succeeded, we still should offer reboot to be safe
        if (-not $simulationMode) {
            Write-RemediationLog "Requesting system reboot to ensure all repairs are applied" 'INFO'
            Request-SystemReboot -Reason "System file repair completed — reboot recommended"
        }
        
        return 0
    }
    
    # ── PHASE 2: Deep Image Repair (DISM) ───────────────────────────────────
    Write-RemediationLog "PHASE 2: SFC insufficient — escalating to DISM deep image repair" 'WARN'
    $dismSuccess = Invoke-DISM -Simulation $simulationMode
    
    if ($dismSuccess) {
        Write-RemediationLog "DISM repair successful — system image restored" 'INFO'
        Write-RemediationLog "════════════════════════════════════════════════════════════════" 'INFO'
        
        if (-not $simulationMode) {
            Write-RemediationLog "System reboot required for DISM changes to take effect" 'WARN'
            Request-SystemReboot -Reason "System image repair completed — reboot required"
        }
        
        return 0
    }
    
    # ── If we get here, both sfc and DISM failed ────────────────────────────
    Write-RemediationLog "CRITICAL: Both SFC and DISM failed to repair the system" 'ERROR'
    Write-RemediationLog "Manual intervention required — faulting module may be unrecoverable" 'ERROR'
    Write-RemediationLog "Recommend: Boot into Windows Recovery Environment or reinstall Windows" 'ERROR'
    Write-RemediationLog "════════════════════════════════════════════════════════════════" 'ERROR'
    
    return 1
}

# ── Execution ───────────────────────────────────────────────────────────────

try {
    $exitCode = Main
    exit $exitCode
} catch {
    Write-RemediationLog "Unhandled exception in SystemRepair fallback: $_" 'ERROR'
    exit 1
}

Write-RepairLog 'INFO'  "======================================================="
Write-RepairLog 'INFO'  "System Repair Fallback triggered"
Write-RepairLog 'INFO'  "Original Event ID   : $OriginalEventId"
Write-RepairLog 'INFO'  "Faulting OS module  : $FaultingModule"
Write-RepairLog 'INFO'  "Escalation reason   : $EscalationReason"
if ($CompoundCause) {
    Write-RepairLog 'INFO'  "Compound cause      : $CompoundCause"
    Write-RepairLog 'INFO'  "Co-event IDs        : $CoEventIds"
}
Write-RepairLog 'INFO'  "======================================================="

# ── Step 1: SFC — System File Checker ────────────────────────────────────────
Write-RepairLog 'INFO' "Step 1/2: Running SFC (System File Checker)..."
Write-RepairLog 'INFO' "This verifies and repairs protected Windows system files."

$sfcResult = & cmd.exe /c "sfc /scannow" 2>&1
$sfcOutput = $sfcResult -join "`n"

Write-RepairLog 'INFO' "SFC completed."

$sfcFoundCorruption = ($sfcOutput -match 'found corrupt files' -or
                       $sfcOutput -match 'found integrity violations')
$sfcRepaired        = ($sfcOutput -match 'successfully repaired' -or
                       $sfcOutput -match 'repaired them')
$sfcNoViolations    = ($sfcOutput -match 'did not find any integrity violations')

if ($sfcNoViolations) {
    Write-RepairLog 'INFO'  "SFC: No integrity violations found. OS files are intact."
} elseif ($sfcRepaired) {
    Write-RepairLog 'INFO'  "SFC: Corruption found and successfully repaired."
} elseif ($sfcFoundCorruption) {
    Write-RepairLog 'WARN'  "SFC: Corruption detected but could not fully repair. Escalating to DISM..."
} else {
    Write-RepairLog 'INFO'  "SFC: Scan complete (status inconclusive from output)."
}

# ── Step 2: DISM — if SFC couldn't fully repair ───────────────────────────────
$dismRan    = $false
$dismStatus = 'skipped'

if ($sfcFoundCorruption -and -not $sfcRepaired) {
    Write-RepairLog 'INFO' "Step 2/2: Running DISM to restore Windows component store..."
    Write-RepairLog 'INFO' "DISM /Online /Cleanup-Image /RestoreHealth — this may take several minutes."

    $dismResult = & cmd.exe /c "DISM /Online /Cleanup-Image /RestoreHealth" 2>&1
    $dismOutput = $dismResult -join "`n"
    $dismRan    = $true

    if ($dismOutput -match 'The restore operation completed successfully') {
        $dismStatus = 'success'
        Write-RepairLog 'INFO' "DISM: Component store restored successfully."
    } elseif ($dismOutput -match 'Error') {
        $dismStatus = 'failed'
        Write-RepairLog 'WARN' "DISM: Restoration encountered errors. Manual intervention may be required."
    } else {
        $dismStatus = 'completed'
        Write-RepairLog 'INFO' "DISM: Completed. Review output manually if issues persist."
    }
} else {
    Write-RepairLog 'INFO' "Step 2/2: DISM not required (SFC handled repairs or no corruption found)."
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-RepairLog 'INFO'  "======================================================="
Write-RepairLog 'INFO'  "Repair Summary:"
Write-RepairLog 'INFO'  "  Faulting module : $FaultingModule"
Write-RepairLog 'INFO'  "  SFC result      : $(if ($sfcNoViolations) {'clean'} elseif ($sfcRepaired) {'repaired'} elseif ($sfcFoundCorruption) {'corruption-found'} else {'scan-complete'})"
Write-RepairLog 'INFO'  "  DISM ran        : $dismRan ($dismStatus)"
Write-RepairLog 'INFO'  "  Recommendation  : $(if ($sfcNoViolations -or $sfcRepaired -or $dismStatus -eq 'success') {'System files restored — safe to reboot.'} else {'Manual investigation recommended.'})"
Write-RepairLog 'INFO'  "======================================================="

exit 0
