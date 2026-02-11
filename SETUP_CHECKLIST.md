# Setup Checklist

Use this checklist to ensure you've completed all necessary steps to run the project.

## ✅ Prerequisites Checklist

- [ ] Windows 10/11 or Windows Server 2016+ installed
- [ ] Python 3.8+ installed and added to PATH
  - Test: Open Command Prompt and run `python --version`
- [ ] PowerShell 5.1+ available
  - Test: Open PowerShell and run `$PSVersionTable.PSVersion`
- [ ] Administrator privileges available
  - Test: Right-click PowerShell → "Run as Administrator" works
- [ ] Internet connection (for pip install)

---

## ✅ Initial Setup Checklist

### Step 1: Project Setup
- [ ] Downloaded or cloned the project
- [ ] Navigated to project root directory
- [ ] Verified `backend` folder exists
- [ ] Verified `collector` folder exists
- [ ] Verified `windows_error_events.json` exists

### Step 2: Python Environment
**📍 Location:** Command Prompt/PowerShell in project root

- [ ] Created virtual environment: `python -m venv .venv`
- [ ] Activated virtual environment: `.\.venv\Scripts\activate`
- [ ] Verified activation (prompt shows `(.venv)`)
- [ ] Installed dependencies: `pip install -r backend\requirements.txt`
- [ ] Verified installation (no errors shown)

### Step 3: Database Initialization
**📍 Location:** Same terminal (with .venv activated)

- [ ] Ran database init: `python backend\db_init.py`
- [ ] Verified success message shown
- [ ] Verified `backend\events.db` file created

---

## ✅ Running the System Checklist

### Terminal 1: Backend
**📍 Location:** Project root directory

- [ ] Opened terminal/command prompt
- [ ] Activated virtual environment: `.\.venv\Scripts\activate`
- [ ] Started backend: `python backend\app.py`
- [ ] Verified message: "Running on http://localhost:5000"
- [ ] **Kept this terminal open and running** ✅

### Terminal 2: Event Monitor
**📍 Location:** Project root directory (new terminal)

- [ ] Opened new terminal/command prompt
- [ ] Started event monitor: `start_event_monitor.bat`
- [ ] Verified new PowerShell window opened
- [ ] Verified message: "Windows Event Monitor - Polling Mode"
- [ ] Verified message: "Starting monitoring..."
- [ ] **Kept this window open and running** ✅

### Browser: Dashboard
**📍 Location:** Web browser

- [ ] Opened browser
- [ ] Navigated to: http://localhost:5000
- [ ] Dashboard loaded successfully
- [ ] Can see all tabs: Dashboard, Events, Event Catalog, Rules, Approvals, History

---

## ✅ Configuration Checklist

### Import Rules
**📍 Location:** Web dashboard

- [ ] Clicked on "Rules" tab
- [ ] Clicked "Import from JSON" button
- [ ] Saw success message
- [ ] Verified rules appear in the table
- [ ] Verified approximately 20+ rules imported

### Configure Event Monitor (Optional)
**📍 Location:** `collector\monitor_config.json`

