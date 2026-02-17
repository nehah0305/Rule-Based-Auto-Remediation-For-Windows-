import os
import sqlite3
import re
import subprocess
import json
import csv
from datetime import datetime
from pathlib import Path

DB_PATH = os.path.join(os.path.dirname(__file__), 'rules.db')
EVENT_DEFINITIONS_PATH = os.path.join(os.path.dirname(__file__), '..', 'windows_error_events.json')

# Data directory for CSV exports and state
DATA_DIR = os.path.join(os.path.dirname(__file__), 'data')
ALL_EVENTS_CSV = os.path.join(DATA_DIR, 'all_events.csv')
FILTERED_EVENTS_CSV = os.path.join(DATA_DIR, 'filtered_events.csv')
LAST_PROCESSED_PATH = os.path.join(DATA_DIR, 'last_processed.json')

# Ensure data dir exists
Path(DATA_DIR).mkdir(parents=True, exist_ok=True)

# Cache for event definitions
_event_definitions_cache = None


def _conn():
    return sqlite3.connect(DB_PATH)


def load_event_definitions():
    """Load event definitions from JSON file and cache them."""
    global _event_definitions_cache

    if _event_definitions_cache is not None:
        return _event_definitions_cache

    if not os.path.exists(EVENT_DEFINITIONS_PATH):
        print(f"Warning: Event definitions file not found at {EVENT_DEFINITIONS_PATH}")
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
    """Get event definition from JSON by event_id and optionally source."""
    definitions = load_event_definitions()

    # Try to find exact match with source first
    if source:
        for defn in definitions:
            if defn.get('event_id') == event_id and defn.get('event_source', '').lower() == source.lower():
                return defn

    # Fall back to matching just event_id
    for defn in definitions:
        if defn.get('event_id') == event_id:
            return defn

    return None


def get_all_event_definitions():
    """Get all event definitions from JSON."""
    return load_event_definitions()


def add_event(event_id, log_name, source, message, timestamp=None, category=None, severity=None, description=None, recommended_action=None):
    conn = _conn()
    c = conn.cursor()
    if timestamp is None:
        timestamp = datetime.utcnow().isoformat()

    # Enrich with metadata from JSON if not provided
    if category is None or severity is None or description is None or recommended_action is None:
        defn = get_event_definition(event_id, source)
        if defn:
            if category is None:
                category = defn.get('category')
            if severity is None:
                severity = defn.get('severity')
            if description is None:
                description = defn.get('description')
            if recommended_action is None:
                recommended_action = defn.get('recommended_action')

    c.execute(
        'INSERT INTO events (event_id, log_name, source, message, timestamp, category, severity, description, recommended_action) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        (event_id, log_name, source, message, timestamp, category, severity, description, recommended_action)
    )
    rowid = c.lastrowid
    conn.commit()
    conn.close()

    # Append to all events CSV
    try:
        write_event_row_to_csv(ALL_EVENTS_CSV, {
            'id': rowid,
            'event_id': event_id,
            'log_name': log_name,
            'source': source,
            'message': message,
            'timestamp': timestamp,
            'category': category,
            'severity': severity,
            'description': description,
            'recommended_action': recommended_action
        })
    except Exception:
        pass

    # If severity indicates warning/error, append to filtered CSV
    try:
        if severity and severity.lower() in ('warning', 'warn', 'error', 'critical'):
            write_event_row_to_csv(FILTERED_EVENTS_CSV, {
                'id': rowid,
                'event_id': event_id,
                'log_name': log_name,
                'source': source,
                'message': message,
                'timestamp': timestamp,
                'category': category,
                'severity': severity,
                'description': description,
                'recommended_action': recommended_action
            })
    except Exception:
        pass

    # Update last processed marker
    try:
        with open(LAST_PROCESSED_PATH, 'w', encoding='utf-8') as f:
            json.dump({'last_rowid': rowid, 'last_timestamp': timestamp}, f)
    except Exception:
        pass
    return rowid


def write_event_row_to_csv(path, rowdict):
    fieldnames = ['id', 'event_id', 'log_name', 'source', 'message', 'timestamp', 'category', 'severity', 'description', 'recommended_action']
    exists = os.path.exists(path)
    with open(path, 'a', newline='', encoding='utf-8') as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        if not exists:
            writer.writeheader()
        writer.writerow({k: (rowdict.get(k) if rowdict.get(k) is not None else '') for k in fieldnames})


