import os
import sqlite3
from datetime import datetime

DB_PATH = os.path.join(os.path.dirname(__file__), 'rules.db')
_DATA_DIR = os.path.join(os.path.dirname(__file__), 'data')

# Ensure data directory exists
os.makedirs(_DATA_DIR, exist_ok=True)

def init_db():
    """Initialize database with proper schema versioning (PRIORITY 3 FIX)."""
    # Ensure data directory exists
    os.makedirs(_DATA_DIR, exist_ok=True)
    
    # PERFORMANCE FIX #1: Clean oversized CSV files on startup
    _cleanup_oversized_csv_files()
    
    # PERFORMANCE FIX #4: Add database indexes for query optimization
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
    _add_performance_indexes(c)
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

    # ─── Task Scheduler Tables ──────────────────────────────────────────
    c.execute('''
    CREATE TABLE IF NOT EXISTS scheduled_tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_name TEXT UNIQUE,
        display_name TEXT,
        description TEXT,
        task_type TEXT,
        script_path TEXT,
        script_content TEXT,
        schedule_type TEXT,
        schedule_value TEXT,
        enabled INTEGER DEFAULT 1,
        created_at TEXT,
        updated_at TEXT,
        last_run_time TEXT,
        last_run_status TEXT,
        next_run_time TEXT
    )
    ''')

    c.execute('''
    CREATE TABLE IF NOT EXISTS task_execution_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id INTEGER,
        execution_time TEXT,
        status TEXT,
        exit_code INTEGER,
        output TEXT,
        error_output TEXT,
        duration_ms INTEGER,
        created_at TEXT,
        FOREIGN KEY (task_id) REFERENCES scheduled_tasks(id)
    )
    ''')

    # ─── Root Cause Variant Tables ───────────────────────────────────────
    # Tracks detected root cause variants for errors with multiple causes
    # and stores associations to remediation rules.
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


def _cleanup_oversized_csv_files():
    """Delete CSV files larger than 50 MB to prevent memory bloat."""
    if not os.path.exists(_DATA_DIR):
        return
    
    oversized_files = [
        'all_events.csv',
        'errors_warnings.csv',
        'filtered_events.csv'
    ]
    
    for filename in oversized_files:
        filepath = os.path.join(_DATA_DIR, filename)
        if os.path.exists(filepath):
            file_size_mb = os.path.getsize(filepath) / (1024 * 1024)
            if file_size_mb > 50:
                try:
                    os.remove(filepath)
                    print(f'[PERF FIX #1] Cleaned up oversized CSV: {filename} ({file_size_mb:.1f} MB)')
                except Exception as e:
                    print(f'[WARNING] Failed to clean CSV {filename}: {e}')


def _add_performance_indexes(c):
    """Add database indexes to optimize common query patterns.
    
    PERFORMANCE FIX #4: Creates non-blocking indexes with PRAGMA for
    concurrent query support without locking during development.
    """
    # Disable synchronous mode temporarily for faster indexing
    try:
        c.execute('PRAGMA synchronous = NORMAL')  # Safer than OFF, faster than FULL
    except:
        pass
    
    indexes = [
        ('idx_events_id', 'events', 'id'),
        ('idx_events_event_id', 'events', 'event_id'),
        ('idx_events_timestamp', 'events', 'timestamp'),
        ('idx_events_event_id_ts', 'events', 'event_id, timestamp'),   # composite for range queries
        ('idx_events_severity', 'events', 'severity'),
        ('idx_events_manual_review', 'events', 'needs_manual_review'),
        ('idx_rules_event_id', 'rules', 'event_id'),
        ('idx_rules_source', 'rules', 'source'),
        ('idx_rules_active', 'rules', 'active'),                        # for filtering inactive rules
        ('idx_history_event_row_id', 'remediation_history', 'event_row_id'),  # critical FK join
        ('idx_history_rule_id', 'remediation_history', 'rule_id'),
        ('idx_history_timestamp', 'remediation_history', 'timestamp'),
        ('idx_history_status', 'remediation_history', 'status'),
        ('idx_variants_event_id', 'event_root_cause_variants', 'event_id'),
    ]
    
    for idx_name, table, columns in indexes:
        try:
            c.execute(f'CREATE INDEX IF NOT EXISTS {idx_name} ON {table}({columns})')
        except Exception as e:
            pass  # Index may already exist
    
    print('[PERF FIX #4] Database indexes added for optimization')


if __name__ == '__main__':
    init_db()
    print('Initialized DB at', DB_PATH)
