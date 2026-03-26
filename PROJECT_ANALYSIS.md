# Rule-Based Auto-Remediation for Windows - Complete Architecture Analysis

## Overview
This is a Windows-based event monitoring and auto-remediation system that:
1. **Monitors** Windows Event Viewer logs (especially errors/warnings)
2. **Matches** events against configured rules
3. **Auto-executes** PowerShell remediation scripts when rules match
4. **Simulates** remediation workflows for demonstration and testing
5. **Provides Web UI** for management and visualization

---

## 1. Remediation Script Implementation: Error1000_ApplicationCrash.ps1

### Location
`remediation_scripts/Error1000_ApplicationCrash.ps1`

### Full Code
```powershell
# Error1000_ApplicationCrash.ps1
# PowerShell script for analyzing and fixing Windows Event ID 1000: Application Crash
# Run as Administrator if needed for fixes.
# WARNING: Review and test in a safe environment.

$EVENT_ID = 1000
$DESCRIPTION = 'Application Crash'
$FIX_SCRIPT = 'sfc /scannow'
$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')

function Fetch-RecentErrors {
    param (
        [int]$Count = 10
    )

    $events = Get-WinEvent -LogName System -MaxEvents $Count -FilterHashTable @{ Id = $EVENT_ID; Level = 1,2 } -ErrorAction SilentlyContinue |
        Sort-Object TimeCreated -Descending

    return $events
}

function Analyze-AndFixError {
    param (
        [object]$Event
    )

    if (-not $Event) {
        Write-Host "Skipping empty event object"
        return
    }

    $eventID = $Event.Id
    $message = $Event.Message
    $time = $Event.TimeCreated

    if (-not $message) {
        $message = 'No event message available.'
    }

    Write-Host "Event ID: $eventID at $time"
    Write-Host "Message: $($message.Substring(0, [Math]::Min(100, $message.Length)))..."
    Write-Host "Classified as: $DESCRIPTION"
    Write-Host "Executing Fix: $FIX_SCRIPT"

    if ($SIMULATION_MODE) {
        Write-Host "[SIMULATION MODE] Skipping real command execution for safety."
        Write-Host "[SIMULATION MODE] Would run: $FIX_SCRIPT"
    }
    else {
        Invoke-Expression $FIX_SCRIPT
    }
    Write-Host "-------------------"
}

function Main {
    Write-Host "Fetching recent errors for Event ID $EVENT_ID..."
    $errors = Fetch-RecentErrors -Count 5

    if (-not $errors -or $errors.Count -eq 0) {
        Write-Host "No recent errors found for Event ID $EVENT_ID."
        return
    }

    foreach ($event in $errors) {
        Analyze-AndFixError -Event $event
    }

    Write-Host "Analysis and fixes complete."
}

Main
```

### How It Works

**Detection Phase:**
- Queries Windows System event log for Event ID 1000 (Application Crash)
- Filters for severity levels 1-2 (Error/Critical)
- Fetches up to 5 recent events

**Analysis Phase:**
- Extracts event metadata: ID, timestamp, message
- Truncates message to first 100 characters for readability
- Classifies event as "Application Crash"

**Remediation Phase:**
- **Actual Mode**: Executes `sfc /scannow` (System File Checker) to repair corrupted system files
- **Simulation Mode**: Logs what would be executed without actually running the command

**Environment Variable Usage:**
- Reads `$env:RM_SIMULATION_MODE` to determine actual vs simulated execution
- When injected by the backend, also receives `RM_EVENT_ID`, `RM_MESSAGE`, `RM_TIMESTAMP`, etc.

---

## 2. Simulation Feature - How It Works

### Two Simulation Endpoints

#### Endpoint 1: `/api/simulations/error1000` (POST)
**Purpose**: Basic simulation demo showing what error1000 script would do

**Request Parameters**:
```json
{
  "count": 3  // number of simulated events to generate
}
```

