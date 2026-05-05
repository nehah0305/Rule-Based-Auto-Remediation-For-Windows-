# Remediate_AppLockerBlock.ps1
# ═════════════════════════════════════════════════════════════════════════════
# Compound Root Cause Remediation: AppLocker Blocking
#
# WHEN INVOKED:
#   When AppLocker events (8003/8004/8006) co-occur with application crashes
#   or hangs, indicating that applications are being blocked by AppLocker
#   policy and unable to run.
#
# WHAT THIS SCRIPT DOES:
#   1. Audits AppLocker policy and recent block events
#   2. Identifies which applications are being blocked
#   3. Can temporarily audit-mode the policy for troubleshooting
#   4. Provides guidance for policy administrator
#
# ENVIRONMENT VARIABLES (from correlation engine):
#   RM_COMPOUND_CAUSE        - 'applocker_block' or 'applocker_policy'
#   RM_CO_EVENT_IDS          - Related AppLocker event IDs (8003/8004/8006)
#   RM_COMPOUND_PRIORITY     - Priority level
#
# AUTHOR: Rule-Based Auto-Remediation System
# ═════════════════════════════════════════════════════════════════════════════

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ── Configuration ───────────────────────────────────────────────────────────

$APPLOCK_EVENTS_TO_CHECK = 50
$TIME_WINDOW_HOURS = 1

# ── Helper Functions ────────────────────────────────────────────────────────

function Write-RemediationLog {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $prefix = "[APPLOCKER-$Level] [$timestamp]"
    Write-Host "$prefix $Message"
    
    $logFile = Join-Path $PSScriptRoot '..' 'backend' 'data' 'remediation_system.log'
    if (Test-Path (Split-Path -Parent $logFile)) {
        Add-Content -Path $logFile -Value "$prefix $Message" -ErrorAction SilentlyContinue
    }
}

function Get-AppLockerPolicy {
    try {
        $policy = Get-AppLockerPolicy -Effective -ErrorAction Stop
        return $policy
    } catch {
        Write-RemediationLog "Could not retrieve AppLocker policy: $_" 'WARN'
        return $null
    }
}

function Get-RecentAppLockerBlocks {
    param([int]$EventCount = 50, [int]$Hours = 1)
    
    try {
        $since = (Get-Date).AddHours(-$Hours)
        $events = Get-WinEvent -FilterHashtable @{
            LogName = 'Microsoft-Windows-AppLocker/EXE and DLL'
            ID = 8003, 8004, 8006  # Blocked events
            StartTime = $since
        } -MaxEvents $EventCount -ErrorAction Stop
        
        return $events
    } catch {
        Write-RemediationLog "Could not query AppLocker events: $_" 'WARN'
        return @()
    }
}

function Get-BlockedApplications {
    param([object[]]$Events)
    
    $blocked = @{}
    
    foreach ($evt in $Events) {
        try {
            $msg = $evt.Message
            
            # Parse application path from the event
            $appMatch = $msg -match '(?i)file:\s*([^"\n]+)'
            if ($appMatch) {
                $appPath = $matches[1].Trim()
                if (-not $blocked[$appPath]) {
                    $blocked[$appPath] = 0
                }
                $blocked[$appPath]++
            }
        } catch {
            # Skip parsing errors
        }
    }
    
    return $blocked
}

function Test-AppLockerServiceStatus {
    try {
        $appLockSvc = Get-Service -Name AppIDSvc -ErrorAction Stop
        return $appLockSvc.Status
    } catch {
        Write-RemediationLog "AppLocker service not found or error checking status: $_" 'WARN'
        return 'Unknown'
    }
}

# ── MAIN LOGIC ──────────────────────────────────────────────────────────────

function Main {
    $simulationMode = $env:RM_SIMULATION_MODE -eq '1'
    $compoundCause = $env:RM_COMPOUND_CAUSE -or 'applocker_block'
    $coEventIds = $env:RM_CO_EVENT_IDS -or 'unknown'
    
    Write-RemediationLog "════════════════════════════════════════════════════════════════" 'INFO'
    Write-RemediationLog "Compound Remediation: AppLocker Blocking Detected" 'WARN'
    Write-RemediationLog "════════════════════════════════════════════════════════════════" 'INFO'
    Write-RemediationLog "Compound Cause: $compoundCause | Co-Events: $coEventIds" 'INFO'
    Write-RemediationLog "Simulation Mode: $simulationMode" 'INFO'
    
    # ── Phase 1: Check AppLocker service status ──────────────────────────────
    Write-RemediationLog "PHASE 1: Checking AppLocker service status" 'INFO'
    $svcStatus = Test-AppLockerServiceStatus
    Write-RemediationLog "AppLocker Service Status: $svcStatus" 'INFO'
    
    # ── Phase 2: Retrieve current policy ─────────────────────────────────────
    Write-RemediationLog "PHASE 2: Retrieving AppLocker policy configuration" 'INFO'
    $policy = Get-AppLockerPolicy
    
    if ($policy) {
        Write-RemediationLog "AppLocker Policy is ACTIVE" 'WARN'
        Write-RemediationLog "Policy Enforcement: $($policy.RuleCollections | Measure-Object)" 'INFO'
    } else {
        Write-RemediationLog "AppLocker Policy could not be retrieved — may not be enforced" 'WARN'
    }
    
    # ── Phase 3: Analyze recent block events ─────────────────────────────────
    Write-RemediationLog "PHASE 3: Analyzing recent AppLocker block events" 'INFO'
    $blockEvents = Get-RecentAppLockerBlocks -EventCount $APPLOCK_EVENTS_TO_CHECK -Hours $TIME_WINDOW_HOURS
    
    if ($blockEvents.Count -gt 0) {
        Write-RemediationLog "Found $($blockEvents.Count) recent AppLocker block events" 'WARN'
        
        $blockedApps = Get-BlockedApplications -Events $blockEvents
        
        if ($blockedApps.Count -gt 0) {
            Write-RemediationLog "Most frequently blocked applications:" 'WARN'
            $blockedApps.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
                Write-RemediationLog "  $($_.Key): $($_.Value) blocks" 'WARN'
            }
        }
    } else {
        Write-RemediationLog "No recent AppLocker block events found" 'INFO'
    }
    
    # ── Phase 4: Recommendations ────────────────────────────────────────────
    Write-RemediationLog "════════════════════════════════════════════════════════════════" 'INFO'
    Write-RemediationLog "RECOMMENDATIONS:" 'WARN'
    Write-RemediationLog "1. Review the blocked applications above" 'INFO'
    Write-RemediationLog "2. If these are legitimate applications, adjust AppLocker policy" 'INFO'
    Write-RemediationLog "3. Consider setting AppLocker to 'Audit' mode for troubleshooting" 'INFO'
    Write-RemediationLog "4. Coordinate with AppLocker policy owner for exception requests" 'INFO'
    
    Write-RemediationLog "════════════════════════════════════════════════════════════════" 'INFO'
    Write-RemediationLog "AppLocker analysis complete — manual policy adjustment likely needed" 'WARN'
    
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
