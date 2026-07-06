# Test-RemediationRules.ps1
# ═══════════════════════════════════════════════════════════════════════════════
# One injector for every ACTIVE rule in backend\rules.db. Writes a real Windows
# Event Log entry with the exact (EventId, Source, Log) tuple the rule matches
# on, and a Message crafted to satisfy each remediation script's own regex
# parsing — so the auto-remediation actually does something real, not just
# "no target found" fallback logic.
#
# IMPORTANT — READ THIS:
#   RM_SIMULATION_MODE is only '1' when the app's own /api/simulations/* demo
#   endpoints fabricate an event with log_name='simulation'. A real Windows
#   Event Log entry (this script) always ingests with log_name='System' or
#   'Application', so RM_SIMULATION_MODE='0' and the matched script runs its
#   REAL action (service restart, process kill, sfc/DISM, audit policy
#   changes, etc.) — see the -List table for exactly what fires per rule.
#
# USAGE:
#   .\Test-RemediationRules.ps1 -List
#       Show every testable rule with EventId/Source/real-action/risk notes.
#
#   .\Test-RemediationRules.ps1 -EventId 7031
#       Inject the Event 7031 test entry (asks for Y/N confirmation first,
#       since it will actually restart the Print Spooler service).
#
#   .\Test-RemediationRules.ps1 -EventId 7031 -Force -TriggerPoll
#       Inject without confirmation, then immediately POST
#       /api/monitor/trigger so you don't have to wait up to 30s for the
#       backend's normal poll loop.
#
# Some rules require an elevated (Administrator) terminal to register a new
# Event Log source. Run this from "Run as Administrator" for 100% reliability
# — especially Event IDs 41 and 2004.
# ═══════════════════════════════════════════════════════════════════════════════

param(
    [int]$EventId,
    [switch]$List,
    [switch]$Force,
    [switch]$TriggerPoll,
    [string]$BackendUrl = 'http://localhost:5000'
)

$ErrorActionPreference = 'Stop'