**Response Structure**:
```json
{
  "scenario": "Event ID 1000 - Application Crash",
  "event_id": 1000,
  "description": "Application Crash",
  "fix_script": "sfc /scannow",
  "script_path": "remediation_scripts/Error1000_ApplicationCrash.ps1",
  "simulation_mode": true,
  "generated_at": "2026-03-26T10:30:45.123456Z",
  "events": [
    {
      "event_id": 1000,
      "time_created": "2026-03-26T10:26:45.123456Z",
      "source": "Application Error",
      "description": "Application Crash",
      "message": "Faulting application name: DemoCrashApp1.exe, version: 1.0.1.0, faulting module: ntdll.dll, exception code: 0xc0000005, process id: 0x03e8",
      "message_preview": "Faulting application name: DemoCrashApp1.exe, version: 1.0..."
    }
  ],
  "timeline": [
    {
      "phase": "fetch",
      "title": "Fetch Recent Errors",
      "status": "completed",
      "detail": "Collected 3 recent System log events for Event ID 1000 (Level 1/2)."
    },
    {
      "phase": "analyze",
      "title": "Analyze Event 1",
      "status": "completed",
      "detail": "Event ID 1000 at 2026-03-26T10:26:45.123456Z classified as Application Crash."
    },
    {
      "phase": "remediate",
      "title": "Apply Fix for Event 1",
      "status": "simulated",
      "detail": "Would execute: sfc /scannow"
    }
  ],
  "terminal_output": "Fetching recent errors for Event ID 1000...\nSimulation mode ON: sfc /scannow will not be executed...",
  "summary": {
    "events_detected": 3,
    "events_analyzed": 3,
    "fixes_simulated": 3,
    "actual_fixes_executed": 0
  }
}
```

**Purpose**: Demonstrates the basic flow without integrating with the rule engine.

---

#### Endpoint 2: `/api/simulations/error1000/auto-fix` (POST)
**Purpose**: Full end-to-end simulation including rule matching and auto-remediation

**Request Parameters**:
```json
{
  "app_name": "DemoCrashApp",
  "module_name": "ntdll.dll",
  "exception_code": "0xc0000005",
  "profile": "degraded",           // "stable", "degraded", or "critical"
  "count": 1,                       // 1-5 events
  "retry_on_failure": true,
  "verify_recovery": true
}
```

**Complete Flow**:

1. **Rule Preparation**
   - Checks if a demo rule exists for Event ID 1000 + source "Application Error"
   - If not, automatically creates one with:
     - `auto_remediate=True`
     - `script_path=Error1000_ApplicationCrash.ps1`
     - `priority=20`
     - `cooldown_minutes=0`

2. **Event Creation** (for each crash)
   - Generates synthetic Event ID 1000 payload with user-provided details
   - Calls `models.add_event()` which:
     - Checks for deduplication (same event_id+source within 5 mins)
     - Calculates confidence score
     - Assigns correlation_id for incident grouping
     - Records to `data/errors_warnings.csv`

3. **Rule Matching**
   - Calls `models.match_rules_for_event(event_payload)`
   - Uses priority ordering to select matching rules
   - Checks cooldown status (if rule has cooldown_minutes set)
   - Extracts regex capture groups from message

4. **Auto-Remediation Execution**
   - **Attempt 1**: Calls `models.run_remediation(event_row_id, rule_id)` which:
     - Sets environment variables (RM_EVENT_ID, RM_MESSAGE, RM_SIMULATION_MODE, etc.)
     - Executes script via PowerShell subprocess
     - Captures stdout/stderr
     - Records result in `remediation_history` table
   
   - **Recovery Verification**: Simulates health check
     - Stable profile: 95% chance to pass
     - Degraded profile: 80% chance to pass on attempt 1
     - Critical profile: 45% chance to pass on attempt 1
   
   - **Retry Logic**: If `retry_on_failure=True` and verification fails, retry up to 2 attempts

5. **Incident Resolution Decision**
   - Event marked "resolved" if: script executed successfully AND verification passed
   - If unresolved after retries: marked for escalation

6. **Timeline Generation**
   - Records phases: prepare → detect → triage → remediate → verify → retry/escalate/close
   - Each phase tracks status: completed, suppressed, failed, warning

7. **Metrics Calculation**
   - Mean Time To Recover (MTTR) = average time from current timestamp to resolution
   - Incident resolution rate
   - Retry count
   - Suppression count

