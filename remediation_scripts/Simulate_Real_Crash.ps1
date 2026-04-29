# Simulate_Real_Crash.ps1
# -----------------------------------------------------------------------------
# This script creates a realistic demonstration of an application crash.
# It forcefully terminates the target application (making it visually disappear)
# and immediately writes the corresponding Application Error (Event ID 1000)
# to the Windows Event Log so the Auto-Remediation dashboard detects it.
# -----------------------------------------------------------------------------

param(
    [string]$AppName = "notepad"
)

Write-Host "[*] Preparing to simulate a hard crash for $AppName.exe..."

# 1. Ensure the app is actually running so we can crash it
$process = Get-Process -Name $AppName -ErrorAction SilentlyContinue
if (-not $process) {
    Write-Host "[+] $AppName is not running. Starting it now for the demonstration..."
    Start-Process "$AppName.exe"
    Start-Sleep -Seconds 2
    $process = Get-Process -Name $AppName -ErrorAction SilentlyContinue
}

if ($process) {
    Write-Host "[!] Forcefully terminating $AppName.exe (PID: $($process[0].Id)) to simulate a crash..."
    Stop-Process -Name $AppName -Force
    Write-Host "[-] $AppName.exe has crashed and disappeared from the screen."
} else {
    Write-Host "[x] Could not start or find $AppName.exe."
    exit 1
}

# 2. Write the Windows Event Log (Event ID 1000) so the dashboard detects it
Write-Host "[!] Writing Event ID 1000 (Application Error) to the Windows Registry..."
Write-EventLog -LogName Application -Source "Application Error" -EventId 1000 -EntryType Error -Message "Faulting application name: $AppName.exe, version: 10.0.19041.1, time stamp: 0x5e2b0a1a`r`nFaulting module name: ntdll.dll, version: 10.0.19041.1"

Write-Host "[+] Crash simulation complete! The dashboard should detect the crash within 3 seconds."
