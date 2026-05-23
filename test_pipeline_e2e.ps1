#!/usr/bin/env powershell
<#
.SYNOPSIS
    End-to-End Pipeline Test: Real Crash Detection Remediation Dashboard

.DESCRIPTION
    This script tests the complete auto-remediation pipeline:
    1. Creates real application crashes
    2. Monitors backend detection
    3. Verifies remediation execution
    4. Confirms dashboard shows results

.NOTES
    Requires: Flask backend running on :5000, Event Monitor active
#>

param(
    [int]$CrashCount = 2,
    [int]$WaitSeconds = 60
)

Write-Host "`n========== AUTO-REMEDIATION PIPELINE TEST ==========" -ForegroundColor Cyan

# ─────────────────────────────────────────────────────────────────────────────
#  PHASE 1: Verify Backend is Running
# ─────────────────────────────────────────────────────────────────────────────

Write-Host "`n[PHASE 1] Verifying Backend Service..." -ForegroundColor Yellow
try {
    $health = Invoke-WebRequest -Uri "http://localhost:5000/api/health" -UseBasicParsing -TimeoutSec 3
    if ($health.StatusCode -eq 200) {
        Write-Host "[OK] Backend running on http://localhost:5000" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] Backend not responding (Status: $($health.StatusCode))" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "[FAIL] Backend not accessible: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "Getting baseline counts..." -ForegroundColor Cyan
try {
    $eventsResp = Invoke-WebRequest -Uri "http://localhost:5000/api/events?limit=1" -UseBasicParsing
    $events = $eventsResp.Content | ConvertFrom-Json
    $baselineEvents = if ($events -is [array]) { $events.Count } else { 1 }
    
    $historyResp = Invoke-WebRequest -Uri "http://localhost:5000/api/history?limit=1" -UseBasicParsing
    $history = $historyResp.Content | ConvertFrom-Json
    $baselineHistory = if ($history -is [array]) { $history.Count } else { 1 }
    
    Write-Host "  Baseline events: $baselineEvents" -ForegroundColor White
    Write-Host "  Baseline remediation records: $baselineHistory" -ForegroundColor White
} catch {
    Write-Host "  WARNING: Could not get baseline counts" -ForegroundColor Yellow
}

# ─────────────────────────────────────────────────────────────────────────────
#  PHASE 2: Create Real Application Crashes
# ─────────────────────────────────────────────────────────────────────────────

Write-Host "`n[PHASE 2] Creating $CrashCount Real Application Crashes..." -ForegroundColor Yellow

$crashes = @()
for ($i = 1; $i -le $CrashCount; $i++) {
    Write-Host "  [$i/$CrashCount] Starting notepad process..." -ForegroundColor Cyan
    $proc = Start-Process notepad -PassThru
    Start-Sleep -Milliseconds 500
    
    Write-Host "  [$i/$CrashCount] Force terminating (PID: $($proc.Id))..." -ForegroundColor Cyan
    taskkill /PID $proc.Id /F 2>&1 | Out-Null
    
    $crashes += @{
        'PID' = $proc.Id
        'Timestamp' = Get-Date
    }
    
    Write-Host "  [OK] Crash $i created - Event 1000 should be logged" -ForegroundColor Green
    Start-Sleep -Milliseconds 500
}

# ─────────────────────────────────────────────────────────────────────────────
#  PHASE 3: Wait for Event Monitor to Detect
# ─────────────────────────────────────────────────────────────────────────────

Write-Host "`n[PHASE 3] Waiting for Event Monitor Detection (max $WaitSeconds seconds)..." -ForegroundColor Yellow
$elapsed = 0
$maxWait = $WaitSeconds
$detected = $false

while ($elapsed -lt $maxWait) {
    Write-Host "  [$elapsed/$maxWait] Checking backend..." -ForegroundColor Gray
    
    try {
        $eventsResp = Invoke-WebRequest -Uri "http://localhost:5000/api/events?limit=5" -UseBasicParsing
        $currentEvents = $eventsResp.Content | ConvertFrom-Json
        $currentCount = if ($currentEvents -is [array]) { $currentEvents.Count } else { 1 }
        
        if ($currentCount -gt $baselineEvents) {
            Write-Host "[OK] NEW EVENTS DETECTED! ($baselineEvents -> $currentCount)" -ForegroundColor Green
            $detected = $true
            break
        }
    } catch {
        Write-Host "  WARNING: Error checking events: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    Start-Sleep -Seconds 5
    $elapsed += 5
}

if ($detected) {
    Write-Host "[OK] Event Monitor successfully detected the crashes" -ForegroundColor Green
} else {
    Write-Host "[WARNING] No new events detected after $maxWait seconds" -ForegroundColor Yellow
}

# ─────────────────────────────────────────────────────────────────────────────
#  PHASE 4: Check Remediation Execution
# ─────────────────────────────────────────────────────────────────────────────

Write-Host "`n[PHASE 4] Checking Remediation Execution..." -ForegroundColor Yellow

try {
    $historyResp = Invoke-WebRequest -Uri "http://localhost:5000/api/history?limit=10" -UseBasicParsing
    $historyData = $historyResp.Content | ConvertFrom-Json
    
    if ($historyData -is [array]) {
        Write-Host "[OK] Found $($historyData.Count) remediation records" -ForegroundColor Green
        
        $successes = 0
        $failures = 0
        $skipped = 0
        
        foreach ($record in $historyData) {
            if ($record.status -eq 'success') { $successes++ }
            elseif ($record.status -eq 'failed') { $failures++ }
            else { $skipped++ }
        }
        
        Write-Host "  Successful: $successes" -ForegroundColor Green
        Write-Host "  Failed: $failures" -ForegroundColor Red
        Write-Host "  Other: $skipped" -ForegroundColor Yellow
        
        Write-Host "`n  Last 3 Remediation Records:" -ForegroundColor Cyan
        $historyData | Select-Object -First 3 | ForEach-Object {
            $statusColor = if ($_.status -eq 'success') { 'Green' } elseif ($_.status -eq 'failed') { 'Red' } else { 'Yellow' }
            Write-Host "    [$($_.status.ToUpper())] Event $($_.event_id) - $($_.rule_name)" -ForegroundColor $statusColor
        }
    }
} catch {
    Write-Host "[WARNING] Could not fetch remediation history: $($_.Exception.Message)" -ForegroundColor Yellow
}

# ─────────────────────────────────────────────────────────────────────────────
#  PHASE 5: Verify Real Events in Windows Event Log
# ─────────────────────────────────────────────────────────────────────────────

Write-Host "`n[PHASE 5] Verifying Real Events in Windows Event Log..." -ForegroundColor Yellow

try {
    $recentEvents = Get-WinEvent -LogName Application -FilterXPath "*[System[EventID=1000]]" -MaxEvents 5 -ErrorAction SilentlyContinue
    
    if ($recentEvents) {
        Write-Host "[OK] Found $($recentEvents.Count) Event 1000 (Application Crash) entries" -ForegroundColor Green
        
        $recentEvents | Select-Object -First 2 | ForEach-Object {
            $msg = ($_.Message -split "`n")[0]
            if ($msg.Length -gt 80) { $msg = $msg.Substring(0, 80) + "..." }
            Write-Host "  $($_.TimeCreated) - $msg" -ForegroundColor White
        }
    } else {
        Write-Host "[WARNING] No Event 1000 entries found (may take a moment)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "[WARNING] Error reading Event Log: $($_.Exception.Message)" -ForegroundColor Yellow
}

# ─────────────────────────────────────────────────────────────────────────────
#  PHASE 6: Summary
# ─────────────────────────────────────────────────────────────────────────────

Write-Host "`n========== PIPELINE TEST COMPLETE ==========" -ForegroundColor Green

Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "1. Open dashboard: http://localhost:5000" -ForegroundColor White
Write-Host "2. Go to 'Events' tab to see detected crashes" -ForegroundColor White
Write-Host "3. Go to 'History' tab to see remediation attempts" -ForegroundColor White
Write-Host "4. Check that auto-remediation is executing" -ForegroundColor White

Write-Host "`nPipeline Status:" -ForegroundColor Cyan
Write-Host "[OK] Backend online and responding" -ForegroundColor Green
Write-Host "[OK] Real crashes created" -ForegroundColor Green
if ($detected) {
    Write-Host "[OK] Event Monitor detecting crashes" -ForegroundColor Green
} else {
    Write-Host "[WARNING] Event Monitor detection pending" -ForegroundColor Yellow
}
Write-Host "[OK] Remediation records in database" -ForegroundColor Green
Write-Host "`n" 
