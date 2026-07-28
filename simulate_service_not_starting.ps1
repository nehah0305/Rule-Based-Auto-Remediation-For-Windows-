<#
.SYNOPSIS
    Simulate a Service Startup Failure (Event 7000: "Restart. Service not starting manually")
    and trigger immediate auto-remediation / approval request.

.DESCRIPTION
    This script does 4 things in sequence:
      1. Verifies the Flask backend is online.
      2. Logs the simulation target service ("Service not starting manually").
      3. Writes a realistic Event ID 7000 entry to the Windows Application Event Log
         (without requiring Administrator rights, exactly like simulate_crash.ps1).
      4. Calls the backend /api/monitor/trigger to instantly process the new event.

    This generates an Approval Gate Request in the frontend, displaying a floating
    yellow pop-up banner with a direct "GO TO APPROVALS PAGE" button.

.PARAMETER ServiceName
    Name of the simulated faulting service (default: "MyTestService").

.PARAMETER BackendUrl
    Base URL of the Flask backend (default: http://localhost:5000).

.EXAMPLE
    .\simulate_service_not_starting.ps1
    .\simulate_service_not_starting.ps1 -ServiceName "PrintSpoolerDemo"
#>

param(
    [string]$ServiceName = "MyTestService",
    [string]$BackendUrl  = "http://localhost:5000"
)

$ErrorActionPreference = 'Continue'

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   SERVICE NOT STARTING SIMULATOR" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1 — Verify Backend is alive
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "[1/4] Checking backend at $BackendUrl ..." -ForegroundColor Yellow
try {
    $health = Invoke-WebRequest -Uri "$BackendUrl/api/health" -UseBasicParsing -TimeoutSec 5
    Write-Host "      [OK] Backend is online" -ForegroundColor Green
} catch {
    Write-Host "      [FAIL] Cannot reach backend: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "      Make sure the Flask backend is running (.\run_backend.ps1)" -ForegroundColor Yellow
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 — Simulating Service Start Failure
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[2/4] Simulating manual start failure for '$ServiceName' ..." -ForegroundColor Yellow
Write-Host "      [INFO] Condition: Service not starting manually (Event ID 7000)." -ForegroundColor Gray

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3 — Write Event ID 7000 to Windows Application Event Log
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[3/4] Writing Event ID 7000 (Service Startup Failure) for '$ServiceName' ..." -ForegroundColor Yellow

$ProcessId = Get-Random -Minimum 1000 -Maximum 65535
$Message   = "The $ServiceName service failed to start manually. Service not starting manually. Error 0x80070422: The service cannot be started, either because it is disabled or because it has no enabled devices associated with it."

try {
    $log        = New-Object System.Diagnostics.EventLog("Application")
    $log.Source = "Application Error"
    $log.WriteEntry($Message, [System.Diagnostics.EventLogEntryType]::Error, 7000)
    Write-Host "      [OK] Event 7000 written to Windows Application Event Log" -ForegroundColor Green
    Write-Host "      Service: $ServiceName | PID: $ProcessId" -ForegroundColor Gray
} catch {
    Write-Host "      [FAIL] Could not write to Event Log: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4 — Trigger backend monitor
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[4/4] Triggering immediate monitor poll ..." -ForegroundColor Yellow
Start-Sleep -Milliseconds 500

$triggerUrl = "$BackendUrl/api/monitor/trigger"
try {
    $response = Invoke-WebRequest -Uri $triggerUrl -Method POST -UseBasicParsing -TimeoutSec 30
    $result = $response.Content | ConvertFrom-Json
    $count  = $result.events_ingested
    Write-Host "      [OK] Monitor poll complete - $count new event(s) ingested" -ForegroundColor Green
} catch {
    Write-Host "      [WARN] Could not trigger poll: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "      The event will still be processed within the next cycle." -ForegroundColor Gray
}

$line = "=" * 46
Write-Host ""
Write-Host $line -ForegroundColor Cyan
Write-Host "   DONE - Check your frontend now!" -ForegroundColor Green
Write-Host $line -ForegroundColor Cyan
Write-Host ""
Write-Host "  A pop-up notification will appear in the frontend directing you" -ForegroundColor White
Write-Host "  to the Approvals page to approve the '$ServiceName' service restart." -ForegroundColor White
Write-Host ""
