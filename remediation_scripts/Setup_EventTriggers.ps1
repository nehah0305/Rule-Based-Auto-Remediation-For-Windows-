# Setup_EventTriggers.ps1
# ═══════════════════════════════════════════════════════════════════════════════
# Installs Windows Task Scheduler tasks that watch the Event Log 24/7 and
# instantly invoke the auto-remediation pipeline the moment a watched error fires.
#
# HOW TO RUN:
#   Right-click → "Run as Administrator"
#   — OR —
#   Start-Process powershell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PSScriptRoot\Setup_EventTriggers.ps1`""
#
# WHAT IT DOES:
#   1. Auto-elevates itself to Administrator if not already elevated.
#   2. Detects the exact python.exe used by this project (venv-aware).
#   3. Registers one Task Scheduler task per watched Event ID.
#   4. Each task runs silently (hidden window) the instant a matching event fires.
#   5. Suppresses duplicate task launches if a previous run is still active.
# ═══════════════════════════════════════════════════════════════════════════════

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Self-elevation: re-launch as Administrator if needed ────────────────────
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Host "[*] Not running as Administrator. Requesting elevation..." -ForegroundColor Yellow
    $scriptPath = $MyInvocation.MyCommand.Definition
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    exit 0
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Auto-Remediation Task Scheduler Setup                " -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ── Resolve project paths ───────────────────────────────────────────────────
# This script lives in: <project_root>\remediation_scripts\
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProjectRoot = Split-Path -Parent $ScriptDir
$BackendDir  = Join-Path $ProjectRoot 'backend'
$CliScript   = Join-Path $BackendDir 'cli_process_event.py'

Write-Host "[INFO] Project root : $ProjectRoot"
Write-Host "[INFO] Backend dir  : $BackendDir"
Write-Host "[INFO] CLI script   : $CliScript"
Write-Host ""

if (-not (Test-Path $CliScript)) {
    Write-Host "[ERROR] cli_process_event.py not found at: $CliScript" -ForegroundColor Red
    Write-Host "        Please ensure the backend directory is intact." -ForegroundColor Red
    exit 1
}

# ── Detect the correct python.exe (handles venv, global installs) ───────────
# Priority: project venv → PATH python → system-wide python
$PythonExe = $null

$VenvPython = Join-Path $BackendDir '_env\Scripts\python.exe'
if (Test-Path $VenvPython) {
    $PythonExe = $VenvPython
    Write-Host "[INFO] Using virtual environment Python: $PythonExe" -ForegroundColor Green
} else {
    $pyCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pyCmd) {
        $PythonExe = $pyCmd.Source
    }
    if (-not $PythonExe) {
        $pyCmd3 = Get-Command python3 -ErrorAction SilentlyContinue
        if ($pyCmd3) {
            $PythonExe = $pyCmd3.Source
        }
    }
    if (-not $PythonExe) {
        Write-Host "[ERROR] Python executable not found in PATH or project venv." -ForegroundColor Red
        Write-Host "        Install Python or activate your virtual environment and retry." -ForegroundColor Red
        exit 1
    }
    Write-Host "[INFO] Using system Python: $PythonExe" -ForegroundColor Green
}

Write-Host ""

