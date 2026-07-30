<#
.SYNOPSIS
    Simulate a Low Disk Space event (Event 2013) and trigger immediate auto-remediation.

.DESCRIPTION
    This script calls the backend /api/simulations/lowdiskspace/auto-fix endpoint.
    It is intended to exercise the end-to-end disk space simulation demo.

.PARAMETER BackendUrl
    Base URL of the Flask backend (default: http://localhost:5000).

.PARAMETER Profile
    Simulation profile to use. One of: stable, degraded, critical.
    Default: degraded.

.PARAMETER RetryOnFailure
    Whether the backend should retry remediation on failure. Default: $true.

.EXAMPLE
    .\simulate_lowdiskspace.ps1
    .\simulate_lowdiskspace.ps1 -Profile stable
    .\simulate_lowdiskspace.ps1 -BackendUrl "http://localhost:5000" -Profile critical -RetryOnFailure $false
#>

param(
    [string]$BackendUrl      = "http://localhost:5000",
    [string]$Profile         = "degraded",
    [bool]$RetryOnFailure    = $true
)

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   LOW DISK SPACE SIMULATION" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "[1/3] Checking backend at $BackendUrl ..." -ForegroundColor Yellow
try {
    $health = Invoke-WebRequest -Uri "$BackendUrl/api/health" -UseBasicParsing -TimeoutSec 5
    Write-Host "      [OK] Backend is online" -ForegroundColor Green
} catch {
    Write-Host "      [FAIL] Cannot reach backend: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "      Make sure the Flask backend is running (powershell -ExecutionPolicy Bypass -File .\run_backend.ps1)" -ForegroundColor Yellow
    exit 1
}

$Profile = $Profile.Trim().ToLower()
if ($Profile -notin @('stable','degraded','critical')) {
    Write-Host "[WARNING] Invalid profile '$Profile'; using 'degraded' instead." -ForegroundColor Yellow
    $Profile = 'degraded'
}

$body = @{
    profile = $Profile
    retry_on_failure = $RetryOnFailure
} | ConvertTo-Json

Write-Host ""
Write-Host "[2/3] Triggering low disk space auto-fix simulation..." -ForegroundColor Yellow
Write-Host "      Profile: $Profile" -ForegroundColor Gray
Write-Host "      Retry on failure: $RetryOnFailure" -ForegroundColor Gray

try {
    $response = Invoke-RestMethod -Uri "$BackendUrl/api/simulations/lowdiskspace/auto-fix" -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 30
    Write-Host "      [OK] Simulation request completed" -ForegroundColor Green
} catch {
    Write-Host "      [FAIL] Simulation request failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[3/3] Simulation result:" -ForegroundColor Yellow
Write-Host "      Scenario: $($response.scenario)" -ForegroundColor Gray
Write-Host "      Event ID: $($response.event_id)" -ForegroundColor Gray
Write-Host "      Description: $($response.description)" -ForegroundColor Gray
if ($response.timeline) {
    Write-Host "      Timeline entries: $($response.timeline.Count)" -ForegroundColor Gray
}
if ($response.summary) {
    Write-Host "      Summary: $($response.summary | ConvertTo-Json -Compress)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Done. Check the frontend dashboard or backend logs for the new simulation event." -ForegroundColor Green
Write-Host ""
