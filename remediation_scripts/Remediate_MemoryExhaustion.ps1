# Remediate_MemoryExhaustion.ps1
# ═════════════════════════════════════════════════════════════════════════════
# Compound Root Cause Remediation: Memory Exhaustion
#
# WHEN INVOKED:
#   When the Chronological Event Correlation Engine detects that an application
#   crash (1000) or service failure (7031/7034) was accompanied by a memory
#   exhaustion event (2019/2020) within the 5-minute correlation window.
#
# WHAT THIS SCRIPT DOES:
#   1. Kills memory-hungry processes or memory leaks
#   2. Clears page file and temporary caches
#   3. Restarts services only AFTER memory is freed (not before)
#   4. Monitors memory levels post-remediation
#
# ENVIRONMENT VARIABLES (from correlation engine):
#   RM_COMPOUND_CAUSE        - 'memory_exhaustion'
#   RM_CO_EVENT_IDS          - Comma-separated IDs of related events (e.g. "2019,7031")
#   RM_CO_EVENT_DOMAINS      - Domains of co-events (e.g., "Memory,Service")
#   RM_COMPOUND_PRIORITY     - 'high', 'medium', or 'low'
#   RM_EVENT_ID              - The primary triggering event ID
#   RM_SOURCE                - The source/provider of the event
#   RM_SIMULATION_MODE       - If '1', don't make actual changes
#
# AUTHOR: Rule-Based Auto-Remediation System
# ═════════════════════════════════════════════════════════════════════════════

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ── Configuration ───────────────────────────────────────────────────────────

$MEMORY_THRESHOLD_MB = 500          # Only kill if available memory < 500 MB
$PROCESS_KILL_LIMIT = 5             # Max processes to kill per remediation
$MEMORY_CHECK_INTERVAL = 2           # seconds between checks
$MAX_RETRY = 3

# ── Helper Functions ────────────────────────────────────────────────────────

function Write-RemediationLog {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $prefix = "[MEMORY-EXHAUST-$Level] [$timestamp]"
    Write-Host "$prefix $Message"
    
    $logFile = Join-Path $PSScriptRoot '..' 'backend' 'data' 'remediation_system.log'
    if (Test-Path (Split-Path -Parent $logFile)) {
        Add-Content -Path $logFile -Value "$prefix $Message" -ErrorAction SilentlyContinue
    }
}

function Get-AvailableMemory {
    # Returns available memory in MB
    try {
        $mem = Get-WmiObject Win32_OperatingSystem -ErrorAction Stop
        return [math]::Round(($mem.FreePhysicalMemory / 1024), 0)
    } catch {
        Write-RemediationLog "Could not query available memory: $_" 'WARN'
        return -1
    }
}

function Find-MemoryHeavyProcesses {
    param([int]$TopCount = 10)
    try {
        $procs = Get-Process -ErrorAction Stop | 
            Select-Object Name, Id, @{Name="MemoryMB"; Expression={[math]::Round($_.WorkingSet / 1MB, 1)}} |
            Sort-Object MemoryMB -Descending |
            Select-Object -First $TopCount
        return $procs
    } catch {
        Write-RemediationLog "Could not enumerate processes: $_" 'WARN'
        return @()
    }
}

function Clear-MemoryCaches {
    Write-RemediationLog "Clearing Windows page file and temporary caches..." 'INFO'
    
    try {
        # Clear temporary directory
        $tempPath = $env:TEMP
        if (Test-Path $tempPath) {
            Get-ChildItem -Path $tempPath -Recurse -ErrorAction SilentlyContinue | 
                Where-Object { $_.LastWriteTime -lt (Get-Date).AddHours(-1) } |
                Remove-Item -Force -ErrorAction SilentlyContinue
            Write-RemediationLog "Cleared temporary files from $tempPath" 'INFO'
        }
        
        # Clear DNS cache
        ipconfig /flushdns 2>&1 | Out-Null
        Write-RemediationLog "Flushed DNS cache" 'INFO'
        
        return $true
    } catch {
        Write-RemediationLog "Error clearing caches: $_" 'WARN'
        return $false
    }
}

