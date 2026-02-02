import os
import sqlite3

DB_PATH = os.path.join(os.path.dirname(__file__), 'rules.db')

def init_db():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    c.execute('''
    CREATE TABLE IF NOT EXISTS events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id INTEGER,
        log_name TEXT,
        source TEXT,
        message TEXT,
        timestamp TEXT
    )
    ''')

    c.execute('''
    CREATE TABLE IF NOT EXISTS rules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        event_id INTEGER,
        source TEXT,
        message_regex TEXT,
        remediation_script TEXT,
        auto_remediate INTEGER DEFAULT 0
    )
    ''')

    c.execute('''
    CREATE TABLE IF NOT EXISTS remediation_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_row_id INTEGER,
        rule_id INTEGER,
        status TEXT,
        output TEXT,
        timestamp TEXT
    )
    ''')

    c.execute('''
    CREATE TABLE IF NOT EXISTS remediation_requests (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_row_id INTEGER,
        rule_id INTEGER,
        status TEXT,
        requested_by TEXT,
        requested_at TEXT,
        processed_by TEXT,
        processed_at TEXT,
        decision_note TEXT
    )
    ''')

    conn.commit()
    conn.close()


if __name__ == '__main__':
    init_db()
    print('Initialized DB at', DB_PATH)
