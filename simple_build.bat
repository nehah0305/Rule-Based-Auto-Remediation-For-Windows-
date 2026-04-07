@echo off
setlocal enabledelayedexpansion

REM Very simple build script
REM Just run flutter from fresh CMD environment

echo Starting Flutter build...
cd /d "C:\Users\bios\Desktop\unisys-ab\Rule-Based-Auto-Remediation-For-Windows-\frontend"

REM Try pub get first
echo Getting dependencies...
call C:\flutter\bin\flutter.bat pub get
if errorlevel 1 echo WARNING: pub get had issues, continuing...

REM Build web
echo.
echo Building web app (this will take 2-5 minutes)...
echo.
call C:\flutter\bin\flutter.bat build web --web-renderer canvaskit --release

if errorlevel 1 (
    echo.
    echo BUILD FAILED - Check errors above
    pause
    exit /b 1
)

echo.
echo ===================================================
echo BUILD SUCCESSFUL!
echo ===================================================
echo.
echo App is at: frontend\build\web\
echo Listening at: http://localhost:5000
echo.
pause
