@echo off
REM Simple Flutter build script - runs in native CMD environment
REM This avoids PowerShell compatibility issues

setlocal enabledelayedexpansion

echo.
echo ================================================================================
echo                      FLUTTER BUILD
echo ================================================================================
echo.

REM Ensure all necessary tools are in PATH
REM Windows built-in tools
set PATH=%SystemRoot%\System32;%SystemRoot%;%PATH%

REM Git
if exist "C:\Program Files\Git\cmd" set PATH=C:\Program Files\Git\cmd;%PATH%
if exist "C:\Program Files\Git\bin" set PATH=C:\Program Files\Git\bin;%PATH%
if exist "C:\Program Files (x86)\Git\cmd" set PATH=C:\Program Files (x86)\Git\cmd;%PATH%
if exist "C:\Program Files (x86)\Git\bin" set PATH=C:\Program Files (x86)\Git\bin;%PATH%

REM Verify we're in the right place
cd /d "c:\Users\bios\Desktop\unisys-ab\Rule-Based-Auto-Remediation-For-Windows-\frontend"

if errorlevel 1 (
    echo ERROR: Could not navigate to frontend directory
    pause
    exit /b 1
)

REM Verify git is available
where git.exe >nul 2>&1
if errorlevel 1 (
    echo ERROR: git not found
    echo Please run: https://git-scm.com/download/win (you may have already done this)
    echo Reboot if just installed
    pause
    exit /b 1
)

echo Building Flutter web app...
echo This may take a few minutes...
echo.

REM Clean old build
echo Cleaning...
call c:\flutter\bin\flutter.bat clean
if errorlevel 1 (
    echo WARNING: Clean failed, continuing anyway...
)

REM Get dependencies  
echo Getting dependencies...
call c:\flutter\bin\flutter.bat pub get
if errorlevel 1 (
    echo ERROR: pub get failed
    pause
    exit /b 1
)

REM Run the actual build
echo Building...
call c:\flutter\bin\flutter.bat build web --release

if errorlevel 1 (
    echo.
    echo ERROR: Build failed!
    pause
    exit /b 1
)

echo.
echo ================================================================================
echo                    BUILD COMPLETE!
echo ================================================================================
echo.
echo The app has been rebuilt successfully!
echo.
echo Next steps:
echo 1. Make sure Flask backend is running: python backend\app.py
echo 2. Open http://localhost:5000 in your browser
echo 3. Test:
echo    - Go to Simulation tab
echo    - Click "High CPU Alert"
echo    - Click "Auto-Remediate"
echo    - Go to History tab WITHOUT refreshing
echo    - New entry should appear IMMEDIATELY!
echo.
pause
