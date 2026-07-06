# run_frontend.ps1 - starts the Flutter Windows desktop app.
# Usage:  powershell -ExecutionPolicy Bypass -File run_frontend.ps1
#         powershell -ExecutionPolicy Bypass -File run_frontend.ps1 -ApiUrl http://localhost:5001
param(
    [string]$ApiUrl = ''
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

$fl = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $fl) {
    Write-Host "[FAIL] Flutter SDK not found on PATH." -ForegroundColor Red
    Write-Host "       Install it (https://docs.flutter.dev/get-started/install/windows) and enable" -ForegroundColor Yellow
    Write-Host "       Windows desktop support (Visual Studio 'Desktop development with C++' workload)." -ForegroundColor Yellow
    exit 1
}

Set-Location (Join-Path $root 'frontend')
flutter pub get

if ($ApiUrl) {
    Write-Host "[OK] Starting desktop app (backend: $ApiUrl)" -ForegroundColor Green
    flutter run -d windows --dart-define=API_URL=$ApiUrl
} else {
    Write-Host "[OK] Starting desktop app (backend: http://localhost:5000)" -ForegroundColor Green
    flutter run -d windows
}
