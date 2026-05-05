"""
event_log_monitor.py
━━━━━━━━━━━━━━━━━━━
Background service that polls Windows Event Logs every POLL_INTERVAL seconds,
ingests new events into the database, auto-remediates matched rules, and flags
events with no matching rule for manual review in the dashboard.

Usage:
    from event_log_monitor import start_monitor
    start_monitor()   # call once at app startup
"""

import json
import os
import threading
import time
import subprocess
import shutil
import logging
import re
from datetime import datetime, timezone

import models


# ─────────────────────────────────────────────────────────────────────────────
#  Security: Sanitize environment variables for PowerShell injection safety
# ─────────────────────────────────────────────────────────────────────────────

def sanitize_for_powershell_env(value: str, max_length: int = 1000) -> str:
    """
    Sanitize a string before passing it as a PowerShell environment variable.
    
    Removes or escapes characters that could cause command injection:
    - Backticks (`) - PowerShell command substitution
    - Dollar signs ($) - PowerShell variable substitution
    - Pipes (|) - PowerShell pipeline
    - Semicolons (;) - PowerShell statement terminator
    - Parentheses ( ) - PowerShell subexpression
    
    Also truncates to max_length to prevent buffer overflow.
    
    Args:
        value: String to sanitize (typically from untrusted Event Log)
        max_length: Maximum output length (default 1000 chars)
    
    Returns:
        Sanitized string safe for use as PowerShell env var
    """
    if not value:
        return ''
    
    # Truncate first
    value = str(value)[:max_length]
    
    # Replace dangerous characters with underscore
    # Backticks, pipes, dollar, semicolon, parens, ampersand
    dangerous_chars = r'[`|$;()\&\n\r\t]'
    sanitized = re.sub(dangerous_chars, '_', value)
    
    return sanitized

# ─────────────────────────────────────────────────────────────────────────────
#  Constants
# ─────────────────────────────────────────────────────────────────────────────

POLL_INTERVAL   = 30          # seconds between each poll
MAX_EVENTS      = 50          # cap per poll to avoid bursts overwhelming the DB
DATA_DIR        = os.path.join(os.path.dirname(__file__), 'data')
WATERMARK_PATH  = os.path.join(DATA_DIR, 'eventlog_watermark.json')

# Windows event levels we care about (1=Critical, 2=Error, 3=Warning)
WATCH_LEVELS   = [1, 2, 3]
# Logs to poll
WATCH_LOGS     = ['System', 'Application']

# Map Windows numeric Level → severity string used inside the app
LEVEL_MAP = {1: 'Critical', 2: 'Error', 3: 'Warning'}

# Find PowerShell once at module load
_POWERSHELL = (
    shutil.which('powershell')
    or shutil.which('powershell.exe')
    or r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
)

# ─────────────────────────────────────────────────────────────────────────────
#  Shared state (thread-safe reads, written only by the monitor thread)
# ─────────────────────────────────────────────────────────────────────────────

_monitor_state = {
    'running':         False,
    'last_poll':       None,   # ISO timestamp string
    'events_ingested': 0,
    'errors':          [],     # last N error messages from poll failures
}
_state_lock = threading.Lock()

logger = logging.getLogger('event_log_monitor')
logging.basicConfig(level=logging.INFO,
                    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s')


# ─────────────────────────────────────────────────────────────────────────────
#  Watermark helpers  (stores the last-polled timestamp to disk)
# ─────────────────────────────────────────────────────────────────────────────

def _load_watermark() -> datetime:
    """Return last-processed datetime (UTC). Defaults to 1 hour ago."""
    os.makedirs(DATA_DIR, exist_ok=True)
    if os.path.exists(WATERMARK_PATH):
        try:
            with open(WATERMARK_PATH, 'r') as f:
                data = json.load(f)
                ts = data.get('eventlog_since')
                if ts:
                    return datetime.fromisoformat(ts)
        except Exception:
            pass
    # Default: look back 1 hour on first run so we pick up recent events
    from datetime import timedelta
    return datetime.now(timezone.utc).replace(microsecond=0) - timedelta(hours=1)


def _save_watermark(dt: datetime):
    os.makedirs(DATA_DIR, exist_ok=True)
    try:
        with open(WATERMARK_PATH, 'w') as f:
            json.dump({'eventlog_since': dt.isoformat()}, f)
    except Exception as e:
        logger.warning(f'Could not save watermark: {e}')


# ─────────────────────────────────────────────────────────────────────────────
#  PowerShell event fetcher
# ─────────────────────────────────────────────────────────────────────────────

_PS_QUERY = r"""
param($Since, $MaxEvents, $LogNames, $Levels)
$levelList = $Levels -split ',' | ForEach-Object { [int]$_ }
$logList   = $LogNames -split ','
try {
    $parsedDate = [datetime]::ParseExact($Since, 'yyyy-MM-ddTHH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
    $filter = @{
        LogName   = $logList
        Level     = $levelList
        StartTime = $parsedDate
    }
    $events = Get-WinEvent -FilterHashtable $filter -MaxEvents $MaxEvents -ErrorAction Stop |
              Select-Object Id, LogName, ProviderName, Message, TimeCreated, Level, LevelDisplayName
    if ($events) { $events | ConvertTo-Json -Depth 3 -Compress } else { '[]' }
} catch [System.Exception] {
    if ($_.Exception.Message -match 'No events were found') { '[]' }
    else { Write-Error $_.Exception.Message; exit 1 }
}
"""


def _fetch_windows_events(since: datetime) -> list:
    """
    Query Windows Event Log via PowerShell using EncodedCommand to safely
    handle multi-line scripts and parameters.
    """
    import base64
    since_str = since.strftime('%Y-%m-%dT%H:%M:%S')
    levels_str = ','.join(str(l) for l in WATCH_LEVELS)
    logs_str   = ','.join(WATCH_LOGS)

    # PowerShell can define the param and process it dynamically
    # We construct the entire script block including the variable assignments
    script = f'''
        $Since = "{since_str}"
        $MaxEvents = {MAX_EVENTS}
        $LogNames = "{logs_str}"
        $Levels = "{levels_str}"
        {_PS_QUERY}
    '''
    # PowerShell -EncodedCommand requires UTF-16LE base64
    encoded_cmd = base64.b64encode(script.encode('utf-16le')).decode('ascii')

    try:
        result = subprocess.run(
            [
                _POWERSHELL,
                '-NoProfile', '-ExecutionPolicy', 'Bypass',
                '-EncodedCommand', encoded_cmd
            ],
            capture_output=True, text=True, timeout=20
        )
        if result.returncode != 0:
            logger.warning(f'PS query failed: {result.stderr.strip()[:200]}')
            return []
        raw = result.stdout.strip()
        if not raw or raw == 'null':
            return []
        parsed = json.loads(raw)
        # PowerShell returns a dict (not list) when there's only one event
        if isinstance(parsed, dict):
            parsed = [parsed]
        return parsed if isinstance(parsed, list) else []
    except subprocess.TimeoutExpired:
        logger.warning('PowerShell event query timed out')
        return []
    except json.JSONDecodeError as e:
        logger.warning(f'Could not parse PS JSON: {e}')
        return []
    except Exception as e:
        logger.warning(f'Unexpected error fetching events: {e}')
        return []


# ─────────────────────────────────────────────────────────────────────────────
#  Event processing
# ─────────────────────────────────────────────────────────────────────────────

def _parse_timestamp(ts_raw) -> str:
    """Normalise PowerShell timestamp strings to ISO format."""
    if not ts_raw:
        return datetime.now(timezone.utc).isoformat()
    # PowerShell sometimes returns '/Date(1234567890000)/' style
    if isinstance(ts_raw, str) and ts_raw.startswith('/Date('):
        try:
            ms = int(ts_raw[6:ts_raw.index(')')])
            return datetime.fromtimestamp(ms / 1000, tz=timezone.utc).isoformat()
        except Exception:
            pass
    return str(ts_raw)


def _process_event(raw: dict) -> int:
    """
    Ingest one Windows Event into the DB, run rule matching, handle
    auto-remediation or flag for manual review.

    IMPROVEMENTS IMPLEMENTED:
      1. [CHRONOLOGICAL CORRELATION] Detects when multiple errors co-occur (e.g.,
         memory exhaustion + service crash). Routes to compound remediation scripts
         that fix the root cause first.
      2. [DEEP SYSTEM REPAIR] Detects when an app crashed due to a corrupted
         core Windows DLL. Escalates to sfc /scannow instead of just restarting.
      3. [ENVIRONMENT INJECTION] Passes context to PowerShell scripts via env vars
         so they can adapt their remediation strategy intelligently.
    """
    event_id  = str(raw.get('Id', '0'))
    log_name  = raw.get('LogName', 'Unknown')
    source    = raw.get('ProviderName', 'Unknown')
    message   = (raw.get('Message') or '')[:2000]   # cap message length
    level_num = raw.get('Level', 3)
    severity  = LEVEL_MAP.get(int(level_num), 'Warning')
    timestamp = _parse_timestamp(raw.get('TimeCreated'))

    # ── Enrich from catalog BEFORE inserting so category is available everywhere ──
    catalog_defn = models.get_event_definition(event_id, source)
    catalog_category    = catalog_defn.get('category')             if catalog_defn else None
    catalog_severity    = catalog_defn.get('severity')             if catalog_defn else severity
    catalog_description = catalog_defn.get('description')          if catalog_defn else None
    catalog_action      = catalog_defn.get('recommended_action')   if catalog_defn else None

    event_dict = {
        'event_id':    event_id,
        'log_name':    log_name,
        'source':      source,
        'message':     message,
        'timestamp':   timestamp,
        'severity':    catalog_severity or severity,
        'level':       severity,
        'category':    catalog_category,
        'source_type': 'eventlog',
    }

    # Store the event — pass enriched fields so the DB row has category populated
    row_id = models.add_event(
        event_id           = event_id,
        log_name           = log_name,
        source             = source,
        message            = message,
        timestamp          = timestamp,
        category           = catalog_category,
        severity           = catalog_severity or severity,
        description        = catalog_description,
        recommended_action = catalog_action,
        level              = severity,
        source_type        = 'eventlog',
    )

    # ── [IMPROVEMENT 1] Chronological Event Correlation Engine ────────────────
    # Multi-Event Inference: before matching rules, check if any co-related events
    # fired in the same time window. If yes, we know the true root cause and can
    # escalate the fix. For example, if memory exhaustion (2019) caused a service
    # crash (7031), we fix memory first — restarting a starved service will just fail.
    correlation = models.correlate_events(event_id, timestamp)
    extra_env = {}   # passed to run_remediation as env vars for intelligent script behavior

    if correlation['has_correlation']:
        cause = correlation['compound_cause']
        priority = correlation.get('priority', 'low')
        script = correlation.get('compound_script')
        co_ids = [str(e['event_id']) for e in correlation['correlated_events']]
        
        logger.info(
            f'[CORRELATE-{priority.upper()}] Event {event_id} → '
            f'Compound cause: "{cause}" | Co-events: {", ".join(co_ids)} | '
            f'Escalating to: {script}'
        )
        
        # Inject context into PowerShell scripts so they understand the full situation
        extra_env['RM_COMPOUND_CAUSE']      = cause or ''
        extra_env['RM_COMPOUND_PRIORITY']   = priority
        extra_env['RM_COMPOUND_SCRIPT']     = script or ''
        extra_env['RM_CO_EVENT_IDS']        = ','.join(co_ids)
        extra_env['RM_CO_EVENT_DOMAINS']    = ','.join(
            e['domain'] for e in correlation['correlated_events']
        )
        extra_env['RM_CO_EVENT_COUNT']      = str(len(correlation['correlated_events']))

    # ── [IMPROVEMENT 2] Core OS Faulting Module Detection (Deep System Repair) ──
    # If the crash message names a core Windows system DLL as the faulting module,
    # restarting the app will just produce an infinite crash loop. We need to
    # escalate to a deep system integrity check (sfc /scannow or DISM) to repair
    # the corrupted system file. This is the "Deep System Repair Fallback."
    is_os_module_crash = False
    faulting_module = None
    
    if event_id == '1000' and message:  # Application crash
        faulting_module = models.detect_faulting_module(message)
        if faulting_module and models.is_core_os_module(faulting_module):
            is_os_module_crash = True
            extra_env['RM_FAULTING_MODULE']         = faulting_module
            extra_env['RM_ESCALATION_REASON']       = f'Core OS module crash: {faulting_module}'
            extra_env['RM_REQUIRES_DEEP_REPAIR']    = '1'
            logger.warning(
                f'[SYSREPAIR] Event {event_id} — CORE OS MODULE CRASH detected: '
                f'{faulting_module}. Standard restart will loop infinitely. '
                f'Escalating to deep system integrity check (sfc /scannow).'
            )

    # ── Match rules — event_dict already has category populated ──────────────
    matched = models.match_rules_for_event(event_dict)

    # ── [IMPROVEMENT 2 cont.] DEEP SYSTEM REPAIR FALLBACK ──────────────────────
    # If a core OS module crashed, escalate to system integrity repair immediately.
    # This bypasses normal rules and goes straight to sfc /scannow or DISM.
    if is_os_module_crash:
        SYSREPAIR_SCRIPT = os.path.join(
            os.path.dirname(__file__), '..', 'remediation_scripts',
            'Remediate_SystemRepair_Fallback.ps1'
        )
        if os.path.exists(SYSREPAIR_SCRIPT):
            logger.info(f'[SYSREPAIR] Invoking deep system repair fallback for {faulting_module}')
            
            # Prepare environment for the repair script
            # CRITICAL SECURITY FIX: Sanitize all env vars to prevent command injection
            env_copy = os.environ.copy()
            env_copy.update(extra_env)
            env_copy['RM_EVENT_ROW_ID']         = str(row_id)
            env_copy['RM_EVENT_ID']             = sanitize_for_powershell_env(event_id)
            env_copy['RM_SOURCE']               = sanitize_for_powershell_env(source)
            env_copy['RM_MESSAGE']              = sanitize_for_powershell_env(message, max_length=500)
            env_copy['RM_FAULTING_MODULE']      = sanitize_for_powershell_env(faulting_module or '')
            env_copy['RM_ESCALATION_REASON']    = sanitize_for_powershell_env(
                f'Core OS module crash: {faulting_module}'
            )

            try:
                proc = subprocess.run(
                    [_POWERSHELL, '-NoProfile', '-ExecutionPolicy', 'Bypass',
                     '-File', os.path.abspath(SYSREPAIR_SCRIPT)],
                    capture_output=True, text=True, timeout=600, env=env_copy
                )
                status = 'success' if proc.returncode == 0 else 'failed'
                output = (proc.stdout + '\n' + proc.stderr).strip()
                
                # Record with a synthetic rule ID (999) to track system repair
                rule_id_sysrepair = 999
                models.record_remediation(row_id, rule_id_sysrepair, status, output)
                
                logger.info(
                    f'[SYSREPAIR-{status.upper()}] System integrity repair completed. '
                    f'Module: {faulting_module}. Output: {output[:200]}'
                )
            except Exception as e:
                logger.error(f'[SYSREPAIR-ERROR] Failed to invoke repair fallback: {e}')
                models.record_remediation(row_id, 999, 'failed', f'Exception: {str(e)}')
            
            return row_id

    # ── Rule-based auto-remediation ──────────────────────────────────────────
    if not matched:
        # No rule → flag for manual review
        models.set_manual_review(
            row_id,
            f'No remediation rule configured for Event {event_id} from {source}'
        )
        logger.info(f'[REVIEW] Event {event_id} ({source}) — manual review required')
    else:
        for rule_tuple in matched:
            cooldown_active = rule_tuple[15] if len(rule_tuple) > 15 else False
            regex_captures  = {**(rule_tuple[16] if len(rule_tuple) > 16 else {}), **extra_env}
            rid             = rule_tuple[0]
            auto_remediate  = rule_tuple[6]
            rule_name       = rule_tuple[1]

            if auto_remediate and not cooldown_active:
                result = models.run_remediation(row_id, rid, regex_captures=regex_captures)
                extra_info = ''
                if correlation['has_correlation']:
                    extra_info = f' [COMPOUND: {correlation["compound_cause"]} (priority={correlation.get("priority", "low")})]'
                logger.info(
                    f'[AUTO] Event {event_id} → rule "{rule_name}" → {result.get("status")}{extra_info}'
                )
            elif auto_remediate and cooldown_active:
                models.record_remediation(
                    row_id, rid, 'suppressed',
                    'Auto-remediation suppressed — rule cooldown active'
                )
                logger.info(f'[COOLDOWN] Rule "{rule_name}" is in cooldown, skipping')
            else:
                logger.info(f'[MATCH] Event {event_id} matched rule "{rule_name}" (auto_remediate=False)')

    return row_id




# ─────────────────────────────────────────────────────────────────────────────
#  Poll loop
# ─────────────────────────────────────────────────────────────────────────────

def _poll():
    """One poll cycle: fetch new events, process each one."""
    since    = _load_watermark()
    new_high = since   # will advance after each event

    raw_events = _fetch_windows_events(since)
    ingested   = 0

    for raw in raw_events:
        try:
            _process_event(raw)
            ingested += 1

            # Advance watermark to the latest event seen
            ts_raw = raw.get('TimeCreated')
            if ts_raw:
                try:
                    evt_dt = datetime.fromisoformat(_parse_timestamp(ts_raw).replace('Z', '+00:00'))
                    if evt_dt > new_high:
                        new_high = evt_dt
                except Exception:
                    pass
        except Exception as e:
            logger.exception(f'Failed processing event: {e}')

    if ingested:
        logger.info(f'[MONITOR] Ingested {ingested} event(s) from Windows Event Log')
        # Move watermark forward by 1 second past last event to avoid re-ingesting
        from datetime import timedelta
        _save_watermark(new_high + timedelta(seconds=1))

    return ingested


def _monitor_loop():
    """Runs forever in a background daemon thread."""
    with _state_lock:
        _monitor_state['running'] = True

    logger.info('[MONITOR] Windows Event Log monitor started')

    while True:
        try:
            count = _poll()
            now = datetime.now(timezone.utc).isoformat()
            with _state_lock:
                _monitor_state['last_poll']       = now
                _monitor_state['events_ingested'] += count
                # Keep only last 10 errors
                if len(_monitor_state['errors']) > 10:
                    _monitor_state['errors'].pop(0)
        except Exception as e:
            logger.exception(f'[MONITOR] Poll error: {e}')
            with _state_lock:
                _monitor_state['errors'].append(str(e))

        time.sleep(POLL_INTERVAL)


# ─────────────────────────────────────────────────────────────────────────────
#  Public API
# ─────────────────────────────────────────────────────────────────────────────

_monitor_thread: threading.Thread | None = None


def start_monitor():
    """
    Start the background Windows Event Log monitor thread.
    Safe to call multiple times — only one thread will be started.
    """
    global _monitor_thread
    if _monitor_thread and _monitor_thread.is_alive():
        logger.info('[MONITOR] Already running, skipping start')
        return

    _monitor_thread = threading.Thread(
        target=_monitor_loop,
        name='EventLogMonitor',
        daemon=True,          # dies automatically when main process exits
    )
    _monitor_thread.start()
    logger.info('[MONITOR] Background thread launched')


def get_status() -> dict:
    """Return current monitor state for the /api/monitor/status endpoint."""
    with _state_lock:
        return {
            'running':         _monitor_state['running'],
            'last_poll':       _monitor_state['last_poll'],
            'events_ingested': _monitor_state['events_ingested'],
            'poll_interval_s': POLL_INTERVAL,
            'recent_errors':   list(_monitor_state['errors']),
            'thread_alive':    bool(_monitor_thread and _monitor_thread.is_alive()),
        }


def trigger_poll() -> int:
    """
    Manually force an immediate poll cycle and return the number of ingested events.
    Useful for 'Refresh' buttons in the UI.
    """
    try:
        count = _poll()
        now = datetime.now(timezone.utc).isoformat()
        with _state_lock:
            _monitor_state['last_poll'] = now
            _monitor_state['events_ingested'] += count
        return count
    except Exception as e:
        logger.error(f'[MONITOR] Manual trigger error: {e}')
        with _state_lock:
            _monitor_state['errors'].append(str(e))
        return 0
