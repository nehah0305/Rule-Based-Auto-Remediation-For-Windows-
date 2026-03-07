@echo off
REM Start the Flask Backend Server
REM This script activates the virtual environment and starts the Flask application

echo ========================================
echo Flask Backend Server Launcher
echo ========================================
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

REM Check if virtual environment exists
if not exist "%~dp0.venv\Scripts\activate.bat" (
    echo WARNING: Virtual environment not found!
    echo.
    echo Please run setup.ps1 first to create the virtual environment:
    echo   powershell -ExecutionPolicy Bypass -File setup.ps1
    echo.
    echo Or create it manually:
    echo   python -m venv .venv
    echo   .\.venv\Scripts\activate
    echo   pip install -r backend\requirements.txt
    echo.
    pause
    exit /b 1
)

echo Activating virtual environment...
call "%~dp0.venv\Scripts\activate.bat"

echo.
echo Starting Flask backend server...
echo Configuration loaded from .env file
echo.
echo Press Ctrl+C to stop the server
echo.

REM Start the Flask application
python "%~dp0backend\app.py"

pause

