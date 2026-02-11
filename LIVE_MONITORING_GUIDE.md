# Live Windows Event Monitoring Guide

## Overview

This guide explains how to connect the Auto-Remediation system to Windows Event Viewer for real-time event monitoring. The system can now automatically detect and respond to Windows events as they occur.

## Architecture

```
Windows Event Viewer → Event Monitor Script → Flask API → Database → Auto-Remediation
```

The event monitor continuously watches Windows Event Logs and sends new events to the Flask backend API, which then:
1. Enriches events with metadata from `windows_error_events.json`
2. Matches events against configured rules
3. Triggers auto-remediation or creates approval requests

## Available Monitoring Scripts

### 1. **event_monitor.ps1** (Recommended for Testing)
Simple polling-based monitor with command-line parameters.

**Features:**
- Easy to use and configure
- Polls event logs at regular intervals
- Supports filtering by Event IDs
- Throttling to avoid duplicates

**Usage:**
```powershell
# Monitor System and Application logs (default)
.\collector\event_monitor.ps1

# Monitor specific logs with custom interval
.\collector\event_monitor.ps1 -LogNames "System,Application,Security" -PollIntervalSeconds 5

# Monitor only specific Event IDs
.\collector\event_monitor.ps1 -EventIds "7031,7034,1000,1001" -MaxEventsPerPoll 100

# Custom API URL
.\collector\event_monitor.ps1 -ApiUrl "http://192.168.1.100:5000"
```

### 2. **event_monitor_config.ps1** (Recommended for Production)
Configuration file-based monitor for easier management.

**Features:**
- Reads settings from `monitor_config.json`
- Centralized configuration
- Easy to update without changing scripts

**Usage:**
```powershell
# Use default config (collector/monitor_config.json)
.\collector\event_monitor_config.ps1

# Use custom config file
.\collector\event_monitor_config.ps1 -ConfigFile "C:\path\to\custom_config.json"
```

**Configuration File (`collector/monitor_config.json`):**
```json
{
  "api_url": "http://localhost:5000",
  "poll_interval_seconds": 10,
  "max_events_per_poll": 50,
  "log_names": ["System", "Application"],
  "event_ids_to_monitor": [7031, 7034, 1000, 1001],
  "description": "Leave event_ids_to_monitor empty to monitor all events"
}
```

### 3. **event_watcher.ps1** (Advanced)
Event subscription-based monitor for real-time notifications.

**Features:**
- True real-time event notifications
- Lower latency than polling
- More complex setup

**Usage:**
```powershell
.\collector\event_watcher.ps1 -LogNames "System,Application" -MinSeverityLevel "Error"
```

## Quick Start

### Step 1: Start the Flask Backend
```bash
python backend/app.py
```

The backend should be running at `http://localhost:5000`

### Step 2: Start the Event Monitor

**Option A: Using the Batch File (Easiest)**
```cmd
start_event_monitor.bat
```

**Option B: Using PowerShell Directly**
```powershell
powershell -ExecutionPolicy Bypass -File collector\event_monitor.ps1
```

**Option C: Using Configuration File**
```powershell
powershell -ExecutionPolicy Bypass -File collector\event_monitor_config.ps1
```

### Step 3: Verify Monitoring
1. Open the dashboard: http://localhost:5000
2. Go to the Dashboard tab
3. Watch the "Total Events" counter increase as events are detected
4. Check the "Recent Events" list for newly captured events

### Step 4: Test with a Sample Event
Generate a test event to verify the system is working:

```powershell
# Create a test event in Application log
Write-EventLog -LogName Application -Source "Application" -EventId 1000 -EntryType Error -Message "Test event for auto-remediation system"
```

You should see this event appear in the dashboard within 10 seconds (default poll interval).

## Running as a Background Service

For production use, you can run the event monitor as a Windows Scheduled Task that starts automatically.

### Install as Scheduled Task

1. **Open PowerShell as Administrator**

2. **Run the installation script:**
```powershell
.\collector\install_as_task.ps1
```

3. **Follow the prompts:**
   - Task name: `WindowsEventMonitor` (default)
   - Run as: `SYSTEM` (default) or specify a user account
   - Start now: `Y` to start immediately

4. **Verify the task:**
```powershell
Get-ScheduledTask -TaskName "WindowsEventMonitor"
Get-ScheduledTask -TaskName "WindowsEventMonitor" | Get-ScheduledTaskInfo
```

