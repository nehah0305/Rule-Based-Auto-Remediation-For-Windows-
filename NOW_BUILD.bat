@echo off
REM Absolute simplest Flutter build - no path complexity

setlocal

cd /d c:\Users\bios\Desktop\unisys-ab\Rule-Based-Auto-Remediation-For-Windows-\frontend

echo Building...
c:\flutter\bin\flutter.bat pub get
c:\flutter\bin\flutter.bat build web --release

if errorlevel 1 (
    echo Build failed
    pause
    exit /b 1
)

echo Build complete!
pause