def read_filtered_events_csv(limit=500):
    """Read filtered events CSV and return list of dicts (most recent first)."""
    if not os.path.exists(FILTERED_EVENTS_CSV):
        return []
    rows = []
    with open(FILTERED_EVENTS_CSV, 'r', encoding='utf-8') as csvfile:
        reader = csv.DictReader(csvfile)
        for r in reader:
            rows.append(r)
    # Return most recent first (CSV is append-only chronological)
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
    c.execute('SELECT id, event_id, log_name, source, message, timestamp, category, severity, description, recommended_action FROM events ORDER BY id DESC LIMIT ?', (limit,))
    rows = c.fetchall()
    conn.close()
    return rows


def add_rule(name, event_id=None, source=None, message_regex=None, remediation_script=None, auto_remediate=0, category=None, severity=None, description=None, recommended_action=None):
    conn = _conn()
    c = conn.cursor()

    # Enrich with metadata from JSON if not provided
    if event_id and (category is None or severity is None or description is None or recommended_action is None):
        defn = get_event_definition(event_id, source)
        if defn:
            if category is None:
                category = defn.get('category')
            if severity is None:
                severity = defn.get('severity')
            if description is None:
                description = defn.get('description')
            if recommended_action is None:
                recommended_action = defn.get('recommended_action')

    c.execute(
        'INSERT INTO rules (name, event_id, source, message_regex, remediation_script, auto_remediate, category, severity, description, recommended_action) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        (name, event_id, source, message_regex, remediation_script, int(auto_remediate), category, severity, description, recommended_action)
    )
    conn.commit()
    rid = c.lastrowid
    conn.close()
    return rid


def get_rules():
    conn = _conn()
    c = conn.cursor()
    c.execute('SELECT id, name, event_id, source, message_regex, remediation_script, auto_remediate, category, severity, description, recommended_action FROM rules')
    rows = c.fetchall()
    conn.close()
    return rows


def match_rules_for_event(event):
    """Return list of rule rows that match the given event dict."""
    matched = []
    rules = get_rules()
    for r in rules:
        # Unpack all fields including new metadata fields
        (rid, name, r_event_id, r_source, r_message_regex, remediation_script,
         auto_remediate, category, severity, description, recommended_action) = r
        # event fields: event_id, log_name, source, message
        if r_event_id and r_event_id != event.get('event_id'):
            continue
        if r_source and r_source.lower() != (event.get('source') or '').lower():
            continue
        if r_message_regex:
            try:
                if not re.search(r_message_regex, event.get('message') or ''):
                    continue
            except re.error:
                continue
        matched.append(r)
    return matched


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


def get_rule(rule_id):
    conn = _conn()
    c = conn.cursor()
    c.execute('SELECT id, name, event_id, source, message_regex, remediation_script, auto_remediate, category, severity, description, recommended_action FROM rules WHERE id=?', (rule_id,))
    r = c.fetchone()
    conn.close()
    return r


def update_rule(rule_id, name=None, event_id=None, source=None, message_regex=None, remediation_script=None, auto_remediate=None, category=None, severity=None, description=None, recommended_action=None):
    conn = _conn()
    c = conn.cursor()
    fields = []
    vals = []
    if name is not None:
        fields.append('name=?'); vals.append(name)
    if event_id is not None:
        fields.append('event_id=?'); vals.append(event_id)
    if source is not None:
        fields.append('source=?'); vals.append(source)
    if message_regex is not None:
        fields.append('message_regex=?'); vals.append(message_regex)
    if remediation_script is not None:
        fields.append('remediation_script=?'); vals.append(remediation_script)
    if auto_remediate is not None:
        fields.append('auto_remediate=?'); vals.append(int(bool(auto_remediate)))
    if category is not None:
        fields.append('category=?'); vals.append(category)
    if severity is not None:
        fields.append('severity=?'); vals.append(severity)
    if description is not None:
        fields.append('description=?'); vals.append(description)
    if recommended_action is not None:
        fields.append('recommended_action=?'); vals.append(recommended_action)
    if not fields:
        conn.close()
        return False
    vals.append(rule_id)
    sql = 'UPDATE rules SET ' + ', '.join(fields) + ' WHERE id=?'
    c.execute(sql, vals)
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


