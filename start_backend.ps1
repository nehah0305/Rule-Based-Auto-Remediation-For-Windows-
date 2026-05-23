# Backend startup script with comprehensive diagnostics
# This script will identify and fix common startup issues

param(
    [switch]$NoVenv = $false,
    [switch]$NoInstall = $false
)

Write-Host "`n" -ForegroundColor Gray
Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  FLASK BACKEND - DIAGNOSTIC & STARTUP SCRIPT" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Check Python
Write-Host "[→] Checking Python installation..." -ForegroundColor Yellow
$pythonVer = python --version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "[✗] Python not found in PATH" -ForegroundColor Red
    Write-Host "    Please install Python 3.9+ from https://www.python.org" -ForegroundColor Red
    pause
    exit 1
}
Write-Host "[✓] $pythonVer" -ForegroundColor Green

# Navigate to backend
Push-Location (Join-Path $PSScriptRoot backend)
Write-Host "[→] Working directory: $(Get-Location)" -ForegroundColor Yellow

# Virtual environment setup
if (-not $NoVenv) {
    if (-not (Test-Path _env)) {
        Write-Host "[→] Creating Python virtual environment..." -ForegroundColor Yellow
        python -m venv _env
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[✗] Failed to create virtual environment" -ForegroundColor Red
            pause
            exit 1
        }
    }
    
    Write-Host "[→] Activating virtual environment..." -ForegroundColor Yellow
    & .\\_env\\Scripts\\Activate.ps1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[✗] Failed to activate virtual environment" -ForegroundColor Red
        Write-Host "    Try running: .\\_env\\Scripts\\Activate.ps1" -ForegroundColor Yellow
        pause
        exit 1
    }
}

# Install dependencies
if (-not $NoInstall) {
    Write-Host "[→] Installing Python dependencies..." -ForegroundColor Yellow
    pip install -q -r requirements.txt 2>&1 | Where-Object { $_ -match 'error|ERROR' } | ForEach-Object { 
        Write-Host "    $_" -ForegroundColor Red 
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[!] Some packages may not have installed correctly" -ForegroundColor Yellow
        Write-Host "    Try running manually: pip install -r requirements.txt" -ForegroundColor Yellow
    } else {
        Write-Host "[✓] Dependencies installed" -ForegroundColor Green
    }
}

# Check .env file
Write-Host "[→] Checking configuration..." -ForegroundColor Yellow
if (-not (Test-Path .env)) {
    Write-Host "[!] Creating .env file with default settings..." -ForegroundColor Yellow
    @"
FLASK_HOST=0.0.0.0
FLASK_PORT=5000
FLASK_DEBUG=True
USE_TASK_SCHEDULER=false
POLL_INTERVAL=10
MAX_EVENTS_PER_POLL=50
"@ | Set-Content .env
    Write-Host "[✓] .env created" -ForegroundColor Green
} else {
    Write-Host "[✓] .env file exists" -ForegroundColor Green
}

# Initialize database
Write-Host "[→] Initializing database..." -ForegroundColor Yellow
python db_init.py 2>&1 | Select-Object -First 10
if ($LASTEXITCODE -ne 0) {
    Write-Host "[!] Warning: Database initialization had issues, but continuing..." -ForegroundColor Yellow
} else {
    Write-Host "[✓] Database initialized" -ForegroundColor Green
}

# Port check
Write-Host "[→] Checking if port 5000 is available..." -ForegroundColor Yellow
$portCheck = netstat -ano 2>$null | Select-String ":5000 "
if ($portCheck) {
    Write-Host "[!] Port 5000 is already in use!" -ForegroundColor Red
    Write-Host "    $portCheck" -ForegroundColor Yellow
    Write-Host "    Please close the existing application or use a different port" -ForegroundColor Yellow
    Write-Host "    To change port, set FLASK_PORT in .env" -ForegroundColor Yellow
} else {
    Write-Host "[✓] Port 5000 is available" -ForegroundColor Green
}

Write-Host ""
Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  STARTING FLASK BACKEND" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "Backend API: http://localhost:5000" -ForegroundColor Green
Write-Host "Dashboard:   http://localhost:5000" -ForegroundColor Green
Write-Host ""
Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow
Write-Host ""

# Start Flask
python app.py

# Error handling
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "[✗] Flask exited with error code: $LASTEXITCODE" -ForegroundColor Red
    Write-Host "    Check the error messages above" -ForegroundColor Yellow
    pause
}

Pop-Location
