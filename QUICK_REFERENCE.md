# Quick Reference Card

## 🚀 Essential Commands

### Initial Setup (One-time)
```bash
# 1. Create virtual environment
python -m venv .venv

# 2. Activate virtual environment
.\.venv\Scripts\activate

# 3. Install dependencies
pip install -r backend\requirements.txt

# 4. Initialize database
python backend\db_init.py
```

---

## ▶️ Starting the System

### Terminal 1: Backend (Required)
**📍 Location:** Project root directory
```bash
.\.venv\Scripts\activate
python backend\app.py
```
**Keep this running!** ✅

### Terminal 2: Event Monitor (Required)
**📍 Location:** Project root directory
```cmd
start_event_monitor.bat
```
**Keep this running!** ✅

### Browser: Dashboard
**📍 URL:** http://localhost:5000

---

## 🔧 Common Commands

### Import Rules from JSON
**📍 Location:** Web Dashboard → Rules tab → "Import from JSON" button

Or via API:
```powershell
Invoke-RestMethod -Uri "http://localhost:5000/api/populate-rules" -Method Post
```

### Test Event Monitoring
**📍 Location:** Project root (PowerShell)
```powershell
.\test_live_monitoring.ps1
```

### Generate Test Event
**📍 Location:** PowerShell (as Administrator)
```powershell
Write-EventLog -LogName Application -Source "Application" -EventId 1000 -EntryType Error -Message "Test event"
```

### Check Backend Status
**📍 Location:** Any terminal
```powershell
Invoke-RestMethod -Uri "http://localhost:5000/api/events"
```

---

## 🛠️ Event Monitor Options

### Option 1: Batch File (Easiest)
```cmd
start_event_monitor.bat
```

### Option 2: Config-based (Recommended)
```powershell
powershell -ExecutionPolicy Bypass -File collector\event_monitor_config.ps1
```

### Option 3: Custom Parameters
```powershell
powershell -ExecutionPolicy Bypass -File collector\event_monitor.ps1 -LogNames "System,Application" -PollIntervalSeconds 5
```

### Option 4: Specific Event IDs
```powershell
powershell -ExecutionPolicy Bypass -File collector\event_monitor.ps1 -EventIds "7031,7034,1000,1001"
```

---

## 📝 Configuration Files

### Event Monitor Config
**📍 File:** `collector\monitor_config.json`
```json
{
  "api_url": "http://localhost:5000",
  "poll_interval_seconds": 10,
  "max_events_per_poll": 50,
  "log_names": ["System", "Application"],
  "event_ids_to_monitor": [7031, 7034, 1000, 1001]
}
```

**After editing:** Restart event monitor

---

## 🔄 Background Service (Production)

### Install as Scheduled Task
**📍 Location:** PowerShell as Administrator
```powershell
.\collector\install_as_task.ps1
```

### Manage Scheduled Task
```powershell
# Start
Start-ScheduledTask -TaskName "WindowsEventMonitor"

# Stop
Stop-ScheduledTask -TaskName "WindowsEventMonitor"

# Status
Get-ScheduledTask -TaskName "WindowsEventMonitor" | Get-ScheduledTaskInfo

# Remove
Unregister-ScheduledTask -TaskName "WindowsEventMonitor" -Confirm:$false
```

---

## 🐛 Troubleshooting

### Backend won't start
```bash
# Check port 5000
netstat -ano | findstr :5000

# Use different port
set FLASK_RUN_PORT=5001
python backend\app.py
```

### PowerShell execution policy
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Reset database
```bash
python backend\db_init.py
```

### Check Windows Event Logs
```powershell
Get-WinEvent -LogName System -MaxEvents 10
```

---

## 📊 Dashboard Tabs

| Tab | Purpose |
|-----|---------|
| **Dashboard** | Statistics, charts, recent activity |
| **Events** | All captured events with search/filter |
| **Event Catalog** | Browse 40+ event definitions |
| **Rules** | Manage remediation rules |
| **Approvals** | Approve/deny remediation requests |
| **History** | View remediation outcomes |

---

## 🔗 API Endpoints

### Events
- `GET /api/events` - List all events
- `POST /api/events` - Create event

### Rules
- `GET /api/rules` - List all rules
- `POST /api/rules` - Create rule
- `POST /api/rules/<id>/run` - Run rule

### Event Definitions
- `GET /api/event-definitions` - Get all definitions
- `POST /api/populate-rules` - Import rules from JSON

### Approvals
- `GET /api/requests` - List requests
- `POST /api/requests/<id>/approve` - Approve
- `POST /api/requests/<id>/deny` - Deny

### History
- `GET /api/history` - Get remediation history

---

## 📁 Important Files

| File | Purpose |
|------|---------|
| `backend/app.py` | Flask backend |
| `backend/events.db` | SQLite database |
| `collector/monitor_config.json` | Event monitor config |
| `windows_error_events.json` | Event definitions |
| `start_event_monitor.bat` | Quick start script |
| `test_live_monitoring.ps1` | Test script |

---

## ⚡ Quick Workflow

1. **Start backend** → `python backend\app.py`
2. **Start monitor** → `start_event_monitor.bat`
3. **Open dashboard** → http://localhost:5000
4. **Import rules** → Rules tab → "Import from JSON"
5. **Monitor events** → Dashboard tab (auto-refreshes)
6. **Create custom rules** → Event Catalog → "Create Rule"
7. **View results** → History tab

---

## 📚 Documentation

- **README.md** - Complete setup guide
- **LIVE_MONITORING_GUIDE.md** - Detailed monitoring documentation
- **LIVE_MONITORING_SUMMARY.md** - Implementation summary
- **INTEGRATION_SUMMARY.md** - Integration details
- **QUICK_START_GUIDE.md** - Quick start guide
- **QUICK_REFERENCE.md** - This file

---

## 💡 Tips

✅ Always run backend before starting event monitor  
✅ Keep both terminals open while system is running  
✅ Test remediation scripts manually before enabling auto-remediation  
✅ Use Event Catalog to quickly create rules  
✅ Monitor the History tab to verify remediations work  
✅ Start with filtered event monitoring (specific Event IDs)  
✅ Install as scheduled task for production use  

---

## 🆘 Need Help?

1. Check **README.md** for detailed instructions
2. Run **test_live_monitoring.ps1** to diagnose issues
3. Check **LIVE_MONITORING_GUIDE.md** for troubleshooting
4. Review Windows Event Viewer for actual events
5. Check Flask terminal for error messages