# ── Define the events to watch ──────────────────────────────────────────────
# Each entry: @{TaskName; Log; EventId; Description}
# Expanded to cover all domains from the correlation map:
#   App Crashes, Service Failures, Memory, Disk/NTFS, Networking, Firewall, AppLocker, Privilege
$WatchedEvents = @(
    # ── Application Crashes ─────────────────────────────────────────────────
    @{ TaskName = 'AutoRemediate_AppCrash_1000';        Log = 'Application'; EventId = 1000;  Description = 'Application Error / App Crash' },
    @{ TaskName = 'AutoRemediate_AppHang_1001';         Log = 'Application'; EventId = 1001;  Description = 'Application Hang' },
    @{ TaskName = 'AutoRemediate_DotNetCrash_1026';     Log = 'Application'; EventId = 1026;  Description = '.NET Runtime Crash' },

    # ── Service Failures ────────────────────────────────────────────────────
    @{ TaskName = 'AutoRemediate_ServiceFail_7034';     Log = 'System';      EventId = 7034;  Description = 'Service Terminated Unexpectedly' },
    @{ TaskName = 'AutoRemediate_ServiceFail_7031';     Log = 'System';      EventId = 7031;  Description = 'Service Terminated Unexpectedly (v2)' },
    @{ TaskName = 'AutoRemediate_ServiceStart_7000';    Log = 'System';      EventId = 7000;  Description = 'Service Failed to Start' },
    @{ TaskName = 'AutoRemediate_ServiceError_7023';    Log = 'System';      EventId = 7023;  Description = 'Service Terminated with Error' },
    @{ TaskName = 'AutoRemediate_ServiceHung_7022';     Log = 'System';      EventId = 7022;  Description = 'Service Hung on Starting' },

    # ── Disk / NTFS ─────────────────────────────────────────────────────────
    @{ TaskName = 'AutoRemediate_DiskError_11';         Log = 'System';      EventId = 11;    Description = 'Disk Controller Error' },
    @{ TaskName = 'AutoRemediate_NTFSCorruption_55';    Log = 'System';      EventId = 55;    Description = 'NTFS Corruption Detected' },
    @{ TaskName = 'AutoRemediate_BadBlocks_7';          Log = 'System';      EventId = 7;     Description = 'Bad Blocks Detected on Disk' },
    @{ TaskName = 'AutoRemediate_DiskPagingIO_51';      Log = 'System';      EventId = 51;    Description = 'Disk Paging I/O Error' },

    # ── Memory ──────────────────────────────────────────────────────────────
    @{ TaskName = 'AutoRemediate_MemoryExhaust_2019';   Log = 'System';      EventId = 2019;  Description = 'Non-Paged Pool Memory Exhausted' },
    @{ TaskName = 'AutoRemediate_MemoryExhaust_2020';   Log = 'System';      EventId = 2020;  Description = 'Paged Pool Memory Exhausted' },
    @{ TaskName = 'AutoRemediate_ResourceExhaust_2004'; Log = 'System';      EventId = 2004;  Description = 'Resource Exhaustion Detected' },

    # ── Networking ──────────────────────────────────────────────────────────
    @{ TaskName = 'AutoRemediate_DNSTimeout_1014';      Log = 'System';      EventId = 1014;  Description = 'DNS Name Resolution Timeout' },
    @{ TaskName = 'AutoRemediate_NetDisconnect_4202';   Log = 'System';      EventId = 4202;  Description = 'Network Interface Disconnected' },

    # ── Firewall ────────────────────────────────────────────────────────────
    @{ TaskName = 'AutoRemediate_FWBlocked_5157';       Log = 'Security';    EventId = 5157;  Description = 'Application Blocked by Firewall' },
    @{ TaskName = 'AutoRemediate_FWStopped_5025';       Log = 'Security';    EventId = 5025;  Description = 'Windows Firewall Service Stopped' },

    # ── AppLocker ───────────────────────────────────────────────────────────
    @{ TaskName = 'AutoRemediate_AppLocker_8003';       Log = 'Microsoft-Windows-AppLocker/EXE and DLL'; EventId = 8003; Description = 'AppLocker Blocked Executable' },
    @{ TaskName = 'AutoRemediate_AppLocker_8004';       Log = 'Microsoft-Windows-AppLocker/EXE and DLL'; EventId = 8004; Description = 'AppLocker Blocked DLL' },
    @{ TaskName = 'AutoRemediate_AppLocker_8006';       Log = 'Microsoft-Windows-AppLocker/EXE and DLL'; EventId = 8006; Description = 'AppLocker Blocked Script' },

    # ── Event Log / Audit ────────────────────────────────────────────────────
    @{ TaskName = 'AutoRemediate_EventLogShutdown_1100'; Log = 'System';      EventId = 1100;  Description = 'Event Log Shutdown' },
    @{ TaskName = 'AutoRemediate_AuditEventsDrop_1101';  Log = 'System';      EventId = 1101;  Description = 'Audit Events Dropped' },

    # ── Privilege / Security ─────────────────────────────────────────────────
    @{ TaskName = 'AutoRemediate_LogonFail_4625';       Log = 'Security';    EventId = 4625;  Description = 'Logon Failure (Repeated)' },
    @{ TaskName = 'AutoRemediate_DCOMPerm_10016';       Log = 'System';      EventId = 10016; Description = 'DCOM Permission Denied' },

    # ── System Resource Events ──────────────────────────────────────────────
    @{ TaskName = 'AutoRemediate_SystemReboot_41';      Log = 'System';      EventId = 41;    Description = 'System Reboot Due to Resource Exhaustion' }
)


