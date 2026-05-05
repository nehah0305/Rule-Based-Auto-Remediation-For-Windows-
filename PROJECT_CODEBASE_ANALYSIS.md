# Windows Auto-Remediation System - Complete Codebase Analysis

**Last Updated:** May 5, 2026  
**Project Purpose:** A lightweight, intelligent system for monitoring Windows Event Logs and automatically remediating common system issues using rule-based automation.

---

## Table of Contents

1. [Project Purpose & Architecture](#project-purpose--architecture)
2. [Core Components](#core-components)
3. [Data Flow](#data-flow)
4. [Critical Functions](#critical-functions)
5. [Configuration & State Management](#configuration--state-management)
6. [Advanced Features](#advanced-features)

---

## Project Purpose & Architecture

### **System Goal**
Monitor Windows Event Logs (Errors/Warnings only, matching "Administrative Events" view) and automatically remediate issues through configurable rule-based automation. The system reduces manual intervention by up to 70% through intelligent multi-event correlation and targeted remediation strategies.

### **High-Level Architecture**

```
┌─────────────────────────────────────────────────────────────────┐
│                    WINDOWS EVENT LOG MONITORING                 │
│              (System & Application Administrative Events)        │
└────────────────────┬────────────────────────────────────────────┘
                     │ (Level 2=Error, Level 3=Warning)
                     ▼
    ┌────────────────────────────────────────┐
    │   Event Collection (PowerShell)        │
    │  ┌──────────────────────────────────┐  │
    │  │ • event_monitor.ps1 (polling)   │  │
    │  │ • Real-time listener (via Task   │  │
    │  │   Scheduler + cli_process_event) │  │
    │  └──────────────────────────────────┘  │
    └─────┬──────────────────────────────────┘
          │ Raw event JSON
          ▼
    ┌────────────────────────────────────────────────────────────┐
    │         Flask Backend (Python) - REST API Server           │
    │                   app.py (Port 5000)                       │
    ├────────────────────────────────────────────────────────────┤
    │ Key Components:                                            │
    │ ┌────────────────────────────────────────────────────────┐ │
    │ │ Event Processing Pipeline (event_log_monitor.py)      │ │
    │ │  1. Fetch from Windows Event Log via PowerShell       │ │
    │ │  2. Deduplication (5-min window)                      │ │
    │ │  3. Enrichment from catalog (windows_error_events.json)│ │
    │ │  4. Root Cause Variant Detection (root_cause_analyzer)│ │
    │ │  5. Multi-Event Correlation (chronological)           │ │
    │ │  6. Confidence Scoring (0-100 urgency)               │ │
    │ │  7. Rule Matching (priority-based)                    │ │
    │ │  8. Auto-Remediation or Manual Review Flagging        │ │
    │ └────────────────────────────────────────────────────────┘ │
    │                                                            │
    │ ┌────────────────────────────────────────────────────────┐ │
    │ │ SQLite Database (rules.db)                            │ │
    │ │  • events: Ingested events + metadata                │ │
    │ │  • rules: Remediation rules with priorities          │ │
    │ │  • remediation_history: Audit trail                  │ │
    │ │  • root_cause_variants: Detected variants per event  │ │
    │ │  • rule_variant_associations: Variant-specific rules │ │
    │ └────────────────────────────────────────────────────────┘ │
    │                                                            │
    │ ┌────────────────────────────────────────────────────────┐ │
    │ │ PowerShell Execution Engine                           │ │
    │ │  • Runs remediation scripts with environment context  │ │
    │ │  • Injects event data via env vars (RM_EVENT_ID, etc)│ │
    │ │  • Captures output and status                         │ │
    │ │  • Records in remediation_history table               │ │
    │ └────────────────────────────────────────────────────────┘ │
    └─────┬──────────────────────────────────────────────────────┘
          │ REST API endpoints (/api/events, /api/rules, etc)
          │
          ├────────────────────┬─────────────────────────────┐
          │                    │                             │
          ▼                    ▼                             ▼
    ┌──────────────┐     ┌──────────────┐     ┌─────────────────────┐
    │ Flutter UI   │     │ Task Scheduler│     │ CLI Processor       │
    │ (Web/Windows)│     │ Event Triggers│     │ (cli_process_event) │
    │              │     │               │     │                     │
    │ Dashboard,   │     │ Direct event  │     │ Stateless runner    │
    │ Rules, Rules │     │ detection via │     │ for TS integration  │
    │ History,     │     │ WMI/etwtrace  │     │ Zero idle CPU       │
    │ Approvals    │     │               │     │                     │
    └──────────────┘     └──────────────┘     └─────────────────────┘
                               │
                               ▼
    ┌────────────────────────────────────────────────────────┐
    │ PowerShell Remediation Scripts                         │
    │ (remediation_scripts/ folder)                         │
    │  • 60+ specialized scripts (Error7031_*.ps1, etc)     │
    │  • Targeted fixes based on root cause                 │
    │  • Can use compound remediation for multi-event issues│
    │  • Escalation to deep repairs (sfc /scannow, etc)     │
    └────────────────────────────────────────────────────────┘
```

### **Design Principles**

1. **Lightweight & Zero-Idle CPU**: PowerShell collector is event-driven (via Task Scheduler) or low-frequency polling. No daemon constantly running.
2. **Separation of Concerns**: Event collection, processing, and remediation are independent modules that can run on different machines.
3. **Rule-Based & Extensible**: Rules defined in database; new rules can be added via web dashboard without code changes.
4. **Intelligent Correlation**: Multi-event inference detects compound root causes (e.g., memory exhaustion causing service crash → fix memory first).
5. **Variant-Aware**: Same error ID can have different root causes; system detects variants and applies targeted fixes.
6. **Backward Compatible**: Root cause variants and advanced features layer on top of existing simple rule system—old rules still work.

---

## Core Components

### **1. Backend Python Modules**

#### **app.py** - Flask REST API Server

**Purpose:** Central hub exposing all system capabilities via REST endpoints.

**Key Endpoints:**
- `POST /api/events` - Ingest a new event, trigger rule matching + auto-remediation
- `GET /api/events` - List all events (paginated)
- `GET /api/events/manual-review` - Events with no matching rule (need operator attention)
- `POST /api/events/<id>/dismiss-review` - Mark event as acknowledged
- `POST /api/rules` - Create/update remediation rules
- `GET /api/rules` - List all rules
- `POST /api/monitor/trigger` - Force an immediate event log poll
- `GET /api/monitor/status` - Status of background polling thread
- `GET /api/monitor/log` - Recent log entries (shared with CLI script)

**Key Features:**
- CORS support for Flutter frontend
- Unified logging: Flask and CLI script write to same `remediation_system.log`
- Middleware to serve Flutter web build or fallback template
- Supports both polling mode and Task Scheduler event-triggered mode

**Database Initialization:**
```python
init_db()  # Called on startup to ensure schema and migrations
```

---

#### **models.py** - Core Business Logic & Data Layer

**Purpose:** All database operations, rule matching engine, remediation execution, and intelligent event processing.

**Key Data Structures:**

1. **Events Table**
   - `id` (PK), `event_id`, `log_name`, `source`, `message`, `timestamp`
   - `category`, `severity`, `description`, `recommended_action` (from catalog enrichment)
   - `dedup_count` (how many duplicates collapsed into this row)
   - `last_seen`, `confidence_score` (0-100 urgency)
   - `correlation_id` (groups related events in same incident)
   - `root_cause_variant_id`, `root_cause_variant_label`, `root_cause_confidence`
   - `detected_root_causes` (JSON array of all detected variants)
   - `needs_manual_review`, `manual_review_reason` (for events with no rule)

2. **Rules Table**
   - `id` (PK), `name`, `event_id`, `source`, `message_regex`
   - `remediation_script`, `script_type` ('file' or 'inline')
   - `auto_remediate` (bool), `stop_processing` (short-circuit flag)
   - `category`, `severity` (match filters)
   - `priority` (lower number = higher priority)
   - `cooldown_minutes` (suppress re-run within N minutes)

3. **Remediation History Table**
   - `id`, `event_row_id`, `rule_id`, `status` (success/failed/skipped/suppressed)
   - `output` (stdout/stderr), `timestamp`

4. **Root Cause Variant Tables**
   - `event_root_cause_variants`: Detected variants per event
   - `rule_variant_associations`: Maps rules to specific variants with min_confidence threshold

**Critical Functions:**

1. **`add_event()`** - Smart event ingestion
   - Deduplication: Merges events with same `event_id+source` within 5-minute window
   - Enrichment: Looks up `event_id` in `windows_error_events.json` catalog for category/severity/description
   - Confidence Scoring: Calculates 0-100 urgency score based on severity, frequency, rules
   - Root Cause Variant Analysis: Detects different root causes for same error
   - Correlation ID Computation: Groups related events by source + 10-minute time bucket
   - Returns: DB row ID (new or existing if deduplicated)

2. **`calculate_confidence_score(event_dict, dedup_count, has_matching_rule)`** - Urgency Ranking
   - Severity factor (up to 40 pts): Critical=40, Error=32, Warning=20, etc.
   - Level factor (up to 20 pts)
   - Frequency bonus (up to 20 pts): +4 per duplicate occurrence
   - Rule presence bonus (20 pts): +20 if operator has created a rule for this event
   - Result: 0-100 score; high score = needs immediate attention

3. **`correlate_events(event_id, timestamp, window_minutes)`** - Multi-Event Inference
   - Queries database for co-occurring events within time window
   - Uses `CORRELATION_MAP` to identify compound root causes
   - Example: If Event 7031 (service crash) + Event 2019 (memory exhaustion) detected → compound_cause="memory_exhaustion"
   - Maps to compound remediation script (e.g., `Remediate_MemoryExhaustion.ps1`)
   - Returns: Correlation data with priority level (high/medium/low)
   - **Domains covered:** Memory, Disk, AppLocker, Networking, Firewall, Privilege/Security, Event Log, .NET Runtime

4. **`match_rules_for_event(event)`** - Rule Engine
   - Iterates through rules (sorted by priority ASC)
   - Matches event against rule criteria: `event_id`, `source`, `category`, `severity`, `message_regex`
   - Extracts regex capture groups for script context injection
   - Checks if rule is in cooldown (suppression window)
   - Returns: List of matching rules, sorted by priority
   - Supports `stop_processing` flag: If set on matched rule, stops evaluating lower-priority rules

5. **`run_remediation(event_row_id, rule_id, timeout=60, regex_captures)`** - Execution Engine
   - Fetches rule and event details from DB
   - **Context Injection**: Passes event data to PowerShell via environment variables:
     - `RM_EVENT_ROW_ID`, `RM_EVENT_ID`, `RM_LOG_NAME`, `RM_SOURCE`
     - `RM_MESSAGE`, `RM_TIMESTAMP`, `RM_CATEGORY`, `RM_SEVERITY`
     - `RM_SIMULATION_MODE` (for testing)
     - `RM_MATCH_*` variables from regex captures
   - Executes PowerShell script with bypass execution policy
   - Records result (success/failed/skipped) in `remediation_history` table
   - Timeout: 60 seconds (customizable)

6. **`detect_faulting_module(message)` & `is_core_os_module(module_name)`** - Deep System Repair
   - Parses application crash messages for "faulting module name: X.dll"
   - If core OS DLL detected (ntdll.dll, kernel32.dll, etc.), escalates to `sfc /scannow`
   - Prevents infinite crash loops from corrupted system libraries

**Other Important Functions:**
- `get_event_definition(event_id, source)` - Lookup event metadata from JSON catalog
- `get_correlation_id(source, timestamp)` - Groups events into 10-min buckets
- `is_rule_in_cooldown(rule_id, event_id, source, cooldown_minutes)` - Suppression window check
- `set_manual_review()`, `dismiss_manual_review()` - Manual review workflow

---

#### **event_log_monitor.py** - Background Event Poller

**Purpose:** Periodically polls Windows Event Log for new errors/warnings and injects them into the system.

**Key Components:**

1. **Watermark System** (`eventlog_watermark.json`)
   - Stores `last_processed_timestamp` on disk
   - On startup: Looks back 1 hour (or loads from watermark)
   - Prevents duplicate processing

2. **PowerShell Event Fetcher** (`_fetch_windows_events()`)
   - Constructs PowerShell command to query Event Log
   - Filters: `LogNames=['System', 'Application']`, `Level=[1,2,3]` (Critical, Error, Warning)
   - MaxEvents: 50 per poll (configurable)
   - Uses Base64-encoded PowerShell to safely pass multi-line script
   - Returns JSON array of events

3. **Event Processing Pipeline** (`_process_event()`)
   - Parses PowerShell JSON response
   - Normalizes timestamp format (handles PowerShell `/Date()` notation)
   - Enriches event with catalog metadata (category, severity, description)
   - **Multi-Event Inference**: Calls `correlate_events()` to detect compound root causes
   - **Deep System Repair**: Detects faulting modules, escalates core OS DLL crashes
   - **Rule Matching**: Calls `match_rules_for_event()`
   - **Auto-Remediation**: If rule has `auto_remediate=1` AND not in cooldown → `run_remediation()`
   - **Manual Review**: If no rule matched → `set_manual_review()` with reason
   - Records event in DB and CSV

4. **Polling Loop** (`_monitor_thread()`)
   - Runs every `POLL_INTERVAL` seconds (default 30)
   - Thread-safe state tracking (`_monitor_state` dict)
   - Catches and logs exceptions (non-fatal)
   - Updates watermark on successful poll

5. **Public Interface:**
   - `start_monitor()` - Spawns background thread on Flask startup
   - `trigger_poll()` - Forces immediate poll (called by `/api/monitor/trigger`)
   - `get_status()` - Returns monitor thread state (running, last_poll, events_ingested, errors)

**Configuration** (from `.env` or environment):
```
POLL_INTERVAL_SECONDS=30
MAX_EVENTS_PER_POLL=50
HISTORICAL_DAYS=30
MAX_HISTORICAL_EVENTS=10000
LOG_NAMES=System,Application
```

---

#### **cli_process_event.py** - Task Scheduler Integration

**Purpose:** Lightweight script run directly by Windows Task Scheduler whenever a watched event ID is detected.

**Key Features:**

1. **Stateless & Zero-CPU-Idle**: No daemon running; exits immediately after processing
2. **Unified Logging**: Writes to same `remediation_system.log` as Flask server
3. **Crash Logging**: Catches all unhandled exceptions and writes to `task_scheduler_crash.log`
4. **Single Poll Cycle**:
   - Loads `.env` configuration
   - Initializes database (runs migrations if needed)
   - Calls `event_log_monitor.trigger_poll()` once
   - Exits with status code 0 (success) or 1 (failure)

**Entry Point:**
```python
if __name__ == '__main__':
    main()  # Triggered by Task Scheduler
```

**Usage by Task Scheduler:**
```powershell
# Via Setup_EventTriggers.ps1
python C:\path\backend\cli_process_event.py
```

---

#### **db_init.py** - Database Initialization & Migration

**Purpose:** Creates SQLite schema and runs backward-compatible migrations.

**Schema:**
- `events` table with 20+ columns
- `rules` table with priority/cooldown support
- `remediation_history` audit trail
- `remediation_requests` approval workflow
- `event_root_cause_variants` variant tracking
- `rule_variant_associations` variant-to-rule mapping

**Migration Strategy:**
- `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`
- Non-breaking: Existing data unchanged, new columns default to NULL or sensible defaults
- Called at Flask startup AND by CLI script before processing events

---

#### **root_cause_analyzer.py** - Intelligent Root Cause Detection

**Purpose:** Detect different root causes for errors with the same event ID.

**Architecture:**

1. **`RootCauseVariant` Class**
   - Represents a detected root cause with confidence level
   - Fields: `variant_id`, `label`, `description`, `confidence`, `matched_indicators`, `timestamp`
   - Confidence enum: CERTAIN(100), HIGH(80), MEDIUM(60), LOW(40), UNKNOWN(0)

2. **`RootCauseAnalyzer` Class**
   - Singleton pattern (one instance per process)
   - Pattern registry: Maps `event_id` → list of variant definitions
   - Each variant definition:
     ```python
     {
         'variant_id': 'unique_id',
         'label': 'display_label',
         'description': 'what caused this',
         'message_patterns': [(regex, weight), ...],  # Higher weight = more confident
         'required_keywords': [keywords, ...],         # At least one must be present
         'context_checks': [                           # Additional criteria
             {'field': 'severity', 'values': ['error', 'critical'], 'weight': 1},
             ...
         ]
     }
     ```

3. **Scoring Algorithm:**
   - Regex patterns: Add pattern weight for each match
   - Required keywords: +25 bonus if any match; half confidence if required not found
   - Context checks: +weight*10 for each field match
   - Total confidence: CERTAIN(≥60), HIGH(≥40), MEDIUM(≥20), LOW(>0)

4. **Default Patterns** (Pre-Configured):
   - **Error 1003 (Service Crash):**
     - `svc_crash_high_memory`: Memory patterns (out of memory, heap, allocation)
     - `svc_crash_resource_lock`: Deadlock patterns (deadlock, lock timeout, blocked)
     - `svc_crash_missing_dependency`: File patterns (not found, missing, DLL, dependency)
   - **Error 1000 (Application Error):**
     - `app_crash_exception`: Exception patterns
     - `app_crash_plugin_failure`: Plugin/extension patterns

5. **Public Interface:**
   - `register_variant_pattern(event_id, definition)` - Add custom variant
   - `analyze_event(event_dict)` - Returns list of `RootCauseVariant` objects
   - `get_analyzer()` - Singleton accessor

**Example Usage:**
```python
from root_cause_analyzer import get_analyzer

analyzer = get_analyzer()

# Register custom variant
analyzer.register_variant_pattern(1003, {
    'variant_id': 'my_custom_crash',
    'label': 'CustomCrash',
    'message_patterns': [(r'(?i)my_pattern', 3)],
})

# Analyze event
variants = analyzer.analyze_event({
    'event_id': 1003,
    'message': 'Service crashed: out of memory allocation failed',
    'severity': 'error'
})
# Returns: [RootCauseVariant(variant_id='...', confidence=CERTAIN, ...)]
```

---

### **2. PowerShell Collector Scripts** (collector/ folder)

#### **event_monitor.ps1** - Main Event Polling Script

**Purpose:** Continuously polls Windows Event Log and sends events to Flask backend.

**Key Parameters:**
- `ApiUrl`: Flask API endpoint (default: http://localhost:5000)
- `LogNames`: Comma-separated logs to monitor (default: System,Application)
- `PollIntervalSeconds`: How often to check (default: 10)
- `MaxEventsPerPoll`: Batch size (default: 100)
- `HistoricalDays`: Days of history to import on startup (default: 30)

**Features:**
- Configurable via command-line parameters or `.env` file
- Filters Errors (Level 2) and Warnings (Level 3) only
- Deduplication of already-sent events
- Historical import on startup
- Continuous polling loop until manually stopped

**Example:**
```powershell
.\collector\event_monitor.ps1 -LogNames "System,Application" -PollIntervalSeconds 5
```

---

#### **Load-Config.ps1** - Configuration Loader

**Purpose:** Reads `.env` file and returns configuration as hash table.

**Outputs:**
```powershell
@{
    API_BASE_URL = "http://localhost:5000"
    LOG_NAMES = "System,Application"
    POLL_INTERVAL_SECONDS = 30
    MAX_EVENTS_PER_POLL = 50
    HISTORICAL_DAYS = 30
    ...
}
```

---

#### **Setup_EventTriggers.ps1** - Task Scheduler Integration

**Purpose:** Configures Windows Task Scheduler to run `cli_process_event.py` whenever watched event IDs occur.

**Creates:**
- Scheduled task triggered by WMI event (new events matching criteria)
- Action: Run `python cli_process_event.py`
- Runs with system privileges

**Usage:**
```powershell
.\remediation_scripts\Setup_EventTriggers.ps1
```

---

### **3. Remediation Scripts** (remediation_scripts/ folder)

**Purpose:** Specialized PowerShell scripts that fix specific issues.

**Structure:** 60+ scripts following naming pattern: `Error<ID>_<Description>.ps1`

**Examples:**
- `Error7031_ServiceTerminatedUnexpectedly.ps1` → Restarts terminated service
- `Error2019_NonPagedPoolMemoryExhausted.ps1` → Clears memory caches
- `Error1000_ApplicationCrash.ps1` → Checks logs and restarts app
- `Remediate_MemoryExhaustion.ps1` → Compound remediation for memory issues
- `Remediate_SystemRepair_Fallback.ps1` → Deep system repair (sfc /scannow)

**Standard Input** (Injected as Environment Variables):
```powershell
$EventId      = $env:RM_EVENT_ID
$Source       = $env:RM_SOURCE
$Message      = $env:RM_MESSAGE
$Severity     = $env:RM_SEVERITY
$SimulationMode = $env:RM_SIMULATION_MODE
```

**Standard Output:**
- stdout: Status messages
- stderr: Errors/warnings
- Exit code 0: Success, non-zero: Failure

---

### **4. Frontend** (frontend/ folder - Flutter Web)

**Technology:** Flutter (Dart), compiled to web (JavaScript/HTML/CSS)

**Key Screens:**
- **Dashboard**: Statistics, charts, real-time monitoring
- **Events/Warnings**: List of captured events with filtering/sorting
- **Rules**: Create, edit, delete remediation rules
- **History**: Audit trail of remediation actions
- **Approvals**: Workflow for sensitive remediation requests
- **Manual Review**: Events that need operator attention

**API Integration:**
- All backend operations via REST calls to `http://localhost:5000/api/...`
- WebSocket or polling for real-time updates

---

---

## Data Flow

### **Complete Flow: Event → Remediation → Feedback**

```
1. EVENT DETECTION
   ├─ Method A (Polling): event_monitor.ps1 polls every 30s
   │  └─ Queries: Get-WinEvent -LogName System,Application -Level 2,3 -Since <watermark>
   │
   ├─ Method B (Task Scheduler): WMI trigger detects event immediately
   │  └─ Runs: cli_process_event.py
   │
   └─ Method C (Manual/API): POST /api/events with event data

2. EVENT INGESTION (app.py → models.add_event())
   ├─ Normalize: Parse timestamp, level, source
   ├─ Enrich: Lookup event_id in windows_error_events.json catalog
   │  └─ Add: category, severity, description, recommended_action
   ├─ Deduplicate: Check if event_id+source seen in last 5 minutes
   │  ├─ If yes: Increment dedup_count, update last_seen, recalculate confidence
   │  └─ If no: Insert new DB row
   ├─ Score: Calculate confidence_score (0-100 urgency)
   ├─ Detect Variants: Call analyze_root_cause() to find root cause variants
   ├─ Correlate: Look for related events in time window
   ├─ Store: Insert into events table with all enriched fields
   └─ CSV: Append to errors_warnings.csv for UI

3. RULE MATCHING (models.match_rules_for_event())
   ├─ Load all rules from DB (sorted by priority ASC)
   ├─ For each rule:
   │  ├─ Check: event_id, source, category, severity match rule filters
   │  ├─ Regex: Extract named capture groups from message
   │  ├─ Cooldown: Skip if rule was executed in cooldown window
   │  └─ Collect: Accumulate matching rules
   ├─ Stop Processing: If matched rule has stop_processing=1, halt evaluation
   └─ Return: List of matching rules (or empty if no match)

4. AUTO-REMEDIATION (app.py → models.run_remediation())
   ├─ Check: Does matched rule have auto_remediate=1?
   │  ├─ No: Create remediation_request with "pending" status (manual approval)
   │  └─ Yes: Proceed to execution
   │
   ├─ Context Injection: Prepare environment variables
   │  ├─ RM_EVENT_ID, RM_SOURCE, RM_MESSAGE, RM_SEVERITY
   │  ├─ RM_MATCH_* (from regex captures)
   │  └─ RM_SIMULATION_MODE
   │
   ├─ Load Script: Get remediation_script path from rule
   │  ├─ Type 'file': Load from remediation_scripts/
   │  └─ Type 'inline': Create temp file
   │
   ├─ Execute: subprocess.run(powershell -File script, env=env, timeout=60s)
   │  └─ PowerShell can access event data via $env:RM_* variables
   │
   ├─ Capture: stdout + stderr
   ├─ Status: success (exit 0) or failed (exit ≠ 0)
   └─ Record: Insert into remediation_history table

5. MANUAL REVIEW FLAGGING (event_log_monitor._process_event())
   ├─ If no matching rules found:
   │  ├─ Set: needs_manual_review=1
   │  ├─ Reason: "No matching remediation rules"
   │  └─ Dashboard: Shows in "Manual Review" tab
   │
   ├─ Operator Reviews:
   │  ├─ Can Create: New rule directly from event
   │  ├─ Can Dismiss: Mark as acknowledged
   │  └─ Can Approve: Manual remediation request
   │
   └─ Follow-up: Next similar event will match new rule

6. DASHBOARD FEEDBACK LOOP
   ├─ Real-time Updates: UI polls /api/events, /api/monitor/log
   ├─ Confidence Display: Shows urgency score
   ├─ Variant Info: Displays detected root cause + confidence
   ├─ Correlation: Shows related events if multi-event inference triggered
   ├─ History: Audit trail of remediation actions
   └─ Next Steps: Operator can review or create new rules
```

### **Example Scenario: Service Crash with Memory Exhaustion**

```
┌─ EVENT LOGS IN RAPID SUCCESSION ─────────────────────────┐
│                                                            │
│ 1. 14:32:10 - Event 2019: "Non-paged pool exhausted"     │
│    Source: Kernel-General, Severity: Error               │
│                                                            │
│ 2. 14:32:45 - Event 7031: "Service terminated unexpectedly"
│    Source: Service Control Manager, Severity: Error      │
│    Message: "System service X stopped unexpectedly"      │
│                                                            │
└────────────────────────────────────────────────────────────┘

SYSTEM PROCESSING:

1. Event 2019 arrives:
   ✓ Ingested, enriched: category=Memory, severity=Error
   ✓ Dedup check: No duplicate in 5 min → new row
   ✓ Confidence score: 32 (Error) + 20 (Level) = 52
   ✓ Root cause: "MemoryExhaustion" (confidence: 100)
   ✓ Correlation: No related events yet
   ✓ Rule matching: Rule exists "Clear Memory Cache" (priority 10)
   ✓ Auto-remediate: YES → Executes Remediate_MemoryExhaustion.ps1
     ├─ Script clears caches, compacts working set
     ├─ Returns: success, output="Memory freed: 2GB"
     └─ Record: remediation_history status=success

2. Event 7031 arrives (13 seconds later):
   ✓ Ingested, enriched: category=Services, severity=Error
   ✓ Dedup check: No duplicate in 5 min → new row
   ✓ Confidence score: 32 + 20 = 52
   ✓ Root cause: No specific variant detected
   ✓ Correlation: YES! Event 2019 within 5-min window detected
     ├─ compound_cause: "memory_exhaustion"
     ├─ compound_script: Remediate_MemoryExhaustion.ps1
     └─ priority: HIGH
   ✓ Escalation: System recognizes this as compound issue
     ├─ Doesn't just restart service (would fail again)
     └─ Already fixed memory → service may auto-recover
   ✓ Rule matching: Rule "Restart Service X" matches
     ├─ But system knows memory was root cause
     ├─ Waits 30 seconds to see if service auto-recovers
     └─ If not, restarts with better confidence
   ✓ Result: Service recovers; system logs success

DASHBOARD VIEW:
- Shows 2 events correlated (correlation_id: "abc123def456")
- Displays: "Root cause identified: High Memory Usage (100% confidence)"
- Shows both remediation actions taken
- Status: "Resolved automatically"
- Operator notes: System fixed root cause first, then symptom
```

---

## Critical Functions

### **models.py - Key Functions**

#### **1. `add_event(event_id, log_name, source, message, ...)`**

```python
def add_event(event_id, log_name, source, message,
              timestamp=None, category=None, severity=None, ...):
    """
    Smart event ingestion with deduplication, enrichment, and correlation.
    
    Flow:
    1. Deduplication check: event_id + source within 5 min window?
       - YES: Increment dedup_count, update last_seen, recalculate confidence → return existing ID
       - NO: Continue to create new event
    2. Catalog enrichment: Look up event_id in windows_error_events.json
    3. Confidence scoring: Calculate 0-100 urgency
    4. Root cause variant analysis: Detect different root causes
    5. Correlation ID: Group related events
    6. Insert into DB + CSV
    
    Returns: DB row ID (int)
    """
```

**Deduplication Logic:**
```python
cutoff = datetime.utcnow() - timedelta(seconds=300)  # 5 min window
SELECT id, dedup_count FROM events
WHERE event_id = ? AND source = ?
  AND timestamp >= cutoff
ORDER BY id DESC LIMIT 1
```

---

#### **2. `calculate_confidence_score(event_dict, dedup_count, has_matching_rule)`**

```python
def calculate_confidence_score(event_dict, dedup_count=1, has_matching_rule=False):
    """
    Compute 0-100 confidence score (urgency/priority).
    
    Factors:
    - Severity: Critical(40) > Error(32) > Warning(20) > Info(8)
    - Level: Critical/Error(20) > Warning(10) > Info(4)
    - Frequency: +4 per duplicate (capped at 20)
    - Rule exists: +20 if operator has created a rule
    
    Use: Higher score = more urgent = should remediate first
    """
```

**Scoring Table:**
| Severity | Level | Dedup | Rule | Total |
|----------|-------|-------|------|-------|
| Critical | Error | 1×    | Yes  | 80    |
| Error    | Error | 5×    | Yes  | 92    |
| Warning  | Warn  | 1×    | No   | 30    |
| Info     | Info  | 1×    | No   | 12    |

---

#### **3. `correlate_events(event_id, timestamp, window_minutes)`**

```python
def correlate_events(event_id, timestamp=None, window_minutes=None):
    """
    Detect compound root causes by finding related events in time window.
    
    Algorithm:
    1. Look up event_id in CORRELATION_MAP
       CORRELATION_MAP[event_id] = [(corr_id, domain, cause_hint), ...]
    2. Query DB for events matching corr_id within window_minutes
    3. For each found event, track severity and cause_hint
    4. Return highest-priority compound_cause
    
    Example:
    - Trigger: Event 7031 (service crash)
    - Found: Event 2019 (memory exhausted) from 2 min ago
    - CORRELATION_MAP[7031] = [(2019, 'Memory', 'memory_exhaustion'), ...]
    - Result: compound_cause='memory_exhaustion', priority='high'
    - Script: Remediate_MemoryExhaustion.ps1
    
    Returns: {
        'has_correlation': bool,
        'compound_cause': str | None,
        'compound_script': str | None,
        'correlated_events': [
            {'db_id': int, 'event_id': int, 'domain': str, 'severity': str, ...}
        ],
        'priority': 'high' | 'medium' | 'low'
    }
    """
```

**CORRELATION_MAP Structure (Simplified):**
```python
CORRELATION_MAP = {
    1000: [  # Application crash may be caused by:
        (2019, 'Memory', 'memory_exhaustion'),
        (8003, 'AppLocker', 'applocker_block'),
    ],
    7031: [  # Service crash may be caused by:
        (2019, 'Memory', 'memory_exhaustion'),
        (11, 'Disk', 'disk_io_error'),
    ],
    # ... 50+ event correlations defined
}
```

---

#### **4. `match_rules_for_event(event)`**

```python
def match_rules_for_event(event):
    """
    Find all rules that match the given event.
    
    Matching logic (AND semantics):
    - event_id: rule.event_id = event.event_id (if rule specifies)
    - source: rule.source = event.source (if rule specifies)
    - category: rule.category = event.category (if rule specifies)
    - severity: rule.severity = event.severity (if rule specifies)
    - regex: rule.message_regex matches event.message (if rule specifies)
    
    Cooldown check:
    - If rule.auto_remediate=1 and rule in cooldown window → skip
    
    Stop processing:
    - If matched rule has stop_processing=1 → halt (don't eval lower priority rules)
    
    Returns: List of matching rules
    [(id, name, event_id, source, ..., cooldown_active, regex_captures), ...]
    """
```

**Example Rule:**
```python
{
    'id': 5,
    'name': 'Fix Service Crash',
    'event_id': 7031,
    'source': 'Service Control Manager',
    'message_regex': r'Service.*stopped',
    'remediation_script': 'Error7031_ServiceTerminatedUnexpectedly.ps1',
    'auto_remediate': 1,
    'priority': 10,
    'cooldown_minutes': 60,
    'stop_processing': 1,  # Don't check lower priority rules after this
}
```

---

#### **5. `run_remediation(event_row_id, rule_id, timeout=60, regex_captures)`**

```python
def run_remediation(event_row_id, rule_id, timeout=60, regex_captures=None):
    """
    Execute PowerShell remediation script with event context.
    
    Steps:
    1. Fetch rule and event from DB
    2. Build environment dict with RM_* variables
    3. Execute PowerShell script with timeout
    4. Capture output (stdout + stderr)
    5. Record result in remediation_history
    
    Context Injection (Environment Variables):
        RM_EVENT_ROW_ID = DB row ID
        RM_EVENT_ID = Event ID (e.g., 7031)
        RM_LOG_NAME = Log name (e.g., System)
        RM_SOURCE = Event source (e.g., Service Control Manager)
        RM_MESSAGE = Event message
        RM_TIMESTAMP = When event occurred
        RM_CATEGORY = Category (e.g., Services)
        RM_SEVERITY = Severity (e.g., Error)
        RM_SIMULATION_MODE = 0/1 (for testing)
        RM_MATCH_<name> = Regex capture groups
    
    PowerShell Access:
        $service_name = $env:RM_SOURCE  # Use in script
    
    Returns: {
        'status': 'success' | 'failed' | 'skipped' | 'error',
        'output': 'stdout + stderr'
    }
    """
```

**Execution Command:**
```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "Remediate_MemoryExhaustion.ps1"
# Environment: $env:RM_EVENT_ID, $env:RM_SOURCE, etc.
```

---

#### **6. `detect_faulting_module(message)` & `is_core_os_module(module_name)`**

```python
def detect_faulting_module(message):
    """Extract faulting DLL from crash message."""
    # Pattern: "faulting module name: ntdll.dll"
    match = re.search(r'faulting module name:\s*([^\s,\n]+)', message)
    return match.group(1).lower() if match else None

def is_core_os_module(module_name):
    """Check if DLL is a core Windows system file."""
    CORE_OS_MODULES = {
        'ntdll.dll', 'kernel32.dll', 'kernelbase.dll', 'msvcrt.dll',
        'user32.dll', 'advapi32.dll', 'ole32.dll', 'rpcrt4.dll',
        # ... 10+ more core DLLs
    }
    return module_name.lower() in CORE_OS_MODULES
```

**Deep System Repair Escalation:**
```python
if is_core_os_module(faulting_module):
    # Don't just restart the app—that will crash again
    # Escalate to Remediate_SystemRepair_Fallback.ps1
    # Which runs: sfc /scannow (System File Checker)
```

---

### **event_log_monitor.py - Key Functions**

#### **1. `_fetch_windows_events(since: datetime)`**

```python
def _fetch_windows_events(since: datetime):
    """
    Query Windows Event Log via PowerShell.
    
    Query:
        Get-WinEvent -FilterHashtable @{
            LogName = 'System', 'Application'
            Level = 1, 2, 3  # Critical, Error, Warning
            StartTime = <since>
        } -MaxEvents 50
    
    Returns: List of event dicts with Id, LogName, ProviderName, Message, TimeCreated, Level
    """
```

---

#### **2. `_process_event(raw: dict)`**

```python
def _process_event(raw):
    """
    Complete event processing pipeline.
    
    Flow:
    1. Parse: Extract event_id, source, message, severity from raw PowerShell JSON
    2. Normalize: Timestamp parsing (handles /Date() notation)
    3. Enrich: Lookup in catalog
    4. Multi-Event Inference: Detect compound root causes
    5. Deep Repair: Check for faulting core DLLs
    6. Rule Matching: Call match_rules_for_event()
    7. Auto-Remediate: If rule matches and auto_remediate=1 → run_remediation()
    8. Manual Review: If no rule matched → set_manual_review()
    """
```

---

#### **3. `trigger_poll()`**

```python
def trigger_poll():
    """Force an immediate poll cycle (non-blocking)."""
    # Called by /api/monitor/trigger or cli_process_event.py
    # Returns: Number of events ingested
```

---

### **root_cause_analyzer.py - Key Functions**

#### **1. `analyze_event(event_dict)`**

```python
def analyze_event(event_dict):
    """
    Detect root cause variants for an event.
    
    Input: {
        'event_id': 1003,
        'message': 'Service crashed: out of memory allocation failed',
        'severity': 'error',
        ...
    }
    
    Process:
    1. Look up event_id in variant_patterns
    2. For each variant definition:
       - Score message against patterns
       - Check required keywords
       - Evaluate context fields
       - Assign confidence level
    3. Sort by confidence (highest first)
    4. Return list of RootCauseVariant objects
    
    Returns: [RootCauseVariant(...), RootCauseVariant(...), ...]
    """
```

---

---

## Configuration & State Management

### **State Storage**

#### **1. SQLite Database** (`backend/rules.db`)

Primary persistence layer for all system state.

**Tables:**

| Table | Purpose | Key Columns |
|-------|---------|------------|
| `events` | Ingested events | id (PK), event_id, source, timestamp, dedup_count, confidence_score, correlation_id, root_cause_variant_id |
| `rules` | Remediation rules | id (PK), name, event_id, source, message_regex, remediation_script, auto_remediate, priority, cooldown_minutes |
| `remediation_history` | Audit trail | id (PK), event_row_id (FK), rule_id (FK), status, output, timestamp |
| `remediation_requests` | Approval workflow | id (PK), event_row_id, rule_id, status (pending/approved/rejected), requested_by, processed_by |
| `event_root_cause_variants` | Detected variants | id (PK), event_row_id (FK), variant_id, variant_label, confidence_score, matched_indicators (JSON) |
| `rule_variant_associations` | Variant-specific rules | id (PK), rule_id (FK), variant_id, min_confidence |

---

#### **2. Watermark File** (`backend/data/eventlog_watermark.json`)

Tracks last-processed Event Log timestamp to prevent duplicate processing.

```json
{
    "eventlog_since": "2026-05-05T14:32:00.000000"
}
```

**Logic:**
- On startup: Load watermark, default to 1 hour ago if missing
- After poll: Update watermark to latest event timestamp
- Prevents re-processing same events across restarts

---

#### **3. CSV Export** (`backend/data/errors_warnings.csv`)

Errors and Warnings for dashboard consumption. Lightweight alternative to DB for read-heavy dashboard.

**Columns:**
```
event_id, log_name, source, message, timestamp, category, severity, 
description, recommended_action, level, remediated_at, 
confidence_score, correlation_id
```

**Usage:**
- Flutter dashboard reads for fast rendering
- Avoids expensive DB queries for list views
- Updated in real-time as events arrive

---

#### **4. Last Processed Marker** (`backend/data/last_processed.json`)

Tracks most recent event processed for resumption after crashes.

```json
{
    "last_rowid": 12345,
    "last_timestamp": "2026-05-05T14:32:00.000000"
}
```

---

#### **5. Unified Log File** (`backend/data/remediation_system.log`)

Audit trail shared by Flask server and Task Scheduler CLI script.

```
[2026-05-05 14:32:10 UTC] [INFO] [FLASK] Started Flask server on 0.0.0.0:5000
[2026-05-05 14:32:15 UTC] [INFO] [EVENT-MONITOR] Fetched 3 events from Windows Event Log
[2026-05-05 14:32:16 UTC] [INFO] [FLASK] Event 7031 ingested, matched rule 5
[2026-05-05 14:32:17 UTC] [INFO] [FLASK] Remediation started: Error7031_ServiceTerminatedUnexpectedly.ps1
[2026-05-05 14:32:25 UTC] [INFO] [FLASK] Remediation completed: status=success, output='Service restarted successfully'
[2026-05-05 14:32:26 UTC] [TASK-SCHEDULER] Poll complete — ingested and processed 3 new event(s).
```

---

#### **6. Crash Log** (`backend/data/task_scheduler_crash.log`)

Last-resort exception logging for Task Scheduler background executions.

```
============================================================
[2026-05-05T14:32:10Z] CRASH in cli_process_event.py
Traceback (most recent call last):
  File "cli_process_event.py", line 35, in main
    init_db()
  File "db_init.py", line 45, in init_db
    conn.execute(...)
sqlite3.OperationalError: database locked
============================================================
```

---

### **Configuration Files**

#### **1. Environment Variables** (`.env`)

Created by setup.ps1 or manually copied from `.env.example`.

```bash
# Flask Server
FLASK_ENV=production
FLASK_PORT=5000
API_BASE_URL=http://localhost:5000

# Event Monitoring
POLL_INTERVAL_SECONDS=30
MAX_EVENTS_PER_POLL=50
HISTORICAL_DAYS=30
MAX_HISTORICAL_EVENTS=10000
LOG_NAMES=System,Application
EVENT_IDS_TO_MONITOR=7031,7034,1000,1001

# Task Scheduler Mode
USE_TASK_SCHEDULER=false  # Set to true if Setup_EventTriggers.ps1 run

# PowerShell Paths
POWERSHELL_PATH=C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe

# Remediation
REMEDIATION_TIMEOUT_SECONDS=60
REMEDIATION_SCRIPT_PATH=remediation_scripts/
```

---

#### **2. Event Definitions Catalog** (`windows_error_events.json`)

Pre-loaded metadata for 40+ common Windows error events.

**Structure:**
```json
[
    {
        "event_id": 7031,
        "event_source": "Service Control Manager",
        "category": "Services",
        "severity": "Error",
        "description": "A service was terminated unexpectedly",
        "recommended_action": "Check service logs and restart if necessary",
        "common_causes": [
            "Insufficient memory",
            "Disk I/O errors",
            "Permission issues"
        ]
    },
    {
        "event_id": 1000,
        "event_source": "Application Error",
        "category": "Applications",
        "severity": "Error",
        "description": "An application has crashed",
        "recommended_action": "Check application logs and reinstall if necessary"
    },
    // ... 38 more events
]
```

---

#### **3. Monitor Configuration** (`collector/monitor_config.json`)

Optional configuration for PowerShell collector (can be overridden by command-line params).

```json
{
    "api_endpoint": "http://localhost:5000/api/events",
    "log_names": ["System", "Application"],
    "poll_interval_seconds": 30,
    "max_events_per_poll": 50,
    "event_levels": [1, 2, 3],
    "event_ids_to_filter": null,
    "historical_import_days": 30
}
```

---

### **Runtime State Tracking**

#### **Monitor Thread State** (In-Memory)

```python
_monitor_state = {
    'running': True,
    'last_poll': '2026-05-05T14:32:15Z',
    'events_ingested': 142,
    'errors': [
        '2026-05-05 14:30:00 - PowerShell timeout',
        '2026-05-05 14:15:00 - Database locked'
    ]
}
```

**Thread-Safe Access:**
```python
with _state_lock:
    _monitor_state['events_ingested'] += 1
```

---

### **Rule Configuration Examples**

#### **Simple Rule (Event Matching)**
```python
add_rule(
    name='Restart Service',
    event_id=7031,
    source='Service Control Manager',
    remediation_script='Error7031_ServiceTerminatedUnexpectedly.ps1',
    auto_remediate=1,
    priority=100,
    cooldown_minutes=60
)
```

#### **Regex Rule (Message Parsing)**
```python
add_rule(
    name='Handle Missing File',
    event_id=1000,
    message_regex=r'(?i)file.*not.*found.*(?P<filename>\S+)',
    remediation_script='Remediate_MissingFile.ps1',
    auto_remediate=0,  # Manual approval needed
    priority=50,
    cooldown_minutes=0  # No cooldown
)
```

#### **Variant-Specific Rule**
```python
rule_id = add_rule(
    name='Fix High Memory Usage',
    event_id=1003,
    remediation_script='Remediate_MemoryExhaustion.ps1',
    auto_remediate=1,
    priority=5,
    cooldown_minutes=30
)

# Link to specific root cause variant
link_rule_to_variant(
    rule_id=rule_id,
    variant_id='svc_crash_high_memory',
    variant_label='HighMemoryUsage',
    min_confidence=70  # Only apply if 70%+ confident
)
```

---

---

## Advanced Features

### **1. Multi-Event Inference (Chronological Correlation)**

**Problem:** Same error can have different root causes; simple restart fails.

**Solution:** Detect related events within time window → identify compound root cause → apply targeted fix.

**Example:**
```
Event 2019 (Memory exhaustion) → 5 min later → Event 7031 (Service crash)

System realizes:
- Service didn't crash from a bug
- Memory was exhausted → service was starved
- Fix: Clear memory cache FIRST, then restart service

Success rate: 90% (vs 30% if just restarting)
```

**Implementation:** `correlate_events()` function with `CORRELATION_MAP` (50+ event relationships defined)

---

### **2. Root Cause Variant Detection**

**Problem:** Error 1003 "Service crash" could be:
- A: Memory exhaustion → need `Remediate_MemoryExhaustion.ps1`
- B: Deadlock → need `RecoverFromDeadlock.ps1`
- C: Missing file → need to restore file

**Solution:** Analyze error message for keywords/patterns → identify most likely cause → apply specific fix.

**Scoring:**
- Message pattern matching (regex with weights)
- Required keyword presence
- Context field checks (severity, category)
- Confidence level: CERTAIN(100), HIGH(80), MEDIUM(60), LOW(40), UNKNOWN(0)

**Usage:**
```python
variants = analyze_event({
    'event_id': 1003,
    'message': 'Service crashed: out of memory allocation failed'
})
# Returns: [RootCauseVariant(variant_id='svc_crash_high_memory', confidence=CERTAIN)]

# Apply variant-specific rule
rule = get_variant_associations(rule_id)  # Variants associated with this rule
if event_variant.confidence >= rule.min_confidence:
    run_remediation(...)
```

---

### **3. Deep System Repair Escalation**

**Problem:** App crashes due to corrupted core Windows DLL (e.g., ntdll.dll).
- Restarting app → infinite crash loop
- Need to repair system

**Solution:** Detect faulting core DLL → escalate to `sfc /scannow`

**Implementation:**
```python
faulting_module = detect_faulting_module(message)  # Extract "ntdll.dll"
if is_core_os_module(faulting_module):
    run_remediation(event_row_id, rule_id_for_sfc_scannow)
    # Runs Remediate_SystemRepair_Fallback.ps1
```

---

### **4. Deduplication & Frequency Analysis**

**Problem:** Same event fires 100 times in a minute → clutters DB, inflates statistics

**Solution:** Merge duplicates → track `dedup_count` → factor frequency into confidence score

**Implementation:**
```python
# If event_id+source seen within 5 min, increment counter
UPDATE events SET dedup_count = dedup_count + 1
WHERE event_id = ? AND source = ? AND timestamp >= cutoff
```

**Result:**
- DB stays clean
- Frequency boosts confidence score
- Dashboard shows "This error occurred 47 times in 10 minutes"

---

### **5. Event Correlation Groups (Incident Clustering)**

**Problem:** Related events have different event IDs → hard to track "the incident"

**Solution:** Assign `correlation_id` based on source + 10-min time bucket

**Implementation:**
```python
correlation_id = md5(f"{source.lower()}:{date_hour}{time_bucket}").hex()[:12]
# Example: "6f2c8e1a5d9b" groups all events from "Service X" between 14:30-14:40
```

**Dashboard Usage:**
- Filter by correlation_id to see all related events in one incident
- Timeline view shows how events unfolded

---

### **6. Priority-Based Rule Matching**

**Problem:** Multiple rules match same event; which executes?

**Solution:** Rules have `priority` (lower = higher); first match with highest priority wins

**With `stop_processing` Flag:**
- If matched rule has `stop_processing=1` → don't check lower priority rules
- Allows "veto" rules that override defaults

**Example:**
```python
# Priority 5 (highest): "If memory exhaustion, fix memory FIRST"
rule1 = add_rule(..., priority=5, stop_processing=1)

# Priority 100 (lowest): "Generic service restart"
rule2 = add_rule(..., priority=100)

# Event matches both, but rule1 executes first and stops evaluation
```

---

### **7. Cooldown/Rate-Limiting**

**Problem:** Auto-remediate could loop infinitely if fix doesn't work

**Solution:** `cooldown_minutes` parameter suppresses re-execution within window

**Implementation:**
```python
is_rule_in_cooldown(rule_id, event_id, source, cooldown_minutes):
    cutoff = now - cooldown_minutes
    SELECT COUNT(*) FROM remediation_history h
    WHERE h.rule_id = ? AND h.status IN ('success', 'failed')
      AND h.timestamp > cutoff
```

**Example:**
```python
# This rule can execute at most once per 60 minutes
add_rule(..., cooldown_minutes=60)
```

---

### **8. Approval Workflow**

**Problem:** Some remediations are risky (restart critical service, reboot system)

**Solution:** Require manual approval before execution

**Implementation:**
```python
# auto_remediate=0 → create remediation_request
create_remediation_request(event_row_id, rule_id, requested_by='system')

# Operator reviews in dashboard
operator_approves(request_id)

# Then run_remediation() executes
run_remediation(event_row_id, rule_id)
```

---

### **9. Unified Logging (Flask + Task Scheduler)**

**Problem:** Events processed by both Flask (polling) and Task Scheduler (event-triggered);
operator can't see full picture

**Solution:** Both write to same `remediation_system.log` file with process tags

**Format:**
```
[2026-05-05 14:32:10] [INFO] [FLASK] Event 7031 ingested
[2026-05-05 14:32:12] [INFO] [EVENT-MONITOR] Rule 5 matched
[2026-05-05 14:32:15] [INFO] [TASK-SCHEDULER] Event 1000 processed from event trigger
```

**Dashboard:** `/api/monitor/log` endpoint serves last N lines of unified log

---

### **10. Context Injection (Environment Variables)**

**Problem:** PowerShell scripts need event data (what service crashed? which file is missing?)

**Solution:** Pass event details as environment variables before execution

**Implementation:**
```python
env['RM_EVENT_ID'] = '7031'
env['RM_SOURCE'] = 'Service Control Manager'
env['RM_MESSAGE'] = 'Service X terminated'
env['RM_MATCH_service_name'] = 'X'  # From regex captures

# PowerShell accesses via:
$service_name = $env:RM_SOURCE
$message = $env:RM_MESSAGE
```

**Regex Captures:**
```python
# Rule message_regex: r'Service (?P<service_name>\w+) terminated'
# Capture groups become RM_MATCH_* env vars
env['RM_MATCH_service_name'] = 'ServiceName'
```

---

---

## Performance & Scalability Considerations

### **Event Processing Throughput**
- **Polling Mode:** 30-second intervals, max 50 events/poll → ~100 events/min max
- **Task Scheduler Mode:** Near-instantaneous (1-2 second delay from event occurrence to processing)
- **Database:** SQLite; designed for single-machine use; indexes on (event_id, source, timestamp)

### **Memory Footprint**
- Flask process: ~80-120 MB
- PowerShell collector: ~30 MB
- Database cache: Variable, depends on event history size

### **Scalability Limitations**
- **Single-machine only:** SQLite not suitable for multi-machine deployments
- **Future:** Could refactor to use PostgreSQL/MySQL for central dashboard with multiple collectors

---

## Summary Table: Critical Functions Reference

| Function | Module | Purpose | Input | Output | Critical For |
|----------|--------|---------|-------|--------|--------------|
| `add_event()` | models | Smart event ingestion | Event data | DB row ID | Event processing |
| `calculate_confidence_score()` | models | Urgency ranking | Event dict | 0-100 score | Prioritization |
| `correlate_events()` | models | Multi-event inference | Event ID + time | Compound cause | Root cause detection |
| `match_rules_for_event()` | models | Rule matching | Event dict | List of rules | Remediation selection |
| `run_remediation()` | models | Execute fix script | Event ID + rule ID | Status + output | Remediation execution |
| `detect_faulting_module()` | models | Extract DLL name | Error message | Module name or None | Deep repair detection |
| `_fetch_windows_events()` | event_log_monitor | Query Event Log | Timestamp | List of events | Event collection |
| `_process_event()` | event_log_monitor | Complete pipeline | Raw event JSON | DB insert + remediation | End-to-end processing |
| `analyze_event()` | root_cause_analyzer | Variant detection | Event dict | List of variants | Root cause classification |
| `register_variant_pattern()` | root_cause_analyzer | Add custom variant | Pattern definition | None (side effect) | User customization |

---

## Deployment Architecture

### **Single Machine (Default)**
```
┌─ Windows Machine ─────────────────────┐
│ ┌─ Python Backend (Flask) ──────────┐ │
│ │ app.py (port 5000)                │ │
│ │ event_log_monitor.py (polling)    │ │
│ │ rules.db (SQLite)                 │ │
│ └───────────────────────────────────┘ │
│ ┌─ PowerShell Collector ────────────┐ │
│ │ event_monitor.ps1 (polling)       │ │
│ │ OR Task Scheduler (event-triggered)│ │
│ └───────────────────────────────────┘ │
│ ┌─ Flutter Dashboard (Web) ─────────┐ │
│ │ http://localhost:5000             │ │
│ │ (or Flutter Windows app)          │ │
│ └───────────────────────────────────┘ │
│ ┌─ PowerShell Remediation Scripts ──┐ │
│ │ Error7031_*.ps1, Remediate_*.ps1  │ │
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘
```

### **Multi-Machine (Future)**
```
┌─ Central Management Server ─────────────┐
│ Central Flask + PostgreSQL              │
│ Aggregated dashboard                    │
└────────────────────────────────────────┘
                    │
        ┌───────────┼───────────┐
        │           │           │
        ▼           ▼           ▼
    ┌──────┐   ┌──────┐   ┌──────┐
    │Server│   │Server│   │Server│
    │  A   │   │  B   │   │  C   │
    │      │   │      │   │      │
    │Coll. │   │Coll. │   │Coll. │
    │Events│   │Events│   │Events│
    └──────┘   └──────┘   └──────┘
```

---

This comprehensive analysis covers the complete architecture, data flow, functions, and configuration of the Windows Auto-Remediation System. All major components, their interactions, and critical algorithms are documented with examples and reference tables.

