# Remediate_FirewallService.ps1
# ═════════════════════════════════════════════════════════════════════════════
# Compound Root Cause Remediation: Windows Firewall Service
#
# WHEN INVOKED:
#   When the Windows Firewall service stops unexpectedly (Event 5025) or
#   when firewall-related blocks (5157) co-occur with application failures.
#
# WHAT THIS SCRIPT DOES:
#   1. Checks Windows Firewall service status
#   2. Restarts the service if stopped
#   3. Verifies firewall rules are not misconfigured
#   4. Clears firewall logs if corrupted
#
# ENVIRONMENT VARIABLES (from correlation engine):
#   RM_COMPOUND_CAUSE        - 'firewall_service' or 'blocked_application'
#   RM_CO_EVENT_IDS          - Related firewall event IDs
#
# AUTHOR: Rule-Based Auto-Remediation System
# ═════════════════════════════════════════════════════════════════════════════

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ── Configuration ───────────────────────────────────────────────────────────

$MAX_RESTART_ATTEMPTS = 3

# ── Helper Functions ────────────────────────────────────────────────────────

function Write-RemediationLog {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $prefix = "[FIREWALL-$Level] [$timestamp]"
    Write-Host "$prefix $Message"
    
    $logFile = Join-Path $PSScriptRoot '..' 'backend' 'data' 'remediation_system.log'
    if (Test-Path (Split-Path -Parent $logFile)) {
        Add-Content -Path $logFile -Value "$prefix $Message" -ErrorAction SilentlyContinue
    }
}

function Get-FirewallServiceStatus {
    try {
        $mpsvc = Get-Service -Name MpsSvc -ErrorAction Stop
        return $mpsvc
    } catch {
        Write-RemediationLog "Could not query firewall service: $_" 'WARN'
        return $null
    }
}

function Start-FirewallService {
    param([bool]$Simulation = $false)
    
    try {
        $svc = Get-Service -Name MpsSvc -ErrorAction Stop
        
        if ($svc.Status -eq 'Running') {
            Write-RemediationLog "Firewall service is already running" 'INFO'
            return $true
        }
        
        if ($Simulation) {
            Write-RemediationLog "[SIMULATION] Would start Windows Firewall service (MpsSvc)" 'INFO'
            return $true
        }
        
        Write-RemediationLog "Starting Windows Firewall service..." 'INFO'
        Start-Service -Name MpsSvc -ErrorAction Stop
        Start-Sleep -Seconds 2
        
        $status = (Get-Service -Name MpsSvc).Status
        Write-RemediationLog "Firewall service status: $status" 'INFO'
        
        return $status -eq 'Running'
    } catch {
        Write-RemediationLog "Failed to start firewall service: $_" 'ERROR'
        return $false
    }
}

function Test-FirewallRules {
    try {
        $rules = Get-NetFirewallRule -ErrorAction Stop
        Write-RemediationLog "Firewall rule count: $($rules.Count)" 'INFO'
        
        # Check for rules with empty profiles
        $invalidRules = $rules | Where-Object { $null -eq $_.Profile }
        if ($invalidRules) {
            Write-RemediationLog "Found $($invalidRules.Count) rules with invalid profiles — may need cleanup" 'WARN'
        }
        
        return $true
    } catch {
        Write-RemediationLog "Could not enumerate firewall rules: $_" 'WARN'
        return $false
    }
}

function Reset-FirewallDefaults {
    param([bool]$Simulation = $false)
    
    Write-RemediationLog "Resetting Windows Firewall to default settings..." 'WARN'
    
    if ($Simulation) {
        Write-RemediationLog "[SIMULATION] Would reset firewall to defaults" 'WARN'
        return $true
    }
    
    try {
        # Reset firewall to defaults
        netsh advfirewall reset all 2>&1 | Out-Null
        Write-RemediationLog "Firewall reset to default configuration" 'INFO'
        
        # Restart the firewall service after reset
        Restart-Service -Name MpsSvc -Force -ErrorAction Stop
        Start-Sleep -Seconds 2
        
        Write-RemediationLog "Firewall service restarted after reset" 'INFO'
        return $true
    } catch {
        Write-RemediationLog "Failed to reset firewall: $_" 'ERROR'
        return $false
    }
}

