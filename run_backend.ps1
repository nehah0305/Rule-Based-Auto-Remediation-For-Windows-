# run_backend.ps1 - starts the Flask backend with preflight checks.
# Usage:  powershell -ExecutionPolicy Bypass -File run_backend.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

# Resolve the port (FLASK_PORT in .env, default 5000)
$port = 5000
$envFile = Join-Path $root '.env'
if (Test-Path $envFile) {
    $line = Select-String -Path $envFile -Pattern '^\s*FLASK_PORT\s*=\s*(\d+)' | Select-Object -First 1
    if ($line) { $port = [int]$line.Matches[0].Groups[1].Value }
}

# Preflight: is the port free?
$inUse = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
if ($inUse) {
    $owner = $inUse | Select-Object -First 1
    Write-Host "[FAIL] Port $port is already in use (PID $($owner.OwningProcess))." -ForegroundColor Red
    Write-Host "       Stop that process, or set a different FLASK_PORT in .env and start the UI with:" -ForegroundColor Yellow
    Write-Host "       .\run_frontend.ps1 -ApiUrl http://localhost:<port>" -ForegroundColor Yellow
    exit 1
}

# Prefer the project venv; fall back to system python
$venvPy = Join-Path $root '.venv\Scripts\python.exe'
if (-not (Test-Path $venvPy)) {
    Write-Host "[INFO] No .venv found (run .\setup.ps1 first) - using system python." -ForegroundColor Yellow
    $venvPy = 'python'
}

Write-Host "[OK] Starting backend on http://localhost:$port  (Ctrl+C to stop)" -ForegroundColor Green
Set-Location (Join-Path $root 'backend')
& $venvPy app.py
