# Simulate_ServiceCrash.ps1
# -------------------------------------------------------------------------
# Writes a synthetic "Service Crash" Windows Event Log entry (Event ID 7034)
# under the source "Service Control Manager" in the System log -- the exact
# (EventId, Source) tuple that the "Service Failure" rule in rules.db matches
# on, so the auto-remediation engine actually picks it up and runs
# Error7034_ServiceTerminatedUnexpectedly.ps1.
#
# NO actual service is stopped or modified by this script. The remediation
# script it triggers WILL, however, really restart the target service once
# the backend polls this event (RM_SIMULATION_MODE is only '1' for the app's
# own /api/simulations/* demo events, not for real Windows Event Log entries).
#
# USAGE:
#   .\Simulate_ServiceCrash.ps1                        # defaults to Print Spooler
#   .\Simulate_ServiceCrash.ps1 -ServiceName Spooler
#   .\Simulate_ServiceCrash.ps1 -ServiceName "Print Spooler"
# -------------------------------------------------------------------------

param(
    [string]$ServiceName = 'Spooler',
    [switch]$RequireApproval,
    [string]$BackendUrl = 'http://localhost:5000'
)

$EVENT_SOURCE = 'Service Control Manager'
$EVENT_LOG    = 'System'
$EVENT_ID     = 7034
$SEVERITY     = 'High'

if ($RequireApproval) {
    $randomTag = Get-Random -Minimum 1000 -Maximum 9999
    $SERVICE_NAME = "UnapprovedService_$randomTag"
    $DISPLAY_NAME = "Unapproved Service $randomTag"
} else {
    # --- Resolve the requested service to its real Name/DisplayName -----------
    $resolved = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $resolved) {
        $resolved = Get-Service -DisplayName $ServiceName -ErrorAction SilentlyContinue
    }
    if (-not $resolved) {
        Write-Host "[WARN] Service '$ServiceName' not found on this machine. Using simulated service name '$ServiceName'." -ForegroundColor Yellow
        $SERVICE_NAME = $ServiceName
        $DISPLAY_NAME = "$ServiceName Service"
    } else {
        $SERVICE_NAME = $resolved.Name
        $DISPLAY_NAME = $resolved.DisplayName
    }
}

# --- Register the source if it isn't already (it normally already is, as
#     "Service Control Manager" is a built-in Windows System-log source) ---
if (-not [System.Diagnostics.EventLog]::SourceExists($EVENT_SOURCE)) {
    try {
        New-EventLog -LogName $EVENT_LOG -Source $EVENT_SOURCE -ErrorAction Stop
        Write-Host "[INFO] Registered event source: $EVENT_SOURCE"
    } catch {
        Write-Host "[WARN] Could not register event source (may need Admin): $_"
    }
}

# --- Compose a message that matches the remediation script's own regex ----
# Error7034_ServiceTerminatedUnexpectedly.ps1 parses:
#   "The <service> service terminated unexpectedly"
$timestamp  = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'
$crashCount = Get-Random -Minimum 1 -Maximum 5

$message = "The $DISPLAY_NAME service terminated unexpectedly.  It has done this $crashCount time(s). The following corrective action will be taken in 60000 milliseconds: Restart the service."

# --- Write the event to the Windows System log -----------------------------
try {
    Write-EventLog `
        -LogName    $EVENT_LOG `
        -Source     $EVENT_SOURCE `
        -EventId    $EVENT_ID `
        -EntryType  'Error' `
        -Message    $message `
        -ErrorAction Stop

    Write-Host "[SUCCESS] Event ID $EVENT_ID written to $EVENT_LOG log (Source: $EVENT_SOURCE)."
    Write-Host "[INFO]    Service crash simulated: $DISPLAY_NAME ($SERVICE_NAME) crashed $crashCount time(s)."

    # --- Trigger backend monitor poll immediately ---------------------------
    Write-Host ""
    Write-Host "[INFO] Triggering immediate monitor poll at $BackendUrl/api/monitor/trigger ..." -ForegroundColor Yellow
    try {
        $res = Invoke-WebRequest -Uri "$BackendUrl/api/monitor/trigger" -Method POST -UseBasicParsing -TimeoutSec 10
        $data = $res.Content | ConvertFrom-Json
        Write-Host "[SUCCESS] Monitor poll complete - $($data.events_ingested) new event(s) ingested." -ForegroundColor Green
    } catch {
        Write-Host "[WARN] Could not trigger monitor poll: $_" -ForegroundColor Yellow
    }

    Write-Host "[INFO]    Check your frontend dashboard/approvals page for the pop-up notification!" -ForegroundColor Cyan
    exit 0
} catch {
    Write-Host "[ERROR] Failed to write event log entry: $_" -ForegroundColor Red
    Write-Host "[INFO]  This may require running PowerShell as Administrator." -ForegroundColor Red
    exit 1
}
