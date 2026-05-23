import os
import sqlite3
import re
import logging
import shutil
import subprocess
import json
import csv
import hashlib
import tempfile
from datetime import datetime, timedelta
from pathlib import Path

# Root cause variant detection
from root_cause_analyzer import analyze_event as analyze_root_cause, get_analyzer

logger = logging.getLogger(__name__)

DB_PATH = os.path.join(os.path.dirname(__file__), 'rules.db')
EVENT_DEFINITIONS_PATH = os.path.join(os.path.dirname(__file__), '..', 'windows_error_events.json')

# Resolve PowerShell path once at startup so subprocess never gets WinError 2
_POWERSHELL = (
    shutil.which('powershell')
    or shutil.which('powershell.exe')
    or r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
)

# Data directory for CSV exports and state
DATA_DIR = os.path.join(os.path.dirname(__file__), 'data')
ERRORS_WARNINGS_CSV = os.path.join(DATA_DIR, 'errors_warnings.csv')
LAST_PROCESSED_PATH = os.path.join(DATA_DIR, 'last_processed.json')

# Deduplication window — events with same event_id+source within this window are merged
DEDUP_WINDOW_SECONDS = 300   # 5 minutes

# Correlation window — configurable per event type (minutes)
# Determines how far back to look for correlated events (PRIORITY 3 FIX)
CORRELATION_WINDOW_MINUTES_DEFAULT = 5
CORRELATION_WINDOW_MINUTES_MAP = {
    1000: 10,   # App crash: look back 10 minutes
    7031: 5,    # Service crash: look back 5 minutes  
    2019: 15,   # Non-paged pool exhaustion: look back 15 minutes (slow buildup)
    2020: 15,   # Paged pool exhaustion: look back 15 minutes
    11: 30,     # Disk error: look back 30 minutes (cascading issues)
    41: 5,      # System reboot: look back 5 minutes
    129: 15,    # Storage timeout: look back 15 minutes
    140: 30,    # NTFS corruption: look back 30 minutes
    153: 15,    # Disk IO retry: look back 15 minutes
}

# Ensure data dir exists
Path(DATA_DIR).mkdir(parents=True, exist_ok=True)

# Cache for event definitions
_event_definitions_cache = None


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
    - Ampersand (&) - PowerShell operator
    
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


def _conn():
    return sqlite3.connect(DB_PATH)


# ─────────────────────────────────────────────────────────────────────────────
#  Event Definitions (JSON catalog)
# ─────────────────────────────────────────────────────────────────────────────

def load_event_definitions():
    """Load event definitions from JSON file and cache them."""
    global _event_definitions_cache
    if _event_definitions_cache is not None:
        return _event_definitions_cache
    if not os.path.exists(EVENT_DEFINITIONS_PATH):
        _event_definitions_cache = []
        return _event_definitions_cache
    try:
        with open(EVENT_DEFINITIONS_PATH, 'r', encoding='utf-8') as f:
            _event_definitions_cache = json.load(f)
        return _event_definitions_cache
    except Exception as e:
        print(f"Error loading event definitions: {e}")
        _event_definitions_cache = []
        return _event_definitions_cache


def get_event_definition(event_id, source=None):
    definitions = load_event_definitions()
    if source:
        for defn in definitions:
            if str(defn.get('event_id')) == str(event_id) and defn.get('event_source', '').lower() == source.lower():
                return defn
    for defn in definitions:
        if str(defn.get('event_id')) == str(event_id):
            return defn
    return None


def get_all_event_definitions():
    return load_event_definitions()


# ─────────────────────────────────────────────────────────────────────────────
#  ALERT INTELLIGENCE ENGINE
# ─────────────────────────────────────────────────────────────────────────────

def calculate_confidence_score(event_dict, dedup_count=1, has_matching_rule=False):
    """
    Compute a 0–100 confidence score representing how urgently this event
    needs remediation.

    Factors:
      - Severity (up to 40 pts)
      - Level / log level (up to 20 pts)
      - Frequency / dedup count (up to 20 pts, capped at 5 occurrences)
      - Has a matching rule configured (20 pts)
    """
    score = 0.0

    severity = (event_dict.get('severity') or '').lower()
    severity_map = {
        'critical':    40,
        'error':       32,
        'warning':     20,
        'information': 8,
        'info':        8,
        'verbose':     4,
    }
    score += severity_map.get(severity, 10)

    level = (event_dict.get('level') or '').lower()
    level_map = {
        'critical': 20,
        'error':    20,
        'warning':  10,
        'info':     4,
        'test':     2,
    }
    score += level_map.get(level, 0)

    # Frequency bonus — every duplicate occurrence adds confidence (cap at 5×)
    score += min(20, (dedup_count - 1) * 4)

    # Presence of a matching rule means the operator has assessed this event
    if has_matching_rule:
        score += 20

    return round(min(100.0, score), 1)