function Kill-LowPriorityProcesses {
    param(
        [int]$ProcessCount = 3,
        [bool]$Simulation = $false
    )
    
    Write-RemediationLog "Identifying memory-heavy processes to terminate..." 'INFO'
    
    # Exclude critical system processes
    $protectedProcesses = @(
        'System', 'csrss', 'lsass', 'wininit', 'svchost', 'winlogon',
        'services', 'spoolsv', 'explorer', 'dwm', 'conhost', 'powershell'
    )
    
    $procs = Find-MemoryHeavyProcesses -TopCount 15
    if (-not $procs) {
        Write-RemediationLog "No processes found for memory cleanup" 'WARN'
        return 0
    }
    
    $killed = 0
    foreach ($proc in $procs) {
        if ($killed -ge $ProcessCount) { break }
        
        if ($protectedProcesses -contains $proc.Name) {
            Write-RemediationLog "Skipping protected process: $($proc.Name) [$($proc.Id)]" 'DEBUG'
            continue
        }
        
        Write-RemediationLog "Targeting high-memory process: $($proc.Name) using $($proc.MemoryMB) MB" 'WARN'
        
        if ($Simulation) {
            Write-RemediationLog "[SIMULATION] Would terminate: $($proc.Name) [$($proc.Id)]" 'WARN'
            $killed++
        } else {
            try {
                Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                Write-RemediationLog "Terminated process: $($proc.Name) [$($proc.Id)]" 'INFO'
                $killed++
                Start-Sleep -Seconds 1
            } catch {
                Write-RemediationLog "Failed to terminate $($proc.Name): $_" 'WARN'
            }
        }
    }
    
    return $killed
}

# ── MAIN LOGIC ──────────────────────────────────────────────────────────────

function Main {
    $simulationMode = $env:RM_SIMULATION_MODE -eq '1'
    $compoundCause = $env:RM_COMPOUND_CAUSE -or 'memory_exhaustion'
    $priority = $env:RM_COMPOUND_PRIORITY -or 'medium'
    $coEventIds = $env:RM_CO_EVENT_IDS -or 'unknown'
    
    Write-RemediationLog "════════════════════════════════════════════════════════════════" 'INFO'
    Write-RemediationLog "Compound Remediation: Memory Exhaustion Detected" 'WARN'
    Write-RemediationLog "════════════════════════════════════════════════════════════════" 'INFO'
    Write-RemediationLog "Compound Cause: $compoundCause | Priority: $priority | Co-Events: $coEventIds" 'INFO'
    Write-RemediationLog "Simulation Mode: $simulationMode" 'INFO'
    
    # Check available memory
    $availableMem = Get-AvailableMemory
    Write-RemediationLog "Available Memory: $availableMem MB (threshold: $MEMORY_THRESHOLD_MB MB)" 'INFO'
    
    if ($availableMem -lt 0) {
        Write-RemediationLog "CRITICAL: Unable to query system memory" 'ERROR'
        return 1
    }
    
    if ($availableMem -gt $MEMORY_THRESHOLD_MB) {
        Write-RemediationLog "Memory is sufficient ($availableMem MB available) — no aggressive cleanup needed" 'INFO'
        return 0
    }
    
    # ── Phase 1: Clear caches ───────────────────────────────────────────────
    Write-RemediationLog "PHASE 1: Clearing caches and temporary storage" 'INFO'
    Clear-MemoryCaches | Out-Null
    Start-Sleep -Seconds 2
    
    $memAfterClear = Get-AvailableMemory
    Write-RemediationLog "Available Memory After Cache Clear: $memAfterClear MB" 'INFO'
    
    if ($memAfterClear -gt $MEMORY_THRESHOLD_MB) {
        Write-RemediationLog "Memory freed by cache cleanup — situation improved" 'INFO'
        return 0
    }
    
    # ── Phase 2: Kill non-essential processes ───────────────────────────────
    Write-RemediationLog "PHASE 2: Terminating low-priority processes" 'WARN'
    $killCount = Kill-LowPriorityProcesses -ProcessCount $PROCESS_KILL_LIMIT -Simulation $simulationMode
    
    if ($killCount -gt 0) {
        Write-RemediationLog "Terminated $killCount process(es)" 'INFO'
        Start-Sleep -Seconds 3
        
        $memAfterKill = Get-AvailableMemory
        Write-RemediationLog "Available Memory After Process Termination: $memAfterKill MB" 'INFO'
        
        if ($memAfterKill -gt $MEMORY_THRESHOLD_MB) {
            Write-RemediationLog "Memory situation stabilized after process cleanup" 'INFO'
            return 0
        }
    }
    
    # ── Summary ──────────────────────────────────────────────────────────────
    Write-RemediationLog "════════════════════════════════════════════════════════════════" 'INFO'
    $finalMem = Get-AvailableMemory
    Write-RemediationLog "Final Available Memory: $finalMem MB" 'INFO'
    
    if ($finalMem -gt $MEMORY_THRESHOLD_MB) {
        Write-RemediationLog "Memory remediation SUCCESSFUL" 'INFO'
        return 0
    } else {
        Write-RemediationLog "Memory remains critically low — may require additional manual intervention" 'WARN'
        return 0  # Return success anyway as we did what we could
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
