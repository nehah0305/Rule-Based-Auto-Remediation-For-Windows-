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
        timestamp TEXT,
        category TEXT,
        severity TEXT,
        description TEXT,
        recommended_action TEXT,
        level TEXT,
        remediated_at TEXT
    )
    ''')

    # Add remediated_at column if it doesn't exist (migration)
    try:
        c.execute('ALTER TABLE events ADD COLUMN remediated_at TEXT')
        conn.commit()
    except sqlite3.OperationalError:
        # Column already exists
        pass

    c.execute('''
    CREATE TABLE IF NOT EXISTS rules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        event_id INTEGER,
        source TEXT,
        message_regex TEXT,
        remediation_script TEXT,
        script_type TEXT DEFAULT 'file',
        auto_remediate INTEGER DEFAULT 0,
        stop_processing INTEGER DEFAULT 0,
        category TEXT,
        severity TEXT,
        description TEXT,
        recommended_action TEXT
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

    # Migrate existing tables to add new columns if they don't exist
    migrate_db(conn)

    conn.close()


def migrate_db(conn):
    """Add new columns to existing tables if they don't exist."""
    c = conn.cursor()

    # Get existing columns in events table
    c.execute("PRAGMA table_info(events)")
    events_columns = [col[1] for col in c.fetchall()]

    # Add missing columns to events table
    new_event_columns = [
        ('category',         'TEXT'),
        ('severity',         'TEXT'),
        ('description',      'TEXT'),
        ('recommended_action','TEXT'),
        ('level',            'TEXT'),
        # --- Alert Intelligence columns ---
        ('dedup_count',      'INTEGER DEFAULT 1'),   # collapsed duplicate count
        ('last_seen',        'TEXT'),                # last occurrence timestamp
        ('confidence_score', 'REAL DEFAULT 0.0'),    # 0-100 urgency score
        ('correlation_id',   'TEXT'),                # groups related events
    ]

    for col_name, col_type in new_event_columns:
        if col_name not in events_columns:
            try:
                c.execute(f'ALTER TABLE events ADD COLUMN {col_name} {col_type}')
                print(f'Added column {col_name} to events table')
            except Exception:
                pass

    # Get existing columns in rules table
    c.execute("PRAGMA table_info(rules)")
    rules_columns = [col[1] for col in c.fetchall()]

    # Add missing columns to rules table
    new_rule_columns = [
        ('category',          'TEXT'),
        ('severity',          'TEXT'),
        ('description',       'TEXT'),
        ('recommended_action','TEXT'),
        ("script_type",       "TEXT DEFAULT 'file'"),
        # --- Rule Matching Engine columns ---
        ('priority',          'INTEGER DEFAULT 100'), # lower = higher priority
        ('cooldown_minutes',  'INTEGER DEFAULT 0'),   # suppress re-run within N min
        ('stop_processing',   'INTEGER DEFAULT 0'),   # skip lower priority matching rules
    ]

    for col_name, col_type in new_rule_columns:
        if col_name not in rules_columns:
            try:
                c.execute(f'ALTER TABLE rules ADD COLUMN {col_name} {col_type}')
                print(f'Added column {col_name} to rules table')
            except Exception:
                pass

    conn.commit()


if __name__ == '__main__':
    init_db()
    print('Initialized DB at', DB_PATH)
