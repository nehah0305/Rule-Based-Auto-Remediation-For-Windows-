@echo off
REM Start the Windows Event Monitor
REM This script launches the PowerShell event monitor in a new window

echo Starting Windows Event Monitor...
echo.
echo This will monitor Windows Event Logs and send events to the backend.
echo Make sure the Flask backend is running at http://localhost:5000
echo.
echo The monitor will import historical events from the last 30 days (1 month),
echo then continue monitoring for new events.
echo.
echo Press Ctrl+C in the PowerShell window to stop monitoring.
echo.

REM Start the event monitor in a new PowerShell window with historical import
start "Windows Event Monitor" powershell.exe -ExecutionPolicy Bypass -NoExit -File "%~dp0collector\event_monitor.ps1" -LogNames "System,Application" -PollIntervalSeconds 10 -HistoricalDays 30 -MaxHistoricalEvents 10000

echo.
echo Event monitor started in a new window.
echo.
pause

