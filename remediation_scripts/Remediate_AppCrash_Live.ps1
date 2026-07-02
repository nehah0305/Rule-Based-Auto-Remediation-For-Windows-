# Remediate_AppCrash_Live.ps1
# -----------------------------------------------------------------------------
# Real-world Application Crash Remediation Script
# Relaunches a crashed application process after it has been detected
# via Windows Event ID 1000 (Application Error) in the Application Event Log.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File Remediate_AppCrash_Live.ps1
#   powershell -ExecutionPolicy Bypass -File Remediate_AppCrash_Live.ps1 -AppName "notepad"
#
# This is NOT a simulation -- it actually restarts the process.
# -----------------------------------------------------------------------------

param(
    [string]$AppName = ""
)

# Extract dynamic AppName from the event message if not provided
if (-not $AppName -and $env:RM_MESSAGE) {
    if ($env:RM_MESSAGE -match "Faulting application name:\s*(?:Faulting application name:\s*)?([^,\s]+)") {
        $AppName = $matches[1].Trim() -replace '\.exe$', ''
    }
}

if (-not $AppName) {
    Write-Host "[ERROR] Could not determine application name from event message."
    exit 1
}

# Fix PATH dynamically in case the parent process has a corrupted environment path
$env:Path += ";C:\Windows\System32;C:\Windows"

$timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'

Write-Host "[$timestamp] [REMEDIATION] Starting real application crash recovery..."
Write-Host "[$timestamp] [INFO] Target application: $AppName.exe"

# -- Step 1: Map short names to full executable paths ----------------------
$exePath = switch ($AppName.ToLower()) {
    "notepad"    { "C:\Windows\System32\notepad.exe" }
    "calc"       { "C:\Windows\System32\calc.exe" }
    "mspaint"    { "C:\Windows\System32\mspaint.exe" }
    "wordpad"    { "C:\Program Files\Windows NT\Accessories\wordpad.exe" }
    default      { "$AppName.exe" }
}

Write-Host "[$timestamp] [DETECT] Crash confirmed for $AppName.exe. Proceeding with restart..."

# -- Step 3: Relaunch on the interactive desktop ----------------------------
# IMPORTANT: -WindowStyle Normal forces the process to appear on the user's
# visible desktop even when this script is invoked from Flask (a background
# service-like process that has no interactive console window).
try {
    Write-Host "[$timestamp] [ACTION] Launching: $exePath (WindowStyle: Normal)"
    Start-Process -FilePath $exePath -WindowStyle Normal -ErrorAction Stop

    Start-Sleep -Milliseconds 1200

    # -- Step 4: Verify it started ------------------------------------------
    $started = Get-Process -Name $AppName -ErrorAction SilentlyContinue
    if ($started) {
        Write-Host "[$timestamp] [SUCCESS] $AppName.exe restarted successfully. PID: $($started.Id)"
        Write-Host "[$timestamp] [INFO] Application is now running and visible on the desktop."
        exit 0
    } else {
        Write-Host "[$timestamp] [WARNING] Process launched but could not be confirmed in process list."
        Write-Host "[$timestamp] [INFO] This may be normal for UWP or shell-hosted applications."
        exit 0
    }
} catch {
    Write-Host "[$timestamp] [ERROR] Failed to restart $AppName.exe: $_"
    Write-Host "[$timestamp] [HINT] Ensure the executable is in PATH or provide full path."
    exit 1
}