def get_event(event_row_id):
    conn = _conn()
    c = conn.cursor()
    c.execute('SELECT id, event_id, log_name, source, message, timestamp, category, severity, description, recommended_action FROM events WHERE id=?', (event_row_id,))
    r = c.fetchone()
    conn.close()
    return r


def run_remediation(event_row_id, rule_id, timeout=60):
    rule = get_rule(rule_id)
    if not rule:
        return {'status': 'error', 'output': 'rule not found'}
    remediation_script = rule[5]
    if remediation_script and os.path.exists(remediation_script):
        try:
            proc = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', remediation_script], capture_output=True, text=True, timeout=timeout)
            status = 'success' if proc.returncode == 0 else 'failed'
            output = proc.stdout + '\n' + proc.stderr
            record_remediation(event_row_id, rule_id, status, output)
            return {'status': status, 'output': output}
        except Exception as e:
            record_remediation(event_row_id, rule_id, 'error', str(e))
            return {'status': 'error', 'output': str(e)}
    else:
        record_remediation(event_row_id, rule_id, 'skipped', 'no script or missing file')
        return {'status': 'skipped', 'output': 'no script or missing file'}


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
    if status:
        c.execute('''
            SELECT r.id, r.event_row_id, r.rule_id, r.status, r.requested_by, r.requested_at, r.processed_by, r.processed_at, r.decision_note,
                   e.event_id, e.source, rules.name
            FROM remediation_requests r
            LEFT JOIN events e ON r.event_row_id = e.id
            LEFT JOIN rules ON r.rule_id = rules.id
            WHERE r.status = ?
            ORDER BY r.id DESC
            LIMIT ?
        ''', (status, limit))
    else:
        c.execute('''
            SELECT r.id, r.event_row_id, r.rule_id, r.status, r.requested_by, r.requested_at, r.processed_by, r.processed_at, r.decision_note,
                   e.event_id, e.source, rules.name
            FROM remediation_requests r
            LEFT JOIN events e ON r.event_row_id = e.id
            LEFT JOIN rules ON r.rule_id = rules.id
            ORDER BY r.id DESC
            LIMIT ?
        ''', (limit,))
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
    c.execute('UPDATE remediation_requests SET status=?, processed_by=?, processed_at=?, decision_note=? WHERE id=?', (status, processed_by, processed_at, decision_note, request_id))
    conn.commit()
    conn.close()
    return True


def populate_rules_from_json(overwrite=False):
    """
    Populate rules from the JSON event definitions file.
    Only creates rules for events marked as auto_remediate_candidate.

    Args:
        overwrite: If True, delete existing rules before populating

    Returns:
        Number of rules created
    """
    definitions = load_event_definitions()

    if overwrite:
        conn = _conn()
        c = conn.cursor()
        c.execute('DELETE FROM rules')
        conn.commit()
        conn.close()
        print("Cleared existing rules")

    created_count = 0
    for defn in definitions:
        if not defn.get('auto_remediate_candidate', False):
            continue

        event_id = defn.get('event_id')
        source = defn.get('event_source')
        category = defn.get('category')
        severity = defn.get('severity')
        description = defn.get('description')
        recommended_action = defn.get('recommended_action')

        # Create a rule name
        rule_name = f"{source} - Event {event_id}"
        if category:
            rule_name = f"{category} - {source} Event {event_id}"

        # Check if rule already exists
        existing_rules = get_rules()
        rule_exists = False
        for r in existing_rules:
            if r[2] == event_id and (r[3] or '').lower() == (source or '').lower():
                rule_exists = True
                break

        if not rule_exists:
            # Create the rule with auto_remediate=False by default for safety
            # Users can enable it manually after reviewing
            add_rule(
                name=rule_name,
                event_id=event_id,
                source=source,
                message_regex=None,
                remediation_script=None,
                auto_remediate=False,
                category=category,
                severity=severity,
                description=description,
                recommended_action=recommended_action
            )
            created_count += 1
            print(f"Created rule: {rule_name}")

    return created_count


if __name__ == '__main__':
    print('No tests here, use app or import functions')