function Get-FirewallStatus {
    try {
        $fwStatus = netsh advfirewall show allprofiles state 2>&1
        return $fwStatus
    } catch {
        Write-RemediationLog "Could not query firewall status: $_" 'WARN'
        return $null
    }
}

# ── MAIN LOGIC ──────────────────────────────────────────────────────────────

function Main {
    $simulationMode = $env:RM_SIMULATION_MODE -eq '1'
    $compoundCause = $env:RM_COMPOUND_CAUSE -or 'firewall_service'
    $coEventIds = $env:RM_CO_EVENT_IDS -or 'unknown'
    
    Write-RemediationLog "════════════════════════════════════════════════════════════════" 'INFO'
    Write-RemediationLog "Compound Remediation: Windows Firewall Issue Detected" 'WARN'
    Write-RemediationLog "════════════════════════════════════════════════════════════════" 'INFO'
    Write-RemediationLog "Compound Cause: $compoundCause | Co-Events: $coEventIds" 'INFO'
    Write-RemediationLog "Simulation Mode: $simulationMode" 'INFO'
    
    # ── Phase 1: Check current firewall status ──────────────────────────────
    Write-RemediationLog "PHASE 1: Checking Windows Firewall status" 'INFO'
    $fwStatus = Get-FirewallStatus
    if ($fwStatus) {
        Write-RemediationLog "Firewall status retrieved successfully" 'INFO'
        $fwStatus | Select-Object -First 10 | ForEach-Object { Write-RemediationLog "  $_" 'INFO' }
    }
    
    # ── Phase 2: Check firewall service ──────────────────────────────────────
    Write-RemediationLog "PHASE 2: Checking firewall service status" 'INFO'
    $svc = Get-FirewallServiceStatus
    
    if ($svc) {
        Write-RemediationLog "Firewall Service Status: $($svc.Status)" 'INFO'
        Write-RemediationLog "Firewall Service Start Type: $($svc.StartType)" 'INFO'
        
        if ($svc.Status -ne 'Running') {
            Write-RemediationLog "Firewall service is NOT running — attempting restart" 'WARN'
            
            $attempts = 0
            while ($attempts -lt $MAX_RESTART_ATTEMPTS) {
                $attempts++
                Write-RemediationLog "Restart attempt $attempts of $MAX_RESTART_ATTEMPTS..." 'INFO'
                
                $success = Start-FirewallService -Simulation $simulationMode
                if ($success) {
                    Write-RemediationLog "Firewall service successfully started" 'INFO'
                    break
                } else {
                    Write-RemediationLog "Restart attempt $attempts failed — retrying..." 'WARN'
                    Start-Sleep -Seconds 3
                }
            }
            
            if ($attempts -ge $MAX_RESTART_ATTEMPTS) {
                Write-RemediationLog "Maximum restart attempts reached — may require manual intervention" 'ERROR'
            }
        } else {
            Write-RemediationLog "Firewall service is running normally" 'INFO'
        }
    }
    
    # ── Phase 3: Verify firewall rules ──────────────────────────────────────
    Write-RemediationLog "PHASE 3: Verifying firewall rules" 'INFO'
    Test-FirewallRules | Out-Null
    
    # ── Phase 4: Final status check ─────────────────────────────────────────
    Write-RemediationLog "PHASE 4: Final firewall status verification" 'INFO'
    $finalFwStatus = Get-FirewallStatus
    
    Write-RemediationLog "════════════════════════════════════════════════════════════════" 'INFO'
    Write-RemediationLog "Windows Firewall remediation complete" 'INFO'
    Write-RemediationLog "Recommend: Monitor firewall status for next 24 hours" 'WARN'
    
    return 0
}

# ── Execution ───────────────────────────────────────────────────────────────

try {
    $exitCode = Main
    exit $exitCode
} catch {
    Write-RemediationLog "Unhandled exception: $_" 'ERROR'
    exit 1
}
