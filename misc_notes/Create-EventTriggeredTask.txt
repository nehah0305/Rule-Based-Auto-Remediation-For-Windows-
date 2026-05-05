# PowerShell Script to Create a Task Scheduler Task Triggered by Windows Event Viewer
# This script creates a scheduled task that runs when a specific Windows event occurs

<#
.SYNOPSIS
    Creates a scheduled task triggered by a Windows Event Viewer event.

.DESCRIPTION
    This script demonstrates how to create a Windows Task Scheduler task that is triggered
    by a specific event in the Windows Event Viewer. You can customize the event log,
    event ID, and the action to perform.

.EXAMPLE
    .\Create-EventTriggeredTask.ps1
#>

# Requires Administrator privileges
#Requires -RunAsAdministrator

# ===== CONFIGURATION SECTION =====
# Customize these variables according to your needs

# Task Configuration
$TaskName = "EventTriggeredTask"
$TaskDescription = "Task triggered by Windows Event Viewer event"

# Event Trigger Configuration
$EventLogName = "System"           # Common options: System, Application, Security
$EventSource = "*"                 # Event source (use * for any source)
$EventID = 1074                    # Event ID to monitor (1074 = System shutdown initiated)

# Alternative examples:
# Event ID 4624 = Successful logon (Security log)
# Event ID 1000 = Application error (Application log)
# Event ID 7036 = Service state change (System log)

# Action Configuration - What to execute when event occurs
$ActionExecutable = "powershell.exe"
$ActionArguments = '-NoProfile -WindowStyle Hidden -Command "& { Add-Content -Path C:\Logs\EventLog.txt -Value \"Event triggered at $(Get-Date)\" }"'

# ===== SCRIPT EXECUTION =====

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Creating Event-Triggered Scheduled Task" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Create the log directory if it doesn't exist
$LogDir = "C:\Logs"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    Write-Host "[+] Created log directory: $LogDir" -ForegroundColor Green
}

# Check if task already exists
$ExistingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($ExistingTask) {
    Write-Host "[!] Task '$TaskName' already exists. Removing it..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "[+] Existing task removed." -ForegroundColor Green
}

# Create the Event Trigger using CIM
Write-Host "[*] Configuring event trigger..." -ForegroundColor Cyan
Write-Host "    Log Name: $EventLogName" -ForegroundColor Gray
Write-Host "    Event ID: $EventID" -ForegroundColor Gray

# Create the event trigger XML query
$EventQuery = @"
<QueryList>
  <Query Id="0" Path="$EventLogName">
    <Select Path="$EventLogName">*[System[(EventID=$EventID)]]</Select>
  </Query>
</QueryList>
"@

# Create CIM trigger
$CIMTriggerClass = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler:MSFT_TaskEventTrigger
$Trigger = New-CimInstance -CimClass $CIMTriggerClass -ClientOnly
$Trigger.Subscription = $EventQuery
$Trigger.Enabled = $True

Write-Host "[+] Event trigger configured." -ForegroundColor Green

# Create the Action
Write-Host "[*] Configuring task action..." -ForegroundColor Cyan
$Action = New-ScheduledTaskAction -Execute $ActionExecutable -Argument $ActionArguments
Write-Host "[+] Task action configured." -ForegroundColor Green

# Create Task Settings
$Settings = New-ScheduledTaskSettings -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

# Create the Task Principal (run with highest privileges)
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

# Register the Scheduled Task
Write-Host "[*] Registering scheduled task..." -ForegroundColor Cyan
try {
    Register-ScheduledTask -TaskName $TaskName `
                          -Description $TaskDescription `
                          -Trigger $Trigger `
                          -Action $Action `
                          -Settings $Settings `
                          -Principal $Principal `
                          -ErrorAction Stop
    
    Write-Host "[+] Task '$TaskName' successfully created!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Task Details:" -ForegroundColor Cyan
    Write-Host "  - Task Name: $TaskName" -ForegroundColor White
    Write-Host "  - Trigger: Event ID $EventID from $EventLogName log" -ForegroundColor White
    Write-Host "  - Action: $ActionExecutable" -ForegroundColor White
    Write-Host ""
    Write-Host "[i] You can view this task in Task Scheduler under:" -ForegroundColor Yellow
    Write-Host "    Task Scheduler Library > $TaskName" -ForegroundColor Yellow
    
} catch {
    Write-Host "[!] Error creating scheduled task:" -ForegroundColor Red
    Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Display the created task
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Task Configuration Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$Task = Get-ScheduledTask -TaskName $TaskName
$Task | Format-List TaskName, State, Description

Write-Host ""
Write-Host "[✓] Setup complete!" -ForegroundColor Green
Write-Host ""

# Optional: Display how to test or view the task
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Open Task Scheduler (taskschd.msc) to view the task" -ForegroundColor White
Write-Host "2. The task will trigger when Event ID $EventID occurs in the $EventLogName log" -ForegroundColor White
Write-Host "3. Check C:\Logs\EventLog.txt for execution logs" -ForegroundColor White
Write-Host ""