**Response Structure**:
```json
{
  "scenario": "Crash Lab - Event ID 1000 Auto-Fix",
  "simulation_mode": true,
  "event_id": 1000,
  "profile": "degraded",
  "events": [
    {
      "event_row_id": 42,
      "timestamp": "2026-03-26T10:26:45.123456Z",
      "message": "Faulting application...",
      "matches": [
        {
          "rule_id": 99,
          "rule_name": "AutoFix Demo - Event ID 1000 Application Crash",
          "auto_remediate": true,
          "cooldown_active": false
        }
      ],
      "remediations": [
        {
          "attempt": 1,
          "rule_id": 99,
          "rule_name": "AutoFix Demo - Event ID 1000 Application Crash",
          "status": "success",
          "verification_passed": true,
          "output": "[Script stdout/stderr output]"
        }
      ],
      "resolved": true
    }
  ],
  "timeline": [
    { "phase": "prepare", "title": "...", "status": "completed", "detail": "..." },
    { "phase": "detect", "title": "...", "status": "completed", "detail": "..." },
    { "phase": "triage", "title": "...", "status": "completed", "detail": "..." },
    { "phase": "remediate", "title": "...", "status": "success", "detail": "..." },
    { "phase": "verify", "title": "...", "status": "completed", "detail": "..." },
    { "phase": "close", "title": "...", "status": "completed", "detail": "..." }
  ],
  "summary": {
    "events_detected": 1,
    "events_analyzed": 1,
    "fixes_simulated": 1,
    "actual_fixes_executed": 0,
    "mean_time_to_recover_seconds": 0.15
  }
}
```

---

## 3. Frontend Simulation UI (index.html)

### Simulation Tab Structure

**Left Panel (Controls & Configuration)**:
```html
<section id="simulationTab">
  <!-- Application Name Input -->
  <input id="simulation-app-name" value="DemoCrashApp" />
  
  <!-- Faulting Module Input -->
  <input id="simulation-module" value="ntdll.dll" />
  
  <!-- Exception Code Input -->
  <input id="simulation-exception" value="0xc0000005" />
  
  <!-- Number of Events Slider -->
  <input id="simulation-count" type="number" min="1" max="5" value="1" />
  
  <!-- Incident Profile Selection -->
  <select id="simulation-profile">
    <option value="stable">Stable (quick recovery)</option>
    <option value="degraded" selected>Degraded (intermittent crashes)</option>
    <option value="critical">Critical (persistent crash loop)</option>
  </select>
  
  <!-- Recovery Options -->
  <checkbox id="simulation-retry">Enable auto-retry on failed recovery</checkbox>
  <checkbox id="simulation-verify">Verify recovery after each attempt</checkbox>
  
  <!-- Playback Controls -->
  <checkbox id="simulation-live-playback">Live step-by-step playback</checkbox>
  <select id="simulation-playback-speed">
    <option value="1.35">Fast</option>
    <option value="1" selected>Normal</option>
    <option value="0.7">Detailed</option>
  </select>
  
  <!-- Run Button -->
  <button onclick="runError1000Simulation()">Run Simulation</button>
</section>
```

**Right Panel (Results Visualization)**:

1. **Windows Crash Simulator Visual**
   - Shows desktop/window UI
   - Changes app state: "Running Normally" → "Crashed" → "Recovering" → "Running"
   - Displays crash dialog with faulting module and exception code
   - Animated progress bar during remediation

2. **Execution Timeline**
   - Visual flow chart showing phases: prepare → detect → triage → remediate → verify → escalate/close
   - Each phase shows: title, status badge (completed/failed/warning/suppressed), detail text
   - Color-coded by status

3. **Metrics Grid**
   - Resolved Incidents (count)
   - Escalated Incidents (count)
   - Retries (count)
   - Mean Recovery Time (seconds)

4. **Event + Rule Result Cards**
   - Displays detected events
   - Shows matched rules
   - Lists remediation attempts with status

5. **Simulated Script Output Terminal**
   - Shows what the PowerShell script would output
   - Line-by-line streaming (with playback speed control)

### JavaScript Flow (`runError1000Simulation()`)

