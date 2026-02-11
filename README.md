# Rule-Based Auto Remediation (Windows)

Lightweight PoC dashboard and collector for auto-remediation driven by Windows Event Logs.

## Features
- **Live Event Monitoring**: Real-time connection to Windows Event Viewer for automatic event detection
- **Event Collection**: Collect and monitor Windows Event Log entries (System, Application, Security, etc.)
- **Rule-Based Remediation**: Define rules to automatically remediate common issues
- **Event Definitions**: Pre-loaded with 40+ common Windows error events from `windows_error_events.json`
- **Metadata Enrichment**: Events are automatically enriched with category, severity, description, and recommended actions
- **Approval Workflow**: Manual approval process for sensitive remediation actions
- **Web Dashboard**: Modern, responsive UI with statistics, charts, and real-time monitoring
- **Background Service**: Run as Windows Scheduled Task for continuous monitoring

## Prerequisites

- **Windows OS** (Windows 10/11 or Windows Server 2016+)
- **Python 3.8+** installed and added to PATH
- **PowerShell 5.1+** (comes with Windows)
- **Administrator privileges** (for event monitoring and remediation)

## Quick Start Guide

### Step 1: Clone or Download the Project

```bash
# If using Git
git clone <repository-url>
cd Rule-Based-Auto-Remediation-For-Windows-

# Or download and extract the ZIP file, then navigate to the folder
```

