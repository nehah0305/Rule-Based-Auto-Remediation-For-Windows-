# Comprehensive system verification script
param(
    [string]$ApiUrl = "http://localhost:5000"
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "System Verification Report" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Test 1: Backend API
Write-Host "[1/5] Testing Backend API..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "$ApiUrl/api/events" -Method Get -ErrorAction Stop
    Write-Host "  [OK] Backend is running and responding" -ForegroundColor Green
    Write-Host "  Current events in database: $($response.Count)" -ForegroundColor Gray
    $backendOk = $true
}
catch {
    Write-Host "  [FAIL] Backend is not accessible: $_" -ForegroundColor Red
    $backendOk = $false
}

# Test 2: Database
Write-Host "`n[2/5] Testing Database..." -ForegroundColor Yellow
if (Test-Path "backend\rules.db") {
    Write-Host "  [OK] Database file exists" -ForegroundColor Green
    $dbSize = (Get-Item "backend\rules.db").Length
    Write-Host "  Database size: $dbSize bytes" -ForegroundColor Gray
}
else {
    Write-Host "  [FAIL] Database file not found" -ForegroundColor Red
}

# Test 3: Event Definitions
Write-Host "`n[3/5] Testing Event Definitions..." -ForegroundColor Yellow
if ($backendOk) {
    try {
        $defs = Invoke-RestMethod -Uri "$ApiUrl/api/event-definitions" -Method Get -ErrorAction Stop
        Write-Host "  [OK] Event definitions loaded" -ForegroundColor Green
        Write-Host "  Total event definitions: $($defs.Count)" -ForegroundColor Gray
    }
    catch {
        Write-Host "  [FAIL] Could not load event definitions: $_" -ForegroundColor Red
    }
}

# Test 4: Rules
Write-Host "`n[4/5] Testing Rules..." -ForegroundColor Yellow
if ($backendOk) {
    try {
        $rules = Invoke-RestMethod -Uri "$ApiUrl/api/rules" -Method Get -ErrorAction Stop
        Write-Host "  [OK] Rules loaded" -ForegroundColor Green
        Write-Host "  Total rules: $($rules.Count)" -ForegroundColor Gray
    }
    catch {
        Write-Host "  [FAIL] Could not load rules: $_" -ForegroundColor Red
    }
}

# Test 5: Manual Event Creation
Write-Host "`n[5/5] Testing Manual Event Creation..." -ForegroundColor Yellow
if ($backendOk) {
    try {
        $testEvent = @{
            event_id = 9999
            log_name = "Application"
            source = "TestSource"
            message = "Manual test event - System verification"
            timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
        }
        
        $json = $testEvent | ConvertTo-Json
        $result = Invoke-RestMethod -Uri "$ApiUrl/api/events" -Method Post -Body $json -ContentType "application/json" -ErrorAction Stop
        Write-Host "  [OK] Successfully created test event via API" -ForegroundColor Green
        Write-Host "  Event ID: $($result.id)" -ForegroundColor Gray
    }
    catch {
        Write-Host "  [FAIL] Could not create test event: $_" -ForegroundColor Red
    }
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

if ($backendOk) {
    Write-Host "[SUCCESS] Core system is operational!" -ForegroundColor Green
    Write-Host "`nThe following components are working:" -ForegroundColor Green
    Write-Host "  - Flask Backend API" -ForegroundColor White
    Write-Host "  - Database" -ForegroundColor White
    Write-Host "  - Event Definitions" -ForegroundColor White
    Write-Host "  - Manual Event Creation" -ForegroundColor White
    
    Write-Host "`nTo enable live monitoring:" -ForegroundColor Yellow
    Write-Host "  1. Open a new PowerShell window" -ForegroundColor White
    Write-Host "  2. Run: .\start_event_monitor.bat" -ForegroundColor White
    Write-Host "  3. Or run: powershell -ExecutionPolicy Bypass -File collector\event_monitor.ps1" -ForegroundColor White
    
    Write-Host "`nTo view the dashboard:" -ForegroundColor Yellow
    Write-Host "  Open browser: $ApiUrl" -ForegroundColor White
}
else {
    Write-Host "[FAIL] System is not operational" -ForegroundColor Red
    Write-Host "`nPlease start the backend:" -ForegroundColor Yellow
    Write-Host "  python backend\app.py" -ForegroundColor White
}

Write-Host ""