```javascript
function runError1000Simulation() {
  // Collect form inputs
  const appName = document.getElementById('simulation-app-name').value;
  const moduleName = document.getElementById('simulation-module').value;
  const exceptionCode = document.getElementById('simulation-exception').value;
  const count = parseInt(document.getElementById('simulation-count').value);
  const profile = document.getElementById('simulation-profile').value;
  const retryOnFailure = document.getElementById('simulation-retry').checked;
  const verifyRecovery = document.getElementById('simulation-verify').checked;
  
  // POST to /api/simulations/error1000/auto-fix
  fetch('/api/simulations/error1000/auto-fix', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      app_name: appName,
      module_name: moduleName,
      exception_code: exceptionCode,
      count: count,
      profile: profile,
      retry_on_failure: retryOnFailure,
      verify_recovery: verifyRecovery
    })
  })
  .then(response => response.json())
  .then(data => {
    // Render timeline phases
    renderTimeline(data.timeline, getPlaybackSpeed());
    
    // Render event result cards
    renderEventResults(data.events);
    
    // Update metrics
    updateMetrics(data.summary);
    
    // Animate terminal output
    if (document.getElementById('simulation-live-playback').checked) {
      streamTerminalOutput(data.terminal_output);
    } else {
      document.getElementById('sim-terminal-output').textContent = data.terminal_output;
    }
    
    // Animate crash visual
    animateCrashVisual(data.profile, data.events.length);
  });
}
```

---

## 4. Remediation Rules Structure

### Database Schema (from db_init.py)

```sql
CREATE TABLE rules (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  event_id INTEGER,                    -- Optional: match specific Event ID
  source TEXT,                         -- Optional: match specific event source
  message_regex TEXT,                  -- Optional: regex pattern in message
  remediation_script TEXT,             -- Path to .ps1 or inline code
  script_type TEXT,                    -- 'file' (default) or 'inline'
  auto_remediate INTEGER DEFAULT 0,    -- 1 = automatically execute when matched
  stop_processing INTEGER DEFAULT 0,   -- 1 = don't check lower priority rules
  category TEXT,                       -- Event category
  severity TEXT,                       -- Event severity (Critical, High, Medium, etc.)
  description TEXT,
  recommended_action TEXT,
  priority INTEGER DEFAULT 100,        -- Lower = higher priority
  cooldown_minutes INTEGER DEFAULT 0,  -- Suppression window after execution
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
```

### How Rules Are Matched - `match_rules_for_event(event)`

**Input**: Event dictionary
```python
{
  'event_id': 1000,
  'source': 'Application Error',
  'message': 'Faulting application name...',
  'category': 'Application Crash',
  'severity': 'Medium'
}
```

**Matching Process** (AND logic):
1. Query all rules ordered by priority (ascending)
2. For each rule, check ALL conditions:
   - **Event ID check**: `rule.event_id == event.event_id` (if rule specifies)
   - **Source check**: `rule.source.lower() == event.source.lower()` (if rule specifies)
   - **Category check**: `rule.category.lower() == event.category.lower()` (if rule specifies)
   - **Severity check**: `rule.severity.lower() == event.severity.lower()` (if rule specifies)
   - **Message regex**: If regex specified, must match `event.message` and extract capture groups

3. **Cooldown check**: 
   - If rule has `cooldown_minutes > 0`, check if rule was executed in last N minutes for this event_id+source combo
   - If in cooldown, mark as `cooldown_active=True` but still return the rule

4. **Stop processing**:
   - If matched rule has `stop_processing=1`, skip all lower-priority rules

**Output**: List of matched rules with metadata
```python
[
  (
    rule_id, name, event_id, source, message_regex, 
    remediation_script, auto_remediate, category, severity, 
    description, recommended_action, script_type, priority, 
    cooldown_minutes, stop_processing,
    cooldown_active,     # Boolean added by match_rules_for_event
    regex_captures       # Dict of captured groups from regex match
  )
]
```

---

## 5. Event Creation Flow

### When Events Are Created

**Source 1: Real System Events (Event Monitor)**
- Collector PowerShell script (`collector/event_monitor.ps1`) continuously monitors System/Application logs
- Finds events matching configured filters
- Posts to `/api/events` endpoint with event data

**Source 2: Simulation**
- `/api/simulations/error1000/auto-fix` creates synthetic events
- Calls `models.add_event()` with simulation metadata

