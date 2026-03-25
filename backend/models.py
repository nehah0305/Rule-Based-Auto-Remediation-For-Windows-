import os
import sqlite3
import re
import shutil
import subprocess
import json
import csv
import hashlib
import tempfile
from datetime import datetime, timedelta
from pathlib import Path

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

# Ensure data dir exists
Path(DATA_DIR).mkdir(parents=True, exist_ok=True)

# Cache for event definitions
_event_definitions_cache = None


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
            if defn.get('event_id') == event_id and defn.get('event_source', '').lower() == source.lower():
                return defn
    for defn in definitions:
        if defn.get('event_id') == event_id:
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

    conn.close()
    return {
        'total_events': total_events,
        'deduplicated_events': deduplicated_events,
        'total_suppressed': total_suppressed,
        'avg_confidence': avg_confidence,
        'rules_with_cooldown': rules_with_cooldown,
    }


# ─────────────────────────────────────────────────────────────────────────────
#  Events
# ─────────────────────────────────────────────────────────────────────────────

def add_event(event_id, log_name, source, message,
              timestamp=None, category=None, severity=None,
              description=None, recommended_action=None, level=None,
              remediated_at=None):
    """
    Smart event ingestion with deduplication, confidence scoring, and correlation.

    If an event with the same event_id + source was seen within DEDUP_WINDOW_SECONDS,
    this call increments its dedup_count and updates last_seen instead of inserting
    a new row.  Returns the DB row id (new or existing).
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
    c = conn.cursor()
    cutoff = (datetime.utcnow() - timedelta(seconds=DEDUP_WINDOW_SECONDS)).isoformat()

    c.execute('''
        SELECT id, dedup_count
        FROM events
        WHERE event_id = ?
          AND LOWER(COALESCE(source,'')) = LOWER(COALESCE(?,''))
          AND timestamp >= ?
        ORDER BY id DESC
        LIMIT 1
    ''', (event_id, source or '', cutoff))
    existing = c.fetchone()

    if existing:
        # Merge into existing row — update count and last_seen
        existing_id, prev_count = existing
        new_count = prev_count + 1
        # Recompute confidence including new frequency
        event_dict = {'severity': severity, 'level': level}
        new_score = calculate_confidence_score(event_dict, dedup_count=new_count)
        c.execute('''
            UPDATE events
            SET dedup_count = ?, last_seen = ?, confidence_score = ?
            WHERE id = ?
        ''', (new_count, timestamp, new_score, existing_id))
        conn.commit()
        conn.close()
        return existing_id

    # ── New event — compute correlation_id and confidence score ──────────────
    correlation_id = get_correlation_id(source, timestamp)
    event_dict = {'severity': severity, 'level': level}
    confidence_score = calculate_confidence_score(event_dict, dedup_count=1)

    c.execute(
        '''INSERT INTO events
           (event_id, log_name, source, message, timestamp, category, severity,
            description, recommended_action, level, remediated_at,
            dedup_count, last_seen, confidence_score, correlation_id)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        (event_id, log_name, source, message, timestamp, category, severity,
         description, recommended_action, level, remediated_at,
         1, timestamp, confidence_score, correlation_id)
    )
    rowid = c.lastrowid
    conn.commit()
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

    return rowid


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


def read_filtered_events_csv(limit=500):
    """Read errors/warnings CSV — most recent first."""
    if not os.path.exists(ERRORS_WARNINGS_CSV):
        return []
    rows = []
    with open(ERRORS_WARNINGS_CSV, 'r', encoding='utf-8') as csvfile:
        reader = csv.DictReader(csvfile)
        for r in reader:
            rows.append(r)
    rows = rows[-limit:]
    rows.reverse()
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
    c = conn.cursor()
    c.execute('''
        SELECT id, event_id, log_name, source, message, timestamp,
               category, severity, description, recommended_action,
               dedup_count, last_seen, confidence_score, correlation_id
        FROM events
        ORDER BY id DESC
        LIMIT ?
    ''', (limit,))
    rows = c.fetchall()
    conn.close()
    return rows


def get_event(event_row_id):
    conn = _conn()
    c = conn.cursor()
    c.execute('''
        SELECT id, event_id, log_name, source, message, timestamp,
               category, severity, description, recommended_action,
               dedup_count, last_seen, confidence_score, correlation_id
        FROM events WHERE id=?
    ''', (event_row_id,))
    r = c.fetchone()
    conn.close()
    return r


# ─────────────────────────────────────────────────────────────────────────────
#  Rules — now with priority and cooldown
# ─────────────────────────────────────────────────────────────────────────────

def add_rule(name, event_id=None, source=None, message_regex=None,
             remediation_script=None, script_type='file',
             auto_remediate=0, stop_processing=0, category=None, severity=None,
             description=None, recommended_action=None,
             priority=100, cooldown_minutes=0):
    conn = _conn()
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
    conn.close()
    return rid


def get_rules():
    conn = _conn()
    c = conn.cursor()
    c.execute('''
        SELECT id, name, event_id, source, message_regex, remediation_script,
               auto_remediate, category, severity, description, recommended_action,
               script_type, priority, cooldown_minutes, stop_processing
        FROM rules
        ORDER BY priority ASC, id ASC
    ''')
    rows = c.fetchall()
    conn.close()
    return rows


def get_rule(rule_id):
    conn = _conn()
    c = conn.cursor()
    c.execute('''
        SELECT id, name, event_id, source, message_regex, remediation_script,
               auto_remediate, category, severity, description, recommended_action,
               script_type, priority, cooldown_minutes, stop_processing
        FROM rules WHERE id=?
    ''', (rule_id,))
    r = c.fetchone()
    conn.close()
    return r


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
    c = conn.cursor()
    c.execute('DELETE FROM rules WHERE id=?', (rule_id,))
    conn.commit()
    conn.close()
    return True


def match_rules_for_event(event):
    """
    Return rules that match the given event dict, with intelligence additions:
      1. Strict category/severity matching if configured.
      2. Regex capture groups are extracted and appended to the rule tuple limit.
      3. Rules in cooldown are skipped (with reason recorded).
      4. Support for stop_processing short-circuiting.
    """
    matched = []
    rules = get_rules()   # already sorted by priority ASC

    event_id_val = event.get('event_id')
    source_val   = event.get('source') or ''
    category_val = (event.get('category') or '').lower()
    severity_val = (event.get('severity') or '').lower()

    stop_triggered = False

    for r in rules:
        if stop_triggered:
            break

        # r index mapping:
        # 0=id,1=name,2=event_id,3=source,4=message_regex,
        # 5=remediation_script,6=auto_remediate,7=category,
        # 8=severity,9=description,10=recommended_action,
        # 11=script_type,12=priority,13=cooldown_minutes,14=stop_processing
        (rid, name, r_event_id, r_source, r_message_regex, remediation_script,
         auto_remediate, r_category, r_severity, description, recommended_action,
         script_type, priority, cooldown_minutes, stop_processing) = r

        # ── Matching logic (AND semantics) ────────────────────────────────
        if r_event_id and r_event_id != event_id_val:
            continue
        if r_source and r_source.lower() != source_val.lower():
            continue
        if r_category and r_category.lower() != category_val:
            continue
        if r_severity and r_severity.lower() != severity_val:
            continue

        regex_captures = {}
        if r_message_regex:
            try:
                m = re.search(r_message_regex, event.get('message') or '')
                if not m:
                    continue
                # Extract named capture groups for the script environment context
                regex_captures = m.groupdict()
            except re.error:
                continue

        # ── Cooldown check for auto-remediation ──────────────────────────
        if auto_remediate and is_rule_in_cooldown(rid, event_id_val, source_val, cooldown_minutes):
            matched.append((*r, True, regex_captures))   # True = cooldown_active flag
            continue

        matched.append((*r, False, regex_captures))      # False = not suppressed

        # Support short-circuiting:
        # If this rule matches AND has stop_processing=1, do not evaluate lower priority rules
        if stop_processing:
            stop_triggered = True

    return matched


# ─────────────────────────────────────────────────────────────────────────────
#  Remediation requests & history
# ─────────────────────────────────────────────────────────────────────────────

def record_remediation(event_row_id, rule_id, status, output=''):
    conn = _conn()
    c = conn.cursor()
    ts = datetime.utcnow().isoformat()
    c.execute(
        'INSERT INTO remediation_history (event_row_id, rule_id, status, output, timestamp) VALUES (?, ?, ?, ?, ?)',
        (event_row_id, rule_id, status, output, ts)
    )
    conn.commit()
    conn.close()


def get_history(limit=200):
    conn = _conn()
    c = conn.cursor()
    c.execute('''
        SELECT h.id, h.event_row_id, h.rule_id, h.status, h.output, h.timestamp,
               e.event_id, e.source, r.name, e.timestamp as event_timestamp
        FROM remediation_history h
        LEFT JOIN events e ON h.event_row_id = e.id
        LEFT JOIN rules r ON h.rule_id = r.id
        ORDER BY h.id DESC
        LIMIT ?
    ''', (limit,))
    rows = c.fetchall()
    conn.close()
    return rows


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
    env = os.environ.copy()
    env['RM_EVENT_ROW_ID'] = str(event_data[0])
    env['RM_EVENT_ID'] = str(event_data[1] or '')
    env['RM_LOG_NAME'] = str(event_data[2] or '')
    env['RM_SOURCE'] = str(event_data[3] or '')
    env['RM_MESSAGE'] = str(event_data[4] or '')
    env['RM_TIMESTAMP'] = str(event_data[5] or '')
    env['RM_CATEGORY'] = str(event_data[6] or '')
    env['RM_SEVERITY'] = str(event_data[7] or '')
    env['RM_SIMULATION_MODE'] = '1' if (str(event_data[2] or '').lower() == 'simulation') else '0'
    
    if regex_captures:
        for k, v in regex_captures.items():
            env[f'RM_MATCH_{k}'] = str(v)

    tmp_path = None
    try:
        if script_type == 'inline':
            with tempfile.NamedTemporaryFile(mode='w', suffix='.ps1', delete=False, encoding='utf-8') as tmp:
                tmp.write(remediation_script)
                tmp_path = tmp.name
            script_to_run = tmp_path
        else:
            if not os.path.exists(remediation_script):
                record_remediation(event_row_id, rule_id, 'skipped',
                                   f'script file not found: {remediation_script}')
                return {'status': 'skipped', 'output': f'script file not found: {remediation_script}'}
            script_to_run = remediation_script

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

        existing = get_rules()
        if any(r[2] == event_id and (r[3] or '').lower() == (source or '').lower() for r in existing):
            continue

        add_rule(
            name=rule_name, event_id=event_id, source=source,
            message_regex=None, remediation_script=None,
            auto_remediate=False, stop_processing=False, category=category, severity=severity,
            description=description, recommended_action=recommended,
            priority=100, cooldown_minutes=0,
        )
        created_count += 1

    return created_count


if __name__ == '__main__':
    print('models.py — import and use as a module')
