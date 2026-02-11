# Check events in the system
Start-Sleep -Seconds 8

$events = Invoke-RestMethod -Uri 'http://localhost:5000/api/events' -Method Get

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Event Monitoring Status Check" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Total events captured: $($events.Count)" -ForegroundColor Green
Write-Host ""

if ($events.Count -gt 0) {
    Write-Host "Latest events:" -ForegroundColor Yellow
    $events | Select-Object -Last 5 | ForEach-Object {
        Write-Host "  - Event $($_.event_id) from $($_.source) at $($_.timestamp)" -ForegroundColor White
    }
} else {
    Write-Host "No events captured yet." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan

