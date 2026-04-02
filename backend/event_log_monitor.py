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
from datetime import datetime, timezone

import models

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
    Returns the event row id.
    """
    event_id  = str(raw.get('Id', '0'))
    log_name  = raw.get('LogName', 'Unknown')
    source    = raw.get('ProviderName', 'Unknown')
    message   = (raw.get('Message') or '')[:2000]   # cap message length
    level_num = raw.get('Level', 3)
    severity  = LEVEL_MAP.get(int(level_num), 'Warning')
    timestamp = _parse_timestamp(raw.get('TimeCreated'))

    event_dict = {
        'event_id':  event_id,
        'log_name':  log_name,
        'source':    source,
        'message':   message,
        'timestamp': timestamp,
        'severity':  severity,
        'level':     severity,
        'source_type': 'eventlog',
    }

    # Store the event (dedup logic is inside add_event)
    row_id = models.add_event(
        event_id   = event_id,
        log_name   = log_name,
        source     = source,
        message    = message,
        timestamp  = timestamp,
        severity   = severity,
        level      = severity,
        source_type = 'eventlog',
    )

    # Match rules
    matched = models.match_rules_for_event(event_dict)

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
            regex_captures  = rule_tuple[16] if len(rule_tuple) > 16 else {}
            rid             = rule_tuple[0]
            auto_remediate  = rule_tuple[6]
            rule_name       = rule_tuple[1]

            if auto_remediate and not cooldown_active:
                result = models.run_remediation(row_id, rid, regex_captures=regex_captures)
                logger.info(
                    f'[AUTO] Event {event_id} → rule "{rule_name}" → {result.get("status")}'
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
            logger.error(f'Failed processing event: {e}')

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
            logger.error(f'[MONITOR] Poll error: {e}')
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