# ── Rule catalog: mirrors backend\rules.db exactly (event_id + source = match key) ──
$Rules = @(
    [pscustomobject]@{
        EventId='7000'; Source='Service Control Manager'; LogName='System'; EntryType='Error'
        Message='The Print Spooler service failed to start due to the following error: The service did not respond to the start or control request in a timely fashion.'
        Script='Error7000_ServiceStartupFailure.ps1'
        RealAction='Sets Print Spooler startup type check + Start-Service if stopped.'
        Risk='Low — Print Spooler restart only.'
    },
    [pscustomobject]@{
        EventId='7001'; Source='Service Control Manager'; LogName='System'; EntryType='Error'
        Message='The Print Spooler service depends on the RPC service which failed to start.'
        Script='Error7001_ServiceDependencyFailure.ps1'
        RealAction='Starts RPC if stopped (always already running -> no-op), sets Spooler to Automatic + starts it.'
        Risk='Low.'
    },
    [pscustomobject]@{
        EventId='7031'; Source='Service Control Manager'; LogName='System'; EntryType='Error'
        Message='The Print Spooler service terminated unexpectedly.  It has done this 1 time(s).'
        Script='Error7031_ServiceTerminatedUnexpectedly.ps1'
        RealAction='Restart-Service Print Spooler (or Start-Service if stopped).'
        Risk='Low.'
    },
    [pscustomobject]@{
        EventId='7034'; Source='Service Control Manager'; LogName='System'; EntryType='Error'
        Message='The Print Spooler service terminated unexpectedly.'
        Script='Error7034_ServiceTerminatedUnexpectedly.ps1'
        RealAction='Restart-Service Print Spooler (or Start-Service if stopped).'
        Risk='Low.'
    },
    [pscustomobject]@{
        EventId='1000'; Source='Application Error'; LogName='Application'; EntryType='Error'
        Message="Faulting application name: notepad.exe, version: 10.0.19041.3636, time stamp: 0x5284d537`nFaulting module name: KERNELBASE.dll, version: 10.0.19041.3636, time stamp: 0x5284d537`nException code: 0xc0000005`nFaulting process id: 0x1a2c`nFaulting application path: C:\Windows\system32\notepad.exe`nReport Id: 12345678-1234-1234-1234-123456789012"
        Script='Remediate_AppCrash_Live.ps1'
        RealAction='Relaunches notepad.exe -- ONLY if it is not already running (else no-op "already running").'
        Risk='Low. Close Notepad first if you want to see the actual relaunch happen.'
    },
    [pscustomobject]@{
        EventId='1001'; Source='Windows Error Reporting'; LogName='Application'; EntryType='Warning'
        Message='Faulting application name: notepad.exe, version: 10.0.19041.1, time stamp: 0x00000000. Application hang, hang type: Blocked. Report Id: 12345678-abcd-1234-abcd-1234567890ab'
        Script='Error1001_ApplicationHang.ps1'
        RealAction='Kills+relaunches processes ONLY if Notepad is genuinely not responding (Responding=$false). In practice a healthy Notepad makes this a safe no-op.'
        Risk='Low.'
    },
    [pscustomobject]@{
        EventId='1026'; Source='.NET Runtime'; LogName='Application'; EntryType='Error'
        Message="Application name: notepad.exe`nFramework Version: v4.0.30319`nDescription: The process was terminated due to an unhandled exception.`nException Info: System.NullReferenceException"
        Script='Error1026_DotNetRuntimeCrash.ps1'
        RealAction='Force Stop-Process + relaunch of notepad.exe IF it is currently running.'
        Risk='Medium — actually kills Notepad. Start `notepad` first if you want to watch it get killed+restarted; otherwise it is a safe no-op.'
    },
    [pscustomobject]@{
        EventId='26'; Source='Application'; LogName='Application'; EntryType='Warning'
        Message='Application notepad failed due to memory limits imposed by the system. The process was terminated to free memory.'
        Script='Error26_ApplicationFailedDueToMemoryLimits.ps1'
        RealAction='Clears %TEMP%/C:\Windows\Temp, empties Recycle Bin, Stop-Process on notepad.exe IF running, then runs REAL `sfc /scannow` + `DISM /RestoreHealth` (slow, several minutes).'
        Risk='Medium — real temp/recycle-bin cleanup + long-running sfc/DISM scan.'
    },
    [pscustomobject]@{
        EventId='41'; Source='Kernel-Power'; LogName='System'; EntryType='Error'
        Message='The system has rebooted without cleanly shutting down first. This error could be caused if the system stopped responding, crashed, or lost power due to resource exhaustion, memory limits, or low memory conditions.'
        Script='Error41_SystemRebootDueToResourceExhaustion.ps1'
        RealAction='Clears temp/recycle bin, logs (read-only) top 10 processes by memory, then runs REAL `sfc /scannow` + `DISM /RestoreHealth` (slow, several minutes).'
        Risk='Medium — long-running sfc/DISM scan. No reboot is triggered, no processes are killed.'
    },
    [pscustomobject]@{
        EventId='1100'; Source='EventLog'; LogName='System'; EntryType='Error'
        Message='The Event Log service was stopped unexpectedly.'
        Script='Error1100_EventLogShutdown.ps1'
        RealAction='Starts the EventLog service if stopped (already running -> no-op), sets it to Automatic startup, runs REAL `sfc /scannow` + `DISM /RestoreHealth` (slow).'
        Risk='Medium — long-running sfc/DISM scan.'
    },
    [pscustomobject]@{
        EventId='1101'; Source='EventLog'; LogName='System'; EntryType='Warning'
        Message='Audit events have been dropped by the transport due to insufficient audit log size or system resource constraints.'
        Script='Error1101_AuditEventsDropped.ps1'
        RealAction='PERMANENTLY resizes the Security event log to 100MB, sets its retention to overwrite-as-needed, runs `auditpol /set /category:* /success:enable /failure:enable` (enables ALL Windows audit categories), runs REAL sfc/DISM, then Restart-Service EventLog -Force.'
        Risk='HIGH — lasting changes to Security log size/retention and system-wide audit policy, plus a brief EventLog service restart. Consider toggling this rule''s Auto-Remediate OFF in the Rules screen before testing detection, then re-enable only when you intend the real action to fire.'
    },
    [pscustomobject]@{
        EventId='2004'; Source='Resource-Exhaustion-Detector'; LogName='System'; EntryType='Error'
        Message='Windows successfully diagnosed a low memory condition and identified the largest memory consumers. Resource exhaustion detected on this system due to handles and committed memory pressure.'
        Script='Error2004_ResourceExhaustionDetected.ps1'
        RealAction='Clears temp/recycle bin, logs (read-only) top 10 processes, runs REAL `sfc /scannow` + `DISM /RestoreHealth` (slow).'
        Risk='Medium — long-running sfc/DISM scan.'
    },
    [pscustomobject]@{
        EventId='2013'; Source='Disk'; LogName='System'; EntryType='Warning'
        Message='Disk space on volume C: is running low. Only 2.1 GB (4%) of free space remains.'
        Script='LowDiskSpace_Remediation.ps1'
        RealAction='Only cleans temp/recycle bin/prefetch if a REAL local drive is actually below 5GB or 10% free. Otherwise logs "sufficient free space" and does nothing.'
        Risk='Low — conditional on genuinely low disk space.'
    },
    [pscustomobject]@{
        EventId='2019'; Source='Srv'; LogName='System'; EntryType='Error'
        Message='The server was unable to allocate from the system nonpaged pool because the pool was empty. Process notepad was using high memory and exhausted available resources.'
        Script='Error2019_NonPagedPoolMemoryExhausted.ps1'
        RealAction='Clears temp/recycle bin, Stop-Process on notepad.exe IF running, then runs REAL sfc/DISM (slow).'
        Risk='Medium — kills Notepad if running, plus long sfc/DISM scan.'
    },
    [pscustomobject]@{
        EventId='2020'; Source='Srv'; LogName='System'; EntryType='Error'
        Message='The server was unable to allocate from the system paged pool because the pool was empty. Process notepad was using high memory and exhausted available resources.'
        Script='Error2020_PagedPoolMemoryExhausted.ps1'
        RealAction='Clears temp/recycle bin, Stop-Process on notepad.exe IF running, then runs REAL sfc/DISM (slow).'
        Risk='Medium — kills Notepad if running, plus long sfc/DISM scan.'
    }
)