- [ ] Opened `collector\monitor_config.json` in text editor
- [ ] Reviewed settings:
  - [ ] `api_url` is correct (default: http://localhost:5000)
  - [ ] `poll_interval_seconds` is acceptable (default: 10)
  - [ ] `log_names` includes desired logs (default: System, Application)
  - [ ] `event_ids_to_monitor` is configured (empty = all events)
- [ ] Saved any changes
- [ ] Restarted event monitor if changes were made

---

## ✅ Testing Checklist

### Test 1: Backend Connectivity
**📍 Location:** PowerShell

- [ ] Ran: `Invoke-RestMethod -Uri "http://localhost:5000/api/events"`
- [ ] Received response (array of events, may be empty)
- [ ] No error messages

### Test 2: Generate Test Event
**📍 Location:** PowerShell as Administrator

- [ ] Ran: `Write-EventLog -LogName Application -Source "Application" -EventId 1000 -EntryType Error -Message "Test event"`
- [ ] No error messages
- [ ] Event created successfully

### Test 3: Automated Test Script
**📍 Location:** PowerShell in project root

- [ ] Ran: `.\test_live_monitoring.ps1`
- [ ] Step 1: Backend check passed ✓
- [ ] Step 2: Test events created ✓
- [ ] Step 3: Waited 15 seconds
- [ ] Step 4: Events captured successfully ✓
- [ ] Saw "SUCCESS! Captured X new event(s)"

### Test 4: Dashboard Verification
**📍 Location:** Web browser at http://localhost:5000

- [ ] Clicked "Dashboard" tab
- [ ] Verified "Total Events" count > 0
- [ ] Verified charts are displaying data
- [ ] Verified "Recent Events" list shows events

- [ ] Clicked "Events" tab
- [ ] Verified events are listed
- [ ] Verified search box works
- [ ] Verified filters work

- [ ] Clicked "Event Catalog" tab
- [ ] Verified 40+ event definitions shown
- [ ] Verified search works
- [ ] Verified "Create Rule" button appears

---

## ✅ Production Deployment Checklist (Optional)

### Install as Scheduled Task
**📍 Location:** PowerShell as Administrator

- [ ] Opened PowerShell as Administrator
- [ ] Navigated to project root
- [ ] Ran: `.\collector\install_as_task.ps1`
- [ ] Followed prompts
- [ ] Task created successfully
- [ ] Started task when prompted (or manually)

### Verify Scheduled Task
**📍 Location:** PowerShell as Administrator

- [ ] Ran: `Get-ScheduledTask -TaskName "WindowsEventMonitor"`
- [ ] Task exists and shows "Ready" or "Running" state
- [ ] Ran: `Get-ScheduledTask -TaskName "WindowsEventMonitor" | Get-ScheduledTaskInfo`
- [ ] Verified LastRunTime is recent
- [ ] Verified LastTaskResult is 0 (success)

### Manage Scheduled Task
**📍 Location:** PowerShell as Administrator

Know how to:
- [ ] Start: `Start-ScheduledTask -TaskName "WindowsEventMonitor"`
- [ ] Stop: `Stop-ScheduledTask -TaskName "WindowsEventMonitor"`
- [ ] Remove: `Unregister-ScheduledTask -TaskName "WindowsEventMonitor" -Confirm:$false`

---

## ✅ Workflow Verification Checklist

### Create a Custom Rule
**📍 Location:** Web dashboard

- [ ] Went to "Event Catalog" tab
- [ ] Found an event (e.g., Event 7031)
- [ ] Clicked "Create Rule" button
- [ ] Filled in rule details
- [ ] Added remediation script (optional)
- [ ] Saved the rule
- [ ] Verified rule appears in "Rules" tab

### Monitor Events
**📍 Location:** Web dashboard

- [ ] Dashboard tab shows real-time statistics
- [ ] Events tab shows captured events
- [ ] Can search and filter events
- [ ] Can view event details

### View History
**📍 Location:** Web dashboard → History tab

- [ ] Can see remediation history (if any remediations ran)
- [ ] Can see success/failure status
- [ ] Can see timestamps

---

## ✅ Troubleshooting Checklist

If something doesn't work, check:

### Backend Issues
- [ ] Virtual environment is activated (prompt shows `.venv`)
- [ ] Port 5000 is not in use: `netstat -ano | findstr :5000`
- [ ] No errors in backend terminal
- [ ] Python dependencies installed correctly

### Event Monitor Issues
- [ ] Backend is running first
- [ ] PowerShell execution policy allows scripts
- [ ] Event monitor window is open and running
- [ ] No connection errors shown
- [ ] API URL in config is correct

### No Events Captured
- [ ] Event monitor is running
- [ ] Backend is running
- [ ] Events exist in Windows Event Viewer
- [ ] Event IDs match filter (if filtering enabled)
- [ ] Wait at least 10 seconds (default poll interval)

### Permission Issues
- [ ] Running PowerShell as Administrator
- [ ] User has rights to read Event Logs
- [ ] User has rights to write Event Logs (for testing)

---

## ✅ Final Verification

- [ ] Backend is running ✅
- [ ] Event monitor is running ✅
- [ ] Dashboard is accessible ✅
- [ ] Rules are imported ✅
- [ ] Events are being captured ✅
- [ ] Test script passes ✅
- [ ] Ready to use! 🎉

---

## 📚 Next Steps

After completing this checklist:

1. [ ] Review [README.md](README.md) for detailed documentation
2. [ ] Review [QUICK_REFERENCE.md](QUICK_REFERENCE.md) for common commands
3. [ ] Review [LIVE_MONITORING_GUIDE.md](LIVE_MONITORING_GUIDE.md) for advanced configuration
4. [ ] Create custom rules for your environment
5. [ ] Test remediation scripts manually before enabling auto-remediation
6. [ ] Monitor the system and review results regularly

---

## 🆘 Need Help?

If you're stuck:

1. ✅ Review this checklist - did you miss a step?
2. ✅ Check [QUICK_REFERENCE.md](QUICK_REFERENCE.md) for troubleshooting
3. ✅ Run `.\test_live_monitoring.ps1` for diagnostics
4. ✅ Check terminal windows for error messages
5. ✅ Review [README.md](README.md) troubleshooting section

---

**Congratulations!** 🎉 If all items are checked, your Rule-Based Auto-Remediation system is fully operational!

