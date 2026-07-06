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

# Prefer the rule's named regex capture when the backend provides it
if (-not $AppName -and $env:RM_MATCH_AppName) {
    $AppName = $env:RM_MATCH_AppName.Trim() -replace '\.exe$', ''
}

# Extract dynamic AppName from the event message if not provided.
# Tolerates the OS template doubling the prefix
# ("Faulting application name: Faulting application name: excel").
if (-not $AppName -and $env:RM_MESSAGE) {
    if ($env:RM_MESSAGE -match "(?i)Faulting application name:\s*(?:Faulting app(?:lication)? name:\s*)?([^\s,:]+)") {
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

# -- Step 1: Verify the process is NOT already running ----------------------
$existing = Get-Process -Name $AppName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "[$timestamp] [INFO] $AppName.exe is already running (PID: $($existing.Id)). No restart needed."
    exit 0
}

Write-Host "[$timestamp] [DETECT] $AppName.exe is NOT running -- crash confirmed. Proceeding with restart..."

# -- Step 2: Relaunch the application ---------------------------------------
# Attempt to relaunch the crashed application by trying common install locations
$appBase = $AppName -replace '\.exe$', ''
$launched = $false

# 0. Known Windows system app locations (fast path)
$knownPath = switch ($appBase.ToLower()) {
    "notepad"    { "C:\Windows\System32\notepad.exe" }
    "calc"       { "C:\Windows\System32\calc.exe" }
    "mspaint"    { "C:\Windows\System32\mspaint.exe" }
    "wordpad"    { "C:\Program Files\Windows NT\Accessories\wordpad.exe" }
    default      { $null }
}
if ($knownPath -and (Test-Path $knownPath)) {
    try {
        Start-Process $knownPath -ErrorAction Stop
        $launched = $true
        Write-Output "[OK] Relaunched $appBase from: $knownPath"
    } catch {}
}

# 1. Try direct process name (works if app is on PATH)
if (-not $launched) {
    try {
        Start-Process "$appBase.exe" -ErrorAction Stop
        $launched = $true
        Write-Output "[OK] Relaunched $appBase via PATH"
    } catch {}
}

# 2. Try common Office/application locations
if (-not $launched) {
    $searchPaths = @(
        "$env:ProgramFiles\Microsoft Office\root\Office16\$appBase.exe",
        "$env:ProgramFiles\Microsoft Office\Office16\$appBase.exe",
        "${env:ProgramFiles(x86)}\Microsoft Office\root\Office16\$appBase.exe",
        "${env:ProgramFiles(x86)}\Microsoft Office\Office16\$appBase.exe",
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\$appBase.exe"
    )
    foreach ($path in $searchPaths) {
        if (Test-Path $path) {
            try {
                Start-Process $path -ErrorAction Stop
                $launched = $true
                Write-Output "[OK] Relaunched $appBase from: $path"
                break
            } catch {}
        }
    }
}

# 3. Fallback: try shell verb (opens via file association/Windows Store)
if (-not $launched) {
    try {
        Start-Process "shell:appsFolder\$appBase" -ErrorAction Stop
        $launched = $true
        Write-Output "[OK] Relaunched $appBase via shell:appsFolder"
    } catch {}
}

if (-not $launched) {
    Write-Output "[WARN] Could not automatically relaunch $appBase. Please reopen it manually."
    exit 1
}

Start-Sleep -Milliseconds 800

# -- Step 3: Verify it started ------------------------------------------
$started = Get-Process -Name $appBase -ErrorAction SilentlyContinue
if ($started) {
    Write-Host "[$timestamp] [SUCCESS] $appBase.exe restarted successfully. PID: $($started.Id)"
    Write-Host "[$timestamp] [INFO] Application is now running and stable."
} else {
    Write-Host "[$timestamp] [WARNING] Process launched but could not be confirmed in process list."
    Write-Host "[$timestamp] [INFO] This may be normal for applications that spawn child processes."
}
exit 0
