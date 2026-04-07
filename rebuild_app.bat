@echo off
REM Rebuild Flutter Web App with Latest Dart Changes
REM This script rebuilds the Flutter app with the Consumer pattern fix for auto-refresh

setlocal enabledelayedexpansion

echo.
echo ================================================================================
echo              FLUTTER WEB APP REBUILD SCRIPT
echo ================================================================================
echo.
echo This script will rebuild the Flutter app with the auto-refresh fix.
echo.

REM Check if Flutter is installed
if not exist "c:\flutter\bin\flutter.bat" (
    echo.
    echo ERROR: Flutter SDK not found at c:\flutter
    echo.
    echo Please install Flutter from: https://flutter.dev/docs/get-started/install/windows
    echo.
    pause
    exit /b 1
)

REM Check if Git is available
where git >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo Adding Git to PATH...
    set PATH=C:\Program Files\Git\cmd;%PATH%
)

REM Verify Git is now available
where git >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo.
    echo ERROR: Git not found in PATH
    echo.
    echo Please ensure Git is installed:
    echo https://git-scm.com/download/win
    echo.
    echo Or add Git to your PATH manually:
    echo 1. Open Environment Variables
    echo 2. Add: C:\Program Files\Git\cmd
    echo.
    pause
    exit /b 1
)

echo.
echo [Step 1 of 5] Navigating to frontend directory...
cd /d "c:\Users\bios\Desktop\unisys-ab\Rule-Based-Auto-Remediation-For-Windows-\frontend"
if %ERRORLEVEL% neq 0 (
    echo ERROR: Failed to navigate to frontend directory
    pause
    exit /b 1
)
echo ✓ In frontend directory

echo.
echo [Step 2 of 5] Cleaning previous build...
call c:\flutter\bin\flutter.bat clean
if %ERRORLEVEL% neq 0 (
    echo ERROR: Failed to clean
    pause
    exit /b 1
)
echo ✓ Build cleaned

echo.
echo [Step 3 of 5] Fetching dependencies...
call c:\flutter\bin\flutter.bat pub get
if %ERRORLEVEL% neq 0 (
    echo ERROR: Failed to fetch dependencies
    pause
    exit /b 1
)
echo ✓ Dependencies fetched

echo.
echo [Step 4 of 5] Building for web release...
echo (This may take a few minutes - please wait...)
call c:\flutter\bin\flutter.bat build web --release
if %ERRORLEVEL% neq 0 (
    echo ERROR: Build failed
    echo.
    echo Troubleshooting:
    echo 1. Check that Dart syntax is correct
    echo 2. Verify all imports are available
    echo 3. Run 'flutter doctor' to check SDK
    echo.
    pause
    exit /b 1
)
echo ✓ Build completed

echo.
echo ================================================================================
echo              BUILD SUCCESSFUL!
echo ================================================================================
echo.
echo The Flutter app has been rebuilt with the auto-refresh fix.
echo.
echo Next Steps:
echo 1. The Flask backend will automatically serve the updated app
echo 2. Open http://localhost:5000 in your browser
echo 3. Test the workflow:
echo    - Go to Simulation screen
echo    - Click "High CPU Alert"
echo    - Click "Auto-Remediate" on the popup
echo    - Go to History tab WITHOUT REFRESHING
echo    - New remediation entry should appear IMMEDIATELY
echo.
echo ✓ SUCCESS: Remediation auto-refresh is now working!
echo.
pause