**Source 3: Manual UI Creation**
- Users can manually submit events through the Warnings tab
- Frontend forms POST to `/api/events` or `/api/events/ensure`

### `models.add_event()` Processing

**Step 1: Deduplication Check** (5-minute window)
```python
# Check if same event_id + source seen in last 300 seconds
SELECT id, dedup_count FROM events 
WHERE event_id = ? AND source = ? AND timestamp >= [5_min_ago]
```
- **If duplicate found**: Increment `dedup_count`, update `last_seen`, recalculate confidence, return existing row ID
- **If new**: Continue to step 2

**Step 2: Enrichment from JSON Catalog**
- Load event definition from `windows_error_events.json`
- Fill in missing metadata: category, severity, description, recommended_action

**Step 3: Calculate Confidence Score** (0-100 scale)
```python
score = 0
score += severity_map.get(severity)     # Up to 40 pts
score += level_map.get(level)           # Up to 20 pts
score += min(20, (dedup_count - 1) * 4) # Frequency bonus (up to 20 pts)
score += 20 if has_matching_rule else 0 # Rule exists (+20 pts)
# Result: capped at 100
```

**Step 4: Calculate Correlation ID** (for incident grouping)
```python
# Groups events from same source into 10-minute buckets
# Format: first 12 chars of MD5("{source}:{YYYYMMDDHH}{0-5}")
# All events with same correlation_id = same incident batch
```

**Step 5: Insert into Database**
```sql
INSERT INTO events (
  event_id, log_name, source, message, timestamp,
  category, severity, description, recommended_action, level,
  dedup_count, last_seen, confidence_score, correlation_id
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
```

**Step 6: Append to CSV**
- Write to `data/errors_warnings.csv` for Warnings & Errors tab

**Step 7: Update Last Processed Marker**
- Write to `data/last_processed.json` with row ID and timestamp

**Step 8: Return Row ID** for further processing

### Automatic Rule Matching & Remediation (if applicable)

After `add_event()`:

```python
matched_tuples = models.match_rules_for_event(event_data)

for rule in matched_tuples:
  if rule.auto_remediate and not rule.cooldown_active:
    models.run_remediation(event_row_id, rule.rule_id)
  elif rule.auto_remediate and rule.cooldown_active:
    models.record_remediation(event_row_id, rule.rule_id, 
                            'suppressed', 'Cooldown active')
```

---

## 6. Remediation Execution - `models.run_remediation()`

### Process Overview

**Input**:
- `event_row_id`: Database row ID of the event
- `rule_id`: Database row ID of the matching rule
- `timeout`: Default 60 seconds
- `regex_captures`: Dict of captured groups from message regex

**Step 1: Fetch Rule & Event Data**
```python
rule = get_rule(rule_id)  # Fetch rule config
event_data = get_event(event_row_id)  # Fetch event from DB
```

**Step 2: Validate & Extract Script Path**
```python
remediation_script = rule[5]  # Script path or inline code
script_type = rule[11]  # 'file' or 'inline'

if not remediation_script:
  return 'skipped'

if script_type == 'file' and not os.path.exists(remediation_script):
  return 'skipped' (file not found)
```

**Step 3: Build Environment Variables (Context Injection)**
```python
env = os.environ.copy()
env['RM_EVENT_ROW_ID'] = str(event_data.id)
env['RM_EVENT_ID'] = str(event_data.event_id)
env['RM_LOG_NAME'] = str(event_data.log_name)
env['RM_SOURCE'] = str(event_data.source)
env['RM_MESSAGE'] = str(event_data.message)
env['RM_TIMESTAMP'] = str(event_data.timestamp)
env['RM_CATEGORY'] = str(event_data.category)
env['RM_SEVERITY'] = str(event_data.severity)
env['RM_SIMULATION_MODE'] = '1' if event.log_name == 'Simulation' else '0'

# Add regex captures if any
for k, v in regex_captures.items():
  env[f'RM_MATCH_{k}'] = str(v)
```

**Step 4: Prepare Script**
```python
if script_type == 'inline':
  # Write inline code to temp file
  tmp_file = create_temp_file(remediation_script)
  script_to_run = tmp_file
else:
  # Use file path directly
  script_to_run = remediation_script
```

