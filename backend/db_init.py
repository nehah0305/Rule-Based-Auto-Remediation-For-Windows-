import os
import json
import sqlite3
from datetime import datetime

DB_PATH = os.path.join(os.path.dirname(__file__), 'rules.db')
_DATA_DIR = os.path.join(os.path.dirname(__file__), 'data')
_MANIFEST_PATH = os.path.join(os.path.dirname(__file__), 'rules_manifest.json')

# Ensure data directory exists
os.makedirs(_DATA_DIR, exist_ok=True)

def init_db():
    """Initialize database with proper schema versioning (PRIORITY 3 FIX)."""
    # Ensure data directory exists
    os.makedirs(_DATA_DIR, exist_ok=True)
    
    # PERFORMANCE FIX #1: Clean oversized CSV files on startup
    _cleanup_oversized_csv_files()
    
    # PERFORMANCE FIX #4: Add database indexes for query optimization
    conn = sqlite3.connect(DB_PATH, timeout=30)
    c = conn.cursor()

    # Concurrency hardening: WAL journal mode is persistent (stored in the DB
    # file itself), so setting it once here guarantees every later connection
    # — Flask request threads, the event-monitor thread, remediation workers —
    # opens the database in WAL mode and readers never block on writers.
    try:
        c.execute('PRAGMA journal_mode=WAL')
        c.execute('PRAGMA synchronous=NORMAL')
        c.execute('PRAGMA busy_timeout=30000')
    except sqlite3.Error as e:
        print(f'[WARN] Could not enable WAL mode: {e}')

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

    # NOTE: v4 was already consumed by the approval-workflow tables
    # (approved_event_types, approval_requests) added outside this file's
    # migration sequence. Rollback/verification support starts at v5.
    if current_version < 5:
        _apply_schema_v5_migrations(c)
        c.execute(
            'INSERT INTO schema_version (version, applied_at, description) VALUES (?, ?, ?)',
            (5, datetime.utcnow().isoformat(), 'Added rollback/verification columns and history status tracking')
        )
        print(f'Applied schema migration v5')

    if current_version < 6:
        _apply_schema_v6_migrations(c)
        c.execute(
            'INSERT INTO schema_version (version, applied_at, description) VALUES (?, ?, ?)',
            (6, datetime.utcnow().isoformat(), 'Added app_context to approval tables for per-app-name gating')
        )
        print(f'Applied schema migration v6')

    if current_version < 8:
        _apply_schema_v8_migrations(c)
        c.execute(
            'INSERT INTO schema_version (version, applied_at, description) VALUES (?, ?, ?)',
            (8, datetime.utcnow().isoformat(),
             'Added events.raw_context_json (pristine OS context for Phase 2 SLM training) '
             'and remediation_history.error_output (async execution stderr capture)')
        )
        print(f'Applied schema migration v8')

    conn.commit()
    _ensure_approval_tables(c)
    conn.commit()
    _add_performance_indexes(c)
    conn.commit()
    _load_rules_manifest(c)
    conn.commit()

    # Remove legacy wildcard approvals that bypass per-app gateway
    try:
        c = conn.cursor()
        c.execute("DELETE FROM approved_event_types WHERE event_id='1000' AND app_context=''")
        c.execute("DELETE FROM approved_event_types WHERE event_id='1001' AND app_context=''")
        conn.commit()
    except Exception:
        pass

    try:
        # Prevent identical pending requests at the schema level
        c.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_pending_approval ON approval_requests(event_id, source, app_context, status) WHERE status='pending'")
        conn.commit()
    except Exception as e:
        print(f'[WARN] Could not create unique index: {e}')

    # v7: the legacy approved_event_types table carried UNIQUE(event_id, source),
    # which silently discarded every whitelist entry after the first app for a
    # given event type (mark_event_type_approved uses INSERT OR IGNORE). Rebuild
    # with per-app uniqueness so "approve once, auto-remediate forever" holds
    # for each distinct application.
    try:
        rebuild = False
        c.execute("PRAGMA index_list('approved_event_types')")
        for idx in c.fetchall():
            if idx[2]:  # unique index
                c.execute(f"PRAGMA index_info('{idx[1]}')")
                cols = [r[2] for r in c.fetchall()]
                if cols == ['event_id', 'source']:
                    rebuild = True
                    break
        if rebuild:
            c.execute('''CREATE TABLE approved_event_types_v7 (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                event_id TEXT NOT NULL,
                source TEXT NOT NULL,
                app_context TEXT DEFAULT '',
                approved_by TEXT DEFAULT 'operator',
                approved_at TEXT NOT NULL,
                UNIQUE(event_id, source, app_context)
            )''')
            c.execute('''INSERT OR IGNORE INTO approved_event_types_v7
                         (id, event_id, source, app_context, approved_by, approved_at)
                         SELECT id, event_id, source, COALESCE(app_context, ''), approved_by, approved_at
                         FROM approved_event_types''')
            c.execute('DROP TABLE approved_event_types')
            c.execute('ALTER TABLE approved_event_types_v7 RENAME TO approved_event_types')
            print('[MIGRATE] approved_event_types rebuilt: per-app approvals now persist')
        # Honor every past operator approval: backfill whitelist rows that the
        # legacy constraint discarded. Idempotent (INSERT OR IGNORE), runs on
        # every startup, never re-creates wildcard ('') entries.
        c.execute('''INSERT OR IGNORE INTO approved_event_types
                     (event_id, source, app_context, approved_by, approved_at)
                     SELECT event_id, source, COALESCE(app_context, ''),
                            COALESCE(resolved_by, 'operator'), COALESCE(resolved_at, created_at)
                     FROM approval_requests
                     WHERE status='approved' AND COALESCE(app_context, '') != ''
                     GROUP BY event_id, source, app_context''')
        conn.commit()
    except Exception as e:
        print(f'[WARN] approved_event_types v7 migration: {e}')

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


def _apply_schema_v5_migrations(c):
    """
    Rollback / verification closed-loop (Task 2):
      - rules gains rollback_script + verification_timeout_sec so each rule
        can declare its own "undo" script and how long to watch for recurrence
        before declaring success.
      - remediation_history gains columns to track the verification window
        and any rollback that was executed, without disturbing the existing
        `status` column's values (it now also accepts 'pending', 'executing',
        'verifying', 'rolled_back' alongside the pre-existing ones).
    """
    c.execute("PRAGMA table_info(rules)")
    rules_columns = {col[1] for col in c.fetchall()}
    rules_v5_columns = [
        ('rollback_script', 'TEXT'),
        ('verification_timeout_sec', 'INTEGER DEFAULT 60'),
        # Was previously added lazily/ad-hoc by models.py on first use; ensured
        # here too so _load_rules_manifest() can rely on it existing at init time.
        ('active', 'INTEGER DEFAULT 1'),
    ]
    for col_name, col_type in rules_v5_columns:
        if col_name not in rules_columns:
            try:
                c.execute(f'ALTER TABLE rules ADD COLUMN {col_name} {col_type}')
                print(f'  Added column {col_name} to rules table')
            except sqlite3.OperationalError:
                pass

    c.execute("PRAGMA table_info(remediation_history)")
    history_columns = {col[1] for col in c.fetchall()}
    history_v5_columns = [
        ('verification_started_at', 'TEXT'),
        ('verified_at', 'TEXT'),
        ('rollback_output', 'TEXT'),
    ]
    for col_name, col_type in history_v5_columns:
        if col_name not in history_columns:
            try:
                c.execute(f'ALTER TABLE remediation_history ADD COLUMN {col_name} {col_type}')
                print(f'  Added column {col_name} to remediation_history table')
            except sqlite3.OperationalError:
                pass


def _apply_schema_v6_migrations(c):
    """
    Per-App Approval Gateway: add app_context column to approval tables.
    This changes the approval key from (event_id, source) to
    (event_id, source, app_context) so each unique app name requires
    its own one-time operator approval.
    """
    for table in ('approval_requests', 'approved_event_types'):
        try:
            c.execute(f"PRAGMA table_info({table})")
            cols = {row[1] for row in c.fetchall()}
            if 'app_context' not in cols:
                c.execute(f"ALTER TABLE {table} ADD COLUMN app_context TEXT DEFAULT ''")
                print(f'  Added app_context column to {table}')
        except Exception as e:
            print(f'  [WARN] v6 migration for {table}: {e}')


