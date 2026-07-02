# ─────────────────────────────────────────────────────────────────────────────
# UAC Self-Elevation — re-launch as Administrator if not already elevated
# ─────────────────────────────────────────────────────────────────────────────
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "  [UAC] Requesting elevation to Administrator..." -ForegroundColor Yellow
    $scriptPath = $MyInvocation.MyCommand.Path
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs -Wait
    exit
}

Write-Host "=== REAL NOTEPAD CRASH DEMO ===" -ForegroundColor Green
Write-Host "Starting live remediation demo..." -ForegroundColor Cyan

# 1. Start Notepad instances
Write-Host "`n[1] Starting 3 notepad instances..." -ForegroundColor Yellow
$np1 = Start-Process notepad -PassThru
$np2 = Start-Process notepad -PassThru  
$np3 = Start-Process notepad -PassThru
Write-Host "    Started PIDs: $($np1.Id), $($np2.Id), $($np3.Id)" -ForegroundColor Green

# 2. Wait for them to fully load
Start-Sleep -Seconds 3

# 3. Force kill them (REAL crash)
Write-Host "`n[2] Force terminating (REAL crash simulation)..." -ForegroundColor Yellow
taskkill /PID $($np1.Id) /F | Out-Null
taskkill /PID $($np2.Id) /F | Out-Null
taskkill /PID $($np3.Id) /F | Out-Null
Write-Host "    ? All 3 notepad instances crashed" -ForegroundColor Green

# 4. Log real Application Crash events
Write-Host "`n[3] Logging real Application Crash events..." -ForegroundColor Yellow
for ($i = 1; $i -le 3; $i++) {
    $message = "Faulting application name: notepad.exe, version: 10.0.19041.1, time stamp: 0x98f3b2a2. Faulting module name: KERNELBASE.dll, version: 10.0.19041.1, time stamp: 0x8b3b5c36. Exception code: 0xc0000005. Fault offset: 0x000b87d5"
    Write-EventLog -LogName Application -Source "Application Error" -EventId 1000 -EntryType Error -Message $message -ErrorAction SilentlyContinue
    Write-Host "    Event $i logged" -ForegroundColor Green
    Start-Sleep -Milliseconds 500
}

Write-Host "`n[4] Watching backend detect events..." -ForegroundColor Yellow
Write-Host "    Open dashboard now: http://localhost:5000" -ForegroundColor Cyan
Write-Host "    Check 'Events' tab to see real-time detection" -ForegroundColor Cyan
Write-Host "`n[?] DEMO READY - Check your dashboard!" -ForegroundColor Green
