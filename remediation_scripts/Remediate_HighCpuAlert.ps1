# Remediate_HighCpuAlert.ps1
# -------------------------------------------------------------------------
# Remediates a simulated "High CPU Alert" (Event ID 9999) that was injected
# by Simulate_HighCpuAlert.ps1.
#
# What it does (simulation-safe):
#   1. Writes a resolution event (Event ID 9998) to the Windows Application log.
#   2. Terminates any processes matching 'DemoWorkload' (safe – only simulation stub).
#   3. Reports the remediation result to stdout for capture by the engine.
#
# Environment variables available (injected by models.run_remediation):
#   $env:RM_EVENT_ID, $env:RM_SOURCE, $env:RM_MESSAGE, $env:RM_SEVERITY,
#   $env:RM_SIMULATION_MODE ('1' for simulation events, '0' for real)
# -------------------------------------------------------------------------

$EVENT_SOURCE    = 'AutoRemediationDemo'
$EVENT_LOG       = 'Application'
$ALERT_EVENT_ID  = 9999
$RESOLVE_EVENT_ID = 9998

# Context from the remediation engine (PS 5.1-compatible fallbacks)
if ($env:RM_EVENT_ID) { $eventId = $env:RM_EVENT_ID } else { $eventId = [string]$ALERT_EVENT_ID }
if ($env:RM_SOURCE)   { $source  = $env:RM_SOURCE   } else { $source  = $EVENT_SOURCE }
$simMode   = ($env:RM_SIMULATION_MODE -eq '1')

Write-Host "============================================================"
Write-Host "  High CPU Alert Remediation Script"
Write-Host "============================================================"
Write-Host "[START] Initiating remediation for Event ID $eventId from $source"
Write-Host "[INFO]  Simulation Mode: $simMode"
Write-Host "------------------------------------------------------------"

# STEP 1 — Confirm the alert event exists
Write-Host "[STEP 1] Checking for outstanding CPU alert events..."
$existingEvents = @()
try {
    $existingEvents = Get-WinEvent -LogName $EVENT_LOG `
        -FilterHashTable @{ Id = $ALERT_EVENT_ID; ProviderName = $EVENT_SOURCE } `
        -MaxEvents 5 -ErrorAction SilentlyContinue
    if ($existingEvents.Count -gt 0) {
        Write-Host "[FOUND]  $($existingEvents.Count) outstanding High CPU Alert event(s) in $EVENT_LOG log."
    } else {
        Write-Host "[INFO]   No outstanding events found in log (already cleared or source not registered)."
    }
} catch {
    Write-Host "[WARN]   Could not query event log: $_"
}

# STEP 2 — Terminate any stub demo process
Write-Host "[STEP 2] Checking for DemoWorkload.exe simulation process..."
try {
    $demoProcs = Get-Process -Name 'DemoWorkload' -ErrorAction SilentlyContinue
    if ($demoProcs) {
        foreach ($p in $demoProcs) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            Write-Host "[OK]    Terminated DemoWorkload.exe (PID $($p.Id))"
        }
    } else {
        Write-Host "[INFO]  No DemoWorkload.exe process running (expected for simulation)."
    }
} catch {
    Write-Host "[WARN]  Error stopping demo process: $_"
}

# STEP 3 — Simulate CPU pressure reduction
Write-Host "[STEP 3] Applying CPU throttle policy (simulation)..."
Start-Sleep -Milliseconds 300  # Simulate brief work
Write-Host "[OK]    CPU usage normalizing: 100% → 12% (simulated)"
Write-Host "[OK]    System scheduler rebalanced across all logical cores."

# STEP 4 — Write resolution event to Windows Event Log
Write-Host "[STEP 4] Writing resolution event (ID $RESOLVE_EVENT_ID) to $EVENT_LOG log..."
$timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'
$resolveMessage = @"
[HIGH CPU ALERT RESOLVED] CPU spike has been remediated successfully.

  Timestamp       : $timestamp
  Original EventID: $ALERT_EVENT_ID
  Resolution ID   : $RESOLVE_EVENT_ID
  Source          : $EVENT_SOURCE
  Action Taken    : Process throttle + CPU scheduler rebalance (simulation)
  CPU After Fix   : ~12% (normalized)

Auto-remediated by the Rule-Based Auto-Remediation System.
"@

try {
    # Register source if needed
    if (-not [System.Diagnostics.EventLog]::SourceExists($EVENT_SOURCE)) {
        New-EventLog -LogName $EVENT_LOG -Source $EVENT_SOURCE -ErrorAction SilentlyContinue
    }
    Write-EventLog `
        -LogName    $EVENT_LOG `
        -Source     $EVENT_SOURCE `
        -EventId    $RESOLVE_EVENT_ID `
        -EntryType  'Information' `
        -Message    $resolveMessage `
        -ErrorAction Stop
    Write-Host "[OK]    Resolution event written to Windows Application Log."
} catch {
    Write-Host "[WARN]  Could not write resolution event (may need Admin rights): $_"
}

# STEP 5 — Final status report
Write-Host "------------------------------------------------------------"
Write-Host "[DONE] Remediation complete."
Write-Host "  Events processed : 1"
Write-Host "  Actions taken    : CPU throttle, process check, log resolution"
Write-Host "  Result           : SUCCESS"
Write-Host "============================================================"
exit 0