# ── -List: print the reference table and exit ───────────────────────────────
if ($List -or -not $EventId) {
    Write-Host ''
    Write-Host '═══════════════════════════════════════════════════════════════════' -ForegroundColor Cyan
    Write-Host '  Testable Auto-Remediation Rules' -ForegroundColor Cyan
    Write-Host '═══════════════════════════════════════════════════════════════════' -ForegroundColor Cyan
    foreach ($r in $Rules) {
        Write-Host ''
        Write-Host "  Event $($r.EventId)  |  Source: $($r.Source)  |  Log: $($r.LogName)" -ForegroundColor White
        Write-Host "    Script     : $($r.Script)" -ForegroundColor DarkGray
        Write-Host "    Real action: $($r.RealAction)" -ForegroundColor Gray
        Write-Host "    Risk       : $($r.Risk)" -ForegroundColor Yellow
    }
    Write-Host ''
    Write-Host 'Run: .\Test-RemediationRules.ps1 -EventId <id> [-Force] [-TriggerPoll]' -ForegroundColor Cyan
    Write-Host ''
    exit 0
}

$rule = $Rules | Where-Object { $_.EventId -eq [string]$EventId } | Select-Object -First 1
if (-not $rule) {
    Write-Host "[ERROR] Event ID $EventId is not one of the active rules. Run with -List to see all options." -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host "Event $($rule.EventId)  |  Source: $($rule.Source)  |  Log: $($rule.LogName)" -ForegroundColor White
Write-Host "Remediation script : $($rule.Script)" -ForegroundColor DarkGray
Write-Host "Real action on fire: $($rule.RealAction)" -ForegroundColor Gray
Write-Host "Risk                : $($rule.Risk)" -ForegroundColor Yellow
Write-Host ''

if (-not $Force) {
    $answer = Read-Host 'This will write a REAL Windows Event Log entry and the backend WILL execute the real remediation action above once it polls. Continue? (y/N)'
    if ($answer -notin @('y', 'Y', 'yes', 'Yes')) {
        Write-Host 'Aborted.' -ForegroundColor Yellow
        exit 0
    }
}

# ── Register the source if needed, then write the event ─────────────────────
try {
    if (-not [System.Diagnostics.EventLog]::SourceExists($rule.Source)) {
        New-EventLog -LogName $rule.LogName -Source $rule.Source -ErrorAction Stop
        Write-Host "[INFO] Registered new event source '$($rule.Source)' under log '$($rule.LogName)'." -ForegroundColor Green
    }
} catch {
    Write-Host "[WARN] Could not register source '$($rule.Source)' (may already exist under a different log, or you may need to run as Administrator): $_" -ForegroundColor Yellow
}

try {
    Write-EventLog -LogName $rule.LogName -Source $rule.Source -EventId ([int]$rule.EventId) `
        -EntryType $rule.EntryType -Message $rule.Message -ErrorAction Stop
    Write-Host "[OK] Event $($rule.EventId) written to the $($rule.LogName) log." -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to write event: $_" -ForegroundColor Red
    Write-Host "        Try re-running this terminal 'as Administrator'." -ForegroundColor Red
    exit 1
}

# ── Optionally force an immediate poll instead of waiting up to 30s ─────────
if ($TriggerPoll) {
    try {
        Write-Host "[INFO] Triggering immediate backend poll at $BackendUrl/api/monitor/trigger ..." -ForegroundColor Cyan
        $resp = Invoke-RestMethod -Uri "$BackendUrl/api/monitor/trigger" -Method POST -TimeoutSec 30
        Write-Host "[OK] Poll complete. Events ingested: $($resp.events_ingested)" -ForegroundColor Green
    } catch {
        Write-Host "[WARN] Could not reach backend at $BackendUrl (is it running?): $_" -ForegroundColor Yellow
    }
} else {
    Write-Host '[INFO] The backend polls automatically every 30s. Or re-run with -TriggerPoll for instant ingestion.' -ForegroundColor Cyan
}

Write-Host ''
Write-Host 'Check the dashboard: Events / History / Dashboard screens should now show this event and its remediation outcome.' -ForegroundColor White
Write-Host ''