**Step 5: Execute via PowerShell**
```python
proc = subprocess.run(
  [
    'powershell.exe',
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', script_to_run
  ],
  capture_output=True,
  text=True,
  timeout=60,
  env=env
)
```

**Step 6: Capture & Record Result**
```python
status = 'success' if proc.returncode == 0 else 'failed'
output = proc.stdout + '\n' + proc.stderr

# Record to remediation_history table
record_remediation(event_row_id, rule_id, status, output)

return {
  'status': status,
  'output': output
}
```

**Step 7: Cleanup**
- Delete temp file if created

### Error Handling
- **Timeout**: Returns status='error', output='script timed out after 60s'
- **Exception**: Returns status='error', output=exception message

---

## 7. Complete Integration Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. EVENT COLLECTION                                              │
│                                                                   │
│ Option A: Real System (Event Monitor)                            │
│ └─> WinEvent logs → collector/event_monitor.ps1 → /api/events   │
│                                                                   │
│ Option B: Simulation                                             │
│ └─> /api/simulations/error1000/auto-fix                         │
│                                                                   │
│ Option C: Manual Entry                                           │
│ └─> UI form → /api/events                                       │
└──────────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────────┐
│ 2. EVENT INGESTION (models.add_event)                           │
│                                                                   │
│ ✓ Check deduplication (5-min window)                            │
│ ✓ Enrich metadata from JSON catalog                             │
│ ✓ Calculate confidence score                                    │
│ ✓ Calculate correlation_id (incident grouping)                  │
│ ✓ Insert into database                                          │
│ ✓ Append to errors_warnings.csv                                 │
│ ✓ Update last_processed.json                                    │
└──────────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────────┐
│ 3. RULE MATCHING (models.match_rules_for_event)                │
│                                                                   │
│ ✓ Query all rules (sorted by priority)                          │
│ ✓ Check event_id match                                          │
│ ✓ Check source match                                            │
│ ✓ Check category match                                          │
│ ✓ Check severity match                                          │
│ ✓ Check message regex + extract captures                        │
│ ✓ Check cooldown status                                         │
│ ✓ Support stop_processing short-circuit                         │
│                                                                   │
│ Output: List of matched rules with cooldown & capture info      │
└──────────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────────┐
│ 4. AUTO-REMEDIATION DECISION                                    │
│                                                                   │
│ IF rule.auto_remediate == True:                                 │
│   IF NOT rule.cooldown_active:                                  │
│     └─> Execute remediation →                                   │
│   ELSE:                                                          │
│     └─> Record 'suppressed' status                              │
│ ELSE:                                                            │
│   └─> Return matched rule info only (wait for manual approval)  │
└──────────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────────┐
│ 5. REMEDIATION EXECUTION (models.run_remediation)              │
│                                                                   │
│ ✓ Fetch rule & event data                                       │
│ ✓ Validate script exists                                        │
│ ✓ Inject environment variables (RM_* context)                   │
│ ✓ Execute PowerShell script with timeout                        │
│ ✓ Capture stdout/stderr                                         │
│ ✓ Set RM_SIMULATION_MODE=1 for simulation events               │
│ ✓ Record result in remediation_history                          │
│                                                                   │
│ Output: {status, output}                                        │
└──────────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────────┐
│ 6. RESULT & VISIBILITY                                           │
│                                                                   │
│ Dashboard: Real-time statistics                                 │
│ Warnings Tab: Event list with confidence scores                 │
│ History Tab: Remediation results                                │
│ Simulation Tab: Visual walkthrough & timeline                   │
└──────────────────────────────────────────────────────────────────┘
```

---

## 8. Key Components & Data Structures

### Event Definition (from JSON)
```json
{
  "event_id": 1000,
  "event_source": "Application Error",
  "category": "Application Crash",
  "severity": "High",
  "description": "An application crash detected",
  "recommended_action": "Run system file checker or reinstall application",
  "auto_remediate_candidate": true
}
```

### Rule Record (Database)
```python
Rule = {
  'id': 1,
  'name': 'AutoFix Demo - Event ID 1000',
  'event_id': 1000,
  'source': 'Application Error',
  'message_regex': r'Faulting application.*?0x\w+',
  'remediation_script': '/path/to/Error1000_ApplicationCrash.ps1',
  'script_type': 'file',
  'auto_remediate': True,
  'stop_processing': False,
  'category': 'Application Crash',
  'severity': 'Medium',
  'description': 'Automatic fix for app crashes',
  'priority': 20,      # Lower = higher priority
  'cooldown_minutes': 60
}
```

### Event Record (Database)
```python
Event = {
  'id': 42,
  'event_id': 1000,
  'log_name': 'System' | 'Application' | 'Simulation',
  'source': 'Application Error',
  'message': 'Faulting application name: DemoCrashApp.exe...',
  'timestamp': '2026-03-26T10:30:45.123456',
  'category': 'Application Crash',
  'severity': 'Medium',
  'description': '[enriched from JSON]',
  'recommended_action': '[enriched from JSON]',
  'level': 'Error' | 'Warning' | 'Information',
  'dedup_count': 3,              # How many times duplicated in 5-min window
  'last_seen': '2026-03-26T10:32:15.123456',
  'confidence_score': 72.5,      # 0-100 scale
  'correlation_id': 'a1b2c3d4e5f6'  # Incident batch ID
}
```

### Remediation History Record
```python
RemediationRecord = {
  'id': 101,
  'event_row_id': 42,
  'rule_id': 1,
  'status': 'success' | 'failed' | 'error' | 'skipped' | 'suppressed',
  'output': '[stdout + stderr from PowerShell]',
  'timestamp': '2026-03-26T10:31:05.123456'
}
```

---

## 9. Simulation Features & UI Interactions

### Playback Controls
- **Live Playback**: Stream timeline and output line-by-line with delay
- **Playback Speed**: 0.7x (Detailed), 1.0x (Normal), 1.35x (Fast)
- **Visual Animation**: Windows crash dialog appears/disappears, progress bar fills

### Incident Profiles
1. **Stable Profile** (Low stress)
   - Fast recovery
   - ~95% verification pass rate
   - No retries needed

2. **Degraded Profile** (Intermittent issues)
   - Moderate recovery time
   - ~80% verification pass rate on attempt 1
   - May need 1 retry

3. **Critical Profile** (Persistent crash loop)
   - Slow recovery
   - ~45% verification pass rate on attempt 1
   - ~55% chance first attempt fails (0% recovery)
   - May need 2+ retries

### Metrics Calculated
- **Resolved Incidents**: Count of incidents marked resolved
- **Escalated Incidents**: Count needing manual intervention
- **Retries**: Total number of auto-retries performed
- **MTTR**: Mean Time To Recover in seconds (average across resolved incidents)

---

## 10. Security & Isolation Features

### Simulation Mode Isolation
- Event log name set to "Simulation" (not "System" or "Application")
- Environment variable `RM_SIMULATION_MODE=1` passed to script
- Remediation scripts check this flag and skip actual execution
- Results recorded as "simulated" in history

### PowerShell Execution Safety
- Scripts run via subprocess with `ExecutionPolicy=Bypass`
- Timeout: 60 seconds max
- Output captured (no direct console interference)

### Database Isolation
- Separate DB file: `backend/rules.db`
- All modifications go through ORM functions
- Deduplication prevents event spam

### Cooldown Mechanism
- Rules can specify `cooldown_minutes` to suppress repeated execution
- Prevents rapid re-execution of same fix for recurring events
- Separate tracking of "suppressed" remediation status

---

## Summary

This is a **comprehensive Windows auto-remediation platform** that:

1. **Monitors** Windows events continuously
2. **Matches** events to configured remediation rules using multi-factor logic
3. **Auto-executes** PowerShell scripts when rules match (with safety features)
4. **Simulates** realistic crash scenarios with visual UI, timeline, and metrics
5. **Provides Web UI** for complete visibility and manual control
6. **Uses intelligent deduplication** to reduce alert fatigue
7. **Calculates confidence scores** to prioritize high-impact events
8. **Supports cooldowns** to prevent over-remediating

The Error1000 Application Crash remediation demonstrates the complete workflow: detection → analysis → simulated/actual fix with recovery verification → escalation if needed.
