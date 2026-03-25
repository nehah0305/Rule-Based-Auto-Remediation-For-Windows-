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

### Advanced Features
- **✅ Approval Workflow**: Manual approval process for sensitive remediation actions
- **📜 Remediation History**: Complete audit trail of all remediation actions
- **🔧 Background Service**: Run as Windows Scheduled Task for continuous monitoring
- **🌐 Multi-System Support**: Deploy centrally with monitors on multiple machines
- **⚙️ Flexible Configuration**: Environment-based configuration for easy deployment

---

## 🚀 Quick Start (New Users)

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

### Step 3: Start the Backend

```cmd
start_backend.bat
```

**Expected output:**
```
Starting Flask server on 0.0.0.0:5000
Access the dashboard at: http://localhost:5000
 * Running on http://0.0.0.0:5000
```

**Keep this window open!**

### Step 4: Start the Event Monitor

Open a **new terminal** and run:

```cmd
start_event_monitor.bat
```

**What happens:**
- Imports historical events from the last 30 days
- Starts monitoring for new events
- Sends events to the backend automatically

### Step 5: Access the Dashboard

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

2. **Install dependencies:**
   ```bash
   pip install -r backend\requirements.txt
   ```

3. **Create configuration:**
   ```bash
   copy .env.example .env
   notepad .env  # Edit as needed
   ```

4. **Initialize database:**
   ```bash
   python backend\db_init.py
   ```

5. **Start backend:**
   ```bash
   python backend\app.py
   ```

6. **Start monitor (new terminal):**
   ```cmd
   start_event_monitor.bat
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

### Quick Test

### Crash Lab Simulation (Event ID 1000)

Use the built-in Simulation tab to demonstrate a realistic application crash workflow with automatic remediation.

What it does:
- Creates synthetic Event ID 1000 (`Application Error`) crash events.
- Passes those events through the same rule-matching pipeline used by live monitoring.
- Automatically executes `remediation_scripts/Error1000_ApplicationCrash.ps1` via the remediation engine.
- Shows timeline, rule matches, and script output in the UI.

Safety behavior:
- Simulation events are tagged with `log_name=Simulation`.
- The script detects this context and runs in simulation-safe mode (`RM_SIMULATION_MODE=1`), so the demo shows remediation behavior without applying the real `sfc /scannow` change.

How to run:
1. Start backend with `start_backend.bat`.
2. Open `http://localhost:5000`.
3. Go to **Simulation** tab.
4. Enter app/module/exception details and click **Run Simulation**.

```powershell
# Generate a test event
Write-EventLog -LogName Application -Source "Application" -EventId 1000 -EntryType Error -Message "Test event"

# Check dashboard - event should appear within 10 seconds
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
- Complete audit trail
- Remediation success/failure status
- Script output logs
- Timestamp tracking

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
├── 🚀 Quick Start Scripts
│   ├── setup.ps1                    # Automated setup script
│   ├── start_backend.bat            # Start Flask backend
│   └── start_event_monitor.bat     # Start event monitor
│
├── 🖥️ Backend (Flask Application)
│   ├── app.py                       # Main Flask application
│   ├── models.py                    # Database models & business logic
│   ├── db_init.py                   # Database initialization
│   ├── requirements.txt             # Python dependencies
│   ├── rules.db                     # SQLite database (created after init)
│   ├── templates/
│   │   └── index.html              # Web dashboard UI
│   ├── static/
│   │   └── style.css               # Dashboard styles
│   └── data/
│       └── errors_warnings.csv     # Event data export
│
├── 📡 Collector (PowerShell Scripts)
│   ├── event_monitor.ps1            # Main event monitoring script
│   ├── Load-Config.ps1              # Configuration loader
│   ├── collector.ps1                # One-time event collector
│   ├── event_monitor_config.ps1     # Config-based monitor
│   ├── event_watcher.ps1            # Subscription-based monitor
│   ├── monitor_config.json          # Legacy config file
│   └── install_as_task.ps1          # Scheduled task installer
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

| Component | Technology |
|-----------|------------|
| **Backend** | Python 3.8+, Flask, SQLAlchemy |
| **Database** | SQLite |
| **Frontend** | HTML5, CSS3, JavaScript (Vanilla) |
| **Event Collection** | PowerShell 5.1+ |
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

- **Proof of Concept**: This is a starter scaffold. Enhance with authentication, persistent job execution, better rule language, and safe execution controls before using in production.
- **Approval Workflow**: Manual review of remediation actions before execution
- **Auto-Enrichment**: Events are automatically enriched with metadata from the JSON file
- **Rule Creation**: Rules can be manually created or imported from JSON
- **Live Monitoring**: Connects directly to Windows Event Viewer for real-time detection
- **Testing**: Always test remediation scripts manually before enabling auto-remediation
- **Monitoring**: Review the History tab regularly for remediation outcomes

---

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
- ✅ Monitoring Windows Event Logs (Errors & Warnings)
- ✅ Automatically remediating common issues
- ✅ Tracking remediation history and approvals
- ✅ Deploying across multiple systems
- ✅ Providing a modern web dashboard

**Get started in 3 steps:**
1. Run `.\setup.ps1`
2. Run `start_backend.bat`
3. Run `start_event_monitor.bat`

**That's it!** 🎉

---

**Made with ❤️ for Windows System Administrators**
