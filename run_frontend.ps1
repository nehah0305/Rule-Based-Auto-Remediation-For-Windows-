# run_frontend.ps1 - starts the Flutter Windows desktop app.
# Usage:  powershell -ExecutionPolicy Bypass -File run_frontend.ps1
#         powershell -ExecutionPolicy Bypass -File run_frontend.ps1 -ApiUrl http://localhost:5001
param(
    [string]$ApiUrl = '',
    [string]$Device = ''
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

if (-not $Device) {
    $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    $vsInstalled = $false
    if (Test-Path $vsWhere) {
        $vsPath = & $vsWhere -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($vsPath) { $vsInstalled = $true }
    }
    
    if ($vsInstalled) {
        $Device = 'windows'
    } else {
        Write-Host "[INFO] Visual Studio C++ workload not found. Launching on Chrome (web)..." -ForegroundColor Yellow
        Write-Host "       (To build native Windows desktop app, install Visual Studio 'Desktop development with C++')" -ForegroundColor Yellow
        $Device = 'chrome'
    }
}

$dartDefines = @()
if ($ApiUrl) {
    $dartDefines += "--dart-define=API_URL=$ApiUrl"
}

Write-Host "[OK] Starting app on target device '$Device' (backend: $(if ($ApiUrl) { $ApiUrl } else { 'http://localhost:5000' }))" -ForegroundColor Green
if ($dartDefines.Count -gt 0) {
    flutter run -d $Device $dartDefines
} else {
    flutter run -d $Device
}

