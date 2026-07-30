<#
.SYNOPSIS
    Simulate a Low Disk Space event (Event 2013) and create an approval request.

.DESCRIPTION
    This script writes a synthetic Event ID 2013 entry to Windows Event Log and
    forces the backend monitor to ingest it, which should generate an approval
    request instead of immediately auto-remediating.

.PARAMETER BackendUrl
    Base URL of the Flask backend (default: http://localhost:5000).

.PARAMETER DriveLetter
    Drive letter to simulate low disk space for. Default: C.

.PARAMETER FreeGB
    Simulated free gigabytes. Default: 2.0.

.PARAMETER TotalGB
    Simulated total drive size. Default: 500.

.EXAMPLE
    .\simulate_lowdiskspace_approval.ps1
    .\simulate_lowdiskspace_approval.ps1 -DriveLetter D -FreeGB 1.5 -TotalGB 250
#>

param(
    [string]$BackendUrl = "http://localhost:5000",
    [string]$DriveLetter = "C",
    [double]$FreeGB = 2.0,
    [double]$TotalGB = 500.0
)

$ErrorActionPreference = 'Continue'

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   LOW DISK SPACE APPROVAL SIMULATOR" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "[1/4] Checking backend at $BackendUrl ..." -ForegroundColor Yellow
try {
    $health = Invoke-WebRequest -Uri "$BackendUrl/api/health" -UseBasicParsing -TimeoutSec 5
    Write-Host "      [OK] Backend is online" -ForegroundColor Green
} catch {
    Write-Host "      [FAIL] Cannot reach backend: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "      Make sure the Flask backend is running (powershell -ExecutionPolicy Bypass -File .\run_backend.ps1)" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "[2/4] Resetting approval state before simulation..." -ForegroundColor Yellow
try {
    Invoke-RestMethod -Uri "$BackendUrl/api/approvals/reset" -Method Delete -UseBasicParsing -TimeoutSec 15 | Out-Null
    Write-Host "      [OK] Approval state cleared. New events will require operator sign-off." -ForegroundColor Green
} catch {
    Write-Host "      [WARN] Could not reset approvals: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "      Continuing anyway; approval popup may only appear if the event type is unapproved." -ForegroundColor Gray
}

Write-Host ""
Write-Host "[3/4] Creating approval-gated low disk space event..." -ForegroundColor Yellow
$body = @{
    count = 1
    profile = 'degraded'
    reset_approvals = $true
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Uri "$BackendUrl/api/simulations/lowdiskspace/approval" -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 30
    Write-Host "      [OK] Simulation request completed." -ForegroundColor Green
    Write-Host "      Pending approvals: $($response.pending_approvals)" -ForegroundColor Gray
} catch {
    Write-Host "      [FAIL] Simulation request failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[4/4] Checking approval queue from backend..." -ForegroundColor Yellow
try {
    $approvals = Invoke-RestMethod -Uri "$BackendUrl/api/approvals?status=pending" -UseBasicParsing -TimeoutSec 10
    $count = ($approvals | Measure-Object).Count
    Write-Host "      [OK] Pending approvals: $count" -ForegroundColor Green
    if ($count -gt 0) {
        Write-Host "      Open the frontend and go to the Approvals page to review and approve the request." -ForegroundColor Cyan
    } else {
        Write-Host "      No pending approvals were found. The event may not have matched a gated rule." -ForegroundColor Yellow
    }
} catch {
    Write-Host "      [WARN] Could not query approvals: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Done. If the frontend is open, the approval popup should appear shortly." -ForegroundColor Green
Write-Host ""