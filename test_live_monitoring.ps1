<#
.SYNOPSIS
    Test script to verify live event monitoring is working

.DESCRIPTION
    This script generates test events and verifies they appear in the system.
    Use this to test your live monitoring setup.

.EXAMPLE
    .\test_live_monitoring.ps1
#>

param(
    [string]$ApiUrl = "http://localhost:5000"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Live Monitoring Test Script" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Check if backend is running
Write-Host "Step 1: Checking if backend is running..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "$ApiUrl/api/events" -Method Get -ErrorAction Stop
    Write-Host "✓ Backend is running at $ApiUrl" -ForegroundColor Green
}
catch {
    Write-Host "✗ Backend is not running at $ApiUrl" -ForegroundColor Red
    Write-Host "Please start the backend first: python backend/app.py" -ForegroundColor Yellow
    exit 1
}

# Get current event count
$initialCount = $response.Count
Write-Host "Current event count: $initialCount`n" -ForegroundColor Gray

# Generate test events
Write-Host "Step 2: Generating test events..." -ForegroundColor Yellow

$testEvents = @(
    @{EventId = 1000; Message = "Test Application Error - Live Monitoring Test 1"},
    @{EventId = 1001; Message = "Test Application Hang - Live Monitoring Test 2"},
    @{EventId = 1026; Message = "Test .NET Runtime Error - Live Monitoring Test 3"}
)

foreach ($evt in $testEvents) {
    try {
        # Try to write to Application log
        # Note: This requires the "Application" source to exist
        Write-EventLog -LogName Application -Source "Application" -EventId $evt.EventId -EntryType Error -Message $evt.Message -ErrorAction Stop
        Write-Host "✓ Created Event $($evt.EventId): $($evt.Message)" -ForegroundColor Green
    }
    catch {
        Write-Host "✗ Failed to create Event $($evt.EventId): $_" -ForegroundColor Red
        Write-Host "  Note: You may need to run this script as Administrator" -ForegroundColor Yellow
    }
    
    Start-Sleep -Seconds 1
}

Write-Host "`nStep 3: Waiting for events to be captured..." -ForegroundColor Yellow
Write-Host "The event monitor polls every 10 seconds by default." -ForegroundColor Gray
Write-Host "Waiting 15 seconds...`n" -ForegroundColor Gray

Start-Sleep -Seconds 15

# Check if events were captured
Write-Host "Step 4: Checking if events were captured..." -ForegroundColor Yellow

try {
    $response = Invoke-RestMethod -Uri "$ApiUrl/api/events" -Method Get -ErrorAction Stop
    $newCount = $response.Count
    $capturedCount = $newCount - $initialCount
    
    if ($capturedCount -gt 0) {
        Write-Host "✓ SUCCESS! Captured $capturedCount new event(s)" -ForegroundColor Green
        
        # Show the latest events
        Write-Host "`nLatest events:" -ForegroundColor Cyan
        $latestEvents = $response | Select-Object -Last 5
        foreach ($evt in $latestEvents) {
            Write-Host "  - Event $($evt.event_id) from $($evt.source) at $($evt.timestamp)" -ForegroundColor White
        }
    }
    else {
        Write-Host "✗ No new events captured" -ForegroundColor Red
        Write-Host "`nPossible issues:" -ForegroundColor Yellow
        Write-Host "  1. Event monitor is not running" -ForegroundColor Gray
        Write-Host "  2. Event monitor is filtering out these event IDs" -ForegroundColor Gray
        Write-Host "  3. Events were not created (check Event Viewer)" -ForegroundColor Gray
        Write-Host "`nTo start the event monitor:" -ForegroundColor Yellow
        Write-Host "  start_event_monitor.bat" -ForegroundColor White
        Write-Host "  OR" -ForegroundColor Gray
        Write-Host "  powershell -ExecutionPolicy Bypass -File collector\event_monitor.ps1" -ForegroundColor White
    }
}
catch {
    Write-Host "✗ Failed to check events: $_" -ForegroundColor Red
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Open the dashboard: $ApiUrl" -ForegroundColor White
Write-Host "2. Check the Dashboard tab for statistics" -ForegroundColor White
Write-Host "3. Check the Events tab to see captured events" -ForegroundColor White
Write-Host "4. Create rules for these events in the Event Catalog tab`n" -ForegroundColor White

pause