def get_correlation_id(source, timestamp=None):
    """
    Group events from the same source into 10-minute time buckets.
    Events with the same correlation_id occurred at the same source within
    the same 10-minute window — i.e. part of the same incident.
    Returns a 12-char hex string.
    """
    if timestamp:
        try:
            ts = datetime.fromisoformat(timestamp)
        except Exception:
            ts = datetime.utcnow()
    else:
        ts = datetime.utcnow()

    # bucket = hour + which 10-min slot (0,1,2,3,4,5)
    bucket = ts.strftime('%Y%m%d%H') + str(ts.minute // 10)
    raw = f"{(source or 'unknown').lower()}:{bucket}"
    return hashlib.md5(raw.encode()).hexdigest()[:12]


# ─────────────────────────────────────────────────────────────────────────────
#  Chronological Event Correlation Engine (Multi-Event Inference)
# ─────────────────────────────────────────────────────────────────────────────
#
# This engine correlates related Windows events that occur within a time window
# to detect compound root causes. For example, if Event 2019 (memory exhaustion)
# co-occurs with Event 7031 (service crashed), we know to fix memory first
# rather than just restarting the service, which would fail again.
#
# Correlation map: for a given trigger event_id, which co-event_ids within the
# time window indicate a compound root cause, and which remediation strategy applies.
#
# Structure: { trigger_event_id: [(correlated_id, domain, compound_script_hint), ...] }
#
# Domains covered:
#   - Memory: non-paged pool, paged pool, resource exhaustion
#   - Disk: controller errors, I/O errors, NTFS corruption, bad blocks
#   - AppLocker: blocked executables, DLLs, scripts
#   - Networking: DNS failures, adapter disconnects, connection timeouts
#   - Firewall: blocked applications, Windows Firewall service issues
#   - Privilege: logon failures, access denied, privilege escalation issues
#   - Services: unexpected termination, startup failures, hung services

CORRELATION_MAP = {
    # ── Application Crashes (1000, 1001) ─────────────────────────────────────
    # App crash may be due to memory exhaustion, AppLocker blocking, or
    # a corrupted system DLL. (DLL corruption is handled separately in fallback.)
    1000: [  # Application Error / App Crash
        (2019, 'Memory',    'memory_exhaustion'),       # Non-paged pool exhausted
        (2020, 'Memory',    'memory_exhaustion'),       # Paged pool exhausted
        (2004, 'Memory',    'resource_exhaustion'),     # General resource exhaustion
        (8003, 'AppLocker', 'applocker_block'),        # AppLocker blocked EXE
        (8004, 'AppLocker', 'applocker_block'),        # AppLocker blocked DLL
        (8006, 'AppLocker', 'applocker_block'),        # AppLocker blocked script
    ],
    1001: [  # Application Hang
        (2019, 'Memory',    'memory_exhaustion'),
        (2020, 'Memory',    'memory_exhaustion'),
    ],
    
    # ── Service Failures (7000, 7022, 7023, 7031, 7034) ─────────────────────
    # Service crash/hang typically due to memory exhaustion or disk I/O issues.
    # If memory/disk issues detected, fix those first.
    7031: [  # Service Terminated Unexpectedly
        (2019, 'Memory',    'memory_exhaustion'),
        (2020, 'Memory',    'memory_exhaustion'),
        (2004, 'Memory',    'resource_exhaustion'),
        (11,   'Disk',      'disk_io_error'),
        (51,   'Disk',      'disk_paging_error'),
    ],
    7034: [  # Service Terminated Unexpectedly (variant)
        (2019, 'Memory',    'memory_exhaustion'),
        (2020, 'Memory',    'memory_exhaustion'),
        (11,   'Disk',      'disk_io_error'),
    ],
    7000: [  # Service Failed to Start
        (2019, 'Memory',    'memory_exhaustion'),
        (10016, 'Privilege', 'dcom_permission'),
    ],
    7022: [  # Service Hung on Starting
        (2019, 'Memory',    'memory_exhaustion'),
        (11,   'Disk',      'disk_io_error'),
    ],
    7023: [  # Service Terminated with Error
        (2019, 'Memory',    'memory_exhaustion'),
        (2004, 'Memory',    'resource_exhaustion'),
    ],

    # ── Disk / Storage Errors (7, 11, 51, 55) ───────────────────────────────
    # Disk errors often cascade — multiple error types indicate NTFS corruption
    # or hardware failure that needs deep filesystem repair.
    11: [  # Disk Controller Error
        (51, 'Disk',   'disk_io_error'),
        (7,  'Disk',   'bad_blocks'),
        (55, 'Disk',   'ntfs_corruption'),
    ],
    51: [  # Disk Paging I/O Error
        (11, 'Disk',   'disk_io_error'),
        (7,  'Disk',   'bad_blocks'),
        (55, 'Disk',   'ntfs_corruption'),
    ],
    7: [  # Bad Blocks Detected
        (11, 'Disk',   'disk_io_error'),
        (51, 'Disk',   'disk_paging_error'),
        (55, 'Disk',   'ntfs_corruption'),
    ],
    55: [  # NTFS Corruption Detected
        (11, 'Disk',   'disk_io_error'),
        (51, 'Disk',   'disk_paging_error'),
        (7,  'Disk',   'bad_blocks'),
    ],

    # ── Memory Issues (2004, 2019, 2020) ─────────────────────────────────────
    # Memory exhaustion often precedes service/app crashes. If detected first,
    # we can be proactive rather than reactive.
    2019: [  # Non-Paged Pool Memory Exhausted
        (2020, 'Memory', 'memory_exhaustion'),
        (41,   'System', 'system_reboot_resource'),
    ],
    2020: [  # Paged Pool Memory Exhausted
        (2019, 'Memory', 'memory_exhaustion'),
        (41,   'System', 'system_reboot_resource'),
    ],
    2004: [  # Resource Exhaustion Detected
        (2019, 'Memory', 'memory_exhaustion'),
        (2020, 'Memory', 'memory_exhaustion'),
        (41,   'System', 'system_reboot_resource'),
    ],

    # ── Networking Issues (1014, 4202) ──────────────────────────────────────
    # Network disconnects and DNS failures can cascade to other services.
    1014: [  # DNS Name Resolution Timeout
        (4202, 'Networking', 'network_disconnect'),
    ],
    4202: [  # Network Interface Disconnected
        (1014, 'Networking', 'dns_timeout'),
    ],

    # ── Firewall Issues (5025, 5157) ─────────────────────────────────────────
    # If Windows Firewall stops, applications may lose network connectivity
    # and report connection errors.
    5025: [  # Windows Firewall Service Stopped
        (5157, 'Firewall', 'blocked_application'),
    ],
    5157: [  # Application Blocked by Firewall
        (5025, 'Firewall', 'firewall_service'),
    ],

    # ── AppLocker Blocks (8003, 8004, 8006) ──────────────────────────────────
    # Multiple AppLocker blocks might indicate a missing or outdated policy
    8003: [  # AppLocker Blocked Executable
        (8004, 'AppLocker', 'applocker_policy'),
        (8006, 'AppLocker', 'applocker_policy'),
    ],
    8004: [  # AppLocker Blocked DLL
        (8003, 'AppLocker', 'applocker_policy'),
        (8006, 'AppLocker', 'applocker_policy'),
    ],
    8006: [  # AppLocker Blocked Script
        (8003, 'AppLocker', 'applocker_policy'),
        (8004, 'AppLocker', 'applocker_policy'),
    ],

    # ── Privilege / Security Issues (4625, 10016) ───────────────────────────
    # Repeated logon failures or DCOM permission issues suggest auth/policy problems
    4625: [  # Logon Failure
        (10016, 'Privilege', 'dcom_permission'),
    ],
    10016: [  # DCOM Permission Denied
        (4625, 'Privilege', 'logon_failure'),
    ],

    # ── Event Log Issues (1100, 1101) ───────────────────────────────────────
    # If event log shuts down unexpectedly, audit events may be dropped
    1100: [  # Event Log Shutdown
        (1101, 'EventLog', 'audit_events_dropped'),
    ],
    1101: [  # Audit Events Dropped
        (1100, 'EventLog', 'event_log_failure'),
    ],

    # ── .NET Runtime Issues (1026) ──────────────────────────────────────────
    1026: [  # .NET Runtime Crash
        (2019, 'Memory',    'memory_exhaustion'),
        (2020, 'Memory',    'memory_exhaustion'),
        (8003, 'AppLocker', 'applocker_block'),
    ],
}

# How far back (in minutes) to look for correlated events
# Default: 5 minutes — adjustable per call
CORRELATION_WINDOW_MINUTES = 5

# Map compound_cause hints to actual remediation script names
COMPOUND_CAUSE_TO_SCRIPT = {
    'memory_exhaustion':       'Remediate_MemoryExhaustion.ps1',
    'resource_exhaustion':     'Remediate_ResourceExhaustion.ps1',
    'disk_io_error':          'Remediate_DiskIOError.ps1',
    'disk_paging_error':      'Remediate_DiskPagingError.ps1',
    'ntfs_corruption':        'Remediate_NTFSCorruption.ps1',
    'bad_blocks':             'Remediate_BadBlocks.ps1',
    'applocker_block':        'Remediate_AppLockerBlock.ps1',
    'applocker_policy':       'Remediate_AppLockerPolicy.ps1',
    'dns_timeout':            'Remediate_DNSTimeout.ps1',
    'network_disconnect':     'Remediate_NetworkDisconnect.ps1',
    'firewall_service':       'Remediate_FirewallService.ps1',
    'blocked_application':    'Remediate_FirewallBlockedApp.ps1',
    'dcom_permission':        'Remediate_DCOMPermission.ps1',
    'logon_failure':          'Remediate_LogonFailure.ps1',
    'system_reboot_resource': 'Remediate_SystemReboot.ps1',
    'audit_events_dropped':   'Remediate_AuditEvents.ps1',
}


def correlate_events(event_id, timestamp=None, window_minutes=None):
    """
    Inspect the events DB for correlated events that co-occurred within
    `window_minutes` of the given event's timestamp. This is the key to
    Multi-Event Inference: we detect compound root causes by looking at
    what other system errors happened in the time window.

    Args:
        event_id: The event ID to correlate (int or string)
        timestamp: ISO timestamp string. If None, uses current time.
        window_minutes: How many minutes back to look. If None, uses per-event-type window
                       from CORRELATION_WINDOW_MINUTES_MAP (PRIORITY 3 FIX).

    Returns a dict:
      {
        'has_correlation':  bool,                       # True if co-events found
        'compound_cause':   str | None,                 # e.g. 'memory_exhaustion'
        'compound_script':  str | None,                 # e.g. 'Remediate_MemoryExhaustion.ps1'
        'correlated_events': [
            {
              'db_id': int,
              'event_id': int,
              'source': str,
              'domain': str,
              'timestamp': str,
              'dedup_count': int,
              'severity': str,
            }
        ],
        'priority': str,                                # 'high', 'medium', 'low'
      }

    The caller (event_log_monitor._process_event) uses this to escalate the
    remediation from a simple restart to a compound-aware fix. For instance:
    - If app crashes (1000) and memory is exhausted (2019), fix memory first.
    - If service crashes (7031) and disk errors logged (11), fix disk first.
    """
    # PRIORITY 3 FIX: Use per-event-type correlation window if available
    event_id_int = int(event_id) if str(event_id).isdigit() else 0
    if window_minutes is None:
        window_minutes = CORRELATION_WINDOW_MINUTES_MAP.get(
            event_id_int, CORRELATION_WINDOW_MINUTES_DEFAULT
        )

    correlated_definitions = CORRELATION_MAP.get(event_id_int, [])
    if not correlated_definitions:
        return {
            'has_correlation': False,
            'compound_cause': None,
            'compound_script': None,
            'correlated_events': [],
            'priority': 'low',
        }

    cutoff = (
        (datetime.fromisoformat(timestamp) if timestamp else datetime.utcnow())
        - timedelta(minutes=window_minutes)
    ).isoformat()

    conn = _conn()
    c = conn.cursor()

    found_events = []
    compound_cause = None
    highest_severity = 'Information'
    severity_rank = {'Critical': 4, 'Error': 3, 'Warning': 2, 'Information': 1}

    for (corr_id, domain, cause_hint) in correlated_definitions:
        c.execute(
            '''SELECT id, event_id, source, timestamp, dedup_count, severity
               FROM events
               WHERE event_id = ? AND timestamp >= ?
               ORDER BY id DESC LIMIT 1''',
            (str(corr_id), cutoff)
        )
        row = c.fetchone()
        if row:
            event_severity = row[5] or 'Information'
            found_events.append({
                'db_id':    row[0],
                'event_id': row[1],
                'source':   row[2],
                'domain':   domain,
                'timestamp': row[3],
                'dedup_count': row[4] or 1,
                'severity': event_severity,
            })
            # Track highest severity and use first compound_cause found
            if severity_rank.get(event_severity, 0) > severity_rank.get(highest_severity, 0):
                highest_severity = event_severity
            if compound_cause is None:
                compound_cause = cause_hint

    conn.close()

    # Determine priority: Critical correlated events → high priority escalation
    priority = 'low'
    if found_events:
        if any(e['severity'].lower() == 'critical' for e in found_events):
            priority = 'high'
        elif any(e['severity'].lower() == 'error' for e in found_events):
            priority = 'medium'
        else:
            priority = 'low'

    return {
        'has_correlation':   len(found_events) > 0,
        'compound_cause':    compound_cause,
        'compound_script':   COMPOUND_CAUSE_TO_SCRIPT.get(compound_cause) if compound_cause else None,
        'correlated_events': found_events,
        'priority':          priority,
    }


def detect_faulting_module(message: str) -> str | None:
    """
    Extract the faulting module name from an application crash message.
    E.g., "faulting module name: ntdll.dll" → "ntdll.dll"
    
    Returns lowercased module name, or None if not found.
    """
    if not message:
        return None
    import re as _re
    m = _re.search(r'faulting module name:\s*([^\s,\n]+)', message, _re.IGNORECASE)
    if m:
        module = m.group(1).strip().lower()
        # Clean up any trailing punctuation
        module = _re.sub(r'[.,;:\s]$', '', module)
        return module
    return None


def is_core_os_module(module_name: str) -> bool:
    """
    Check if a faulting module is a core Windows system DLL.
    If yes, a simple restart will just produce an infinite crash loop —
    we need to escalate to system integrity repair (sfc /scannow).
    """
    CORE_OS_MODULES = {
        'ntdll.dll', 'kernel32.dll', 'kernelbase.dll', 'msvcrt.dll',
        'user32.dll', 'advapi32.dll', 'ole32.dll', 'rpcrt4.dll',
        'combase.dll', 'ucrtbase.dll', 'msvcp_win.dll', 'winhttp.dll',
        'crypt32.dll', 'shlwapi.dll', 'ws2_32.dll', 'winsock2.dll',
        'gdi32.dll', 'shell32.dll', 'comdlg32.dll', 'mapi32.dll',
    }
    return (module_name or '').lower() in CORE_OS_MODULES


# Applications that routinely crash through core OS modules but do NOT
# indicate OS corruption. Triggering sfc/scannow for these would be
# both slow and noisy. We skip the deep-repair escalation for these.
_TRIVIAL_APPS = {
    'notepad.exe', 'wordpad.exe', 'mspaint.exe', 'calc.exe',
    'iexplore.exe', 'msedge.exe', 'chrome.exe', 'firefox.exe',
    'vlc.exe', 'winrar.exe', '7zfm.exe', 'crash.exe',
    'notepad++.exe', 'code.exe',
}


def should_escalate_to_system_repair(faulting_module: str, message: str) -> bool:
    """
    Returns True only when a non-trivial application crashes through a
    core Windows OS module, which genuinely indicates OS file corruption.
    Trivial apps (notepad, browsers, etc.) frequently fault through ntdll.dll
    for app-specific reasons — no SFC scan is warranted for those.
    """
    if not is_core_os_module(faulting_module):
        return False
    # Extract the faulting *application* name from the message
    if message:
        import re as _re
        app_match = _re.search(
            r'faulting application name:\s*([^\s,\n]+)', message, _re.IGNORECASE
        )
        if app_match:
            app_name = app_match.group(1).strip().lower()
            if app_name in _TRIVIAL_APPS:
                logger.debug(
                    f'[SYSREPAIR-SKIP] {app_name} crashed via {faulting_module} '
                    'but it is a trivial app — skipping deep system repair escalation.'
                )
                return False
    return True




def is_rule_in_cooldown(rule_id, event_id_val, source_val, cooldown_minutes):
    """
    Returns True if this rule was successfully (or failed) executed for an
    event matching (event_id + source) within the cooldown window.
    A cooldown of 0 means no suppression.
    """
    if not cooldown_minutes or cooldown_minutes <= 0:
        return False

    cutoff = (datetime.utcnow() - timedelta(minutes=cooldown_minutes)).isoformat()
    conn = _conn()
    c = conn.cursor()
    c.execute('''
        SELECT COUNT(*)
        FROM remediation_history h
        JOIN events e ON h.event_row_id = e.id
        WHERE h.rule_id = ?
          AND e.event_id = ?
          AND LOWER(COALESCE(e.source,'')) = LOWER(COALESCE(?,''))
          AND h.timestamp > ?
          AND h.status IN ('success', 'failed')
    ''', (rule_id, event_id_val, source_val or '', cutoff))
    count = c.fetchone()[0]
    conn.close()
    return count > 0


def get_intelligence_summary():
    """
    Returns a summary dict used by the Dashboard Intelligence card:
      - total_events: total events in DB
      - deduplicated_events: events that were merged (dedup_count > 1)
      - total_suppressed: total individual occurrences that were deduplicated
      - avg_confidence: average confidence score across all events
      - rules_with_cooldown: count of rules that have cooldown_minutes > 0
    """
    conn = _conn()
    try:
        c = conn.cursor()

        c.execute('SELECT COUNT(*) FROM events')
        total_events = c.fetchone()[0]

        c.execute('SELECT COUNT(*), SUM(dedup_count - 1) FROM events WHERE dedup_count > 1')
        row = c.fetchone()
        deduplicated_events = row[0] or 0
        total_suppressed = int(row[1] or 0)

        c.execute('SELECT AVG(confidence_score) FROM events WHERE confidence_score > 0')
        avg_conf = c.fetchone()[0]
        avg_confidence = round(float(avg_conf), 1) if avg_conf else 0.0

        c.execute('SELECT COUNT(*) FROM rules WHERE cooldown_minutes > 0')
        rules_with_cooldown = c.fetchone()[0]

        return {
            'total_events': total_events,
            'deduplicated_events': deduplicated_events,
            'total_suppressed': total_suppressed,
            'avg_confidence': avg_confidence,
            'rules_with_cooldown': rules_with_cooldown,
        }
    finally:
        conn.close()


# ─────────────────────────────────────────────────────────────────────────────
#  Events
# ─────────────────────────────────────────────────────────────────────────────

def add_event(event_id, log_name, source, message,
              timestamp=None, category=None, severity=None,
              description=None, recommended_action=None, level=None,
              remediated_at=None, source_type='api', return_status=False):
    """
    Smart event ingestion with deduplication, confidence scoring, and correlation.

    If an event with the same event_id + source was seen within DEDUP_WINDOW_SECONDS,
    this call increments its dedup_count and updates last_seen instead of inserting
    a new row.  Returns the DB row id (new or existing) unless return_status is True,
    in which case it returns (row_id, is_new).
    """
    if timestamp is None:
        timestamp = datetime.utcnow().isoformat()

    # Enrich with metadata from JSON catalog if not provided
    if category is None or severity is None or description is None or recommended_action is None:
        defn = get_event_definition(event_id, source)
        if defn:
            category = category or defn.get('category')
            severity = severity or defn.get('severity')
            description = description or defn.get('description')
            recommended_action = recommended_action or defn.get('recommended_action')

    # ── Deduplication check ────────────────────────────────────────────────
    conn = _conn()
    try:
        c = conn.cursor()
        cutoff = (datetime.utcnow() - timedelta(seconds=DEDUP_WINDOW_SECONDS)).isoformat()

        c.execute('''
            SELECT id, dedup_count, last_seen
            FROM events
            WHERE event_id = ?
              AND LOWER(COALESCE(source,'')) = LOWER(COALESCE(?,''))
              AND timestamp >= ?
            ORDER BY id DESC
            LIMIT 1
        ''', (event_id, source or '', cutoff))
        existing = c.fetchone()

        if existing:
            existing_id = existing[0]
            prev_count = existing[1] or 1
            existing_last_seen = existing[2]

            if existing_last_seen == timestamp:
                # This is the exact same event being polled again, not a new crash.
                return (existing_id, 'DUPLICATE_POLL') if return_status else existing_id

            # Merge into existing row — use atomic SQL update to avoid race condition
            event_dict = {'severity': severity, 'level': level}
            new_count = prev_count + 1
            new_score = calculate_confidence_score(event_dict, dedup_count=new_count)
            
            # Atomic update: increment dedup_count in single operation
            c.execute('''
                UPDATE events
                SET dedup_count = ?, last_seen = ?, confidence_score = ?
                WHERE id = ?
            ''', (new_count, timestamp, new_score, existing_id))
            conn.commit()
            return (existing_id, 'NEW_OCCURRENCE') if return_status else existing_id
    finally:
        conn.close()

    # ── New event — compute correlation_id and confidence score ──────────────
    conn = _conn()
    c = conn.cursor()
    try:
        correlation_id = get_correlation_id(source, timestamp)
        event_dict = {
            'event_id': event_id,
            'source': source,
            'message': message,
            'severity': severity,
            'level': level,
            'category': category,
        }
        confidence_score = calculate_confidence_score(event_dict, dedup_count=1)
        
        # ── Root Cause Variant Analysis ────────────────────────────────────────
        detected_variants = analyze_root_cause(event_dict)
        root_cause_variant_id = None
        root_cause_variant_label = None
        root_cause_confidence = None
        detected_root_causes_json = None
        
        if detected_variants:
            # Use the highest-confidence variant
            best_variant = detected_variants[0]
            root_cause_variant_id = best_variant.variant_id
            root_cause_variant_label = best_variant.label
            root_cause_confidence = best_variant.confidence.value
            
            # Store all detected variants as JSON for reference
            try:
                detected_root_causes_json = json.dumps([
                    v.to_dict() for v in detected_variants
                ], default=str)
            except Exception as e:
                logger.error(f'Failed to serialize root cause variants: {e}')
                detected_root_causes_json = None

        c.execute(
            '''INSERT INTO events
               (event_id, log_name, source, message, timestamp, category, severity,
                description, recommended_action, level, remediated_at,
                dedup_count, last_seen, confidence_score, correlation_id, source_type,
                root_cause_variant_id, root_cause_variant_label, root_cause_confidence,
                detected_root_causes)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
            (event_id, log_name, source, message, timestamp, category, severity,
             description, recommended_action, level, remediated_at,
             1, timestamp, confidence_score, correlation_id, source_type or 'api',
             root_cause_variant_id, root_cause_variant_label, root_cause_confidence,
             detected_root_causes_json)
        )
        rowid = c.lastrowid
        conn.commit()
    finally:
        conn.close()

    # Append to CSV (for Warnings & Errors tab)
    try:
        write_event_row_to_csv(ERRORS_WARNINGS_CSV, {
            'event_id': event_id, 'log_name': log_name, 'source': source,
            'message': message, 'timestamp': timestamp, 'category': category,
            'severity': severity, 'description': description,
            'recommended_action': recommended_action, 'level': level,
            'remediated_at': remediated_at,
            'confidence_score': confidence_score, 'correlation_id': correlation_id,
        })
    except Exception:
        pass

    # Update last-processed marker
    try:
        with open(LAST_PROCESSED_PATH, 'w', encoding='utf-8') as f:
            json.dump({'last_rowid': rowid, 'last_timestamp': timestamp}, f)
    except Exception:
        pass
    return (rowid, 'NEW_ROW') if return_status else rowid


def write_event_row_to_csv(path, rowdict):
    fieldnames = [
        'event_id', 'log_name', 'source', 'message', 'timestamp',
        'category', 'severity', 'description', 'recommended_action',
        'level', 'remediated_at', 'confidence_score', 'correlation_id',
    ]
    exists = os.path.exists(path)
    with open(path, 'a', newline='', encoding='utf-8') as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames, extrasaction='ignore')
        if not exists:
            writer.writeheader()
        writer.writerow({k: (rowdict.get(k) if rowdict.get(k) is not None else '') for k in fieldnames})


def _rotate_csv_if_needed(csv_path, max_size_mb=500, max_age_days=90):
    """Rotate CSV file if it exceeds size or age limit (PRIORITY 3 FIX).
    
    Prevents unbounded CSV file growth which could exhaust disk space or cause
    memory issues when reading the entire file.
    """
    if not os.path.exists(csv_path):
        return
    
    try:
        file_size_mb = os.path.getsize(csv_path) / (1024 * 1024)
        file_age_days = (datetime.utcnow() - datetime.fromtimestamp(
            os.path.getmtime(csv_path)
        )).days
        
        if file_size_mb > max_size_mb or file_age_days > max_age_days:
            timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
            archive_path = f"{csv_path}.{timestamp}.bak"
            os.rename(csv_path, archive_path)
            logger.info(f'CSV rotation: {csv_path} → {archive_path} '
                       f'(size={file_size_mb:.1f}MB, age={file_age_days}d)')
    except Exception as e:
        logger.warning(f'Failed to rotate CSV file {csv_path}: {e}')


def read_filtered_events_csv(limit=500):
    """Read errors/warnings CSV — most recent first. Handles NUL bytes. Optimized."""
    if not os.path.exists(ERRORS_WARNINGS_CSV):
        return []
    
    # PRIORITY 3 FIX: Rotate CSV if it exceeds size/age limits
    _rotate_csv_if_needed(ERRORS_WARNINGS_CSV, max_size_mb=500, max_age_days=90)
    
    rows = []
    try:
        with open(ERRORS_WARNINGS_CSV, 'rb') as f:
            content = f.read()
        # Remove NUL bytes and decode
        clean_content = content.replace(b'\x00', b'').decode('utf-8', errors='ignore')
        # Parse CSV from cleaned content
        import io
        csvfile = io.StringIO(clean_content)
        reader = csv.DictReader(csvfile)
        # Only keep last N rows to avoid memory issues
        for r in reader:
            if r is None:
                continue
            r.pop(None, None)  # fix for rows having more cols than original header
            rows.append(r)
            if len(rows) > limit:
               rows.pop(0)  # Keep only the last `limit` rows
    except Exception as e:
        print(f"Error reading filtered events CSV: {e}")
        return []
    rows.reverse()  # Most recent first
    return rows


def get_last_processed():
    if not os.path.exists(LAST_PROCESSED_PATH):
        return None
    try:
        with open(LAST_PROCESSED_PATH, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return None


def get_events(limit=100):
    conn = _conn()
    try:
        c = conn.cursor()
        c.execute('''
            SELECT id, event_id, log_name, source, message, timestamp,
                   category, severity, description, recommended_action,
                   COALESCE(dedup_count, 1), last_seen,
                   COALESCE(confidence_score, 0.0), correlation_id,
                   COALESCE(source_type, 'api'),
                   COALESCE(needs_manual_review, 0),
                   manual_review_reason,
                   COALESCE(dismissed_review, 0)
            FROM events
            ORDER BY id DESC
            LIMIT ?
        ''', (limit,))
        rows = c.fetchall()
        return rows
    finally:
        conn.close()


def get_events_paginated(offset=0, limit=50):
    """Get events with pagination support (PERFORMANCE FIX #2).
    
    Uses indexed query for fast retrieval without full table scans.
    """
    conn = _conn()
    try:
        c = conn.cursor()
        c.execute('''
            SELECT id, event_id, log_name, source, message, timestamp,
                   category, severity, description, recommended_action,
                   COALESCE(dedup_count, 1), last_seen,
                   COALESCE(confidence_score, 0.0), correlation_id,
                   COALESCE(source_type, 'api'),
                   COALESCE(needs_manual_review, 0),
                   manual_review_reason,
                   COALESCE(dismissed_review, 0)
            FROM events
            ORDER BY id DESC
            LIMIT ? OFFSET ?
        ''', (limit, offset))
        rows = c.fetchall()
        return rows
    finally:
        conn.close()


_event_count_cache_py = {'count': None, 'timestamp': 0, 'ttl': 60}

def count_events():
    """Count total events (with caching to prevent expensive queries).
    
    PERFORMANCE FIX #5: Caches count for 60 seconds since COUNT queries
    on large tables (166k+ rows) can be expensive.
    """
    import time
    now = time.time()
    
    # Use cached count if valid
    if (_event_count_cache_py['count'] is not None and 
        (now - _event_count_cache_py['timestamp']) < _event_count_cache_py['ttl']):
        return _event_count_cache_py['count']
    
    conn = _conn()
    try:
        c = conn.cursor()
        c.execute('SELECT COUNT(*) FROM events')
        count = c.fetchone()[0]
        
        # Update cache
        _event_count_cache_py['count'] = count
        _event_count_cache_py['timestamp'] = now
        
        return count
    finally:
        conn.close()


# (REMOVED - see _event_count_cache_py version above with caching)


def set_manual_review(event_row_id, reason=''):
    """Flag an event as needing manual intervention (no matching rule found)."""
    conn = _conn()
    try:
        c = conn.cursor()
        c.execute(
            'UPDATE events SET needs_manual_review=1, manual_review_reason=? WHERE id=?',
            (reason, event_row_id)
        )
        conn.commit()
    finally:
        conn.close()


def dismiss_manual_review(event_row_id):
    """Mark an event's manual review as dismissed by the operator."""
    conn = _conn()
    try:
        c = conn.cursor()
        c.execute(
            'UPDATE events SET dismissed_review=1 WHERE id=?',
            (event_row_id,)
        )
        conn.commit()
    finally:
        conn.close()


def get_events_needing_review(limit=100):
    """Return events flagged for manual review that haven't been dismissed."""
    conn = _conn()
    try:
        c = conn.cursor()
        c.execute('''
            SELECT id, event_id, log_name, source, message, timestamp,
                   category, severity, description, recommended_action,
                   COALESCE(dedup_count, 1), last_seen,
                   COALESCE(confidence_score, 0.0), correlation_id,
                   COALESCE(source_type, 'api'),
                   manual_review_reason
            FROM events
            WHERE needs_manual_review = 1
              AND COALESCE(dismissed_review, 0) = 0
            ORDER BY id DESC
            LIMIT ?
        ''', (limit,))
        rows = c.fetchall()
        return rows
    finally:
        conn.close()


def get_event(event_row_id):
    conn = _conn()
    try:
        c = conn.cursor()
        c.execute('''
            SELECT id, event_id, log_name, source, message, timestamp,
                   category, severity, description, recommended_action,
                   dedup_count, last_seen, confidence_score, correlation_id
            FROM events WHERE id=?
        ''', (event_row_id,))
        r = c.fetchone()
        return r
    finally:
        conn.close()


# ─────────────────────────────────────────────────────────────────────────────
#  Rules — now with priority and cooldown
# ─────────────────────────────────────────────────────────────────────────────

def add_rule(name, event_id=None, source=None, message_regex=None,
             remediation_script=None, script_type='file',
             auto_remediate=0, stop_processing=0, category=None, severity=None,
             description=None, recommended_action=None,
             priority=100, cooldown_minutes=0):
    conn = _conn()
    try:
        c = conn.cursor()

        # Enrich metadata from JSON catalog
        if event_id and (category is None or severity is None):
            defn = get_event_definition(event_id, source)
            if defn:
                category = category or defn.get('category')
                severity = severity or defn.get('severity')
                description = description or defn.get('description')
                recommended_action = recommended_action or defn.get('recommended_action')

        c.execute(
            '''INSERT INTO rules
               (name, event_id, source, message_regex, remediation_script,
                script_type, auto_remediate, stop_processing, category, severity, description,
                recommended_action, priority, cooldown_minutes)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
            (name, event_id, source, message_regex, remediation_script,
             script_type or 'file', int(auto_remediate), int(stop_processing), category, severity,
             description, recommended_action, int(priority), int(cooldown_minutes))
        )
        conn.commit()
        rid = c.lastrowid
        return rid
    finally:
        conn.close()


def get_rules():
    conn = _conn()
    try:
        c = conn.cursor()
        # Ensure active column exists (added in schema v4)
        try:
            c.execute('ALTER TABLE rules ADD COLUMN active INTEGER DEFAULT 1')
            conn.commit()
        except Exception:
            pass
        c.execute('''
            SELECT id, name, event_id, source, message_regex, remediation_script,
                   auto_remediate, category, severity, description, recommended_action,
                   script_type, priority, cooldown_minutes, stop_processing,
                   COALESCE(active, 1) as active
            FROM rules
            ORDER BY priority ASC, id ASC
        ''')
        rows = c.fetchall()
        return rows
    finally:
        conn.close()


def get_rule_hit_counts():
    """Return a dict of rule_id -> hit count from remediation_history."""
    conn = _conn()
    try:
        c = conn.cursor()
        c.execute('''
            SELECT rule_id, COUNT(*) as hits, MAX(timestamp) as last_hit
            FROM remediation_history
            WHERE rule_id IS NOT NULL
            GROUP BY rule_id
        ''')
        return {row[0]: {'hits': row[1], 'last_hit': row[2]} for row in c.fetchall()}
    finally:
        conn.close()


def toggle_rule_active(rule_id, active):
    """Enable or disable a rule (1=active, 0=disabled)."""
    conn = _conn()
    try:
        c = conn.cursor()
        # Ensure column exists
        try:
            c.execute('ALTER TABLE rules ADD COLUMN active INTEGER DEFAULT 1')
        except Exception:
            pass
        c.execute('UPDATE rules SET active=? WHERE id=?', (1 if active else 0, rule_id))
        conn.commit()
        return c.rowcount > 0
    finally:
        conn.close()


def get_rule(rule_id):
    conn = _conn()
    try:
        c = conn.cursor()
        c.execute('''
            SELECT id, name, event_id, source, message_regex, remediation_script,
                   auto_remediate, category, severity, description, recommended_action,
                   script_type, priority, cooldown_minutes, stop_processing
            FROM rules WHERE id=?
        ''', (rule_id,))
        r = c.fetchone()
        return r
    finally:
        conn.close()


def update_rule(rule_id, name=None, event_id=None, source=None,
                message_regex=None, remediation_script=None, script_type=None,
                auto_remediate=None, stop_processing=None, category=None, severity=None,
                description=None, recommended_action=None,
                priority=None, cooldown_minutes=None):
    conn = _conn()
    c = conn.cursor()
    fields, vals = [], []

    def _set(col, val, cast=None):
        if val is not None:
            fields.append(f'{col}=?')
            vals.append(cast(val) if cast else val)

    _set('name', name)
    _set('event_id', event_id)
    _set('source', source)
    _set('message_regex', message_regex)
    _set('remediation_script', remediation_script)
    _set('script_type', script_type)
    if auto_remediate is not None:
        fields.append('auto_remediate=?')
        vals.append(int(bool(auto_remediate)))
    if stop_processing is not None:
        fields.append('stop_processing=?')
        vals.append(int(bool(stop_processing)))
    _set('category', category)
    _set('severity', severity)
    _set('description', description)
    _set('recommended_action', recommended_action)
    _set('priority', priority, int)
    _set('cooldown_minutes', cooldown_minutes, int)

    if not fields:
        conn.close()
        return False

    vals.append(rule_id)
    c.execute('UPDATE rules SET ' + ', '.join(fields) + ' WHERE id=?', vals)
    conn.commit()
    conn.close()
    return True


def delete_rule(rule_id):
    conn = _conn()
    try:
        c = conn.cursor()
        c.execute('DELETE FROM rules WHERE id=?', (rule_id,))
        conn.commit()
        return True
    finally:
        conn.close()


# ─────────────────────────────────────────────────────────────────────────────
#  Root Cause Variant Operations
# ─────────────────────────────────────────────────────────────────────────────

def add_root_cause_variant(event_row_id, variant_id, variant_label, description,
                           confidence_score, confidence_level, matched_indicators=None):
    """Store a detected root cause variant for an event."""
    conn = _conn()
    c = conn.cursor()
    ts = datetime.utcnow().isoformat()
    indicators_json = json.dumps(matched_indicators or [])
    
    c.execute(
        '''INSERT INTO event_root_cause_variants
           (event_row_id, variant_id, variant_label, description, confidence_score,
            confidence_level, matched_indicators, detected_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
        (event_row_id, variant_id, variant_label, description, confidence_score,
         confidence_level, indicators_json, ts)
    )
    conn.commit()
    vid = c.lastrowid
    conn.close()
    return vid


def link_rule_to_variant(rule_id, variant_id, variant_label, min_confidence=60):
    """
    Associate a rule with a specific root cause variant.
    The rule will only apply to events matching this variant with confidence >= min_confidence.
    
    This allows different remediation strategies for different variants of the same error.
    """
    conn = _conn()
    c = conn.cursor()
    ts = datetime.utcnow().isoformat()
    
    c.execute(
        '''INSERT INTO rule_variant_associations
           (rule_id, variant_id, variant_label, min_confidence, created_at)
           VALUES (?, ?, ?, ?, ?)''',
        (rule_id, variant_id, variant_label, min_confidence, ts)
    )
    conn.commit()
    aid = c.lastrowid
    conn.close()
    return aid


def get_variant_associations(rule_id):
    """Get all variant associations for a rule."""
    conn = _conn()
    c = conn.cursor()
    c.execute(
        '''SELECT id, rule_id, variant_id, variant_label, min_confidence, created_at
           FROM rule_variant_associations WHERE rule_id = ?''',
        (rule_id,)
    )
    rows = c.fetchall()
    conn.close()
    return rows


def get_event_root_causes(event_row_id):
    """Get all detected root cause variants for an event."""
    conn = _conn()
    c = conn.cursor()
    c.execute(
        '''SELECT id, event_row_id, variant_id, variant_label, description,
                  confidence_score, confidence_level, matched_indicators, detected_at
           FROM event_root_cause_variants
           WHERE event_row_id = ?
           ORDER BY confidence_score DESC''',
        (event_row_id,)
    )
    rows = c.fetchall()
    conn.close()
    return rows


def match_rules_for_event_with_variants(event):
    """
    Enhanced rule matching that considers root cause variants.
    
    Returns matched rules enhanced with:
    - variant_match: True if rule has variant associations and event matches variant
    - variant_info: dict with detected variant details
    - is_variant_rule: True if this rule is specific to a variant
    """
    matched = []
    rules = get_rules()
    
    event_id_val = event.get('event_id')
    source_val = event.get('source') or ''
    detected_variants = event.get('detected_variants', [])  # From analyze_root_cause
    best_variant = detected_variants[0] if detected_variants else None
    
    stop_triggered = False
    
    for r in rules:
        if stop_triggered:
            break
        
        rid = r[0]  # rule id
        
        # Get variant associations for this rule
        variant_associations = get_variant_associations(rid)
        
        # First, check base event matching (existing logic)
        base_match = _matches_base_criteria(event, r)
        if not base_match:
            continue
        
        # If rule has variant associations, check if event variant matches
        if variant_associations:
            variant_matched = False
            matched_association = None
            
            if best_variant:
                for assoc in variant_associations:
                    # assoc: (id, rule_id, variant_id, variant_label, min_confidence, created_at)
                    assoc_variant_id = assoc[2]
                    assoc_min_confidence = assoc[4]
                    
                    if best_variant.variant_id == assoc_variant_id:
                        if best_variant.confidence.value >= assoc_min_confidence:
                            variant_matched = True
                            matched_association = assoc
                            break
            
            # If variant rule but variant didn't match, skip this rule
            if not variant_matched:
                continue
            
            # Variant matched - pass rule with variant info
            matched.append((*r, False, {}, True, best_variant.to_dict(), matched_association))
        else:
            # No variant associations - regular rule matching (backward compatible)
            regex_captures = _extract_regex_captures(event, r)
            if regex_captures is None:
                continue
            
            # Check cooldown
            is_suppressed = _check_rule_cooldown(event, r)
            matched.append((*r, is_suppressed, regex_captures, False, None, None))
        
        # Check stop_processing flag
        stop_processing = r[14]  # Based on r tuple structure from get_rules
        if stop_processing:
            stop_triggered = True
    
    return matched


def _matches_base_criteria(event, rule_tuple):
    """Check if event matches base rule criteria (excluding variants)."""
    (rid, name, r_event_id, r_source, r_message_regex, remediation_script,
     auto_remediate, r_category, r_severity, description, recommended_action,
     script_type, priority, cooldown_minutes, stop_processing, _active) = rule_tuple
    
    event_id_val = event.get('event_id')
    source_val = (event.get('source') or '').lower()
    category_val = (event.get('category') or '').lower()
    severity_val = (event.get('severity') or '').lower()
    
    if not _active:
        return False
        
    if r_event_id and str(r_event_id) != str(event_id_val):
        return False
    if r_source and r_source.lower() != source_val:
        return False
    if r_category and r_category.lower() != category_val:
        return False
    if r_severity and r_severity.lower() != severity_val:
        return False
    
    return True


def _extract_regex_captures(event, rule_tuple):
    """Extract regex capture groups from event message.
    
    SECURITY: Includes length protection against ReDoS (Regular Expression Denial of Service)
    attacks where malicious regex patterns with catastrophic backtracking could hang the system.
    (PRIORITY 2 FIX)
    """
    r_message_regex = rule_tuple[4]  # message_regex index in rule tuple
    
    if not r_message_regex:
        return {}
    
    try:
        # Compile regex to catch obvious errors early
        compiled = re.compile(r_message_regex, flags=re.DOTALL)
        
        # Truncate very long messages to prevent ReDoS and processing issues
        message = event.get('message') or ''
        if len(message) > 10000:
            message = message[:10000]
        
        m = compiled.search(message)
        if not m:
            return None
        return m.groupdict()
    except re.error as e:
        # Regex is invalid — log and skip this rule
        logger.error(f'Invalid regex in rule {rule_tuple[0]}: {r_message_regex}. Error: {e}')
        return None
    except Exception as e:
        logger.error(f'Unexpected error in regex capture for rule {rule_tuple[0]}: {e}')
        return None


def _check_rule_cooldown(event, rule_tuple):
    """Check if rule is in cooldown."""
    rid = rule_tuple[0]  # rule id
    event_id_val = event.get('event_id')
    source_val = (event.get('source') or '').lower()
    cooldown_minutes = rule_tuple[13]
    
    return is_rule_in_cooldown(rid, event_id_val, source_val, cooldown_minutes)


def match_rules_for_event(event):
    """
    Return rules that match the given event dict, with intelligence additions:
      1. Strict category/severity matching if configured.
      2. Regex capture groups are extracted and appended to the rule tuple.
      3. Rules in cooldown are skipped (with reason recorded).
      4. Return ALL matching rules (no stop_processing short-circuiting).
      5. PRIORITY 2 FIX: Removed stop_processing logic that broke priority system.
      
    NOTE: stop_processing is now advisory only (set in rule tuple for caller to check).
    Execution flow should be:
      - Call this function to get ALL matching rules
      - Caller (event_log_monitor.py) decides execution order and when to stop
    """
    matched = []
    rules = get_rules()   # already sorted by priority ASC

    event_id_val = event.get('event_id')
    source_val   = event.get('source') or ''
    category_val = (event.get('category') or '').lower()
    severity_val = (event.get('severity') or '').lower()

    for r in rules:
        # r index mapping:
        # 0=id,1=name,2=event_id,3=source,4=message_regex,
        # 5=remediation_script,6=auto_remediate,7=category,
        # 8=severity,9=description,10=recommended_action,
        # 11=script_type,12=priority,13=cooldown_minutes,14=stop_processing,15=_active
        (rid, name, r_event_id, r_source, r_message_regex, remediation_script,
         auto_remediate, r_category, r_severity, description, recommended_action,
         script_type, priority, cooldown_minutes, stop_processing, _active) = r

        if not _active:
            continue

        # ── Matching logic (AND semantics) ────────────────────────────────
        if r_event_id and str(r_event_id) != str(event_id_val):
            continue
        if r_source and r_source.lower() != source_val.lower():
            continue
        if r_category and r_category.lower() != category_val:
            continue
        if r_severity and r_severity.lower() != severity_val:
            continue

        regex_captures = {}
        if r_message_regex:
            regex_result = _extract_regex_captures(event, r)
            if regex_result is None and r_message_regex:
                continue  # Regex didn't match
            regex_captures = regex_result or {}

        # ── Cooldown check for auto-remediation ──────────────────────────
        if auto_remediate and is_rule_in_cooldown(rid, event_id_val, source_val, cooldown_minutes):
            matched.append((*r, True, regex_captures))   # True = cooldown_active flag
            continue

        matched.append((*r, False, regex_captures))      # False = not suppressed
        # PRIORITY 2 FIX: No longer break on stop_processing
        # Let all matching rules be returned; execution decision is caller's responsibility

    return matched


# ─────────────────────────────────────────────────────────────────────────────
#  Remediation requests & history
# ─────────────────────────────────────────────────────────────────────────────

def record_remediation(event_row_id, rule_id, status, output=''):
    conn = _conn()
    try:
        c = conn.cursor()
        ts = datetime.utcnow().isoformat()
        c.execute(
            'INSERT INTO remediation_history (event_row_id, rule_id, status, output, timestamp) VALUES (?, ?, ?, ?, ?)',
            (event_row_id, rule_id, status, output, ts)
        )
        conn.commit()
    finally:
        conn.close()


def get_history(limit=50, offset=0, status=None, search=None, sort_col='id', sort_dir='DESC'):
    """Paginated, filterable, sortable remediation history."""
    conn = _conn()
    try:
        c = conn.cursor()
        # Whitelist sort columns to prevent injection
        allowed_cols = {'id', 'timestamp', 'event_id', 'status'}
        if sort_col not in allowed_cols:
            sort_col = 'id'
        sort_dir = 'DESC' if sort_dir.upper() != 'ASC' else 'ASC'

        conditions = []
        params = []
        if status and status != 'all':
            conditions.append('h.status = ?')
            params.append(status)
        if search:
            conditions.append('(r.name LIKE ? OR CAST(e.event_id AS TEXT) LIKE ? OR e.source LIKE ?)')
            term = f'%{search}%'
            params.extend([term, term, term])

        where = ('WHERE ' + ' AND '.join(conditions)) if conditions else ''
        query = f'''
            SELECT h.id, h.event_row_id, h.rule_id, h.status, h.output, h.timestamp,
                   e.event_id, e.source, r.name, e.timestamp as event_timestamp
            FROM remediation_history h
            LEFT JOIN events e ON h.event_row_id = e.id
            LEFT JOIN rules r ON h.rule_id = r.id
            {where}
            ORDER BY h.{sort_col} {sort_dir}
            LIMIT ? OFFSET ?
        '''
        c.execute(query, params + [limit, offset])
        rows = c.fetchall()
        return rows
    finally:
        conn.close()


def get_history_count(status=None, search=None):
    """Return total count of history records for pagination."""
    conn = _conn()
    try:
        c = conn.cursor()
        conditions = []
        params = []
        if status and status != 'all':
            conditions.append('h.status = ?')
            params.append(status)
        if search:
            conditions.append('(r.name LIKE ? OR CAST(e.event_id AS TEXT) LIKE ? OR e.source LIKE ?)')
            term = f'%{search}%'
            params.extend([term, term, term])
        where = ('WHERE ' + ' AND '.join(conditions)) if conditions else ''
        query = f'''
            SELECT COUNT(*)
            FROM remediation_history h
            LEFT JOIN events e ON h.event_row_id = e.id
            LEFT JOIN rules r ON h.rule_id = r.id
            {where}
        '''
        c.execute(query, params)
        return c.fetchone()[0]
    finally:
        conn.close()


def get_event_history(event_row_id):
    conn = _conn()
    try:
        c = conn.cursor()
        c.execute('''
            SELECT h.id, h.event_row_id, h.rule_id, h.status, h.output, h.timestamp,
                   e.event_id, e.source, r.name, e.timestamp as event_timestamp
            FROM remediation_history h
            LEFT JOIN events e ON h.event_row_id = e.id
            LEFT JOIN rules r ON h.rule_id = r.id
            WHERE h.event_row_id = ?
            ORDER BY h.id DESC
        ''', (event_row_id,))
        rows = c.fetchall()
        return rows
    finally:
        conn.close()


def create_remediation_request(event_row_id, rule_id, requested_by='web-ui'):
    conn = _conn()
    c = conn.cursor()
    ts = datetime.utcnow().isoformat()
    c.execute(
        'INSERT INTO remediation_requests (event_row_id, rule_id, status, requested_by, requested_at) VALUES (?, ?, ?, ?, ?)',
        (event_row_id, rule_id, 'pending', requested_by, ts)
    )
    conn.commit()
    rid = c.lastrowid
    conn.close()
    return rid


def get_requests(status=None, limit=200):
    conn = _conn()
    c = conn.cursor()
    base = '''
        SELECT r.id, r.event_row_id, r.rule_id, r.status, r.requested_by,
               r.requested_at, r.processed_by, r.processed_at, r.decision_note,
               e.event_id, e.source, rules.name
        FROM remediation_requests r
        LEFT JOIN events e ON r.event_row_id = e.id
        LEFT JOIN rules ON r.rule_id = rules.id
    '''
    if status:
        c.execute(base + ' WHERE r.status = ? ORDER BY r.id DESC LIMIT ?', (status, limit))
    else:
        c.execute(base + ' ORDER BY r.id DESC LIMIT ?', (limit,))
    rows = c.fetchall()
    conn.close()
    return rows


def get_request(request_id):
    conn = _conn()
    c = conn.cursor()
    c.execute('SELECT id, event_row_id, rule_id, status, requested_by, requested_at, processed_by, processed_at, decision_note FROM remediation_requests WHERE id=?', (request_id,))
    r = c.fetchone()
    conn.close()
    return r


def update_request_status(request_id, status, processed_by=None, decision_note=None):
    conn = _conn()
    c = conn.cursor()
    processed_at = datetime.utcnow().isoformat()
    c.execute('UPDATE remediation_requests SET status=?, processed_by=?, processed_at=?, decision_note=? WHERE id=?',
              (status, processed_by, processed_at, decision_note, request_id))
    conn.commit()
    conn.close()
    return True


# ─────────────────────────────────────────────────────────────────────────────
#  find_or_create_event — for CSV-sourced events (UI actions)
# ─────────────────────────────────────────────────────────────────────────────

def find_or_create_event(event_id, log_name=None, source=None, message=None,
                          timestamp=None, category=None, severity=None,
                          description=None, recommended_action=None, level=None):
    """
    Find an existing DB event row by event_id+source+timestamp (or just most recent),
    or create one.  Does NOT trigger auto-remediation.  Returns the DB row id.
    """
    conn = _conn()
    c = conn.cursor()
    if timestamp:
        c.execute(
            'SELECT id FROM events WHERE event_id=? AND source=? AND timestamp=? LIMIT 1',
            (event_id, source or '', timestamp)
        )
    else:
        c.execute(
            'SELECT id FROM events WHERE event_id=? AND source=? ORDER BY id DESC LIMIT 1',
            (event_id, source or '')
        )
    row = c.fetchone()
    conn.close()
    if row:
        return row[0]
    return add_event(
        event_id, log_name or 'System', source or '', message or '',
        timestamp, category, severity, description, recommended_action, level
    )


def get_remediation_script_for_event(event_id):
    """Return the remediation script path for a known event ID, if one exists."""
    script_map = {
        7031: 'remediation_scripts/Error7031_ServiceTerminatedUnexpectedly.ps1',
        7034: 'remediation_scripts/Error7034_ServiceTerminatedUnexpectedly.ps1',
        7036: 'remediation_scripts/Error7036_ServiceStateChanged.ps1',
        7040: 'remediation_scripts/Error7040_ServiceStartTypeChanged.ps1',
        7045: 'remediation_scripts/Error7045_NewServiceInstalled.ps1',
        7000: 'remediation_scripts/Error7000_ServiceStartupFailure.ps1',
        7001: 'remediation_scripts/Error7001_ServiceDependencyFailure.ps1',
        7009: 'remediation_scripts/Error7009_ServiceConnectionTimeout.ps1',
        7011: 'remediation_scripts/Error7011_ServiceTransactionTimeout.ps1',
        7022: 'remediation_scripts/Error7022_ServiceHungOnStarting.ps1',
        7023: 'remediation_scripts/Error7023_ServiceTerminatedWithError.ps1',
        7024: 'remediation_scripts/Error7024_ServiceSpecificError.ps1',
        7: 'remediation_scripts/Error7_BadBlocksDetected.ps1',
        11: 'remediation_scripts/Error11_DiskControllerError.ps1',
        51: 'remediation_scripts/Error51_DiskPagingIOError.ps1',
        55: 'remediation_scripts/Error55_NTFSCorruptionDetected.ps1',
        98: 'remediation_scripts/Error98_VolumeCorruptionDetected.ps1',
        129: 'remediation_scripts/Error129_StorageTimeoutReset.ps1',
        140: 'remediation_scripts/Error140_NTFSMetadataCorruption.ps1',
        153: 'remediation_scripts/Error153_DiskIORetryIssue.ps1',
        1014: 'remediation_scripts/Error1014_DNSNameResolutionTimeout.ps1',
        4199: 'remediation_scripts/Error4199_NetworkAdapterReset.ps1',
        4201: 'remediation_scripts/Error4201_NetworkInterfaceConnected.ps1',
        4202: 'remediation_scripts/Error4202_NetworkInterfaceDisconnected.ps1',
        5719: 'remediation_scripts/Error5719_DomainControllerUnreachable.ps1',
        1129: 'remediation_scripts/Error1129_SecureChannelFailure.ps1',
        36874: 'remediation_scripts/Error36874_TLSHandshakeFailure.ps1',
        5025: 'remediation_scripts/Error5025_FirewallServiceStopped.ps1',
        5031: 'remediation_scripts/Error5031_FirewallBlockedApplication.ps1',
        5152: 'remediation_scripts/Error5152_PacketDroppedByWFP.ps1',
        5155: 'remediation_scripts/Error5155_ConnectionBlockedByFirewall.ps1',
        5157: 'remediation_scripts/Error5157_ApplicationBlockedFromListening.ps1',
        8003: 'remediation_scripts/Error8003_AppLockerBlockedExecutable.ps1',
        8004: 'remediation_scripts/Error8004_AppLockerBlockedDLL.ps1',
        8006: 'remediation_scripts/Error8006_AppLockerScriptExecutionBlocked.ps1',
        8007: 'remediation_scripts/Error8007_AppLockerMSIBlocked.ps1',
        8028: 'remediation_scripts/Error8028_AppLockerEXEBlockedByPolicy.ps1',
        1314: 'remediation_scripts/Error1314_RequiredPrivilegeNotHeld.ps1',
        4625: 'remediation_scripts/Error4625_LogonFailure.ps1',
        4673: 'remediation_scripts/Error4673_PrivilegedServiceOperationFailed.ps1',
        4674: 'remediation_scripts/Error4674_PrivilegeObjectAccessDenied.ps1',
        4697: 'remediation_scripts/Error4697_ServiceInstallationFailure.ps1',
        10016: 'remediation_scripts/Error10016_DCOMPermissionDenied.ps1',
        2004: 'remediation_scripts/Error2004_ResourceExhaustionDetected.ps1',
        2019: 'remediation_scripts/Error2019_NonPagedPoolMemoryExhausted.ps1',
        2020: 'remediation_scripts/Error2020_PagedPoolMemoryExhausted.ps1',
        26: 'remediation_scripts/Error26_ApplicationFailedDueToMemoryLimits.ps1',
        41: 'remediation_scripts/Error41_SystemRebootDueToResourceExhaustion.ps1',
        1000: 'remediation_scripts/Error1000_ApplicationCrash.ps1',
        1001: 'remediation_scripts/Error1001_ApplicationHang.ps1',
        1026: 'remediation_scripts/Error1026_DotNetRuntimeCrash.ps1',
        2013: 'remediation_scripts/LowDiskSpace_Remediation.ps1',
        1100: 'remediation_scripts/Error1100_EventLogShutdown.ps1',
        1101: 'remediation_scripts/Error1101_AuditEventsDropped.ps1',
    }
    return script_map.get(event_id)


# ─────────────────────────────────────────────────────────────────────────────
#  Execution Engine
# ─────────────────────────────────────────────────────────────────────────────

def run_remediation(event_row_id, rule_id, timeout=60, regex_captures=None):
    rule = get_rule(rule_id)
    if not rule:
        return {'status': 'error', 'output': 'rule not found'}

    # Fetch full event to inject into script context
    event_data = get_event(event_row_id)
    if not event_data:
        return {'status': 'error', 'output': 'event not found'}

    # Format of event_data (from get_event): 
    # id(0), event_id(1), log_name(2), source(3), message(4), timestamp(5), category(6), severity(7), ...
    
    remediation_script = rule[5]
    script_type = rule[11] if len(rule) > 11 else 'file'

    if not remediation_script or not remediation_script.strip():
        record_remediation(event_row_id, rule_id, 'skipped', 'no script provided')
        return {'status': 'skipped', 'output': 'no script provided'}

    # ── Context Injection (Environment Variables) ────────────────────────
    # CRITICAL SECURITY FIX: Sanitize all env vars to prevent command injection
    env = os.environ.copy()
    env['RM_EVENT_ROW_ID'] = str(event_data[0])
    env['RM_EVENT_ID'] = sanitize_for_powershell_env(str(event_data[1] or ''), max_length=20)
    env['RM_LOG_NAME'] = sanitize_for_powershell_env(str(event_data[2] or ''), max_length=100)
    env['RM_SOURCE'] = sanitize_for_powershell_env(str(event_data[3] or ''), max_length=200)
    env['RM_MESSAGE'] = sanitize_for_powershell_env(str(event_data[4] or ''), max_length=500)
    env['RM_TIMESTAMP'] = sanitize_for_powershell_env(str(event_data[5] or ''), max_length=50)
    env['RM_CATEGORY'] = sanitize_for_powershell_env(str(event_data[6] or ''), max_length=100)
    env['RM_SEVERITY'] = sanitize_for_powershell_env(str(event_data[7] or ''), max_length=50)
    env['RM_SIMULATION_MODE'] = '1' if (str(event_data[2] or '').lower() == 'simulation') else '0'
    
    if regex_captures:
        for k, v in regex_captures.items():
            env[f'RM_MATCH_{k}'] = sanitize_for_powershell_env(str(v), max_length=500)

    tmp_path = None
    try:
        if script_type == 'inline':
            with tempfile.NamedTemporaryFile(mode='w', suffix='.ps1', delete=False, encoding='utf-8') as tmp:
                tmp.write(remediation_script)
                tmp_path = tmp.name
            script_to_run = tmp_path
        else:
            script_path = remediation_script
            if not os.path.isabs(script_path):
                # Try relative to the backend directory's parent (project root)
                project_root = os.path.join(os.path.dirname(__file__), '..')
                script_path = os.path.abspath(os.path.join(project_root, script_path))
                
            if not os.path.exists(script_path):
                # Fallback to current directory if not found in project root
                if os.path.exists(remediation_script):
                    script_path = os.path.abspath(remediation_script)
                else:
                    record_remediation(event_row_id, rule_id, 'skipped',
                                       f'script file not found: {remediation_script}')
                    return {'status': 'skipped', 'output': f'script file not found: {remediation_script}'}
            script_to_run = script_path

        proc = subprocess.run(
            [_POWERSHELL, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script_to_run],
            capture_output=True, text=True, timeout=timeout, env=env
        )
        status = 'success' if proc.returncode == 0 else 'failed'
        output = proc.stdout + '\n' + proc.stderr
        record_remediation(event_row_id, rule_id, status, output)
        return {'status': status, 'output': output}

    except subprocess.TimeoutExpired:
        msg = f'script timed out after {timeout}s'
        record_remediation(event_row_id, rule_id, 'error', msg)
        return {'status': 'error', 'output': msg}
    except Exception as e:
        record_remediation(event_row_id, rule_id, 'error', str(e))
        return {'status': 'error', 'output': str(e)}
    finally:
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.unlink(tmp_path)
            except Exception:
                pass


# ─────────────────────────────────────────────────────────────────────────────
#  JSON-based rule population
# ─────────────────────────────────────────────────────────────────────────────

def populate_rules_from_json(overwrite=False):
    definitions = load_event_definitions()
    if overwrite:
        conn = _conn()
        c = conn.cursor()
        c.execute('DELETE FROM rules')
        conn.commit()
        conn.close()

    created_count = 0
    for defn in definitions:
        if not defn.get('auto_remediate_candidate', False):
            continue

        event_id    = defn.get('event_id')
        source      = defn.get('event_source')
        category    = defn.get('category')
        severity    = defn.get('severity')
        description = defn.get('description')
        recommended = defn.get('recommended_action')
        rule_name   = f"{category} - {source} Event {event_id}" if category else f"{source} - Event {event_id}"
        remediation_script = get_remediation_script_for_event(event_id)

        existing = get_rules()
        existing_match = None
        for r in existing:
            if r[2] == event_id and (r[3] or '').lower() == (source or '').lower():
                existing_match = r
                break

        if existing_match:
            if remediation_script and not existing_match[5]:
                update_rule(existing_match[0], remediation_script=remediation_script)
            continue

        add_rule(
            name=rule_name, event_id=event_id, source=source,
            message_regex=None, remediation_script=remediation_script,
            auto_remediate=bool(remediation_script), stop_processing=False, category=category, severity=severity,
            description=description, recommended_action=recommended,
            priority=100, cooldown_minutes=0,
        )
        created_count += 1

    return created_count


# ─────────────────────────────────────────────────────────────────────────────
#  Simulation Preferences
# ─────────────────────────────────────────────────────────────────────────────

def get_simulation_preference(simulation_type):
    """Get simulation preference for a given type (crash, diskspace, eventlog, auditevents)."""
    conn = _conn()
    c = conn.cursor()
    c.execute(
        'SELECT run_script, auto_remediate FROM simulation_preferences WHERE simulation_type = ?',
        (simulation_type,)
    )
    row = c.fetchone()
    conn.close()
    
    if row:
        return {'run_script': bool(row[0]), 'auto_remediate': bool(row[1])}
    return None


def set_simulation_preference(simulation_type, run_script, auto_remediate):
    """Set/update simulation preference for a given type."""
    conn = _conn()
    c = conn.cursor()
    now = datetime.utcnow().isoformat() + 'Z'
    
    # Check if preference already exists
    c.execute('SELECT id FROM simulation_preferences WHERE simulation_type = ?', (simulation_type,))
    existing = c.fetchone()
    
    if existing:
        # Update existing
        c.execute(
            '''UPDATE simulation_preferences 
               SET run_script = ?, auto_remediate = ?, updated_at = ?
               WHERE simulation_type = ?''',
            (int(run_script), int(auto_remediate), now, simulation_type)
        )
    else:
        # Insert new
        c.execute(
            '''INSERT INTO simulation_preferences 
               (simulation_type, run_script, auto_remediate, created_at, updated_at)
               VALUES (?, ?, ?, ?, ?)''',
            (simulation_type, int(run_script), int(auto_remediate), now, now)
        )
    
    conn.commit()
    conn.close()


def get_dashboard_stats():
    """Get aggregated stats for dashboard charts (severity and category)."""
    conn = _conn()
    try:
        c = conn.cursor()
        c.execute('SELECT severity, COUNT(*) FROM events GROUP BY severity')
        severity_counts = {row[0] or 'Unknown': row[1] for row in c.fetchall()}
        
        c.execute('SELECT category, COUNT(*) FROM events GROUP BY category')
        category_counts = {row[0] or 'Unknown': row[1] for row in c.fetchall()}
        
        return {
            'by_severity': severity_counts,
            'by_category': category_counts
        }
    finally:
        conn.close()


if __name__ == '__main__':
    print('models.py — import and use as a module')
