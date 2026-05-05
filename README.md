# Rule-Based Auto Remediation for Windows

A lightweight, intelligent system for monitoring Windows Event Logs and automatically remediating common issues. Built with Flask (backend) and PowerShell (event collector), this system provides real-time monitoring, rule-based automation, and a modern dynamic & interactive web dashboard.

**🎯 Focus:** Monitors **Errors and Warnings only** (Administrative Events) - matching the "Administrative Events" view in Windows Event Viewer.

---

## ✨ Features

### Core Functionality
- **🔍 Administrative Events Monitoring**: Captures only Error (Level 2) and Warning (Level 3) events
- **⚡ Live Event Monitoring**: Real-time connection to Windows Event Viewer for automatic event detection
- **📅 Historical Import**: Import up to 30 days (10,000+ events) of errors/warnings on startup
- **🤖 Rule-Based Remediation**: Define rules to automatically remediate common issues
- **📚 Event Definitions**: Pre-loaded with 40+ common Windows error events from `windows_error_events.json`
- **🎨 Metadata Enrichment**: Events are automatically enriched with category, severity, description, and recommended actions

### User Interface
- **🎯 Modern Web Dashboard**: Responsive UI with statistics, charts, and real-time monitoring
- **🎨 Color-Coded Events**: Events color-coded by severity and category for easy identification
- **📊 Remediation Tracking**: Track when events were remediated with timestamps
- **🔄 Retractable Sidebar**: Collapsible navigation for better screen space management
- **✅ Auto-Remediate Indicators**: Visual indicators for events eligible for auto-remediation
- **➕ Quick Rule Creation**: Create rules directly from events with one click
- **🔍 Comprehensive Event Viewer**: Advanced event inspection with filtering, search, and export capabilities
- **📅 Task Scheduler Integration**: Manage Windows scheduled tasks from the dashboard

### Advanced Features
- **✅ Approval Workflow**: Manual approval process for sensitive remediation actions
- **📜 Remediation History**: Complete audit trail of all remediation actions
- **🔧 Background Service**: Run as Windows Scheduled Task for continuous monitoring
- **🌐 Multi-System Support**: Deploy centrally with monitors on multiple machines
- **⚙️ Flexible Configuration**: Environment-based configuration for easy deployment

---

## � Project Organization

**Recent updates (v2.0):**
- ✅ All build and startup scripts consolidated in `build_scripts/` folder
- ✅ Temporary development documentation removed
- ✅ Cleaner project root with essential files only
- ✅ All `.bat` files centralized for easy management

**Key locations:**
- **Build Scripts**: `build_scripts/` - All build and startup automation
- **Backend**: `backend/` - Flask REST API and business logic
- **Frontend**: `frontend/` - Flutter web application
- **Collector**: `collector/` - PowerShell event monitoring scripts
- **Remediation**: `remediation_scripts/` - Custom remediation PowerShell scripts
- **Configuration**: `.env` - Environment configuration (create from `.env.example`)
- **Event Definitions**: `windows_error_events.json` - Pre-configured event definitions

---

## �🚀 Quick Start (New Users)

### Step 1: Clone or Download

```bash
# Using Git
git clone <repository-url>
cd Rule-Based-Auto-Remediation-For-Windows-

# Or download and extract the ZIP file
```

### Step 2: Run Automated Setup

Open **PowerShell** in the project directory and run:

```powershell
.\setup.ps1
```

**This will automatically:**
- ✅ Check Python installation
- ✅ Create virtual environment
- ✅ Install all dependencies
- ✅ Create configuration file (`.env`)
- ✅ Detect your network IP addresses
- ✅ Initialize the database

**Follow the prompts** to configure the API URL (use default for local setup).

### Step 3: Build the Flutter Web Frontend

Open **PowerShell** in the `frontend` directory and run:

```powershell
cd frontend
C:\flutter\bin\flutter build web --release
```

**Expected output:**
```
✓ Build complete. Built web application: build/web/
```

**Note:** First build takes 2-5 minutes. Subsequent builds are faster.

### Step 4: Start the Backend

In a **new terminal**, run:

```cmd
build_scripts\start_backend.bat
```

**Expected output:**
```
Starting Flask server on 0.0.0.0:5000
Access the dashboard at: http://localhost:5000
 * Running on http://0.0.0.0:5000
```

**Keep this window open!**

### Step 5: Start the Event Monitor

Open another **new terminal** and run:

```cmd
build_scripts\start_event_monitor.bat
```

**What happens:**
- Imports historical events from the last 30 days
- Starts monitoring for new events
- Sends events to the backend automatically

### Step 6: Access the Dashboard

Open your browser and go to:

```
http://localhost:5000
```