# ── Task Scheduler action: run python cli_process_event.py silently ──────────
$TaskFolder   = '\AutoRemediation'
$ActionExe    = $PythonExe
$ActionArgs   = "`"$CliScript`""

# ── Create the task folder if it doesn't exist ──────────────────────────────
$TaskService = New-Object -ComObject Schedule.Service
$TaskService.Connect()
$RootFolder = $TaskService.GetFolder('\')
try {
    $RootFolder.GetFolder($TaskFolder) | Out-Null
    Write-Host "[INFO] Task folder '$TaskFolder' already exists." -ForegroundColor DarkGray
} catch {
    $RootFolder.CreateFolder($TaskFolder) | Out-Null
    Write-Host "[OK]   Created Task Scheduler folder: $TaskFolder" -ForegroundColor Green
}

# ── Register a task for each watched event ──────────────────────────────────
$Registered = 0
$Skipped    = 0

foreach ($evt in $WatchedEvents) {
    $taskName    = $evt.TaskName
    $logName     = $evt.Log
    $eventId     = $evt.EventId
    $description = $evt.Description
    $fullPath    = "$TaskFolder\$taskName"

    Write-Host "  [•] Registering: $taskName (EventId=$eventId, Log=$logName)" -ForegroundColor White

    # Build the XML event query filter (XPath)
    $eventFilter = @"
<QueryList>
  <Query Id="0" Path="$logName">
    <Select Path="$logName">*[System[EventID=$eventId and (Level=1 or Level=2)]]</Select>
  </Query>
</QueryList>
"@

    # Build full task XML
    $taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Auto-Remediation: $description (EventId $eventId)</Description>
    <Author>AutoRemediation System</Author>
  </RegistrationInfo>
  <Triggers>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>$([System.Security.SecurityElement]::Escape($eventFilter))</Subscription>
    </EventTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <RunLevel>HighestAvailable</RunLevel>
      <LogonType>InteractiveToken</LogonType>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>false</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>true</Hidden>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$ActionExe</Command>
      <Arguments>$ActionArgs</Arguments>
      <WorkingDirectory>$BackendDir</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@

    try {
        $Folder = $TaskService.GetFolder($TaskFolder)
        # TASK_CREATE_OR_UPDATE = 6
        $Folder.RegisterTask($taskName, $taskXml, 6, $null, $null, 3, $null) | Out-Null
        Write-Host "    [OK] Registered successfully." -ForegroundColor Green
        $Registered++
    } catch {
        Write-Host "    [WARN] Failed to register: $_" -ForegroundColor Yellow
        $Skipped++
    }
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Setup Complete!" -ForegroundColor Green
Write-Host "  Registered : $Registered task(s)" -ForegroundColor Green
if ($Skipped -gt 0) {
    Write-Host "  Skipped    : $Skipped task(s) (see warnings above)" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "  The system is now watching 24/7 for:" -ForegroundColor White
foreach ($evt in $WatchedEvents) {
    Write-Host "    • EventId $($evt.EventId) ($($evt.Description))" -ForegroundColor Gray
}
Write-Host ""
Write-Host "  Each event will instantly invoke:" -ForegroundColor White
Write-Host "    $PythonExe $ActionArgs" -ForegroundColor Gray
Write-Host ""
Write-Host "  Logs are written to:" -ForegroundColor White
Write-Host "    $BackendDir\data\remediation_system.log  (unified log)" -ForegroundColor Gray
Write-Host "    $BackendDir\data\task_scheduler_crash.log (crash log)" -ForegroundColor Gray
Write-Host ""
Write-Host "  To verify, open Task Scheduler and look under:" -ForegroundColor White
Write-Host "    Task Scheduler Library → AutoRemediation" -ForegroundColor Gray
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
