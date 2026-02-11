# Live Event Monitoring - Implementation Summary

## Overview

Successfully implemented real-time Windows Event Viewer integration for the Auto-Remediation system. The system can now automatically detect and respond to Windows events as they occur.

## What Was Created

### 1. Event Monitor Scripts

#### **event_monitor.ps1** (Recommended for Testing)
- Simple polling-based monitor with command-line parameters
- Polls Windows Event Logs at configurable intervals (default: 10 seconds)
- Supports filtering by Event IDs, log names, and maximum events per poll
- Tracks processed events to avoid duplicates
- Easy to use and test

**Usage:**
```powershell
.\collector\event_monitor.ps1 -LogNames "System,Application" -PollIntervalSeconds 10
```

#### **event_monitor_config.ps1** (Recommended for Production)
- Configuration file-based monitor
- Reads settings from `monitor_config.json`
- Same functionality as event_monitor.ps1 but easier to manage
- No need to modify scripts to change settings

**Usage:**
```powershell
.\collector\event_monitor_config.ps1
```

#### **event_watcher.ps1** (Advanced)
- Event subscription-based monitor for true real-time notifications
- Lower latency than polling approach
- More complex setup

### 2. Configuration Files

#### **monitor_config.json**
- Centralized configuration for event monitoring
- Configurable API URL, poll interval, max events per poll
- Specify which logs to monitor (System, Application, etc.)
- Filter by specific Event IDs or monitor all events

**Example:**
```json
{
  "api_url": "http://localhost:5000",
  "poll_interval_seconds": 10,
  "max_events_per_poll": 50,
  "log_names": ["System", "Application"],
  "event_ids_to_monitor": [7031, 7034, 1000, 1001]
}
```

### 3. Startup and Installation Scripts

#### **start_event_monitor.bat**
- Batch file for easy startup
- Launches event monitor in a new PowerShell window
- No need to type long PowerShell commands

#### **install_as_task.ps1**
- Installs event monitor as a Windows Scheduled Task
- Runs at system startup with elevated privileges
- Provides management commands (start, stop, remove)
- Perfect for production deployment

**Usage:**
```powershell
# Run as Administrator
.\collector\install_as_task.ps1
```

### 4. Testing and Documentation

#### **test_live_monitoring.ps1**
- Test script to verify the monitoring setup
- Generates test events in Windows Event Log
- Checks if backend is running
- Verifies events are captured and sent to API
- Provides troubleshooting guidance

#### **LIVE_MONITORING_GUIDE.md**
- Comprehensive 150-line documentation
- Architecture overview
- Detailed usage instructions for all scripts
- Configuration options
- Troubleshooting section
- Best practices

### 5. Updated Documentation

#### **README.md**
- Added "Live Event Monitoring" to features list
- Updated Quick Start section with three options for starting monitoring
- Added new "Live Event Monitoring" section with configuration examples
- Added link to detailed guide

## Key Features

### ✅ Real-time Event Detection
- Automatically detects new Windows events as they occur
- Configurable poll interval (default: 10 seconds)
- Event subscription mode available for even lower latency

### ✅ Smart Filtering
- Filter by Event IDs to monitor only relevant events
- Filter by log names (System, Application, Security, etc.)
- Configurable maximum events per poll to prevent overload

### ✅ Deduplication
- Tracks processed events using unique keys (LogName-RecordId)
- Prevents duplicate events from being sent to the API
- Automatic cleanup to prevent memory growth

### ✅ Multiple Execution Modes
1. **Manual Execution**: Run directly from PowerShell for testing
2. **Batch File**: Double-click to start monitoring
3. **Scheduled Task**: Background service that starts at system boot

### ✅ Robust Error Handling
- Graceful handling of API connection errors
- Continues monitoring even if API is temporarily unavailable
- Detailed error messages and logging

### ✅ Easy Configuration
- JSON-based configuration file
- No need to modify scripts
- Change settings without restarting (for some parameters)

## How It Works

```
Windows Event Viewer → Event Monitor Script → Flask API → Event Enrichment → Database → Rule Matching → Auto-Remediation
```

1. **Event Monitor** polls Windows Event Logs at regular intervals
2. **New events** are detected and filtered based on configuration
3. **Events are sent** to Flask API via HTTP POST
4. **Backend enriches** events with metadata from `windows_error_events.json`
5. **Events are stored** in SQLite database
6. **Rules are matched** against incoming events
7. **Auto-remediation** is triggered for matching rules (if enabled)

## Quick Start

### Step 1: Start the Backend
```bash
python backend/app.py
```

### Step 2: Start Event Monitoring
```cmd
start_event_monitor.bat
```

### Step 3: Verify It's Working
```powershell
.\test_live_monitoring.ps1
```

### Step 4: View Events in Dashboard
Open http://localhost:5000 and check the Dashboard tab

## Production Deployment

For continuous monitoring in production:

```powershell
# Run as Administrator
.\collector\install_as_task.ps1
```

This creates a Windows Scheduled Task that:
- Starts automatically at system boot
- Runs with elevated privileges
- Restarts automatically if it crashes
- Runs in the background (no visible window)

## Files Created

```
collector/
├── event_monitor.ps1              # Simple polling monitor
├── event_monitor_config.ps1       # Config-based monitor (recommended)
├── event_watcher.ps1              # Subscription-based monitor
├── monitor_config.json            # Configuration file
└── install_as_task.ps1            # Scheduled task installer

start_event_monitor.bat            # Easy startup batch file
test_live_monitoring.ps1           # Test script
LIVE_MONITORING_GUIDE.md           # Comprehensive documentation
LIVE_MONITORING_SUMMARY.md         # This file
README.md                          # Updated with live monitoring info
```

## Next Steps

1. ✅ Test the live monitoring with `test_live_monitoring.ps1`
2. ✅ Customize `monitor_config.json` for your environment
3. ✅ Create rules for common events in the Event Catalog
4. ✅ Add remediation scripts to rules
5. ✅ Test manual remediation
6. ✅ Enable auto-remediation for safe, well-tested rules
7. ✅ Install as scheduled task for continuous monitoring

## Success!

The live event monitoring feature is now fully implemented and ready to use. The system can automatically detect Windows events in real-time and trigger remediation actions based on your configured rules.