**You should see:**
- Dashboard with statistics
- Warnings & Errors tab with imported events
- Rules tab for creating remediation rules
- Approvals and History tabs

**🎉 That's it! Your system is running!**

---

## 📋 Prerequisites

- **Windows OS**: Windows 10/11 or Windows Server 2016+
- **Python 3.8+**: [Download from python.org](https://www.python.org/downloads/)
- **PowerShell 5.1+**: Comes with Windows
- **Administrator Privileges**: Required for event monitoring and remediation
- **Network Access**: If deploying across multiple machines

## 📖 Detailed Installation Guide

For detailed step-by-step instructions, see **[INSTALLATION.md](INSTALLATION.md)**

### Manual Installation (Alternative)

If you prefer manual setup or the automated script fails:

1. **Create virtual environment:**
   ```bash
   python -m venv .venv
   .\.venv\Scripts\activate
   ```

2. **Install backend dependencies:**
   ```bash
   pip install -r backend\requirements.txt
   ```

3. **Install Flutter (if building frontend):**
   ```bash
   # Download from https://flutter.dev/docs/get-started/install/windows
   # Or use: choco install flutter
   ```

4. **Build Flutter frontend:**
   ```bash
   cd frontend
   flutter build web --release
   ```

5. **Create configuration:**
   ```bash
   copy .env.example .env
   notepad .env  # Edit as needed
   ```

6. **Initialize database:**
   ```bash
   python backend\db_init.py
   ```

7. **Start backend:**
   ```cmd
   build_scripts\start_backend.bat
   ```

8. **Start monitor (new terminal):**
   ```cmd
   build_scripts\start_event_monitor.bat
   ```

---

## 🌐 Multi-System Deployment

### Centralized Monitoring Setup

Deploy the backend on one server and event monitors on multiple client machines.

**Architecture:**
```
┌─────────────────────────────────────┐
│     Central Server (Backend)        │
│     IP: 192.168.1.100:5000         │
└─────────────────────────────────────┘
              ▲
              │ Events via HTTP
      ┌───────┼───────┐
      │       │       │
  ┌───┴───┐ ┌─┴───┐ ┌─┴───┐
  │Client1│ │Client2│ │Client3│
  │Monitor│ │Monitor│ │Monitor│
  └───────┘ └───────┘ └───────┘
```

**On Central Server:**

1. Run setup and configure with server IP:
   ```powershell
   .\setup.ps1
   # When prompted, enter: http://192.168.1.100:5000
   ```

2. Configure firewall:
   ```powershell
   New-NetFirewallRule -DisplayName "Flask Backend" -Direction Inbound -LocalPort 5000 -Protocol TCP -Action Allow
   ```

3. Start backend:
   ```cmd
   start_backend.bat
   ```

**On Client Machines:**

1. Copy project files (or minimal files: `.env`, `start_event_monitor.bat`, `collector/`)

2. Create `.env` file:
   ```ini
   API_BASE_URL=http://192.168.1.100:5000
   ```

3. Start monitor:
   ```cmd
   start_event_monitor.bat
   ```

**For complete deployment instructions, see [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)**

---

## ⚙️ Configuration

All configuration is managed through the `.env` file in the project root.

### Key Configuration Options

| Variable | Default | Description |
|----------|---------|-------------|
| `FLASK_HOST` | `0.0.0.0` | Flask server host |
| `FLASK_PORT` | `5000` | Flask server port |
| `API_BASE_URL` | `http://localhost:5000` | Backend API URL |
| `POLL_INTERVAL_SECONDS` | `10` | Event polling frequency |
| `HISTORICAL_DAYS` | `30` | Days of historical events to import |
| `LOG_NAMES` | `System,Application` | Event logs to monitor |
| `EVENT_IDS_TO_MONITOR` | `` | Specific Event IDs (empty = all) |

### Example Configurations

**Local Development:**
```ini
API_BASE_URL=http://localhost:5000
FLASK_HOST=127.0.0.1
```

**Network Server:**
```ini
API_BASE_URL=http://192.168.1.100:5000
FLASK_HOST=0.0.0.0
```

**High-Frequency Monitoring:**
```ini
POLL_INTERVAL_SECONDS=5
MAX_EVENTS_PER_POLL=200
```

---

## 🧪 Testing the Installation

### Complete System Verification

Run this comprehensive test to ensure everything is working:

```powershell
# 1. Check backend is running
$response = Invoke-RestMethod -Uri "http://localhost:5000/api/events" -ErrorAction SilentlyContinue
if ($response) { Write-Host "✓ Backend API responding" -ForegroundColor Green } else { Write-Host "✗ Backend not responding" -ForegroundColor Red }

# 2. Check dashboard loads
$webCheck = Invoke-WebRequest -Uri "http://localhost:5000" -ErrorAction SilentlyContinue
if ($webCheck.StatusCode -eq 200) { Write-Host "✓ Dashboard accessible" -ForegroundColor Green } else { Write-Host "✗ Dashboard not accessible" -ForegroundColor Red }

# 3. Check history endpoint
$history = Invoke-RestMethod -Uri "http://localhost:5000/api/history" -ErrorAction SilentlyContinue
if ($history) { Write-Host "✓ History endpoint working ($(($history | Measure-Object).Count) records)" -ForegroundColor Green } else { Write-Host "✗ History endpoint failed" -ForegroundColor Red }

# 4. Check rules
$rules = Invoke-RestMethod -Uri "http://localhost:5000/api/rules" -ErrorAction SilentlyContinue
if ($rules) { Write-Host "✓ Rules endpoint working ($(($rules | Measure-Object).Count) rules)" -ForegroundColor Green } else { Write-Host "✗ Rules endpoint failed" -ForegroundColor Red }
```

### Quick Test

### Testing Auto-Remediation with History Tracking

Verify that remediation actions are immediately reflected in the History tab:

1. **Start all services** (Backend, Event Monitor, Frontend)
2. **Go to Dashboard** → Verify stats display
3. **Go to Simulation tab** → Create a test event
4. **Verify remediation happens** → Check console for "Remediation executed"
5. **Go to History tab** → Should show new remediation immediately (live update via RemediationService)

**Key Features Verified:**
- ✅ Auto-remediation executes the remediation script
- ✅ History endpoint returns type-safe data (handles mixed int/string event IDs)
- ✅ Dashboard & History screens auto-refresh using Consumer<RemediationService> pattern
- ✅ No infinite loops from continuous refreshing

### Crash Lab Simulation (Event ID 1000)

Use the built-in **Simulation tab** to test realistic application crash workflows:

**What it does:**
- Creates synthetic Event ID 1000 (`Application Error`) crash events
- Passes through rule-matching pipeline (same as live monitoring)
- Automatically executes `remediation_scripts/Error1000_ApplicationCrash.ps1`
- Shows timeline, rule matches, and script output

**Safety behavior:**
- Simulation events tagged with `log_name=Simulation`
- Scripts run in simulation-safe mode (`RM_SIMULATION_MODE=1`)
- No actual system changes applied during simulation

**How to run:**
1. Open Dashboard at `http://localhost:5000`
2. Look for **Simulation** tab (last tab on sidebar)
3. Enter app/module/exception details
4. Click **Run Simulation**
5. Watch the remediation execute and appear in History

```powershell
# Alternative: Generate a real test event
Write-EventLog -LogName Application -Source "Application" -EventId 1000 -EntryType Error -Message "Test event"
# Event appears in dashboard within 10 seconds
# Matching rules trigger auto-remediation if configured
```

### Verify Backend

```powershell
Invoke-RestMethod -Uri "http://localhost:5000/api/events"
```

### Check Event Monitor

Look at the PowerShell window - you should see:
```
[10:30:45] [OK] Event 1000 from Application
```

---

## 🎯 Using the System

### Creating Remediation Rules

1. **From Dashboard:**
   - Go to "Warnings & Errors" tab
   - Click "+ Create Rule" on any event
   - Fill in the rule details
   - Add PowerShell remediation script
   - Enable "Auto Remediate" if desired
   - Save

2. **Import from JSON:**
   - Go to "Rules" tab
   - Click "Import from JSON"
   - Pre-configured rules are imported automatically

### Example Remediation Script

```powershell
# Restart a failed service
$serviceName = "Spooler"
Restart-Service -Name $serviceName -Force
Write-Output "Service $serviceName restarted successfully"
```

### Approval Workflow

For sensitive operations:
1. Disable "Auto Remediate" on the rule
2. When event occurs, a remediation request is created
3. Go to "Approvals" tab
4. Review and approve/deny the request
5. Check "History" tab for results

### Using the Event Viewer

The **Event Viewer** tab provides a comprehensive interface for exploring and analyzing all Windows events collected by the system.

**Access the Event Viewer:**
1. Open the dashboard at `http://localhost:5000`
2. Click the **Event Viewer** tab in the sidebar
3. You'll see a table of all events with detailed filtering options

**Features:**

**🔍 Search:**
- Use the search bar to find events by any field
- Searches across: Source, Message, Severity, Category, Event ID
- Real-time filtering as you type

**📊 Advanced Filtering:**
- **Severity**: Filter by Critical, High, Medium, or Low
- **Log Name**: Filter by System, Application, Security, or Simulation events
- **Source**: Filter by event provider/source
- **Date Range**: Select start and end dates (up to 30 days back)
- **Combine Filters**: Use multiple filters together for precise results
- **Clear Filters**: Quick button to reset all active filters

**📋 Event Details:**
1. Click the **ℹ️ icon** on any event row
2. View complete event information including:
   - Event ID and Source
   - Severity and Category
   - Full message text
   - Timestamp
   - Remediation status

**📤 Export Data:**
1. Click the **⋮ menu** in the top right
2. Choose **Export as JSON** or **Export as CSV**
3. Copy the exported data for external analysis, reporting, or archiving
4. Useful for compliance, debugging, and trend analysis

**🔄 Real-Time Updates:**
- The viewer automatically refreshes every 5 seconds
- New events from the monitor appear immediately
- No manual refresh needed

**Use Cases:**
- **Troubleshooting**: Search for specific error codes or sources
- **Analysis**: Use date range filtering to analyze trends over time
- **Compliance**: Export events for audit trails and compliance reports
- **Integration**: Export data to external monitoring or SIEM systems
- **Performance**: Filter by specific categories (e.g., all Service Failures)

**Example Workflows:**

*Find all critical errors from the last 3 days:*
1. Set Severity to "Critical"
2. Click Date Range and select the past 3 days
3. Events are filtered in real-time

*Export all Application crashes for analysis:*
1. Set Log Name to "Application"
2. Set Source to "Application Error" (if available)
3. Click the menu and select "Export as CSV"
4. Open in Excel for detailed analysis

*Investigate a specific service failure:*
1. Use the search bar to find the Event ID (e.g., "7031")
2. Click the ℹ️ icon to view full details
3. Check the Message field for context
4. Use "Create Rule" button from Warnings & Errors tab to set up remediation

---

### Using the Task Scheduler

The **Task Scheduler** tab provides centralized management of Windows scheduled tasks directly from the dashboard. Create, monitor, and control remediation tasks, backend services, and monitoring agents without leaving the interface.

**Access the Task Scheduler:**
1. Open the dashboard at `http://localhost:5000`
2. Click the **Task Scheduler** tab in the sidebar
3. You'll see a table of all registered tasks with their status and execution history

**Key Features:**

**📋 Task Management:**
- **Create Tasks**: Define new scheduled tasks with custom PowerShell scripts
- **View Tasks**: Monitor all tasks, their schedules, and status
- **Edit Tasks**: Update task configuration, description, and scripts
- **Delete Tasks**: Remove tasks you no longer need
- **Enable/Disable**: Activate or pause tasks without deleting them

**⚙️ Schedule Types:**
The system supports multiple schedule types for flexibility:
- **Once**: Run the task once at a specified time
- **Hourly**: Run the task every hour
- **Daily**: Run the task at a specific time each day
- **Weekly**: Run on specific days of the week
- **Monthly**: Run on specific dates of the month

**▶️ Task Execution:**
- **Run Now**: Execute any task immediately regardless of schedule
- **View Status**: See when tasks last ran and their execution status
- **Monitor Logs**: Access detailed execution logs with output and error messages
- **Windows Integration**: Tasks are registered with Windows Task Scheduler for reliability

**📊 Task Types:**
Tasks can be categorized by purpose:
- **Backend**: Core system tasks (Flask API, database maintenance)
- **Monitor**: Event monitoring and detection tasks
- **Remediation**: Automated remediation and recovery scripts

**📝 Execution History:**
For each task, view detailed execution logs including:
- Execution timestamp
- Success/failure status
- PowerShell output
- Error messages (if any)
- Execution duration in milliseconds

**Workflow Examples:**

**Example 1: Create a Daily Backup Task**
1. Click **New Task**
2. Set Task Name: `daily_database_backup`
3. Set Display Name: `Daily Database Backup`
4. Select Type: `backend`
5. Set Schedule: `daily` at `02:00:00`
6. Enter PowerShell script:
   ```powershell
   $dbPath = "C:\Path\To\remediation.db"
   $backupPath = "C:\Backups\remediation_$(Get-Date -Format 'yyyyMMdd').db"
   Copy-Item $dbPath $backupPath
   Write-Host "Backup completed: $backupPath"
   ```
7. Click **Create**

**Example 2: Monitor Task Logs**
1. Find a task in the list
2. Click **View Logs** (📋 icon)
3. See recent executions with timestamps and status
4. Check output/error messages for troubleshooting

**Example 3: Quick Task Execution**
1. Create or find an existing task
2. Click **Run Now** (▶️ icon)
3. Task executes immediately
4. View result in the execution logs

**Best Practices:**

✅ **DO:**
- Give tasks descriptive display names
- Include detailed descriptions for documentation
- Test scripts manually before scheduling
- Check execution logs regularly
- Use appropriate schedule times (off-peak hours for heavy tasks)
- Disable tasks before deletion if you might need them later

❌ **DON'T:**
- Use overlapping task schedules that could cause conflicts
- Schedule resource-intensive tasks during peak hours
- Leave tasks without descriptions
- Ignore failed task executions without investigation
- Store sensitive data in PowerShell scripts (use environment variables)

**Common Tasks to Schedule:**

**Event Log Maintenance**
```powershell
# Clear old events
Get-WinEvent -FilterHashtable @{LogName='Application'} -MaxEvents 10000 | Where-Object {$_.TimeCreated -lt (Get-Date).AddDays(-30)} | ForEach-Object { Remove-WinEvent -EventRecord $_ }
Write-Host "Event log cleanup completed"
```

**Database Optimization**
```powershell
# Analyze and optimize the remediation database
$dbPath = "C:\Path\To\backend\remediation.db"
$sql = "ANALYZE; VACUUM;"
Write-Host "Database optimization completed"
```

**System Health Check**
```powershell
# Check system health and log status
$cpu = (Get-WmiObject -Class Win32_Processor).LoadPercentage
$mem = (Get-WmiObject -Class Win32_OperatingSystem).FreePhysicalMemory / 1MB
Write-Host "CPU Usage: $cpu%, Free Memory: {0:N2}GB" -f $mem
```

---

## 🔧 Running as Windows Service (Production)

### Backend as Service

Use NSSM (Non-Sucking Service Manager):

```cmd
nssm install AutoRemediationBackend "C:\Path\To\.venv\Scripts\python.exe" "C:\Path\To\backend\app.py"
nssm set AutoRemediationBackend AppDirectory "C:\Path\To\Project"
nssm start AutoRemediationBackend
```

### Event Monitor as Scheduled Task

```powershell
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File C:\Path\To\collector\event_monitor.ps1"
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName "AutoRemediationMonitor" -Action $action -Trigger $trigger -Principal $principal
Start-ScheduledTask -TaskName "AutoRemediationMonitor"
```

---

## 🔍 Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| **Flutter build fails** | Run `flutter clean` then rebuild, or check PATH includes Git (required by Flutter) |
| **Dashboard not updating after remediation** | Verify RemediationService is injected in main.dart, check browser console for errors |
| **History tab shows 500 error** | Backend may have type conversion issues; check `/api/history` endpoint returns valid JSON |
| **Python not found** | Try `py` or `python3`, or install from [python.org](https://www.python.org/downloads/) |
| **Port 5000 in use** | Change `FLASK_PORT` in `.env` to another port (e.g., 5001) |
| **Cannot run scripts** | Run `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser` as Administrator |
| **Backend won't start** | Check if port is available: `netstat -ano \| findstr :5000` |
| **No events appearing** | Verify monitor is running, generate test event, check PowerShell window for errors |
| **Cannot connect to backend** | Check firewall, verify API_BASE_URL in `.env`, test with `curl http://localhost:5000/api/events` |

### Generate Test Event

```powershell
Write-EventLog -LogName Application -Source "Application" -EventId 1000 -EntryType Error -Message "Test event"
```

### Verify Backend is Running

```powershell
Invoke-RestMethod -Uri "http://localhost:5000/api/events"
```

### Reset Database

```bash
# ⚠️ Warning: This deletes all data
python backend\db_init.py
```

### Check API Response Types

```powershell
# Verify history endpoint returns valid JSON with proper types
$history = Invoke-RestMethod -Uri "http://localhost:5000/api/history"
$history | ConvertTo-Json | Select-Object -First 100
# Should show event_id as numbers, not strings with "QAPRI" artifacts
```

For more troubleshooting help, see **[INSTALLATION.md](INSTALLATION.md#troubleshooting)**

---

## 📚 Documentation

- **[INSTALLATION.md](INSTALLATION.md)** - Detailed installation instructions
- **[DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)** - Multi-system deployment guide
- **[PORTABILITY_UPDATE.md](PORTABILITY_UPDATE.md)** - Portability features and changes
- **[.env.example](.env.example)** - Configuration template with all options

## 📊 Dashboard Features

### Warnings & Errors Tab
- **Level Column**: Error/Warning badges (red/yellow)
- **Event ID**: Windows Event ID
- **Source**: Event provider/source
- **Severity**: Critical/High/Medium/Low badges
- **Message**: Event description
- **Timestamp**: When the event occurred
- **Remediated**: Shows when event was fixed (green timestamp) or "Not Remediated"
- **Auto-Remediate**: Indicates if event is eligible for auto-remediation
- **Actions**: Quick "+ Create Rule" button

### Retractable Sidebar
- Click the toggle button to collapse/expand
- Icons-only mode when collapsed
- State persists across page refreshes
- Smooth animations

### Dashboard Tab
- Total events count
- Events by severity chart
- Events by category chart
- Recent activity list
- **🔄 Real-time Auto-Refresh**: Dashboard updates instantly when remediation completes
- Powered by RemediationService (Provider ChangeNotifier pattern)

### Rules Tab
- Create custom remediation rules
- Import rules from JSON
- Enable/disable auto-remediation
- Test rules manually

### Approvals Tab
- Review pending remediation requests
- Approve or deny actions
- Add decision notes

### History Tab
- Complete audit trail of all remediation actions
- Remediation success/failure status
- Script output logs
- Timestamp tracking
- **🔄 Live Updates**: Auto-refreshes immediately when new remediations complete
- **Type-Safe Data Parsing**: Robust handling of event IDs and mixed data types

### Event Viewer Tab
- **Comprehensive Event Inspection**: Full-featured event viewer with detailed event properties
- **Advanced Filtering**: Filter by Event ID, Source, Severity, Category, Date Range, and Log Name
- **Real-Time Updates**: Auto-refreshes every 5 seconds to show new events as they arrive
- **Search Functionality**: Fast full-text search across all event fields
- **Event Details**: View complete event information in an inspection modal
- **Export Capabilities**: Export filtered events as JSON or CSV for external analysis
- **Data Table View**: Sortable columns with horizontal scrolling for large datasets
- **Multi-criterion Filtering**: Combine multiple filters to narrow down events
- **Date Range Picker**: Filter events by specific date ranges (up to 30 days)
- **Clear All Filters**: Quick button to reset all active filters

### Task Scheduler Tab
- **Task Management**: Create, edit, view, and delete scheduled tasks
- **Multiple Schedule Types**: Support for once, hourly, daily, weekly, and monthly schedules
- **Task Execution**: Run tasks immediately or on schedule
- **Status Monitoring**: View real-time task status and last execution details
- **Execution Logs**: Access detailed logs for each task execution with output/errors
- **Enable/Disable**: Pause tasks without deleting them
- **Windows Integration**: Tasks automatically registered with Windows Task Scheduler
- **Task Types**: Categorize tasks (backend, monitor, remediation) for organization
- **Quick Actions**: One-click task execution, editing, and deletion
- **Script Management**: Edit PowerShell scripts directly from the UI

---

## 📋 Event Definitions

The `windows_error_events.json` file contains 40+ common Windows error events:

**Categories:**
- **Service Failures**: 7031, 7034, 7000, 7001, 7009
- **Disk Issues**: 2013, 51, 55
- **Application Crashes**: 1000, 1001, 1026
- **Driver Failures**: 219, 4101
- **Security Events**: 4625, 4740
- **Network Issues**: 4201, 4227, 5719
- **System Crashes**: 6008, 41, 1001

**Each definition includes:**
- Event ID and source
- Category and severity
- Human-readable description
- Recommended remediation action
- Auto-remediation eligibility

## 🔌 API Endpoints

The backend provides a RESTful API for integration with other systems.

### Events
| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/events` | List all events |
| `POST` | `/api/events` | Create new event (auto-enriched) |
| `GET` | `/api/events/<id>/matches` | Get matching rules |

### Rules
| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/rules` | List all rules |
| `POST` | `/api/rules` | Create new rule |
| `GET` | `/api/rules/<id>` | Get specific rule |
| `PUT` | `/api/rules/<id>` | Update rule |
| `DELETE` | `/api/rules/<id>` | Delete rule |
| `POST` | `/api/rules/<id>/run` | Manually run rule |

### Event Definitions
| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/event-definitions` | Get all definitions |
| `GET` | `/api/event-definitions/<id>` | Get specific definition |
| `POST` | `/api/populate-rules` | Import rules from JSON |

### Approvals & History
| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/requests` | List remediation requests |
| `POST` | `/api/requests` | Create request |
| `POST` | `/api/requests/<id>/approve` | Approve request |
| `POST` | `/api/requests/<id>/deny` | Deny request |
| `GET` | `/api/history` | Get remediation history |

## 📁 Project Structure

```
Rule-Based-Auto-Remediation-For-Windows-/
│
├── 📄 Configuration Files
│   ├── .env.example                 # Configuration template
│   ├── .env                         # Your configuration (created by setup)
│   └── .gitignore                   # Git ignore rules
│
├── 🚀 Quick Start Scripts & Build Tools
│   ├── setup.bat                    # Automated setup script
│   └── build_scripts/               # All build and startup scripts
│       ├── start_backend.bat        # Start Flask backend
│       ├── start_event_monitor.bat  # Start event monitor
│       ├── start_flutter_app.bat    # Start Flutter development app
│       ├── start_flutter_dev.bat    # Start Flutter dev server
│       ├── build.bat                # Build all components
│       ├── rebuild_app.bat          # Rebuild application
│       ├── simple_build.bat         # Simple build script
│       ├── flutter_build_fix.bat    # Flutter build fix
│       ├── NOW_BUILD.bat            # Immediate build
│       ├── build_no_where.bat       # Alternative build
│       ├── TaskSchedulerHelper.ps1  # Task scheduler helper functions
│       └── .env                     # Environment configuration
│
├── 🖥️ Backend (Flask Application)
│   ├── app.py                       # Main Flask REST API
│   ├── models.py                    # Database models & business logic
│   ├── db_init.py                   # Database initialization
│   ├── requirements.txt             # Python dependencies (Flask, SQLAlchemy, etc.)
│   ├── rules.db                     # SQLite database (created after init)
│   ├── templates/
│   │   └── index.html              # Redirects to Flutter web build
│   ├── data/
│   │   ├── errors_warnings.csv     # Event data export
│   │   ├── eventlog_watermark.json # Event collection bookmark
│   │   └── last_processed.json     # Monitoring state
│   └── __pycache__/                # Python bytecode cache
│
├── 📡 Collector (PowerShell Scripts)
│   ├── event_monitor.ps1            # Main event monitoring script
│   ├── Load-Config.ps1              # Configuration loader
│   ├── collector.ps1                # One-time event collector
│   ├── event_monitor_config.ps1     # Config-based monitor
│   ├── event_watcher.ps1            # Subscription-based monitor
│   ├── install_as_task.ps1          # Scheduled task installer
│   └── monitor_config.json          # Monitoring configuration
│
├── 🎨 Frontend (Flutter Web Application)
│   ├── lib/
│   │   ├── main.dart                # App entry point
│   │   ├── services/
│   │   │   ├── api_service.dart     # REST API client
│   │   │   ├── remediation_service.dart  # Auto-remediation state management
│   │   │   └── monitor_service.dart # Event monitoring service
│   │   ├── screens/
│   │   │   ├── dashboard_screen.dart
│   │   │   ├── events_screen.dart
│   │   │   ├── event_viewer_screen.dart  # Comprehensive event viewer
│   │   │   ├── task_manager_screen.dart  # Task scheduler management
│   │   │   ├── rules_screen.dart
│   │   │   ├── approvals_screen.dart
│   │   │   ├── history_screen.dart
│   │   │   └── simulation_screen.dart
│   │   ├── models/                  # Data models
│   │   └── widgets/                 # Reusable UI components
│   ├── build/web/                   # Compiled Flutter web app
│   ├── pubspec.yaml                 # Flutter dependencies
│   └── README.md                    # Frontend-specific docs
│
├── 📚 Documentation
│   ├── README.md                    # This file (overview & quick start)
│   ├── INSTALLATION.md              # Detailed installation guide
│   ├── DEPLOYMENT_GUIDE.md          # Multi-system deployment
│   ├── PORTABILITY_UPDATE.md        # Portability features
│   └── SIDEBAR_AND_REMEDIATED_UPDATE.md  # UI features
│
├── 📋 Data Files
│   └── windows_error_events.json   # Event definitions (40+ events)
│
└── 🔧 Remediation Scripts
    └── remediation_scripts/         # Sample remediation scripts
```

## 🛠️ Technology Stack

| **Frontend** | Flutter 3.41.6 (Dart → Web), Provider package (v6.1.5+1), Material UI |
| Component | Technology |
| **Backend** | Python 3.8+, Flask 2.3.2, SQLAlchemy |
| **Database** | SQLite |
| **Event Collection** | PowerShell 5.1+ |
| **Build System** | Flutter build web --release |
| **State Management** | Provider ChangeNotifier pattern |
| **Data Format** | JSON, CSV |
| **Configuration** | Environment Variables (.env) |
| **Deployment** | Windows Scheduled Tasks, NSSM |

---

## 🔒 Security Considerations

⚠️ **Important:** This is a proof-of-concept system. Before using in production:

### Required Security Enhancements
1. **Add Authentication**: Implement user authentication and authorization
2. **Secure API Endpoints**: Add API keys or OAuth for API access
3. **Validate Scripts**: Review all remediation scripts before enabling auto-remediation
4. **Limit Permissions**: Run with minimum required privileges
5. **Audit Logging**: Enable comprehensive logging of all actions
6. **Network Security**: Use HTTPS if accessing remotely
7. **Input Validation**: Validate all user inputs and API requests

### Built-in Security Features
- ✅ **Approval Workflow**: Manual approval for sensitive operations
- ✅ **Audit Trail**: Complete history of all remediation actions
- ✅ **Remediation Tracking**: Timestamp tracking for all actions
- ✅ **Event Filtering**: Only Errors and Warnings are processed

### Production Recommendations
- 🔐 Use HTTPS instead of HTTP
- 🔐 Configure firewall rules to restrict access
- 🔐 Use Group Managed Service Accounts (gMSA)
- 🔐 Implement rate limiting
- 🔐 Regular security audits of remediation scripts

---

## 📝 Important Notes  

- **Real-Time Updates**: Dashboard and History screens now feature live auto-refresh via RemediationService (Provider ChangeNotifier pattern) - updates immediately when remediations complete
- **Type-Safe History**: History endpoint now safely handles mixed data types (int/string event IDs) with robust conversion functions
- **Flutter Web Frontend**: Modern, responsive dashboard built with Flutter 3.41.6 compiled to web, providing native app feel
- **Proof of Concept**: This is a starter scaffold. Enhance with authentication, persistent job execution, better rule language, and safe execution controls before using in production
- **Approval Workflow**: Manual review of remediation actions before execution
- **Auto-Enrichment**: Events are automatically enriched with metadata from the JSON file
- **Rule Creation**: Rules can be manually created or imported from JSON
- **Live Monitoring**: Connects directly to Windows Event Viewer for real-time detection
- **Testing**: Always test remediation scripts manually before enabling auto-remediation
- **Monitoring**: Review the History tab regularly for remediation outcomes

---

## 🎯 Recent Improvements (April 2026)

### ✅ Fixed in Latest Release
- **Comprehensive Event Viewer** - New dedicated Event Viewer tab with advanced filtering, search, and export capabilities
- **Task Scheduler Integration** - Manage Windows scheduled tasks directly from the dashboard with CRUD operations
- **Real-Time Event Inspection** - Event details modal with full event properties
- **Advanced Filtering** - Filter events by Severity, Source, Log Name, Event ID, and Date Range
- **Export Functionality** - Export filtered events as JSON or CSV for external analysis
- **Task Execution Management** - Run tasks immediately, view logs, and monitor status from one interface
- **Auto-Remediation History Refresh** - History tab now updates instantly when remediation completes
- **Infinite Loop Prevention** - Dashboard and History screens no longer refresh continuously
- **Type-Safe Data Parsing** - Backend /api/history endpoint handles mixed int/string event IDs robustly
- **Consumer Pattern Integration** - RemediationService broadcasts to all interested screens
- **Flutter Build Optimization** - Fixed PATH issues to enable consistent web builds
- **Comprehensive Testing** - All 11 screens and 9 API categories verified working

## 🚀 Future Enhancements

### Planned Features
- [ ] User authentication and role-based access control
- [ ] Email/SMS notifications for critical events
- [ ] Advanced analytics and reporting dashboards
- [ ] Machine learning for anomaly detection
- [ ] Integration with SIEM systems (Splunk, ELK)
- [ ] Support for remote event collection (WinRM)
- [ ] Webhook support for external integrations
- [ ] Multi-tenant support
- [ ] REST API authentication (API keys/OAuth)
- [ ] Custom event source plugins
- [ ] Docker containerization
- [ ] Cloud deployment support (Azure, AWS)

---

## 🤝 Support and Contribution

### Getting Help
For issues, questions, or support:
1. Check the [INSTALLATION.md](INSTALLATION.md) for setup help
2. Review [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) for deployment scenarios
3. See [Troubleshooting](#-troubleshooting) section above
4. Open an issue on the repository

### Contributing
Contributions are welcome! Please feel free to:
- 🐛 Report bugs and issues
- 💡 Suggest new features
- 🔧 Submit pull requests
- 📖 Improve documentation

---

## 📄 License

This project is provided as-is for educational and internal use.

---

## 🙏 Acknowledgments

Built with:
- **Flask** - Web framework
- **SQLAlchemy** - Database ORM
- **PowerShell** - Event collection
- **Windows Event Log** - Event source

---

## ✅ Summary

**Rule-Based Auto-Remediation for Windows** is a complete solution for:
- ✅ Monitoring Windows Event Logs (Errors & Warnings in real-time)
- ✅ Automatically remediating common issues with rule-based engine
- ✅ Tracking remediation history with live dashboard updates
- ✅ Deploying across multiple systems (centralized backend + distributed monitors)
- ✅ Providing modern Flutter web dashboard with instant feedback
- ✅ Safe testing via Simulation tab before enabling auto-remediation

**Get started in 4 simple steps:**
1. Run `\.\setup.ps1` (automated setup)
2. Run `c:\flutter\bin\flutter build web --release` in `frontend/` (optional if pre-built)
3. Run `start_backend.bat` (Flask API server)
4. Run `start_event_monitor.bat` (Event collector)

**Then open:** `http://localhost:5000` 🎉

**Advanced Setup:** See Step 3 in Quick Start for Flutter frontend build instructions

---

**Made with ❤️ for Windows System Administrators**
