@echo off
REM Start the Windows Event Monitor
REM This script launches the PowerShell event monitor in a new window
REM Configuration is loaded from .env file

echo ========================================
echo Windows Event Monitor Launcher
echo ========================================
echo.
echo This will monitor Windows Event Logs and send events to the backend.
echo Configuration is loaded from .env file in the project root.
echo.
echo The monitor will import historical events, then continue monitoring for new events.
echo.
echo Press Ctrl+C in the PowerShell window to stop monitoring.
echo.

REM Check if .env file exists
if not exist "%~dp0.env" (
    echo WARNING: .env file not found!
    echo.
    echo Please run setup.ps1 first to create the configuration file:
    echo   powershell -ExecutionPolicy Bypass -File setup.ps1
    echo.
    echo Or copy .env.example to .env and edit it manually.
    echo.
    pause
    exit /b 1
)

REM Start the event monitor in a new PowerShell window
REM The script will load configuration from .env file
start "Windows Event Monitor" powershell.exe -ExecutionPolicy Bypass -NoExit -File "%~dp0collector\event_monitor.ps1"

echo.
echo Event monitor started in a new window.
echo Check the PowerShell window for status and logs.
echo.
pause