def _apply_schema_v8_migrations(c):
    """
    Phase 2 readiness (v7 is informally taken by the approved_event_types
    rebuild that runs unconditionally below, so this is v8):
      - events.raw_context_json stores the untouched, structured event context
        (full Properties array + raw XML) exactly as Windows emitted it, so the
        future SLM trains on pristine data instead of regex-flattened strings.
      - remediation_history.error_output stores stderr separately from stdout
        now that remediation runs asynchronously in a worker thread.
    Both are graceful ALTER TABLEs: safe on existing databases.
    """
    c.execute("PRAGMA table_info(events)")
    events_columns = {col[1] for col in c.fetchall()}
    if 'raw_context_json' not in events_columns:
        try:
            c.execute('ALTER TABLE events ADD COLUMN raw_context_json TEXT')
            print('  Added column raw_context_json to events table')
        except sqlite3.OperationalError:
            pass

    c.execute("PRAGMA table_info(remediation_history)")
    history_columns = {col[1] for col in c.fetchall()}
    if 'error_output' not in history_columns:
        try:
            c.execute('ALTER TABLE remediation_history ADD COLUMN error_output TEXT')
            print('  Added column error_output to remediation_history table')
        except sqlite3.OperationalError:
            pass


def _ensure_approval_tables(c):
    """
    approval_requests / approved_event_types back the new-event-type
    sign-off workflow. Idempotent (CREATE TABLE IF NOT EXISTS) and run
    unconditionally on every startup so it self-heals any existing
    deployment as well as brand new ones.
    """
    c.execute('''
    CREATE TABLE IF NOT EXISTS approval_requests (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_row_id INTEGER NOT NULL,
        event_id TEXT NOT NULL,
        source TEXT NOT NULL,
        app_context TEXT DEFAULT '',
        rule_id INTEGER,
        rule_name TEXT,
        status TEXT DEFAULT 'pending',
        created_at TEXT NOT NULL,
        resolved_at TEXT,
        resolved_by TEXT
    )
    ''')
    c.execute('''
    CREATE TABLE IF NOT EXISTS approved_event_types (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id TEXT NOT NULL,
        source TEXT NOT NULL,
        app_context TEXT DEFAULT '',
        approved_by TEXT DEFAULT 'operator',
        approved_at TEXT NOT NULL,
        UNIQUE(event_id, source, app_context)
    )
    ''')
    # Add app_context to any pre-existing tables that lack it (idempotent)
    for table in ('approval_requests', 'approved_event_types'):
        try:
            c.execute(f"PRAGMA table_info({table})")
            cols = {row[1] for row in c.fetchall()}
            if 'app_context' not in cols:
                c.execute(f"ALTER TABLE {table} ADD COLUMN app_context TEXT DEFAULT ''")
        except Exception:
            pass


def _load_rules_manifest(c):
    """
    Task 1 — declarative rule onboarding. Reads rules_manifest.json (produced
    by generate_rules_manifest.py) and inserts a rule for every
    (event_id, source) combination not already present in the rules table.

    This is intentionally an upsert-by-insert-only: it NEVER modifies or
    overwrites a rule that already exists, so the 16 rules already tuned and
    verified in production (auto_remediate flags, priorities, cooldowns)
    are left completely untouched. It only fills in the coverage gap.
    Runs on every startup so newly-added manifest entries are picked up
    without requiring a schema version bump.
    """
    if not os.path.exists(_MANIFEST_PATH):
        return

    try:
        with open(_MANIFEST_PATH, encoding='utf-8') as f:
            manifest = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        print(f'[WARN] Could not read rules_manifest.json: {e}')
        return

    c.execute('SELECT event_id, source FROM rules')
    existing = {(row[0], (row[1] or '').lower()) for row in c.fetchall()}

    inserted = 0
    for entry in manifest:
        event_id = entry.get('event_id')
        source = entry.get('source')
        key = (event_id, (source or '').lower())
        if key in existing:
            continue

        c.execute(
            '''INSERT INTO rules
               (name, event_id, source, message_regex, remediation_script,
                script_type, auto_remediate, stop_processing, category, severity,
                description, recommended_action, priority, cooldown_minutes, active)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
            (
                entry.get('rule_name'), event_id, source, entry.get('message_regex'),
                entry.get('script'), 'file', int(bool(entry.get('auto_remediate', False))), 0,
                entry.get('category'), entry.get('severity'), entry.get('description'),
                entry.get('recommended_action'), entry.get('priority', 100),
                entry.get('cooldown_minutes', 0), 1,
            )
        )
        existing.add(key)
        inserted += 1

    if inserted:
        print(f'[MANIFEST] Onboarded {inserted} new rule(s) from rules_manifest.json '
              f'({len(manifest) - inserted} already present, left untouched)')


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
