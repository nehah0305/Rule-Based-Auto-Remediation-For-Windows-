# Test if event monitor is capturing events
Write-Host "Creating test event..." -ForegroundColor Yellow
Write-EventLog -LogName Application -Source "Application" -EventId 1000 -EntryType Error -Message "Final test event - Verifying live monitoring connection"

Write-Host "Waiting 12 seconds for event monitor to capture..." -ForegroundColor Yellow
Start-Sleep -Seconds 12

Write-Host "Checking events..." -ForegroundColor Yellow
$events = Invoke-RestMethod -Uri 'http://localhost:5000/api/events' -Method Get
Write-Host "Total events in system: $($events.Count)" -ForegroundColor Green

if ($events.Count -gt 1) {
    Write-Host "`nLatest events:" -ForegroundColor Cyan
    $events | Select-Object -Last 3 | ForEach-Object {
        Write-Host "  - Event $($_.event_id) from $($_.source) at $($_.timestamp)" -ForegroundColor White
    }
}

