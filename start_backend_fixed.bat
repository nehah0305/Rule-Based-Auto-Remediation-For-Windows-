@echo off
REM Backend startup script with proper diagnostics
REM This script ensures all dependencies are installed and the Flask backend starts correctly

cd /d "%~dp0"
echo.
echo ════════════════════════════════════════════════════════════════
echo   FLASK BACKEND STARTUP
echo ════════════════════════════════════════════════════════════════
echo.

REM Check if Python is available
python --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python is not installed or not in PATH
    echo Please install Python 3.9+ from https://www.python.org
    pause
    exit /b 1
)

echo [✓] Python found
python --version

REM Check if backend directory exists
if not exist "backend" (
    echo ERROR: backend directory not found
    echo Please run this script from the project root directory
    pause
    exit /b 1
)

cd backend

REM Check if virtual environment exists, create if needed
if not exist "_env" (
    echo [→] Creating Python virtual environment...
    python -m venv _env
    if errorlevel 1 (
        echo ERROR: Failed to create virtual environment
        pause
        exit /b 1
    )
)

REM Activate virtual environment
echo [→] Activating virtual environment...
call _env\Scripts\activate.bat
if errorlevel 1 (
    echo ERROR: Failed to activate virtual environment
    pause
    exit /b 1
)

REM Install dependencies
echo [→] Checking and installing dependencies...
pip install --quiet -r requirements.txt
if errorlevel 1 (
    echo ERROR: Failed to install dependencies
    echo Run this command manually for details:
    echo   pip install -r requirements.txt
    pause
    exit /b 1
)

echo [✓] All dependencies installed

REM Initialize database
echo [→] Initializing database...
python db_init.py
if errorlevel 1 (
    echo WARNING: Database initialization had issues, but continuing...
)

echo [✓] Database ready

REM Start Flask backend
echo.
echo ════════════════════════════════════════════════════════════════
echo   STARTING FLASK BACKEND
echo ════════════════════════════════════════════════════════════════
echo.
echo Backend will run on: http://localhost:5000
echo Dashboard will be served from: http://localhost:5000
echo.
echo Press Ctrl+C to stop the backend
echo.

REM Run Flask app
python app.py

REM If Flask exits with error
if errorlevel 1 (
    echo.
    echo ERROR: Flask backend failed to start
    echo Please check the error messages above
    pause
)
