# Quick test to verify event monitor can start
Write-Host "Testing event monitor startup..." -ForegroundColor Cyan

# Start the monitor in background
$job = Start-Job -ScriptBlock {
    Set-Location "d:\Programming\Unisys\Rule-Based-Auto-Remediation-For-Windows-"
    & powershell -ExecutionPolicy Bypass -File "collector\event_monitor.ps1" -PollIntervalSeconds 5
}

Write-Host "Waiting 5 seconds for monitor to initialize..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

# Check if job is running
$jobState = $job.State
Write-Host "Job State: $jobState" -ForegroundColor $(if ($jobState -eq 'Running') { 'Green' } else { 'Red' })

# Get any output
$output = Receive-Job -Job $job
if ($output) {
    Write-Host "`nMonitor Output:" -ForegroundColor Cyan
    $output | ForEach-Object { Write-Host "  $_" }
}

# Stop the job
Stop-Job -Job $job
Remove-Job -Job $job

if ($jobState -eq 'Running') {
    Write-Host "`n[SUCCESS] Event monitor can start successfully!" -ForegroundColor Green
    Write-Host "You can now run: start_event_monitor.bat" -ForegroundColor White
} else {
    Write-Host "`n[FAIL] Event monitor failed to start" -ForegroundColor Red
}

