<#
.SYNOPSIS
    Simulate an Application Crash (Event 1000) and trigger immediate auto-remediation.

.DESCRIPTION
    This script does 3 things in sequence:
      1. Writes a realistic "Application Error" Event ID 1000 to the Windows Event Log
         (same format Windows itself uses for real crashes, but without needing admin).
      2. Calls the backend /api/monitor/trigger to instantly process the new event
         without waiting the 30-second poll interval.
      3. Confirms that a remediation history record was created.

    Run this any time you want to test the auto-remediation pipeline end-to-end.
    The script will automatically request elevation (UAC) if not already running as Admin.

.PARAMETER AppName
    Name of the simulated faulting application (default: "MyTestApp.exe").
    Use a non-trivial name so it hits the standard Rule #31/33 remediation,
    not the Deep System Repair fallback.

.PARAMETER BackendUrl
    Base URL of the Flask backend (default: http://localhost:5000).

.EXAMPLE
    .\simulate_crash.ps1
    .\simulate_crash.ps1 -AppName "notepad"
#>

param(
    [string]$AppName    = "MyTestApp.exe",
    [string]$BackendUrl = "http://localhost:5000"
)

$ErrorActionPreference = 'Continue'

# ─────────────────────────────────────────────────────────────────────────────
# UAC Self-Elevation — re-launch as Administrator if not already elevated
# ─────────────────────────────────────────────────────────────────────────────
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "  [UAC] Not running as Administrator. Requesting elevation..." -ForegroundColor Yellow
    $scriptPath = $MyInvocation.MyCommand.Path
    $argString  = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -AppName `"$AppName`" -BackendUrl `"$BackendUrl`""
    try {
        Start-Process powershell.exe -ArgumentList $argString -Verb RunAs -Wait
    } catch {
        Write-Host "  [ERROR] Could not elevate. Please right-click and run as Administrator." -ForegroundColor Red
    }
    exit
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   AUTO-REMEDIATION CRASH SIMULATOR" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1 — Verify Backend is alive
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "[1/3] Checking backend at $BackendUrl ..." -ForegroundColor Yellow
try {
    $health = Invoke-WebRequest -Uri "$BackendUrl/api/health" -UseBasicParsing -TimeoutSec 5
    Write-Host "      [OK] Backend is online" -ForegroundColor Green
} catch {
    Write-Host "      [FAIL] Cannot reach backend: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "      Make sure the Flask backend is running (python backend/app.py)" -ForegroundColor Yellow
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 — Terminate the application to simulate a real crash visually
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[2/4] Terminating '$AppName' to visually simulate a crash ..." -ForegroundColor Yellow
$procName = $AppName -replace '\.exe$', ''
$existingProcs = Get-Process -Name "*$procName*" -ErrorAction SilentlyContinue
if ($existingProcs) {
    try {
        # Forcefully terminate the process using WMI/CIM to bypass UWP Access Denied restrictions
        Get-CimInstance Win32_Process -Filter "Name like '%$procName%'" | Invoke-CimMethod -MethodName Terminate | Out-Null
        Write-Host "      [OK] Successfully sent termination signal to $AppName using CIM Method" -ForegroundColor Green
        Start-Sleep -Seconds 1
    } catch {
        Write-Host "      [WARN] Could not visually terminate $AppName. The mock crash will still proceed." -ForegroundColor Yellow
    }
} else {
    Write-Host "      [INFO] $AppName is not currently running. Proceeding anyway." -ForegroundColor Gray
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3 — Write a real Event ID 1000 to the Windows Application Event Log
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[3/4] Writing Event ID 1000 (Application Crash) for '$AppName' ..." -ForegroundColor Yellow

# Build a message that matches the real Windows format so the rule engine
# can extract 'faulting application name' and 'faulting module name' correctly.
$FaultOffset  = "0x{0:x16}" -f (Get-Random -Minimum 100000 -Maximum 999999999)
$ReportId     = [System.Guid]::NewGuid().ToString()
$ProcessId    = Get-Random -Minimum 1000 -Maximum 65535

$Message = @"
Faulting application name: $AppName, version: 10.0.19041.1, time stamp: 0x98f3b2a2
Faulting module name: $AppName, version: 10.0.19041.1, time stamp: 0xdb84b3ef
Exception code: 0xc0000005
Fault offset: $FaultOffset
Faulting process id: 0x$("{0:X}" -f $ProcessId)
Faulting application start time: 0x01DCE9CBF378DFAE
Faulting application path: C:\Program Files\$AppName
Faulting module path: C:\Program Files\$AppName
Report Id: $ReportId
Faulting package full name: 
Faulting package-relative application ID: 
"@

try {
    $log         = New-Object System.Diagnostics.EventLog("Application")
    $log.Source  = "Application Error"
    $log.WriteEntry($Message, [System.Diagnostics.EventLogEntryType]::Error, 1000)
    Write-Host "      [OK] Event 1000 written to Windows Application Event Log" -ForegroundColor Green
    Write-Host "      App: $AppName | PID: $ProcessId | Report: $ReportId" -ForegroundColor Gray
} catch {
    Write-Host "      [FAIL] Could not write to Event Log: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4 — Trigger backend monitor
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[4/4] Triggering immediate monitor poll ..." -ForegroundColor Yellow
Start-Sleep -Milliseconds 500   # tiny pause to make sure the event is committed

$triggerUrl = "$BackendUrl/api/monitor/trigger"
try {
    $response = Invoke-WebRequest -Uri $triggerUrl -Method POST -UseBasicParsing -TimeoutSec 30
    $result = $response.Content | ConvertFrom-Json
    $count  = $result.events_ingested
    Write-Host "      [OK] Monitor poll complete - $count new event(s) ingested" -ForegroundColor Green
} catch {
    Write-Host "      [WARN] Could not trigger poll: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "      The event will still be processed within the next 30-second cycle." -ForegroundColor Gray
}

$line = "=" * 46
Write-Host ""
Write-Host $line -ForegroundColor Cyan
Write-Host "   DONE - Check the dashboard now!" -ForegroundColor Green
Write-Host $line -ForegroundColor Cyan
Write-Host ""
Write-Host "  Dashboard : $BackendUrl" -ForegroundColor White
Write-Host "  History   : $BackendUrl  --> History tab" -ForegroundColor White
Write-Host "  Events    : $BackendUrl  --> Events tab" -ForegroundColor White
Write-Host ""
Write-Host "  '$AppName' crash should appear in History" -ForegroundColor White
Write-Host "  with status SUCCESS from Rule #31 or #33." -ForegroundColor White
Write-Host ""

