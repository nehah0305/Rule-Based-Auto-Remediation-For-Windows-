<#
.SYNOPSIS
    Install the Event Monitor as a Windows Scheduled Task

.DESCRIPTION
    Creates a Windows Scheduled Task that runs the event monitor continuously.
    The task starts at system startup and runs with elevated privileges.

.PARAMETER TaskName
    Name of the scheduled task (default: WindowsEventMonitor)

.PARAMETER RunAsUser
    User account to run the task (default: SYSTEM)

.EXAMPLE
    .\install_as_task.ps1

.EXAMPLE
    .\install_as_task.ps1 -TaskName "MyEventMonitor" -RunAsUser "DOMAIN\User"
#>

param(
    [string]$TaskName = "WindowsEventMonitor",
    [string]$RunAsUser = "SYSTEM"
)

# Check if running as administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Please right-click and select 'Run as Administrator'" -ForegroundColor Yellow
    pause
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Install Event Monitor as Scheduled Task" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Get the script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$monitorScript = Join-Path $scriptDir "event_monitor_config.ps1"

if (-not (Test-Path $monitorScript)) {
    Write-Host "Monitor script not found: $monitorScript" -ForegroundColor Red
    exit 1
}

Write-Host "Monitor Script: $monitorScript" -ForegroundColor Green
Write-Host "Task Name: $TaskName" -ForegroundColor Green
Write-Host "Run As: $RunAsUser`n" -ForegroundColor Green

# Check if task already exists
$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

if ($existingTask) {
    Write-Host "Task '$TaskName' already exists." -ForegroundColor Yellow
    $response = Read-Host "Do you want to remove and recreate it? (Y/N)"
    
    if ($response -eq 'Y' -or $response -eq 'y') {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Existing task removed." -ForegroundColor Green
    } else {
        Write-Host "Installation cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Create the scheduled task action
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$monitorScript`""

# Create the trigger (at startup)
$trigger = New-ScheduledTaskTrigger -AtStartup

# Create the settings
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable `
    -DontStopOnIdleEnd `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

# Create the principal (user context)
if ($RunAsUser -eq "SYSTEM") {
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
} else {
    $principal = New-ScheduledTaskPrincipal -UserId $RunAsUser -LogonType Interactive -RunLevel Highest
}

# Register the task
try {
    Register-ScheduledTask -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description "Monitors Windows Event Logs and sends events to the Auto-Remediation backend" `
        -ErrorAction Stop
    
    Write-Host "`n✓ Scheduled task created successfully!" -ForegroundColor Green
    Write-Host "`nTask Details:" -ForegroundColor Cyan
    Write-Host "  Name: $TaskName" -ForegroundColor White
    Write-Host "  Trigger: At system startup" -ForegroundColor White
    Write-Host "  Action: Run event monitor script" -ForegroundColor White
    Write-Host "  User: $RunAsUser" -ForegroundColor White
    
    Write-Host "`nTo manage the task:" -ForegroundColor Yellow
    Write-Host "  Start:  Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Gray
    Write-Host "  Stop:   Stop-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Gray
    Write-Host "  Remove: Unregister-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Gray
    Write-Host "  Status: Get-ScheduledTask -TaskName '$TaskName' | Get-ScheduledTaskInfo" -ForegroundColor Gray
    
    Write-Host "`nDo you want to start the task now? (Y/N): " -NoNewline -ForegroundColor Yellow
    $startNow = Read-Host
    
    if ($startNow -eq 'Y' -or $startNow -eq 'y') {
        Start-ScheduledTask -TaskName $TaskName
        Write-Host "✓ Task started!" -ForegroundColor Green
        Write-Host "`nThe event monitor is now running in the background." -ForegroundColor Green
        Write-Host "Check Task Scheduler or Event Viewer for logs." -ForegroundColor Gray
    }
}
catch {
    Write-Host "`n✗ Failed to create scheduled task: $_" -ForegroundColor Red
    exit 1
}

Write-Host "`nInstallation complete!" -ForegroundColor Green
pause

