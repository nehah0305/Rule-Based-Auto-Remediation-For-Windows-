import os
import sqlite3
import re
import subprocess
from datetime import datetime

DB_PATH = os.path.join(os.path.dirname(__file__), 'rules.db')


def _conn():
    return sqlite3.connect(DB_PATH)


def add_event(event_id, log_name, source, message, timestamp=None):
    conn = _conn()
    c = conn.cursor()
    if timestamp is None:
        timestamp = datetime.utcnow().isoformat()
    c.execute(
        'INSERT INTO events (event_id, log_name, source, message, timestamp) VALUES (?, ?, ?, ?, ?)',
        (event_id, log_name, source, message, timestamp)
    )
    rowid = c.lastrowid
    conn.commit()
    conn.close()
    return rowid


def get_events(limit=100):
    conn = _conn()
    c = conn.cursor()
    c.execute('SELECT id, event_id, log_name, source, message, timestamp FROM events ORDER BY id DESC LIMIT ?', (limit,))
    rows = c.fetchall()
    conn.close()
    return rows


def add_rule(name, event_id=None, source=None, message_regex=None, remediation_script=None, auto_remediate=0):
    conn = _conn()
    c = conn.cursor()
    c.execute(
        'INSERT INTO rules (name, event_id, source, message_regex, remediation_script, auto_remediate) VALUES (?, ?, ?, ?, ?, ?)',
        (name, event_id, source, message_regex, remediation_script, int(auto_remediate))
    )
    conn.commit()
    rid = c.lastrowid
    conn.close()
    return rid


def get_rules():
    conn = _conn()
    c = conn.cursor()
    c.execute('SELECT id, name, event_id, source, message_regex, remediation_script, auto_remediate FROM rules')
    rows = c.fetchall()
    conn.close()
    return rows


def match_rules_for_event(event):
    """Return list of rule rows that match the given event dict."""
    matched = []
    rules = get_rules()
    for r in rules:
        rid, name, r_event_id, r_source, r_message_regex, remediation_script, auto_remediate = r
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
    c.execute('SELECT id, name, event_id, source, message_regex, remediation_script, auto_remediate FROM rules WHERE id=?', (rule_id,))
    r = c.fetchone()
    conn.close()
    return r


def update_rule(rule_id, name=None, event_id=None, source=None, message_regex=None, remediation_script=None, auto_remediate=None):
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
               e.event_id, e.source, r.name
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
    c.execute('SELECT id, event_id, log_name, source, message, timestamp FROM events WHERE id=?', (event_row_id,))
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


if __name__ == '__main__':
    print('No tests here, use app or import functions')