### Manage the Scheduled Task

**Start the task:**
```powershell
Start-ScheduledTask -TaskName "WindowsEventMonitor"
```

**Stop the task:**
```powershell
Stop-ScheduledTask -TaskName "WindowsEventMonitor"
```

**Remove the task:**
```powershell
Unregister-ScheduledTask -TaskName "WindowsEventMonitor" -Confirm:$false
```

**View task status:**
```powershell
Get-ScheduledTask -TaskName "WindowsEventMonitor" | Select-Object TaskName, State, LastRunTime, NextRunTime
```

## Configuration Options

### Event Filtering

**Monitor specific Event IDs only:**
Edit `collector/monitor_config.json`:
```json
{
  "event_ids_to_monitor": [7031, 7034, 7000, 1000, 1001, 1026]
}
```

**Monitor all events:**
```json
{
  "event_ids_to_monitor": []
}
```

### Poll Interval

Adjust how often to check for new events:
```json
{
  "poll_interval_seconds": 5
}
```

- **Lower values (5-10)**: More responsive, higher CPU usage
- **Higher values (30-60)**: Less responsive, lower CPU usage
- **Recommended**: 10 seconds for most scenarios

### Log Names

Monitor different Windows Event Logs:
```json
{
  "log_names": ["System", "Application", "Security", "Setup"]
}
```

Common log names:
- `System` - System events (services, drivers, hardware)
- `Application` - Application events
- `Security` - Security and audit events
- `Setup` - Windows setup and updates
- `Microsoft-Windows-PowerShell/Operational` - PowerShell events

## Monitoring Output

The event monitor displays real-time status:

```
========================================
Windows Event Monitor - Config Mode
========================================
API Endpoint: http://localhost:5000/api/events
Monitoring Logs: System,Application
Poll Interval: 10 seconds
Max Events/Poll: 50
Filtering Event IDs: 20 IDs
========================================

Starting monitoring...

Press Ctrl+C to stop

[14:23:15] ✓ Event 7031 from Service Control Manager
[14:23:15] ✓ Event 1000 from Application Error
[14:23:45] ♥ Monitoring active
```

**Symbols:**
- `✓` - Event successfully sent to API
- `✗` - Failed to send event (API error)
- `♥` - Heartbeat (shown every minute when no events)

## Troubleshooting

### Monitor not sending events

**Check 1: Is the Flask backend running?**
```bash
curl http://localhost:5000/api/events
```

**Check 2: Are there new events in Event Viewer?**
```powershell
Get-WinEvent -LogName System -MaxEvents 10
```

**Check 3: Check PowerShell execution policy**
```powershell
Get-ExecutionPolicy
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Events not appearing in dashboard

1. Check the browser console for JavaScript errors
2. Refresh the dashboard page
3. Check the Events tab directly
4. Verify the API is receiving events:
```powershell
Invoke-RestMethod -Uri "http://localhost:5000/api/events" -Method Get
```

### Too many events being captured

**Option 1: Filter by Event IDs**
Edit `monitor_config.json` to only monitor specific event IDs

**Option 2: Increase poll interval**
```json
{
  "poll_interval_seconds": 30
}
```

**Option 3: Monitor fewer logs**
```json
{
  "log_names": ["System"]
}
```

### Permission errors

Run PowerShell as Administrator:
```powershell
Start-Process powershell -Verb RunAs
```

## Best Practices

1. **Start with filtered monitoring**: Monitor only the event IDs you care about
2. **Test before production**: Run manually first to verify everything works
3. **Monitor the monitor**: Check Task Scheduler logs to ensure the task is running
4. **Set up alerts**: Configure rules for critical events with auto-remediation
5. **Regular maintenance**: Clean up old events from the database periodically

## Integration with Auto-Remediation

Once events are flowing into the system:

1. **Create Rules**: Go to Event Catalog → Click "Create Rule" on events
2. **Add Remediation Scripts**: Specify PowerShell scripts to fix issues
3. **Enable Auto-Remediation**: For safe, well-tested rules
4. **Monitor Results**: Check the History tab for remediation outcomes

## Next Steps

1. ✅ Start the event monitor
2. ✅ Verify events are being captured
3. ✅ Create rules for common events
4. ✅ Add remediation scripts
5. ✅ Test manual remediation
6. ✅ Enable auto-remediation for safe events
7. ✅ Install as scheduled task for continuous monitoring

