# 📋 Rule-Based Auto-Remediation for Windows — Complete Project Documentation

> **Version:** 1.0.0  
> **Platform:** Windows 10/11 (Event Log + PowerShell Integration)  
> **Frontend:** Flutter Desktop (Windows) + Web  
> **Backend:** Python Flask REST API  
> **Database:** SQLite (WAL mode)

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [System Architecture](#2-system-architecture)
3. [Tech Stack & Dependencies](#3-tech-stack--dependencies)
4. [How It Works](#4-how-it-works)
5. [Core Functionality & Features](#5-core-functionality--features)
6. [Component Breakdown](#6-component-breakdown)
7. [Database Schema](#7-database-schema)
8. [API Reference](#8-api-reference)
9. [Remediation System](#9-remediation-system)
10. [Frontend UI](#10-frontend-ui)
11. [Security & Performance](#11-security--performance)
12. [File Structure](#12-file-structure)
13. [Setup & Deployment](#13-setup--deployment)
14. [Testing & Simulation](#14-testing--simulation)

---

## 1. Project Overview

The **Rule-Based Auto-Remediation for Windows** is an intelligent, real-time system that monitors Windows Event Logs, automatically detects system errors (application crashes, service failures, disk issues, memory exhaustion, network problems, security events), and executes predefined PowerShell remediation scripts to fix them — all without human intervention.

The system features a **Flutter-based desktop dashboard** that provides live visibility into system health, pending approvals, remediation history, rule management, and simulation capabilities for demonstration and testing.

### Key Differentiators

- **Real-time Windows Event Log Monitoring** via background polling thread
- **50+ Remediation Rules** covering Application, Service, Disk, Memory, Network, Firewall, Security, and System domains
- **Approval Gate Workflow** — new error types require one-time operator approval before auto-remediation
- **Closed-Loop Verification** — after remediation, the system verifies the fix held by monitoring for recurrence
- **Chronological Event Correlation Engine** — detects compound root causes (e.g., memory exhaustion causing a service crash) and applies the correct fix order
- **Deep System Repair Fallback** — detects core OS module crashes (e.g., ntdll.dll) and escalates to `sfc /scannow`
- **Root Cause Variant Detection** — identifies different root causes for the same Event ID and applies targeted remediation
- **Live Alert Popups** — real-time High CPU and Service Crash alert simulation with one-click remediation
- **24/7 Silent Protection** via Windows Task Scheduler integration

---

## 2. System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CLIENT LAYER (Flutter)                            │
│                                                                             │
│  ┌────────────┐  ┌────────────┐  ┌────────┐  ┌──────────┐  ┌───────────┐  │
│  │ Dashboard  │  │  Warnings  │  │ Rules  │  │Approvals │  │ Remediation│  │
│  │   Screen   │  │ & Errors   │  │ Screen │  │  Screen  │  │  History   │  │
│  └────────────┘  └────────────┘  └────────┘  └──────────┘  └───────────┘  │
│  ┌────────────┐  ┌────────────────┐  ┌──────────────────────────────────┐  │
│  │ Simulation │  │  Event Viewer  │  │  Live Alert Popup (Overlay)       │  │
│  │    Lab     │  │    Screen      │  │  (HighCPU / ServiceCrash)        │  │
│  └────────────┘  └────────────────┘  └──────────────────────────────────┘  │
└──────────────────────────┬──────────────────────────────────────────────────┘
                           │ HTTP REST API (JSON)
                           ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        API LAYER (Flask Backend)                            │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      app.py (Flask Server)                          │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌───────────────────┐   │   │
│  │  │ /api     │  │ /api     │  │ /api     │  │ /api/simulations/ │   │   │
│  │  │ /events  │  │ /rules   │  │ /history │  │  error1000        │   │   │
│  │  └──────────┘  └──────────┘  └──────────┘  └───────────────────┘   │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌───────────────────┐   │   │
│  │  │ /api     │  │ /api     │  │ /api     │  │ /api/simulations/ │   │   │
│  │  │ /approvals│ │ /metrics │  │ /monitor │  │  highcpu          │   │   │
│  │  └──────────┘  └──────────┘  └──────────┘  └───────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└──────────────────────────┬──────────────────────────────────────────────────┘
                           │
         ┌─────────────────┼─────────────────┐
         ▼                 ▼                  ▼
┌────────────────┐  ┌──────────────┐  ┌──────────────────┐
│   models.py    │  │  analytics   │  │  root_cause_     │
│  (Business     │  │  .py         │  │  analyzer.py     │
│   Logic + DB)  │  │  (Metrics)   │  │  (Variant        │
└───────┬────────┘  └──────────────┘  │   Detection)     │
        │                             └──────────────────┘
        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        DATA LAYER (SQLite)                                  │
│                                                                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐  ┌───────────────────────┐   │
│  │ events   │  │ rules    │  │ remediation_ │  │ approval_requests     │   │
│  │          │  │          │  │ history      │  │ approved_event_types  │   │
│  └──────────┘  └──────────┘  └──────────────┘  └───────────────────────┘   │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐  ┌───────────────────────┐   │
│  │ event_   │  │ rule_    │  │ scheduled_   │  │ task_execution_logs   │   │
│  │ root_    │  │ variant_ │  │ tasks        │  │                       │   │
│  │ cause_   │  │ assoc.   │  │              │  │                       │   │
│  │ variants │  │          │  │              │  │                       │   │
│  └──────────┘  └──────────┘  └──────────────┘  └───────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    MONITORING LAYER                                          │
│                                                                             │
│  ┌─────────────────────────────────────┐  ┌──────────────────────────────┐ │
│  │ event_log_monitor.py                │  │ task_scheduler.py            │ │
│  │  - Background polling thread        │  │  - Windows Task Scheduler   │ │
│  │  - Polls Event Log every 30s        │  │     integration              │ │
│  │  - Rule matching + auto-remediation │  │  - 24/7 silent protection   │ │
│  │  - Approval gate workflow           │  └──────────────────────────────┘ │
│  └─────────────────────────────────────┘                                   │
└─────────────────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    REMEDIATION LAYER (PowerShell)                           │
│                                                                             │
│  60+ PowerShell Scripts:                                                    │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌───────────┐   │
│  │App       │  │Service   │  │Disk      │  │Memory    │  │Network    │   │
│  │Crash     │  │Failures  │  │Errors    │  │Exhaustion│  │Issues     │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘  └───────────┘   │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌───────────┐   │
│  │Firewall  │  │Security  │  │AppLocker │  │System    │  │Remediate_ │   │
│  │Issues    │  │Events    │  │Blocks    │  │Repair    │  │Generic*   │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘  └───────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
Windows Event Log
       │
       ▼
[event_log_monitor.py] ──poll every 30s──▶ PowerShell Get-WinEvent Query
       │
       ▼
[models.add_event()] ──Deduplication Check (within 5 min window)
       │
       ├── Existing event → increment dedup_count, update last_seen
       └── New event → insert with confidence_score, correlation_id
                          │
                          ▼
              [models.correlate_events()] ── Multi-Event Inference
                          │
                          ▼
              [models.detect_faulting_module()] ── Core OS Module Check
                          │
                          ▼
              [models.match_rules_for_event()] ── Rule Matching
                          │
              ┌───────────┴───────────┐
              ▼                       ▼
        No Rule Matched          Rule(s) Matched
              │                       │
              ▼                       ├── New (event_id,source,app) → Create Approval Request
   [Manual Review Flag]               │       → Await operator approval
                                      │
                                      ├── Already Approved → Auto-Remediate
                                      │       → [run_remediation()] 
                                      │       → PowerShell Script Execution
                                      │       → [Closed-Loop Verification]
                                      │         └── Recurrence check → Rollback if failed
                                      │
                                      └── Rule in Cooldown → Skip (record suppressed)
```

---

## 3. Tech Stack & Dependencies

### Backend (Python Flask)

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **Framework** | Flask 2.3+ | REST API server |
| **WSGI Server** | Werkzeug 2.x | Development server |
| **Database** | SQLite 3 (WAL mode) | Persistent storage |
| **Environment** | python-dotenv | Configuration management |
| **HTTP Client** | requests | External API calls |
| **Testing** | pytest | Backend test suite |
| **Logging** | Python logging + RotatingFileHandler | Unified audit log |
| **Caching** | In-memory dict with TTL | Response caching for performance |

### Frontend (Flutter)

| Component | Version/Package | Purpose |
|-----------|----------------|---------|
| **Framework** | Flutter 3.0+ | Cross-platform UI |
| **Language** | Dart 3.0+ | Frontend logic |
| **HTTP** | http ^1.2.1 | API communication |
| **Charts** | fl_chart ^0.68.0 | Dashboard visualizations |
| **State Management** | provider ^6.1.2 | Reactive UI updates |
| **Fonts** | google_fonts ^8.1.0 | Typography |
| **Date/Time** | intl ^0.19.0 | Localization |
| **URL Launcher** | url_launcher ^6.3.0 | External links |

### Remediation Scripts (PowerShell)

- **Language:** PowerShell 5.1+ (built into Windows)
- **Scripts:** 60+ individual `.ps1` files for specific Event IDs
- **Execution:** Subprocess via `subprocess.run()` with environment variable injection
- **Security:** Input sanitization for PowerShell injection prevention

### Infrastructure (Windows)

| Component | Purpose |
|-----------|---------|
| **Windows Event Log** | Source of system errors |
| **PowerShell** | Event query + remediation execution |
| **Windows Task Scheduler** | 24/7 silent protection mode |
| **sfc /scannow** | System file integrity repair fallback |

---

## 4. How It Works

### Step-by-Step Operational Flow

#### 1. MONITOR — Event Log Polling

A background daemon thread (`event_log_monitor.py`) polls the Windows Event Log every **30 seconds** using PowerShell's `Get-WinEvent` cmdlet. It queries:
- **Logs:** System, Application, Security
- **Levels:** Critical (1), Error (2), Warning (3)
- **Max Events:** 50 per poll cycle

A **watermark file** (`eventlog_watermark.json`) tracks the last-processed timestamp, ensuring no events are missed or duplicated. The polling has built-in retry (3 attempts with linear backoff) and timeout (20s per invocation).

#### 2. DEDUPLICATION & INGESTION

Each event passes through `models.add_event()` which:
- Checks if an identical (event_id + source) event was seen in the last **5 minutes**
- If duplicate: increments `dedup_count`, updates `last_seen`, recalculates `confidence_score`
- If new: inserts row with computed `correlation_id` (groups events by source into 10-min buckets)
- Calculates **confidence score** (0–100) based on severity (40pts), level (20pts), frequency (20pts), and rule presence (20pts)

#### 3. CHRONOLOGICAL EVENT CORRELATION (Multi-Event Inference)

Before rule matching, the system checks if related events occurred in the same time window using `models.correlate_events()`. This detects compound root causes:

| Trigger Event | Correlated Events | Cause | Remediation |
|--------------|-------------------|-------|-------------|
| App Crash (1000) | Memory Exhaustion (2019/2020) | Free memory first | Memory → Restart App |
| Service Crash (7031) | Disk Error (11/51) | Fix disk first | Disk IO → Restart Service |
| Memory Exhaustion (2019) | System Reboot (41) | Proactive cleanup | Memory → Prevent Reboot |
| AppLocker Block (8003) | DLL Block (8004) | Policy issue | AppLocker Policy |
| Firewall Stop (5025) | App Blocked (5157) | Restart firewall | Firewall → Unblock App |

If correlated events are found, the system injects environment variables (`RM_COMPOUND_CAUSE`, `RM_COMPOUND_PRIORITY`, etc.) into PowerShell scripts so they can adapt their strategy.

#### 4. ROOT CAUSE VARIANT DETECTION

For known event IDs, the `RootCauseAnalyzer` class analyzes the event message using regex patterns to identify specific root cause **variants**:

- **Example:** Event 1003 (Service Crash) can be:
  - **HighMemoryUsage** — "out of memory", "heap allocation failed"
  - **DeadlockOrLock** — "deadlock", "lock timeout"
  - **MissingDependency** — "file not found", "missing DLL"

Each variant gets a confidence score (CERTAIN/HIGH/MEDIUM/LOW) and can be associated with specific remediation rules.

#### 5. RULE MATCHING

`models.match_rules_for_event()` iterates through all active rules sorted by priority:
- Matches on **event_id**, **source**, **category**, **severity** (AND logic)
- Tests optional **message_regex** patterns with compiled regex caching
- Checks **cooldown** status — if rule was recently executed, skip
- Returns ALL matching rules (sorted by priority ASC)

#### 6. APPROVAL GATE WORKFLOW

The first occurrence of a unique (event_id, source, app_context) combination is **held for operator approval**:
1. `create_approval_request()` creates a pending approval entry
2. The Flutter dashboard shows it in the **Approvals** tab
3. A notification badge appears with a "GO TO APPROVALS PAGE" snackbar
4. Operator can **Approve** (auto-remediate now + future occurrences) or **Reject**
5. Once approved, `mark_event_type_approved()` whitelists that combination forever

This ensures no automatic action is taken for unknown error types without an operator's explicit sign-off.

#### 7. REMEDIATION EXECUTION

`models.run_remediation()` executes the PowerShell script:
1. Records a `remediation_history` row with status **'running'**
2. Builds a sanitized environment with event context variables
3. Submits execution to a **bounded thread pool** (max 4 concurrent remediations)
4. Script runs with 60-second timeout
5. On completion, status updates to **success**, **failed**, or **error**

#### 8. CLOSED-LOOP VERIFICATION (Task 2)

After a successful remediation:
1. A background verification thread starts
2. Waits `verification_timeout_sec` (default 60s) 
3. Queries if the same (event_id, source) recurred during the window
4. **No recurrence** → Status becomes **success** with `verified_at` set
5. **Recurrence detected** → 
   - If **rollback_script** configured → Execute rollback → Status becomes **rolled_back**
   - If **no rollback** → Status becomes **verification_failed**

This prevents false positives where a script reports success but the problem persists.

#### 9. DEEP SYSTEM REPAIR FALLBACK

If an application crash (Event 1000) shows a **core Windows OS module** as the faulting module (`ntdll.dll`, `kernel32.dll`, etc.), the system bypasses normal rules and executes `Remediate_SystemRepair_Fallback.ps1` which runs `sfc /scannow`. This prevents infinite crash loops that simple restarts would cause.

#### 10. LIVE ALERT POPUPS

The Flutter dashboard polls `/api/alerts/live` every 5 seconds for high-severity simulation events. When detected:
- A floating **LiveAlertPopup** widget appears at the bottom
- Shows alert details (type, severity, message)
- One-click **"Remediate"** button executes the matching script
- Success shows a green notification: "✓ Remediation executed successfully!"

---

## 5. Core Functionality & Features

### 🔍 Event Monitoring & Detection

| Feature | Description |
|---------|-------------|
| **Real-time Windows Event Log Polling** | Background thread polls System, Application, Security logs every 30s |
| **Intelligent Deduplication** | Same event within 5 min window increments count rather than creating duplicate rows |
| **Confidence Scoring** | 0–100 score based on severity, frequency, and rule presence |
| **Chronological Correlation** | Groups related events in time windows for compound root cause detection |
| **Manual Review Flagging** | Events with no matching rule are flagged for operator review |
| **Dismissible Reviews** | Operators can dismiss review flags after assessment |

### ⚡ Auto-Remediation Engine

| Feature | Description |
|---------|-------------|
| **60+ Remediation Scripts** | Covers App Crashes, Service Failures, Disk Errors, Memory Issues, Network, Firewall, Security, AppLocker, System |
| **Priority-Ordered Rule Execution** | Rules sorted by priority; highest-priority rules run first |
| **Cooldown Suppression** | Configurable cooldown prevents repeated remediation of flapping issues |
| **Bounded Concurrency** | Max 4 simultaneous remediation executions prevent resource exhaustion |
| **Timeout Protection** | 60-second default timeout per script execution |
| **Script Types** | File-based (.ps1) and inline script execution supported |
| **Environment Injection** | 20+ environment variables provide context to remediation scripts |

### ✅ Closed-Loop Verification

| Feature | Description |
|---------|-------------|
| **Post-Remediation Verification** | Watches for problem recurrence after fix |
| **Configurable Verification Window** | Per-rule timeout (default 60s) |
| **Automatic Rollback** | If recurrence detected, executes rollback script (if configured) |
| **State Machine Tracking** | History entries progress: running → verifying → success/failed/rolled_back/verification_failed |

### 👤 Approval Gate System

| Feature | Description |
|---------|-------------|
| **Per-App Approval** | Unique (event_id, source, app_context) requires one-time operator approval |
| **Pending Approval Queue** | All pending approvals visible in dedicated dashboard tab |
| **Approve/Reject Actions** | Immediate operator decision with audit trail |
| **Auto-Remediation After Approval** | Once approved, future occurrences auto-remediate |
| **Approval Reset** | Operator can wipe the whitelist to force fresh approvals |
| **Snackbar Notifications** | Real-time popup alerts when new approvals are pending |

### 🧠 Root Cause Intelligence

| Feature | Description |
|---------|-------------|
| **Variant Detection** | Identifies different root causes for the same Event ID (e.g., memory vs deadlock vs missing dependency) |
| **Confidence-Based Classification** | Pattern matching with weighted scoring for CERTAIN/HIGH/MEDIUM/LOW confidence |
| **Extensible Pattern Database** | New variant patterns can be registered programmatically |
| **Variant-Specific Remediation** | Rules can be associated with specific variants for targeted fixes |

### 📊 Analytics & Observability

| Feature | Description |
|---------|-------------|
| **Success Rate Tracking** | Percentage of remediation attempts that succeeded |
| **Mean Time To Remediation (MTTR)** | Average time from event detection to successful fix |
| **MTTR Time Series** | Historical MTTR bucketed by day (14-day default window) |
| **Auto vs Manual Ratio** | Percentage of automatic vs operator-approved remediations |
| **Dashboard Statistics** | Events grouped by severity and category |
| **Intelligence Summary** | Total events, deduplicated events, suppression count, avg confidence |
| **CSV Export** | Full remediation history exportable as CSV with filters |
| **Unified Audit Log** | Single rotating log file for Flask + Task Scheduler events |

### 💻 Desktop Dashboard (Flutter)

| Feature | Description |
|---------|-------------|
| **7 Tabbed Screens** | Dashboard, Warnings & Errors, Rules, Approvals, History, Simulation Lab, Event Viewer |
| **Windows 11 Fluent Design** | Dark theme with Microsoft Fluent Design System aesthetics |
| **Live Alert Popups** | Floating overlay for High CPU and Service Crash alerts |
| **Pagination & Filtering** | Efficient data loading with offset/limit pagination |
| **Rule Management** | Create, edit, enable/disable, test, and delete remediation rules |
| **Simulation Lab** | Realistic crash/disk/eventlog/audit simulations with auto-fix demos |
| **History Search & Filter** | Search by keyword, filter by status, sort by columns, date range filtering |
| **Approval Workflow UI** | Visual approval queue with approve/reject actions |
| **Global Error Boundary** | Individual widget failures don't crash the entire app |

### 🔬 Simulation Lab

| Feature | Description |
|---------|-------------|
| **Application Crash (1000)** | Simulates faulting app with configurable count, profile, app name |
| **Low Disk Space (2013)** | Simulates multiple drives with critically low space |
| **Event Log Shutdown (1100)** | Simulates Event Log service failure |
| **Audit Events Dropped (1101)** | Simulates audit log capacity issues |
| **High CPU Alert (live)** | Real-time alert injection with one-click remediation |
| **Service Crash (live)** | Real-time service failure alert with one-click remediation |
| **Root Cause Variants Demo** | Shows 3 different variants of same error with targeted remediation |
| **Configurable Profiles** | Stable/Degraded/Critical profiles affect verification success probability |
| **Retry & Verification** | Automatic retry on failure with post-remediation health checks |
| **MTTR Calculation** | Simulated mean-time-to-recover metrics |

### 🛡️ 24/7 Silent Protection

| Feature | Description |
|---------|-------------|
| **Windows Task Scheduler Integration** | Always-on protection independent of Flask backend |
| **Zero CPU When Idle** | Task Scheduler events trigger only on actual Windows events |
| **Survives Reboots** | Tasks persist across system restarts |
| **8+ Predefined Tasks** | Covers app crashes, service failures, disk errors, NTFS corruption |
| **Task Status API** | Query real Windows Task Scheduler status via `schtasks` |

---

## 6. Component Breakdown

### 6.1 Backend Components

#### `app.py` — Flask REST API Server
- **Routes:** 50+ API endpoints organized by resource
- **CORS:** Whitelist-based origin validation (security)
- **Input Validation:** Schema-based validation for all POST/PUT endpoints
- **Caching:** 30-60s TTL caches for metrics, intelligence summary, dashboard stats, event count
- **Startup:** Inits DB, starts monitor thread (unless Task Scheduler mode), loads Flutter web build
- **Serves:** Flutter Web build at `/` when available, fallback to template

#### `models.py` — Business Logic & Data Layer
- **Database:** Centralized SQLite connection with WAL mode, 30s busy timeout
- **Event Operations:** Add, get, paginate, deduplicate, manual review, dismiss
- **Rule Operations:** CRUD, matching, cooldown checks, variant associations, hit stats
- **Remediation:** Execute scripts, record history, update statuses, verify closed-loop
- **Approval Gate:** Create requests, approve/reject, check status, reset all
- **Correlation Engine:** Multi-event inference with compound cause detection
- **Root Cause Detection:** Faulting module extraction, core OS module detection, system repair escalation
- **Security:** PowerShell injection sanitization, ReDoS protection, input validation
- **Performance:** LRU regex caching, event count caching, paginated queries

#### `event_log_monitor.py` — Background Monitor Thread
- **Polling:** 30-second interval with watermark persistence
- **PowerShell Integration:** EncodedCommand for multi-line scripts, retry logic (3 attempts)
- **Event Processing:** Deduplication, enrichment, correlation, rule matching, auto-remediation
- **Approval Workflow:** Creates approval requests for new (event_id, source, app) combos
- **Deep Repair:** Core OS module detection escalates to system integrity check
- **Error Handling:** Hardened loop prevents thread exit on any exception
- **State Tracking:** Public `get_status()` and `trigger_poll()` for dashboard integration

#### `analytics.py` — Metrics & Observability
- **Success Rate:** Percentage of successful remediation attempts
- **MTTR:** Mean time to remediation with human-readable formatting
- **Time Series:** MTTR bucketed by day for historical trending
- **Auto vs Manual:** Ratio of automatic to operator-approved remediations
- **Performance:** Single-connection helpers to reduce DB connection overhead

#### `root_cause_analyzer.py` — Variant Detection
- **Pattern Database:** Event ID → variant definitions with regex patterns and weights
- **Confidence Levels:** CERTAIN (≥60), HIGH (≥40), MEDIUM (≥20), LOW (>0)
- **Context Checks:** Matches on severity, category, and other metadata fields
- **Extensible:** Custom variant patterns can be registered at runtime

#### `db_init.py` — Database Schema & Migrations
- **Schema Versioning:** Versioned migrations from v1 to v8
- **Tables Created:** events, rules, remediation_history, remediation_requests, simulation_preferences, scheduled_tasks, task_execution_logs, event_root_cause_variants, rule_variant_associations, approval_requests, approved_event_types
- **Performance Indexes:** 14+ indexes on critical query columns
- **Rule Manifest Loading:** Reads `rules_manifest.json` for declarative rule onboarding
- **Self-Healing:** Runs on every startup, applies missing migrations, rebuilds legacy structures

### 6.2 Frontend Components

#### `main.dart` — Application Entry Point
- **Global Error Boundary:** Custom error widget replaces Flutter's red screen of death
- **Provider Setup:** ApiService, AlertPollingService, MonitorService, RemediationService
- **App Shell:** Sidebar navigation with 7 tabs + live alert layer
- **Approval Polling:** 2-second timer checking for new pending approvals with snackbar notifications

#### Screens (7 tabs)

| Screen | File | Purpose |
|--------|------|---------|
| **Dashboard** | `dashboard_screen.dart` | System health overview, stats, intelligence, metrics charts |
| **Warnings & Errors** | `events_screen.dart` | Paginated event list with filtering, manual review |
| **Rules** | `rules_screen.dart` | Full rule CRUD, enable/disable, test, priority management |
| **Approvals** | `approvals_screen.dart` | Approval gate queue with approve/reject actions |
| **History** | `history_screen.dart` | Filterable, sortable, paginated remediation history with CSV export |
| **Simulation Lab** | `simulation_screen.dart` | Crash/Disk/EventLog/Audit/HighCPU/ServiceCrash simulations |
| **Event Viewer** | `event_viewer_screen.dart` | Detailed event inspection with correlation info |

#### Services
- **`api_service.dart`** — Complete REST client with all API endpoints
- **`alert_polling_service.dart`** — Live alert polling (5s interval) with popup state management
- **`monitor_service.dart`** — Event monitor status tracking
- **`remediation_service.dart`** — Remediation event broadcasting

### 6.3 Collector (PowerShell)

The `collector/` directory contains Windows PowerShell scripts for standalone event monitoring:
- **`collector.ps1`** — Main collection loop
- **`event_monitor.ps1`** — Event log monitoring
- **`event_watcher.ps1`** — Real-time event watching
- **`event_monitor_config.ps1`** — Configuration
- **`install_as_task.ps1`** — Install as Windows Scheduled Task for 24/7 operation
- **`Load-Config.ps1`** — Configuration loader

### 6.4 Remediation Scripts (60+ PowerShell scripts)

Organized by error domain and Event ID:

| Domain | Event IDs | Example Scripts |
|--------|-----------|-----------------|
| **Application Crashes** | 1000, 1001, 1026 | `Error1000_ApplicationCrash.ps1` |
| **Service Failures** | 7000-7045 | `Error7031_ServiceTerminatedUnexpectedly.ps1` |
| **Disk Errors** | 7, 11, 51, 55, 98, 129, 140, 153 | `Error11_DiskControllerError.ps1` |
| **Memory Issues** | 2004, 2019, 2020, 26, 41 | `Error2019_NonPagedPoolMemoryExhausted.ps1` |
| **Network Issues** | 1014, 4199, 4201, 4202, 5719, 1129, 36874 | `Error1014_DNSNameResolutionTimeout.ps1` |
| **Firewall** | 5025, 5031, 5152, 5155, 5157 | `Error5025_FirewallServiceStopped.ps1` |
| **AppLocker** | 8003, 8004, 8006, 8007, 8028 | `Error8003_AppLockerBlockedExecutable.ps1` |
| **Security** | 1314, 4625, 4673, 4674, 4697, 10016 | `Error4625_LogonFailure.ps1` |
| **Event Log** | 1100, 1101 | `Error1100_EventLogShutdown.ps1` |
| **Generic Remediation** | Multiple | `Remediate_AppCrash_Live.ps1`, `Remediate_ServiceCrash.ps1` |

---

## 7. Database Schema

The system uses a **SQLite** database (`backend/rules.db`) with **WAL (Write-Ahead Logging)** mode for concurrent read/write access.

### Tables

#### `events`
| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment |
| event_id | INTEGER | Windows Event ID |
| log_name | TEXT | Log source (System/Application/Security) |
| source | TEXT | Provider name |
| message | TEXT | Event message text |
| timestamp | TEXT | ISO 8601 timestamp |
| category | TEXT | Event category |
| severity | TEXT | Critical/Error/Warning/Info |
| description | TEXT | Human-readable description |
| recommended_action | TEXT | Suggested action |
| level | TEXT | Log level |
| dedup_count | INTEGER | Number of merged occurrences |
| last_seen | TEXT | Latest occurrence timestamp |
| confidence_score | REAL | 0–100 confidence score |
| correlation_id | TEXT | 12-char MD5 hash for event grouping |
| source_type | TEXT | 'eventlog' or 'api' |
| needs_manual_review | INTEGER | Boolean flag |
| manual_review_reason | TEXT | Reason for review |
| dismissed_review | INTEGER | Boolean flag |
| root_cause_variant_id | TEXT | Detected variant ID |
| root_cause_variant_label | TEXT | Variant label text |
| root_cause_confidence | INTEGER | Variant confidence score |
| detected_root_causes | TEXT | JSON of all detected variants |
| raw_context_json | TEXT | Pristine OS event context (Phase 2) |

#### `rules`
| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment |
| name | TEXT | Rule display name |
| event_id | INTEGER | Target Event ID |
| source | TEXT | Target source/provider |
| message_regex | TEXT | Message pattern (optional) |
| remediation_script | TEXT | Path to .ps1 or inline script |
| script_type | TEXT | 'file' or 'inline' |
| auto_remediate | INTEGER | Auto-execute on match |
| stop_processing | INTEGER | Stop after this rule (advisory) |
| category | TEXT | Event category filter |
| severity | TEXT | Severity filter |
| description | TEXT | Rule description |
| recommended_action | TEXT | Suggested action |
| priority | INTEGER | Lower = higher priority (default 100) |
| cooldown_minutes | INTEGER | Suppression window (0 = no cooldown) |
| active | INTEGER | 1=enabled, 0=disabled |
| rollback_script | TEXT | Script to undo remediation |
| verification_timeout_sec | INTEGER | Verification window (default 60) |

#### `remediation_history`
| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment |
| event_row_id | INTEGER FK→events.id | Source event |
| rule_id | INTEGER FK→rules.id | Applied rule |
| status | TEXT | running/success/failed/error/suppressed/pending_approval/verifying/rolled_back/verification_failed |
| output | TEXT | Script stdout+stderr |
| timestamp | TEXT | Execution timestamp |
| verification_started_at | TEXT | When verification began |
| verified_at | TEXT | When verification completed |
| rollback_output | TEXT | Rollback script output |
| error_output | TEXT | Separated stderr |

#### `remediation_requests`
| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment |
| event_row_id | INTEGER FK→events.id | Source event |
| rule_id | INTEGER FK→rules.id | Requested rule |
| status | TEXT | pending/approved/denied |
| requested_by | TEXT | Requester identifier |
| requested_at | TEXT | Request timestamp |
| processed_by | TEXT | Processor identifier |
| processed_at | TEXT | Processing timestamp |
| decision_note | TEXT | Approval/denial note |

#### `approval_requests`
| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment |
| event_row_id | INTEGER FK→events.id | Source event |
| event_id | TEXT | Target Event ID |
| source | TEXT | Target source |
| app_context | TEXT | Application name context |
| rule_id | INTEGER FK→rules.id | Matching rule |
| rule_name | TEXT | Rule name |
| status | TEXT | pending/approved/rejected |
| created_at | TEXT | Request timestamp |
| resolved_at | TEXT | Resolution timestamp |
| resolved_by | TEXT | Resolver identifier |

#### `approved_event_types`
| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment |
| event_id | TEXT | Approved Event ID |
| source | TEXT | Approved source |
| app_context | TEXT | Approved app name |
| approved_by | TEXT | Approver identifier |
| approved_at | TEXT | Approval timestamp |
| UNIQUE(event_id, source, app_context) | | Per-app uniqueness |

#### Additional Tables
- `event_root_cause_variants` — Detected root cause variant records
- `rule_variant_associations` — Links rules to specific variants
- `simulation_preferences` — User preferences for simulation behavior
- `scheduled_tasks` — Task Scheduler task definitions
- `task_execution_logs` — Task execution history
- `schema_version` — Migration tracking

---

## 8. API Reference

### Events
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/events` | Paginated events list (limit/offset) |
| POST | `/api/events` | Create event (triggers rule matching) |
| GET | `/api/events/manual-review` | Events needing manual review |
| POST | `/api/events/<id>/dismiss-review` | Dismiss review flag |
| GET | `/api/events/<id>/history` | Remediation history for event |
| GET | `/api/events/<id>/matches` | Matching rules for event |
| POST | `/api/events/ensure` | Find or create event (no auto-remediation) |

### Rules
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/rules` | List all rules |
| POST | `/api/rules` | Create rule |
| GET | `/api/rules/<id>` | Get rule details |
| PUT | `/api/rules/<id>` | Update rule |
| DELETE | `/api/rules/<id>` | Delete rule |
| POST | `/api/rules/<id>/run` | Execute rule on event |
| POST | `/api/rules/<id>/test` | Test rule with synthetic event |
| POST | `/api/rules/<id>/toggle` | Enable/disable rule |
| GET | `/api/rules/stats` | Rule hit counts |
| GET | `/api/tasks/status` | Windows Task Scheduler status |

### History
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/history` | Paginated, filterable, sortable history |
| GET | `/api/history/export` | CSV export with filters |

### Approvals
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/approvals` | Approval request queue |
| POST | `/api/approvals/<id>/approve` | Approve + auto-remediate |
| POST | `/api/approvals/<id>/reject` | Reject approval |
| DELETE | `/api/approvals/reset` | Wipe all approvals |

### Remediation Requests
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/requests` | List requests |
| POST | `/api/requests` | Create request |
| POST | `/api/requests/<id>/approve` | Approve request |
| POST | `/api/requests/<id>/deny` | Deny request |

### Monitoring
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/monitor/status` | Monitor thread status |
| POST | `/api/monitor/trigger` | Force immediate poll |
| GET | `/api/monitor/log` | Get unified audit log |
| GET | `/api/health` | Health check |

### Analytics
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/metrics` | Success rate, MTTR, auto/manual ratio |
| GET | `/api/intelligence/summary` | Intelligence summary stats |
| GET | `/api/dashboard-stats` | Severity/category breakdown |

### Live Alerts
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/alerts/live` | Recent high-severity simulation alerts |

### Simulations
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/simulations/error1000` | Crash simulation demo |
| POST | `/api/simulations/error1000/auto-fix` | End-to-end crash auto-fix |
| POST | `/api/simulations/lowdiskspace` | Disk space demo |
| POST | `/api/simulations/lowdiskspace/auto-fix` | Disk auto-fix |
| POST | `/api/simulations/eventlog` | Event log shutdown demo |
| POST | `/api/simulations/eventlog/auto-fix` | Event log auto-fix |
| POST | `/api/simulations/auditevents` | Audit events demo |
| POST | `/api/simulations/auditevents/auto-fix` | Audit events auto-fix |
| POST | `/api/simulations/highcpu/inject` | Inject High CPU alert |
| POST | `/api/simulations/highcpu/remediate` | Remediate High CPU |
| POST | `/api/simulations/servicecrash/inject` | Inject Service Crash |
| POST | `/api/simulations/servicecrash/remediate` | Remediate Service Crash |
| POST | `/api/simulations/root-cause-variants` | Variant detection demo |
| GET/POST | `/api/simulations/preferences/<type>` | Simulation preferences |

### Tasks
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/tasks` | List scheduled tasks |
| POST | `/api/tasks` | Create task |

---

## 9. Remediation System

### Execution Engine

The remediation execution engine (`models.py`) is designed for safety, observability, and resilience:

```
remediation_worker()
    │
    ├── 1. Validate rule exists
    ├── 2. Fetch event data
    ├── 3. Build sanitized environment
    │       ├── RM_EVENT_ROW_ID, RM_EVENT_ID, RM_LOG_NAME
    │       ├── RM_SOURCE, RM_MESSAGE, RM_TIMESTAMP
    │       ├── RM_CATEGORY, RM_SEVERITY, RM_SIMULATION_MODE
    │       ├── RM_MATCH_* (regex captures)
    │       └── RM_COMPOUND_* / RM_* (correlation / escalation)
    │
    ├── 4. Record 'running' history row
    ├── 5. Submit to ThreadPoolExecutor (max 4 concurrent)
    │
    └── 6. Worker executes:
            ├── _execute_powershell() → subprocess.run()
            │       └── Script types: file (.ps1) or inline (temp file)
            │
            ├── Success?
            │   ├── YES + Approved → finalize as 'success'
            │   ├── YES + Not Approved → set 'verifying', start verification thread
            │   └── NO → set 'failed' or 'error'
            │
            └── Verification thread:
                    ├── Wait verification_timeout_sec
                    ├── Check recurrence
                    ├── No recurrence → 'success'
                    └── Recurrence → execute rollback → 'rolled_back' or 'verification_failed'
```

### PowerShell Script Environment Variables

| Variable | Source | Purpose |
|----------|--------|---------|
| `RM_EVENT_ROW_ID` | Event DB ID | Unique row identifier |
| `RM_EVENT_ID` | Event ID | Windows Event ID |
| `RM_LOG_NAME` | Log name | System/Application/Security |
| `RM_SOURCE` | Provider name | Event source |
| `RM_MESSAGE` | Message text | Event description |
| `RM_TIMESTAMP` | Timestamp | Event time |
| `RM_CATEGORY` | Category | Event category |
| `RM_SEVERITY` | Severity | Critical/Error/Warning |
| `RM_SIMULATION_MODE` | Simulation | 1 if simulation event |
| `RM_MATCH_*` | Regex captures | Named capture groups from rule regex |
| `RM_COMPOUND_CAUSE` | Correlation | Detected compound cause |
| `RM_COMPOUND_PRIORITY` | Correlation | Priority of compound remediation |
| `RM_COMPOUND_SCRIPT` | Correlation | Suggested compound script |
| `RM_CO_EVENT_IDS` | Correlation | Comma-separated correlated event IDs |
| `RM_CO_EVENT_DOMAINS` | Correlation | Comma-separated event domains |
| `RM_CO_EVENT_COUNT` | Correlation | Number of correlated events |
| `RM_FAULTING_MODULE` | Deep Repair | Core OS module detected |
| `RM_ESCALATION_REASON` | Deep Repair | Reason for escalation |
| `RM_REQUIRES_DEEP_REPAIR` | Deep Repair | '1' if sfc needed |

### Security Measures

1. **PowerShell Injection Prevention**: `sanitize_for_powershell_env()` removes/replaces dangerous characters (`` ` ``, `$`, `|`, `;`, `()`, `&`) from all environment variables before passing to PowerShell
2. **ReDoS Protection**: Message length truncated to 10,000 characters before regex matching; compiled regex caching with `functools.lru_cache`
3. **Timeout Protection**: Scripts killed after timeout (default 60s)
4. **Bounded Concurrency**: Thread pool limited to 4 workers
5. **Input Validation**: Schema-based validation on all API inputs with max_length limits
6. **CORS Whitelist**: Only allowed origins receive CORS headers
7. **Output Truncation**: CSV export truncates output to 500 chars

---

## 10. Frontend UI

### Design System
- **Theme:** Windows 11 Fluent Design dark theme
- **Colors:** Deep blacks (#0D0D0D), card grays (#1A1A1A), blue accent (#0078D4), green (#107C10), red (#E74856)
- **Typography:** Google Fonts (Lato)
- **Layout:** Fixed sidebar (80px) + content area with header
- **Animations:** Ambient glow blobs, gradient backgrounds, smooth transitions

### UI Components
- **`AppSidebar`** — Icon-based vertical navigation with active tab highlighting
- **`AppHeader`** — Screen title with refresh-all button
- **`FluentCard`** — Dark card component with border
- **`FluentStatCard`** — Metric display with gradient icon
- **`LiveAlertPopup`** — Floating alert overlay with remediate button
- **`AlertBadge` / `RuleBadge`** — Severity/status indicators
- **`EmptyState`** — Friendly empty data display
- **`ScrollHint`** — Scroll indicator for overflow content

---

## 11. Security & Performance

### Security Hardening

| Area | Measure |
|------|---------|
| **PowerShell Injection** | Environment variable sanitization (removes `$`, `|`, `;`, `` ` ``, `()`, `&`) |
| **ReDoS Prevention** | Message truncation to 10k chars, cached compiled regex |
| **Input Validation** | Schema-based validation with max_length on all API inputs |
| **CORS** | Whitelist-based origin validation (no wildcard) |
| **DB Concurrency** | WAL journal mode, 30s busy timeout |
| **Output Truncation** | 500-char limit on CSV export outputs |

### Performance Optimizations

| Area | Measure |
|------|---------|
| **Regex Caching** | `functools.lru_cache(maxsize=256)` for compiled patterns |
| **Response Caching** | 30-60s TTL caches for metrics, stats, intelligence, event count |
| **Pagination** | All list endpoints use offset/limit pagination (capped at 100-200) |
| **Database Indexes** | 14+ indexes on events, rules, history, variants tables |
| **Bounded Thread Pool** | Max 4 concurrent remediation executions |
| **CSV Rotation** | Auto-rotation at 500MB or 90 days old |
| **Cleanup on Startup** | Oversized CSVs (>50MB) deleted on startup |
| **Soft Deletion** | Not used — actual DELETE for cleanup operations |

---

## 12. Project File Structure

```
Rule-Based-Auto-Remediation-For-Windows-/
│
├── setup.ps1                              # One-time environment setup
├── run_backend.ps1                         # Start Flask backend
├── run_frontend.ps1                        # Start Flutter desktop app
├── start_event_monitor.bat                # Windows Event Log monitor launcher
├── simulate_crash.ps1                      # Safe crash simulator for demos
├── simulate_service_not_starting.ps1       # Service failure simulator
├── simulate_crash.ps1                      # Generic crash simulator
├── demo_real_crash.ps1                     # Real crash demonstration script
├── test_pipeline_e2e.ps1                   # End-to-end pipeline test
├── debug_check.py                          # Debug utility
├── .gitignore                              # Git ignore rules
│
├── backend/                                # Python Flask Backend
│   ├── app.py                              # Flask server + all API routes
│   ├── models.py                           # Business logic, DB queries, remediation engine
│   ├── db_init.py                          # DB schema & migrations
│   ├── event_log_monitor.py                # Background Event Log poller
│   ├── analytics.py                        # Metrics & observability
│   ├── root_cause_analyzer.py              # Root cause variant detection
│   ├── task_scheduler.py                   # Windows Task Scheduler management
│   ├── cli_process_event.py                # CLI event processing
│   ├── generate_rules_manifest.py          # Rules manifest generator
│   ├── populate_regex_patterns.py          # Regex pattern populator
│   ├── populate_rules.py                   # Rules populator
│   ├── requirements.txt                    # Python dependencies
│   ├── rules_manifest.json                 # Declarative rule definitions
│   ├── pytest.ini                          # Test configuration
│   ├── data/                               # Logs, CSVs, watermarks (auto-created)
│   ├── tests/                              # Test suite
│   │   ├── conftest.py
│   │   ├── test_api.py
│   │   └── test_models.py
│   └── templates/index.html                # Legacy web template
│
├── frontend/                               # Flutter Desktop/Web App
│   ├── pubspec.yaml                        # Dependencies
│   ├── lib/
│   │   ├── main.dart                       # Entry point, app shell, provider setup
│   │   ├── config/
│   │   │   ├── api_config.dart             # API URL configuration
│   │   │   └── theme.dart                  # Fluent Design dark theme
│   │   ├── models/
│   │   │   ├── event.dart                  # Event data model
│   │   │   ├── rule.dart                   # Rule data model
│   │   │   ├── alert.dart                  # Live alert model
│   │   │   ├── approval_request.dart       # Approval request model
│   │   │   ├── history_entry.dart          # History entry model
│   │   │   ├── intelligence_summary.dart   # Intelligence summary model
│   │   │   └── metrics_summary.dart        # Metrics summary model
│   │   ├── screens/
│   │   │   ├── dashboard_screen.dart       # Dashboard with stats & charts
│   │   │   ├── events_screen.dart          # Warnings & Errors list
│   │   │   ├── event_viewer_screen.dart    # Detailed event view
│   │   │   ├── rules_screen.dart           # Rule management
│   │   │   ├── approvals_screen.dart       # Approval queue
│   │   │   ├── history_screen.dart         # Remediation history
│   │   │   ├── simulation_screen.dart      # Simulation lab
│   │   │   └── task_scheduler_screen.dart  # Task scheduler view
│   │   ├── services/
│   │   │   ├── api_service.dart            # REST API client
│   │   │   ├── alert_polling_service.dart   # Live alert polling
│   │   │   ├── monitor_service.dart        # Monitor status
│   │   │   └── remediation_service.dart    # Remediation events
│   │   ├── utils/
│   │   │   └── time_fmt.dart               # Time formatting utilities
│   │   └── widgets/
│   │       ├── badges.dart                 # Status/severity badges
│   │       ├── empty_state.dart            # Empty data placeholder
│   │       ├── fluent_button.dart          # Fluent-styled buttons
│   │       ├── fluent_card.dart            # Card component
│   │       ├── fluent_stat_card.dart       # Stat display card
│   │       ├── header.dart                 # Screen header
│   │       ├── live_alert_popup.dart       # Live alert overlay
│   │       ├── scroll_hint.dart            # Scroll indicator
│   │       ├── sidebar.dart                # Navigation sidebar
│   │       └── fluent_sidebar.dart         # Enhanced sidebar variant
│   ├── web/                                # Web build output
│   ├── windows/                            # Windows desktop build
│   └── test/                               # Frontend tests
│
├── remediation_scripts/                    # 60+ PowerShell scripts
│   ├── Error1000_ApplicationCrash.ps1       # App crash remediation
│   ├── Error7031_ServiceTerminatedUnexpectedly.ps1
│   ├── Error11_DiskControllerError.ps1
│   ├── Error2019_NonPagedPoolMemoryExhausted.ps1
│   ├── Error4625_LogonFailure.ps1
│   ├── (50+ more per-event scripts)
│   ├── Remediate_AppCrash_Live.ps1         # Live app crash fix
│   ├── Remediate_ServiceCrash.ps1          # Service restart
│   ├── Remediate_MemoryExhaustion.ps1      # Memory cleanup
│   ├── Remediate_DiskIOError.ps1           # Disk error fix
│   ├── Remediate_SystemRepair_Fallback.ps1  # sfc /scannow repair
│   ├── (Generic remediate scripts)
│   ├── Simulate_* scripts                   # Simulation scripts
│   └── REMEDIATION_SCRIPTS_GUIDE.md         # Script documentation
│
├── collector/                               # PowerShell Event Collector
│   ├── collector.ps1
│   ├── event_monitor.ps1
│   ├── event_watcher.ps1
│   ├── event_monitor_config.ps1
│   ├── install_as_task.ps1
│   ├── Load-Config.ps1
│   └── monitor_config.json
│
└── windows_error_events.json                # Windows error metadata catalog
```

---

## 13. Setup & Deployment

### Prerequisites
- **Windows 10/11** (Event Log + PowerShell integration is Windows-only)
- **Python 3.10+** (on PATH)
- **PowerShell 5.1+** (built into Windows)
- **Flutter SDK** (for desktop UI — requires Visual Studio with "Desktop development with C++")
- **Administrator privileges** (to read Security log and execute remediation)

### Quickstart
```powershell
# 1. One-time setup
powershell -ExecutionPolicy Bypass -File setup.ps1

# 2. Start backend (Administrator PowerShell, Terminal 1)
powershell -ExecutionPolicy Bypass -File run_backend.ps1

# 3. Start desktop app (Terminal 2)
powershell -ExecutionPolicy Bypass -File run_frontend.ps1
```

### 24/7 Silent Mode
```powershell
# Install event-triggered tasks (run as Administrator)
powershell -ExecutionPolicy Bypass -File remediation_scripts\Setup_EventTriggers.ps1

# Then set USE_TASK_SCHEDULER=true in .env and restart backend
```

### Simulation Demo
```powershell
# Simulate an app crash
.\simulate_crash.ps1 -AppName "notepad"

# Simulate service crash
.\remediation_scripts\Simulate_ServiceCrash.ps1

# Test all active rules
.\remediation_scripts\Test-RemediationRules.ps1 -List
```

---

## 14. Testing & Simulation

### Backend Tests
- **Framework:** pytest
- **Test files:** `backend/tests/test_api.py`, `backend/tests/test_models.py`
- **Config:** `backend/pytest.ini`
- **Setup:** `backend/tests/conftest.py`

### End-to-End Test
```powershell
.\test_pipeline_e2e.ps1
```

### Simulation Scripts
| Script | Purpose |
|--------|---------|
| `simulate_crash.ps1` | Safe app crash simulation (Event 1000) |
| `Simulate_ServiceCrash.ps1` | Service crash injection (Event 7034) |
| `Simulate_HighCpuAlert.ps1` | High CPU alert injection (Event 9999) |
| `Simulate_Real_Crash.ps1` | Realistic crash scenario |
| `Test-RemediationRules.ps1` | Test all rules with -List or specific -EventId |
| `demo_real_crash.ps1` | Real crash demonstration |
| `simulate_service_not_starting.ps1` | Service startup failure |
| `test_crash_notepad.ps1` | Notepad crash test |

### Known Limitations
1. **English Windows only** for real events (rule matching keys on English provider names)
2. **Microsoft Store (UWP) apps** can't be auto-relaunched
3. **Antivirus** may flag simulation scripts (terminate processes by design)
4. **Security log** requires elevated/admin PowerShell

---

> **Document Version:** 1.0  
> **Last Updated:** June 2024  
> **Author:** Auto-generated from codebase analysis

