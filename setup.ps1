<#
.SYNOPSIS
    Setup script for Rule-Based Auto-Remediation System

.DESCRIPTION
    This script sets up the project for first-time use on any Windows system.
    It creates the virtual environment, installs dependencies, initializes the database,
    and creates the .env configuration file.

.EXAMPLE
    .\setup.ps1
#>

param(
    [switch]$SkipVenv,
    [switch]$SkipDatabase
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Rule-Based Auto-Remediation Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get the script directory (project root)
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ProjectRoot

Write-Host "Project Root: $ProjectRoot" -ForegroundColor Yellow
Write-Host ""

# Step 1: Check Python installation
Write-Host "[1/6] Checking Python installation..." -ForegroundColor Green
try {
    $pythonVersion = python --version 2>&1
    Write-Host "  ✓ Found: $pythonVersion" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Python not found! Please install Python 3.8+ and add it to PATH." -ForegroundColor Red
    exit 1
}
Write-Host ""

# Step 2: Create virtual environment
if (-not $SkipVenv) {
    Write-Host "[2/6] Creating virtual environment..." -ForegroundColor Green
    if (Test-Path ".venv") {
        Write-Host "  ℹ Virtual environment already exists, skipping..." -ForegroundColor Yellow
    } else {
        python -m venv .venv
        Write-Host "  ✓ Virtual environment created" -ForegroundColor Green
    }
} else {
    Write-Host "[2/6] Skipping virtual environment creation..." -ForegroundColor Yellow
}
Write-Host ""

# Step 3: Activate virtual environment and install dependencies
Write-Host "[3/6] Installing Python dependencies..." -ForegroundColor Green
$venvActivate = Join-Path $ProjectRoot ".venv\Scripts\Activate.ps1"
if (Test-Path $venvActivate) {
    & $venvActivate
    pip install -r backend\requirements.txt
    Write-Host "  ✓ Dependencies installed" -ForegroundColor Green
} else {
    Write-Host "  ⚠ Virtual environment not found, installing globally..." -ForegroundColor Yellow
    pip install -r backend\requirements.txt
}
Write-Host ""

# Step 4: Create .env file from template
Write-Host "[4/6] Creating configuration file..." -ForegroundColor Green
if (Test-Path ".env") {
    Write-Host "  ℹ .env file already exists" -ForegroundColor Yellow
    $overwrite = Read-Host "  Do you want to overwrite it? (y/N)"
    if ($overwrite -eq "y" -or $overwrite -eq "Y") {
        Copy-Item ".env.example" ".env" -Force
        Write-Host "  ✓ .env file created from template" -ForegroundColor Green
    } else {
        Write-Host "  ℹ Keeping existing .env file" -ForegroundColor Yellow
    }
} else {
    Copy-Item ".env.example" ".env"
    Write-Host "  ✓ .env file created from template" -ForegroundColor Green
}
Write-Host ""

# Step 5: Get server IP for configuration
Write-Host "[5/6] Configuring API endpoint..." -ForegroundColor Green
$networkAdapters = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.*" }
if ($networkAdapters) {
    Write-Host "  Detected IP addresses:" -ForegroundColor Cyan
    foreach ($adapter in $networkAdapters) {
        Write-Host "    - $($adapter.IPAddress)" -ForegroundColor Cyan
    }
    Write-Host ""
    Write-Host "  For local-only access, use: http://localhost:5000" -ForegroundColor Yellow
    Write-Host "  For network access, use: http://<IP-ADDRESS>:5000" -ForegroundColor Yellow
    Write-Host ""
    $updateConfig = Read-Host "  Do you want to update the API URL in .env now? (y/N)"
    if ($updateConfig -eq "y" -or $updateConfig -eq "Y") {
        $apiUrl = Read-Host "  Enter API URL (e.g., http://192.168.1.100:5000)"
        if ($apiUrl) {
            (Get-Content ".env") -replace "API_BASE_URL=.*", "API_BASE_URL=$apiUrl" | Set-Content ".env"
            Write-Host "  ✓ API URL updated to: $apiUrl" -ForegroundColor Green
        }
    }
}
Write-Host ""

# Step 6: Initialize database
if (-not $SkipDatabase) {
    Write-Host "[6/6] Initializing database..." -ForegroundColor Green
    python backend\db_init.py
    Write-Host "  ✓ Database initialized" -ForegroundColor Green
} else {
    Write-Host "[6/6] Skipping database initialization..." -ForegroundColor Yellow
}
Write-Host ""

# Final instructions
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "✓ Setup Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Review and edit .env file if needed" -ForegroundColor White
Write-Host "  2. Start the backend:" -ForegroundColor White
Write-Host "     .\.venv\Scripts\activate" -ForegroundColor Cyan
Write-Host "     python backend\app.py" -ForegroundColor Cyan
Write-Host ""
Write-Host "  3. Start the event monitor:" -ForegroundColor White
Write-Host "     .\start_event_monitor.bat" -ForegroundColor Cyan
Write-Host ""
Write-Host "  4. Open the dashboard:" -ForegroundColor White
Write-Host "     http://localhost:5000" -ForegroundColor Cyan
Write-Host ""
Write-Host "For detailed instructions, see INSTALLATION.md" -ForegroundColor Yellow
Write-Host ""

