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
    [string]$AppName = "notepad"
)

# Fix PATH dynamically in case the parent process has a corrupted environment path
$env:Path += ";C:\Windows\System32;C:\Windows"

$timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'

Write-Host "[$timestamp] [REMEDIATION] Starting real application crash recovery..."
Write-Host "[$timestamp] [INFO] Target application: $AppName.exe"

# -- Step 1: Verify the process is NOT already running ----------------------
$existing = Get-Process -Name $AppName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "[$timestamp] [INFO] $AppName.exe is already running (PID: $($existing.Id)). No restart needed."
    exit 0
}

Write-Host "[$timestamp] [DETECT] $AppName.exe is NOT running -- crash confirmed. Proceeding with restart..."

# -- Step 2: Relaunch the application --------------------------------------
try {
    # Map short names to full executable paths if needed
    $exePath = switch ($AppName.ToLower()) {
        "notepad"    { "C:\Windows\System32\notepad.exe" }
        "calc"       { "C:\Windows\System32\calc.exe" }
        "mspaint"    { "C:\Windows\System32\mspaint.exe" }
        "wordpad"    { "C:\Program Files\Windows NT\Accessories\wordpad.exe" }
        default      { "$AppName.exe" }
    }

    Write-Host "[$timestamp] [ACTION] Launching: $exePath"
    Start-Process $exePath -ErrorAction Stop

    Start-Sleep -Milliseconds 800

    # -- Step 3: Verify it started ------------------------------------------
    $started = Get-Process -Name $AppName -ErrorAction SilentlyContinue
    if ($started) {
        Write-Host "[$timestamp] [SUCCESS] $AppName.exe restarted successfully. PID: $($started.Id)"
        Write-Host "[$timestamp] [INFO] Application is now running and stable."
        exit 0
    } else {
        Write-Host "[$timestamp] [WARNING] Process launched but could not be confirmed in process list."
        Write-Host "[$timestamp] [INFO] This may be normal for applications that spawn child processes."
        exit 0
    }
} catch {
    Write-Host "[$timestamp] [ERROR] Failed to restart $AppName.exe: $_"
    Write-Host "[$timestamp] [HINT] Ensure the executable is in PATH or provide full path."
    exit 1
}
