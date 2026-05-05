import os
import sqlite3
from datetime import datetime

DB_PATH = os.path.join(os.path.dirname(__file__), 'rules.db')

def init_db():
    """Initialize database with proper schema versioning (PRIORITY 3 FIX)."""
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    # Create schema version table first (if not exists)
    c.execute('''
    CREATE TABLE IF NOT EXISTS schema_version (
        version INTEGER PRIMARY KEY,
        applied_at TEXT,
        description TEXT
    )
    ''')
    conn.commit()

    # Get current schema version
    c.execute('SELECT MAX(version) FROM schema_version')
    current_version = c.fetchone()[0] or 0

    # Apply migrations in sequence
    if current_version < 1:
        _apply_schema_v1(c)
        c.execute(
            'INSERT INTO schema_version (version, applied_at, description) VALUES (?, ?, ?)',
            (1, datetime.utcnow().isoformat(), 'Initial schema with events, rules, history, requests')
        )
        print(f'Applied schema migration v1')
    
    if current_version < 2:
        _apply_schema_v2_migrations(c)
        c.execute(
            'INSERT INTO schema_version (version, applied_at, description) VALUES (?, ?, ?)',
            (2, datetime.utcnow().isoformat(), 'Added event intelligence columns (dedup, correlation, confidence)')
        )
        print(f'Applied schema migration v2')
    
    if current_version < 3:
        _apply_schema_v3_migrations(c)
        c.execute(
            'INSERT INTO schema_version (version, applied_at, description) VALUES (?, ?, ?)',
            (3, datetime.utcnow().isoformat(), 'Added root cause variant tracking columns')
        )
        print(f'Applied schema migration v3')
    
    conn.commit()
    conn.close()


def _apply_schema_v1(c):
    """Create initial schema."""
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

    c.execute('''
    CREATE TABLE IF NOT EXISTS simulation_preferences (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        simulation_type TEXT UNIQUE,
        run_script INTEGER DEFAULT 0,
        auto_remediate INTEGER DEFAULT 0,
        created_at TEXT,
        updated_at TEXT
    )
    ''')

    c.execute('''
    CREATE TABLE IF NOT EXISTS event_root_cause_variants (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_row_id INTEGER,
        variant_id TEXT,
        variant_label TEXT,
        description TEXT,
        confidence_score INTEGER,
        confidence_level TEXT,
        matched_indicators TEXT,
        detected_at TEXT,
        FOREIGN KEY (event_row_id) REFERENCES events(id)
    )
    ''')

    c.execute('''
    CREATE TABLE IF NOT EXISTS rule_variant_associations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        rule_id INTEGER,
        variant_id TEXT,
        variant_label TEXT,
        min_confidence INTEGER DEFAULT 60,
        priority INTEGER DEFAULT 100,
        created_at TEXT,
        FOREIGN KEY (rule_id) REFERENCES rules(id)
    )
    ''')


def _apply_schema_v2_migrations(c):
    """Add event intelligence columns (PRIORITY 3 FIX)."""
    c.execute("PRAGMA table_info(events)")
    events_columns = {col[1] for col in c.fetchall()}

    v2_columns = [
        ('dedup_count', 'INTEGER DEFAULT 1'),
        ('last_seen', 'TEXT'),
        ('confidence_score', 'REAL DEFAULT 0.0'),
        ('correlation_id', 'TEXT'),
        ('source_type', "TEXT DEFAULT 'api'"),
        ('needs_manual_review', 'INTEGER DEFAULT 0'),
        ('manual_review_reason', 'TEXT'),
        ('dismissed_review', 'INTEGER DEFAULT 0'),
    ]

    for col_name, col_type in v2_columns:
        if col_name not in events_columns:
            try:
                c.execute(f'ALTER TABLE events ADD COLUMN {col_name} {col_type}')
                print(f'  Added column {col_name} to events table')
            except sqlite3.OperationalError:
                pass


def _apply_schema_v3_migrations(c):
    """Add root cause variant tracking columns."""
    c.execute("PRAGMA table_info(events)")
    events_columns = {col[1] for col in c.fetchall()}

    v3_columns = [
        ('root_cause_variant_id', 'TEXT'),
        ('root_cause_variant_label', 'TEXT'),
        ('root_cause_confidence', 'INTEGER'),
        ('detected_root_causes', 'TEXT'),
    ]

    for col_name, col_type in v3_columns:
        if col_name not in events_columns:
            try:
                c.execute(f'ALTER TABLE events ADD COLUMN {col_name} {col_type}')
                print(f'  Added column {col_name} to events table')
            except sqlite3.OperationalError:
                pass

    # Ensure rules table has required columns
    c.execute("PRAGMA table_info(rules)")
    rules_columns = {col[1] for col in c.fetchall()}

    rules_v3_columns = [
        ('priority', 'INTEGER DEFAULT 100'),
        ('cooldown_minutes', 'INTEGER DEFAULT 0'),
    ]

    for col_name, col_type in rules_v3_columns:
        if col_name not in rules_columns:
            try:
                c.execute(f'ALTER TABLE rules ADD COLUMN {col_name} {col_type}')
                print(f'  Added column {col_name} to rules table')
            except sqlite3.OperationalError:
                pass


if __name__ == '__main__':
    init_db()
    print('Initialized DB at', DB_PATH)
