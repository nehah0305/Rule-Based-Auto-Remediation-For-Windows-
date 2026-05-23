$process = Start-Process notepad -PassThru
Write-Host "Started notepad with PID: $($process.Id)"
Start-Sleep -Seconds 2
taskkill /F /PID $($process.Id)
Write-Host "Terminated notepad PID $($process.Id) using taskkill."

$message = "Faulting application name: notepad.exe, Faulting module name: ntdll.dll, Exception code: 0xc0000005"
try {
    Write-EventLog -LogName Application -Source "Application Error" -EventId 1000 -EntryType Error -Message $message
    Write-Host "Successfully logged Event ID 1000 to Application log."
} catch {
    Write-Warning "Could not log event: $($_.Exception.Message)"
    Write-Host "Attempting to register source and retry..."
    New-EventLog -LogName Application -Source "Application Error" -ErrorAction SilentlyContinue
    Write-EventLog -LogName Application -Source "Application Error" -EventId 1000 -EntryType Error -Message $message
    Write-Host "Logged Event ID 1000 after attempt to register source."
}
