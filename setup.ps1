# setup.ps1 - one-time setup for the Rule-Based Auto-Remediation app.
# Usage:  powershell -ExecutionPolicy Bypass -File setup.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "=== Rule-Based Auto-Remediation :: Setup ===" -ForegroundColor Cyan

# 1. Must be Windows (the app monitors the Windows Event Log and runs PowerShell remediations)
if ($env:OS -ne 'Windows_NT') {
    Write-Host "[FAIL] This app requires Windows 10/11." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Windows detected"

# 2. Python 3.10+
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) {
    Write-Host "[FAIL] Python not found on PATH. Install Python 3.10+ from https://python.org and re-run." -ForegroundColor Red
    exit 1
}
$ver = & python -c "import sys; print('%d.%d' % sys.version_info[:2])"
$parts = $ver.Split('.')
if ([int]$parts[0] -lt 3 -or ([int]$parts[0] -eq 3 -and [int]$parts[1] -lt 10)) {
    Write-Host "[FAIL] Python 3.10+ required (found $ver)." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Python $ver"

# 3. Virtual environment + dependencies
$venv = Join-Path $root '.venv'
$venvPy = Join-Path $venv 'Scripts\python.exe'
if (-not (Test-Path $venvPy)) {
    Write-Host "[..] Creating virtual environment (.venv)"
    & python -m venv $venv
}
Write-Host "[..] Installing Python dependencies"
& $venvPy -m pip install --upgrade pip --quiet
& $venvPy -m pip install -r (Join-Path $root 'backend\requirements.txt') --quiet
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] pip install failed - see output above." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Python dependencies installed"

# 4. .env from template (first run only)
$envFile = Join-Path $root '.env'
if (-not (Test-Path $envFile)) {
    Copy-Item (Join-Path $root '.env.example') $envFile
    Write-Host "[OK] Created .env from .env.example"
}

# 5. Flutter (optional - only needed for the desktop UI)
$fl = Get-Command flutter -ErrorAction SilentlyContinue
if ($fl) {
    Write-Host "[..] Fetching Flutter dependencies"
    Push-Location (Join-Path $root 'frontend')
    flutter pub get | Out-Null
    Pop-Location
    Write-Host "[OK] Flutter dependencies fetched"
} else {
    Write-Host "[INFO] Flutter SDK not found - backend-only setup complete." -ForegroundColor Yellow
    Write-Host "       Install Flutter (with Windows desktop support) to run the UI - see README." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Setup complete. Next steps:" -ForegroundColor Green
Write-Host "  .\run_backend.ps1     starts the Flask backend (keep it running)"
Write-Host "  .\run_frontend.ps1    starts the Flutter desktop app (separate terminal)"
Write-Host ""
Write-Host "Tip: run the simulation scripts from an ADMINISTRATOR PowerShell -"
Write-Host "     they write real entries to the Windows Event Log."
