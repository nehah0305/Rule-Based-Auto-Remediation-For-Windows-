@echo off
REM Start the Flask Backend Server
REM This script activates the virtual environment and starts the Flask application

echo ========================================
echo Flask Backend Server Launcher
echo ========================================
echo.

REM Check if .env file exists (look in script dir first, then repo root)
if not exist "%~dp0.env" if not exist "%~dp0..\.env" (
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

REM Check if virtual environment exists (allow repo-root .venv)
if not exist "%~dp0.venv\Scripts\activate.bat" if not exist "%~dp0..\.venv\Scripts\activate.bat" (
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
REM Prefer venv in script dir, fall back to repo root
if exist "%~dp0.venv\Scripts\activate.bat" (
    call "%~dp0.venv\Scripts\activate.bat"
) else (
    call "%~dp0..\.venv\Scripts\activate.bat"
)

echo.
echo Starting Flask backend server...
echo Configuration loaded from .env file
echo.
echo Press Ctrl+C to stop the server
echo.

REM Start the Flask application (resolve path to repo-root backend)
if exist "%~dp0backend\app.py" (
    python "%~dp0backend\app.py"
) else (
    python "%~dp0..\backend\app.py"
)

pause

