# Simple test script for live monitoring
param(
    [string]$ApiUrl = "http://localhost:5000"
)

Write-Host "========================================"  -ForegroundColor Cyan
Write-Host "Live Monitoring Simple Test" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Check backend
Write-Host "Step 1: Checking backend..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "$ApiUrl/api/events" -Method Get -ErrorAction Stop
    $initialCount = $response.Count
    Write-Host "[OK] Backend is running" -ForegroundColor Green
    Write-Host "Current event count: $initialCount" -ForegroundColor Gray
}
catch {
    Write-Host "[FAIL] Backend is not running" -ForegroundColor Red
    Write-Host "Please start: python backend/app.py" -ForegroundColor Yellow
    exit 1
}

Write-Host ""

# Step 2: Generate test events
Write-Host "Step 2: Generating test events..." -ForegroundColor Yellow

try {
    Write-EventLog -LogName Application -Source "Application" -EventId 1000 -EntryType Error -Message "Test Event 1 - Live Monitoring Test" -ErrorAction Stop
    Write-Host "[OK] Created Event 1000" -ForegroundColor Green
    
    Write-EventLog -LogName Application -Source "Application" -EventId 1001 -EntryType Error -Message "Test Event 2 - Live Monitoring Test" -ErrorAction Stop
    Write-Host "[OK] Created Event 1001" -ForegroundColor Green
    
    Write-EventLog -LogName Application -Source "Application" -EventId 1026 -EntryType Error -Message "Test Event 3 - Live Monitoring Test" -ErrorAction Stop
    Write-Host "[OK] Created Event 1026" -ForegroundColor Green
}
catch {
    Write-Host "[WARN] Could not create test events: $_" -ForegroundColor Yellow
    Write-Host "You may need to run as Administrator" -ForegroundColor Yellow
}

Write-Host ""

# Step 3: Wait for event monitor to capture
Write-Host "Step 3: Waiting 15 seconds for event monitor to capture events..." -ForegroundColor Yellow
Write-Host "(Event monitor polls every 10 seconds by default)" -ForegroundColor Gray
Start-Sleep -Seconds 15

Write-Host ""

# Step 4: Check if events were captured
Write-Host "Step 4: Checking if events were captured..." -ForegroundColor Yellow

try {
    $response = Invoke-RestMethod -Uri "$ApiUrl/api/events" -Method Get -ErrorAction Stop
    $newCount = $response.Count
    $capturedCount = $newCount - $initialCount
    
    Write-Host "Initial count: $initialCount" -ForegroundColor Gray
    Write-Host "Current count: $newCount" -ForegroundColor Gray
    Write-Host "New events: $capturedCount" -ForegroundColor Gray
    Write-Host ""
    
    if ($capturedCount -gt 0) {
        Write-Host "[SUCCESS] Captured $capturedCount new events!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Latest events:" -ForegroundColor Cyan
        $response | Select-Object -Last 5 | ForEach-Object {
            Write-Host "  - Event $($_.event_id) from $($_.source) at $($_.timestamp)" -ForegroundColor White
        }
    }
    else {
        Write-Host "[WARN] No new events captured" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Possible reasons:" -ForegroundColor Yellow
        Write-Host "  1. Event monitor is not running" -ForegroundColor Gray
        Write-Host "  2. Event monitor is filtering out these event IDs" -ForegroundColor Gray
        Write-Host "  3. Events were not created successfully" -ForegroundColor Gray
        Write-Host ""
        Write-Host "To start event monitor:" -ForegroundColor Yellow
        Write-Host "  start_event_monitor.bat" -ForegroundColor White
    }
}
catch {
    Write-Host "[FAIL] Could not check events: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Test Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Open dashboard: $ApiUrl" -ForegroundColor White
Write-Host "2. Start event monitor if not running" -ForegroundColor White
Write-Host "3. Check Dashboard tab for statistics" -ForegroundColor White
Write-Host ""

