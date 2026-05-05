@echo off
REM ============================================================================
REM  Comprehensive Setup Script for Rule-Based Auto-Remediation System
REM  
REM  This script:
REM  - Initializes the database
REM  - Populates remediation rules
REM  - Sets up Windows Task Scheduler for backend and event monitor
REM  - Configures the system for production deployment
REM ============================================================================

SETLOCAL EnableDelayedExpansion
cd /d "%~dp0\.."
set BASE_DIR=%cd%

echo.
echo ============================================================================
echo  Rule-Based Auto-Remediation System - Setup
echo ============================================================================
echo.
echo Base Directory: %BASE_DIR%
echo.

REM Check if Python is installed
python --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python is not installed or not in PATH
    echo Please install Python 3.8+ and ensure it's in your PATH
    pause
    exit /b 1
)

echo [1/5] Initializing database...
python backend\db_init.py
if errorlevel 1 (
    echo ERROR: Failed to initialize database
    pause
    exit /b 1
)

echo [2/5] Populating default remediation rules...
python backend\populate_rules.py
if errorlevel 1 (
    echo ERROR: Failed to populate rules
    pause
    exit /b 1
)

echo [3/5] Installing Python dependencies...
pip install -r backend\requirements.txt --quiet
if errorlevel 1 (
    echo ERROR: Failed to install Python dependencies
    pause
    exit /b 1
)

echo.
echo [4/5] Registering Windows Task Scheduler tasks...
echo.

REM Import the task scheduler helper functions
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference = 'Stop'; . '%BASE_DIR%\build_scripts\TaskSchedulerHelper.ps1'"

REM Create backend service task
echo Creating 'RemediationBackendService' task...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "& { . '%BASE_DIR%\build_scripts\TaskSchedulerHelper.ps1'; " ^
    "$result = New-ScheduledTaskFromScript -TaskName 'RemediationBackendService' " ^
    "-ScriptPath '%BASE_DIR%\backend\app.py' " ^
    "-ScheduleType 'once' " ^
    "-RunWithHighestPrivileges; " ^
    "Write-Host $result.message; " ^
    "exit ([int]!$result.success) }"

if errorlevel 1 (
    echo WARNING: Failed to create backend task (may require manual setup)
)

REM Create event monitor task
echo Creating 'RemediationEventMonitor' task...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "& { . '%BASE_DIR%\build_scripts\TaskSchedulerHelper.ps1'; " ^
    "$result = New-ScheduledTaskFromScript -TaskName 'RemediationEventMonitor' " ^
    "-ScriptPath '%BASE_DIR%\backend\event_log_monitor.py' " ^
    "-ScheduleType 'once' " ^
    "-RunWithHighestPrivileges; " ^
    "Write-Host $result.message; " ^
    "exit ([int]!$result.success) }"

if errorlevel 1 (
    echo WARNING: Failed to create event monitor task (may require manual setup)
)

echo.
echo [5/5] Setup verification...
echo.

REM Verify database was created
if exist "%BASE_DIR%\backend\remediation.db" (
    echo [OK] Database created
) else (
    echo [WARN] Database may not have been created
)

REM Verify rules were populated
python -c "from backend.models import get_rules; print('[OK] Rules populated - {} rules loaded'.format(len(get_rules())))" 2>nul
if errorlevel 1 (
    echo [WARN] Could not verify rules
)

echo.
echo ============================================================================
echo Setup Complete!
echo ============================================================================
echo.
echo Next steps:
echo 1. Review the .env file in build_scripts\ to configure settings
echo 2. Start the backend: call build_scripts\start_backend.bat
echo 3. Start the event monitor: call build_scripts\start_event_monitor.bat
echo 4. Open the Flutter app: call build_scripts\start_flutter_app.bat
echo.
echo Or use the new Task Scheduler integration in the dashboard to manage tasks!
echo.
pause