**📍 Location:** Run this in your desired project directory (e.g., `C:\Projects\`)

---

### Step 2: Setup Python Environment

**📍 Location:** Open **Command Prompt** or **PowerShell** in the project root directory

```bash
# Create a virtual environment
python -m venv .venv

# Activate the virtual environment
.\.venv\Scripts\activate

# You should see (.venv) in your prompt now

# Install required Python packages
pip install -r backend\requirements.txt
```

**Expected Output:**
```
Successfully installed Flask-3.x.x SQLAlchemy-2.x.x ...
```

**Troubleshooting:**
- If `python` command not found, try `py` or `python3`
- If activation fails, run: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`

---

### Step 3: Initialize the Database

**📍 Location:** Same terminal (with virtual environment activated)

```bash
python backend\db_init.py
```

**Expected Output:**
```
Database initialized successfully!
Database location: backend/events.db
```

**What this does:**
- Creates `backend/events.db` SQLite database
- Creates tables: events, rules, remediation_history, remediation_requests
- Applies schema migrations if needed

---

### Step 4: Start the Flask Backend

**📍 Location:** Same terminal (keep this terminal open)

```bash
python backend\app.py
```

**Expected Output:**
```
 * Running on http://127.0.0.1:5000
 * Running on http://localhost:5000
Press CTRL+C to quit
```

**⚠️ Important:** Keep this terminal window open! The backend must be running for the system to work.

---

### Step 5: Open the Web Dashboard

**📍 Location:** Open your web browser

Navigate to: **http://localhost:5000**

**What you'll see:**
- Dashboard tab with statistics and charts
- Events tab (empty initially)
- Event Catalog tab (40+ event definitions)
- Rules tab (empty initially)
- Approvals tab
- History tab

---

### Step 6: Import Event Rules from JSON

**📍 Location:** In the web dashboard (http://localhost:5000)

**Method 1: Using the Dashboard (Recommended)**
1. Click on the **"Rules"** tab
2. Click the **"Import from JSON"** button at the top
3. Wait for the success message
4. You should see multiple rules imported

**Method 2: Using API (Alternative)**

**📍 Location:** Open a **new terminal** (keep backend running in the first one)

```bash
curl -X POST -H "Content-Type: application/json" http://localhost:5000/api/populate-rules
```

Or using PowerShell:
```powershell
Invoke-RestMethod -Uri "http://localhost:5000/api/populate-rules" -Method Post
```

**What this does:**
- Imports rules for all events marked as `auto_remediate_candidate: true` in `windows_error_events.json`
- Creates approximately 20+ rules automatically

---

### Step 7: Start Live Event Monitoring

**📍 Location:** Open a **new terminal/PowerShell window** (keep backend running)

**Option A: Quick Start with Batch File (Easiest)**

**📍 Location:** Double-click `start_event_monitor.bat` in the project root folder

Or from Command Prompt:
```cmd
start_event_monitor.bat
```

**Expected Output:** A new PowerShell window opens showing:
```
========================================
Windows Event Monitor - Polling Mode
========================================
API Endpoint: http://localhost:5000/api/events
Monitoring Logs: System,Application
Poll Interval: 10 seconds
...
Starting monitoring...
```

---

**Option B: PowerShell with Configuration (Recommended for Production)**

**📍 Location:** Open **PowerShell** in the project root directory

```powershell
powershell -ExecutionPolicy Bypass -File collector\event_monitor_config.ps1
```

**Expected Output:**
```
========================================
Windows Event Monitor - Config Mode
========================================
Config File: collector\monitor_config.json
API Endpoint: http://localhost:5000/api/events
...
```

---

**Option C: PowerShell with Custom Parameters**

**📍 Location:** PowerShell in project root

```powershell
# Monitor specific logs with custom interval
powershell -ExecutionPolicy Bypass -File collector\event_monitor.ps1 -LogNames "System,Application" -PollIntervalSeconds 5

# Monitor only specific Event IDs
powershell -ExecutionPolicy Bypass -File collector\event_monitor.ps1 -EventIds "7031,7034,1000,1001" -MaxEventsPerPoll 100
```

---

**Option D: Manual Event Collection (One-time, for testing)**

**📍 Location:** PowerShell in project root

```powershell
powershell -ExecutionPolicy Bypass -File collector\collector.ps1 -MaxEvents 5 -LogName System
```

**What this does:** Collects the last 5 events from System log and sends them to the backend (one-time only, not continuous monitoring)

---

### Step 8: Verify Everything is Working

**📍 Location:** Open **PowerShell** in project root

```powershell
.\test_live_monitoring.ps1
```

**Expected Output:**
```
========================================
Live Monitoring Test Script
========================================

Step 1: Checking if backend is running...
✓ Backend is running at http://localhost:5000

Step 2: Generating test events...
✓ Created Event 1000: Test Application Error
✓ Created Event 1001: Test Application Hang
✓ Created Event 1026: Test .NET Runtime Error

Step 3: Waiting for events to be captured...
Waiting 15 seconds...

Step 4: Checking if events were captured...
✓ SUCCESS! Captured 3 new event(s)
```

**If test fails:**
- Make sure backend is running (Step 4)
- Make sure event monitor is running (Step 7)
- Run PowerShell as Administrator

---

### Step 9: View Events in Dashboard

**📍 Location:** Web browser at http://localhost:5000

1. Click on the **"Dashboard"** tab
   - See total events count increase
   - View charts showing events by severity and category
   - See recent events in the activity list

2. Click on the **"Events"** tab
   - See all captured events
   - Use search and filters to find specific events
   - Click on events to see details

3. Click on the **"Event Catalog"** tab
   - Browse all 40+ event definitions
   - Click "Create Rule" to create rules for specific events
   - Search and filter by severity, category, etc.

---

## Running the Complete System

**You need 2 terminal windows running simultaneously:**

### Terminal 1: Flask Backend
**📍 Location:** Project root directory
```bash
.\.venv\Scripts\activate
python backend\app.py
```
**Status:** Keep running ✅

### Terminal 2: Event Monitor
**📍 Location:** Project root directory
```cmd
start_event_monitor.bat
```
**Status:** Keep running ✅

### Browser: Web Dashboard
**📍 Location:** http://localhost:5000
**Status:** Open and refresh as needed ✅

---

## Installing as Background Service (Production)

For continuous monitoring without keeping terminal windows open:

**📍 Location:** Open **PowerShell as Administrator** in project root

```powershell
# Install as Windows Scheduled Task
.\collector\install_as_task.ps1

# Follow the prompts:
# - Task name: WindowsEventMonitor (default)
# - Run as: SYSTEM (default)
# - Start now: Y
```

**Manage the service:**
```powershell
# Start the task
Start-ScheduledTask -TaskName "WindowsEventMonitor"

# Stop the task
Stop-ScheduledTask -TaskName "WindowsEventMonitor"

# Check status
Get-ScheduledTask -TaskName "WindowsEventMonitor" | Get-ScheduledTaskInfo

# Remove the task
Unregister-ScheduledTask -TaskName "WindowsEventMonitor" -Confirm:$false
```

**Note:** The backend (Flask) still needs to run separately. Only the event monitor runs as a scheduled task.

---

## Configuration

### Event Monitor Configuration

**📍 Location:** Edit `collector\monitor_config.json`

```json
{
  "api_url": "http://localhost:5000",
  "poll_interval_seconds": 10,
  "max_events_per_poll": 50,
  "log_names": ["System", "Application"],
  "event_ids_to_monitor": [7031, 7034, 1000, 1001]
}
```

**Options:**
- `api_url`: Backend URL (change if running on different machine)
- `poll_interval_seconds`: How often to check for events (5-60 recommended)
- `max_events_per_poll`: Maximum events per check (prevent overload)
- `log_names`: Which Windows logs to monitor
- `event_ids_to_monitor`: Specific Event IDs (empty array = all events)

**After editing:** Restart the event monitor for changes to take effect

---

## Troubleshooting

### Backend won't start
```bash
# Check if port 5000 is already in use
netstat -ano | findstr :5000

# Try a different port
set FLASK_RUN_PORT=5001
python backend\app.py
```

### Event monitor can't connect to backend
```powershell
# Test if backend is running
curl http://localhost:5000/api/events

# Or in PowerShell
Invoke-RestMethod -Uri "http://localhost:5000/api/events"
```

### PowerShell execution policy error
```powershell
# Run as Administrator
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### No events being captured
1. Check if event monitor is running
2. Check if backend is running
3. Generate a test event:
   ```powershell
   Write-EventLog -LogName Application -Source "Application" -EventId 1000 -EntryType Error -Message "Test event"
   ```
4. Check Event Viewer to see if events exist

### Database errors
```bash
# Reinitialize database (⚠️ deletes all data)
python backend\db_init.py
```

---

## Complete Workflow Example

**Scenario:** Monitor for service failures and auto-remediate

1. **Start the system** (Steps 1-7 above)

2. **Create a rule for Event 7031 (Service Crash)**
   - Go to Event Catalog tab
   - Find Event 7031 (Service Control Manager)
   - Click "Create Rule"
   - Add remediation script:
     ```powershell
     # Restart the failed service
     $serviceName = "YourServiceName"
     Restart-Service -Name $serviceName -Force
     ```
   - Enable "Auto Remediate" if desired
   - Save the rule

3. **Wait for events**
   - Event monitor detects Event 7031
   - Sends to backend
   - Backend matches against rules
   - If auto-remediate enabled: runs script automatically
   - If not: creates approval request

4. **View results**
   - Check History tab for remediation results
   - Check Approvals tab for pending requests

---

## Additional Resources

- **Live Monitoring Guide:** [LIVE_MONITORING_GUIDE.md](LIVE_MONITORING_GUIDE.md)
- **Implementation Summary:** [LIVE_MONITORING_SUMMARY.md](LIVE_MONITORING_SUMMARY.md)
- **Integration Details:** [INTEGRATION_SUMMARY.md](INTEGRATION_SUMMARY.md)
- **Quick Start Guide:** [QUICK_START_GUIDE.md](QUICK_START_GUIDE.md)

## Event Definitions

The `windows_error_events.json` file contains definitions for 40+ common Windows error events including:
- **Service Failures** (Event IDs: 7031, 7034, 7000, 7001, etc.)
- **Disk Issues** (Event IDs: 2013, 51, 55, etc.)
- **Application Crashes** (Event IDs: 1000, 1001, 1026)
- **Driver Failures** (Event IDs: 219, 4101)
- **Security Events** (Event IDs: 4625, 4740)
- **Network Issues** (Event IDs: 4201, 4227, 5719)
- **System Crashes** (Event IDs: 6008, 41, 1001)
- And more...

Each event definition includes:
- `event_id`: Windows Event ID
- `event_source`: Event source/provider name
- `category`: Event category (e.g., "Service Failure", "Disk I/O Error")
- `severity`: Severity level (Critical, High, Medium, Low, Info)
- `description`: Human-readable description
- `recommended_action`: Suggested remediation action
- `auto_remediate_candidate`: Whether this event is suitable for auto-remediation

## API Endpoints

### Events
- `GET /api/events` - List all events
- `POST /api/events` - Create a new event (automatically enriched with metadata from JSON)
- `GET /api/events/<id>/matches` - Get matching rules for an event

### Rules
- `GET /api/rules` - List all rules
- `POST /api/rules` - Create a new rule
- `GET /api/rules/<id>` - Get a specific rule
- `PUT /api/rules/<id>` - Update a rule
- `DELETE /api/rules/<id>` - Delete a rule
- `POST /api/rules/<id>/run` - Manually run a rule

### Event Definitions
- `GET /api/event-definitions` - Get all event definitions from JSON
- `GET /api/event-definitions/<event_id>?source=<source>` - Get a specific event definition
- `POST /api/populate-rules` - Populate rules from JSON file

### Approvals
- `GET /api/requests` - List remediation requests
- `POST /api/requests` - Create a remediation request
- `POST /api/requests/<id>/approve` - Approve a request
- `POST /api/requests/<id>/deny` - Deny a request

### History
- `GET /api/history` - Get remediation history

## Project Structure

```
Rule-Based-Auto-Remediation-For-Windows-/
│
├── backend/                          # Flask backend application
│   ├── app.py                       # Main Flask application
│   ├── models.py                    # Database models and JSON integration
│   ├── db_init.py                   # Database initialization script
│   ├── events.db                    # SQLite database (created after init)
│   ├── requirements.txt             # Python dependencies
│   └── templates/
│       └── index.html               # Web dashboard UI
│
├── collector/                        # Event collection scripts
│   ├── collector.ps1                # One-time event collector
│   ├── event_monitor.ps1            # Polling-based monitor
│   ├── event_monitor_config.ps1     # Config-based monitor (recommended)
│   ├── event_watcher.ps1            # Subscription-based monitor
│   ├── monitor_config.json          # Event monitor configuration
│   └── install_as_task.ps1          # Scheduled task installer
│
├── windows_error_events.json        # Event definitions (40+ events)
├── start_event_monitor.bat          # Quick start batch file
├── test_live_monitoring.ps1         # Test script
│
├── LIVE_MONITORING_GUIDE.md         # Detailed monitoring guide
├── LIVE_MONITORING_SUMMARY.md       # Implementation summary
├── INTEGRATION_SUMMARY.md           # Integration documentation
├── QUICK_START_GUIDE.md             # Quick start guide
└── README.md                        # This file
```

## Security Considerations

⚠️ **Important:** This is a proof-of-concept system. Before using in production:

1. **Add Authentication**: Implement user authentication and authorization
2. **Secure API Endpoints**: Add API keys or OAuth for API access
3. **Validate Scripts**: Review all remediation scripts before enabling auto-remediation
4. **Limit Permissions**: Run with minimum required privileges
5. **Audit Logging**: Enable comprehensive logging of all actions
6. **Network Security**: Use HTTPS if accessing remotely
7. **Input Validation**: Validate all user inputs and API requests

## Notes

- This is a starter scaffold. Enhance with authentication, persistent job execution, better rule language, and safe execution controls before using in production.
- The approval workflow allows manual review of remediation actions before execution
- Events are automatically enriched with metadata from the JSON file when ingested
- Rules can be manually created or imported from the JSON file
- Live monitoring connects directly to Windows Event Viewer for real-time event detection
- Always test remediation scripts manually before enabling auto-remediation
- Monitor the system regularly and review the History tab for remediation outcomes

## Support and Contribution

For issues, questions, or contributions, please refer to the project repository.

## License

[Add your license information here]
