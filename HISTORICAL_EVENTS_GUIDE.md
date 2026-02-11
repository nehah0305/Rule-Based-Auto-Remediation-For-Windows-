# Historical Events Import Guide

## ✅ NEW FEATURE: Historical Event Import

The event monitor now supports importing historical events from Windows Event Viewer, not just new events!

---

## 🎯 What This Means

When you start the event monitor, it will:
1. **Import historical events** from the last 7 days (configurable)
2. **Continue monitoring** for new events in real-time

This means you'll see:
- ✅ Old errors and events that happened in the past week
- ✅ New events as they occur in real-time
- ✅ Complete event history in your dashboard

---

## 🚀 How to Use

### Option 1: Using the Batch File (Default: 7 Days)

Simply double-click:
```
start_event_monitor.bat
```

This will automatically import events from the last **7 days**.

### Option 2: Custom Time Range

To import a different number of days:

```powershell
# Import last 30 days
powershell -ExecutionPolicy Bypass -File collector\event_monitor.ps1 -HistoricalDays 30

# Import last 1 day
powershell -ExecutionPolicy Bypass -File collector\event_monitor.ps1 -HistoricalDays 1

# Import last 90 days (3 months)
powershell -ExecutionPolicy Bypass -File collector\event_monitor.ps1 -HistoricalDays 90
```

### Option 3: Skip Historical Import (New Events Only)

If you only want new events going forward:

```powershell
powershell -ExecutionPolicy Bypass -File collector\event_monitor.ps1 -SkipHistorical
```

### Option 4: Using Configuration File

Edit `collector\monitor_config.json`:

```json
{
  "historical_days": 7,
  ...
}
```

Then run:
```powershell
powershell -ExecutionPolicy Bypass -File collector\event_monitor_config.ps1
```

Set `"historical_days": 0` to skip historical import.

---

## 📊 What You'll See

When the monitor starts with historical import:

```
========================================
Windows Event Monitor - Polling Mode
========================================
API Endpoint: http://localhost:5000/api/events
Monitoring Logs: System,Application
Poll Interval: 10 seconds
Max Events/Poll: 50
Historical Import: Last 7 days
========================================

Importing historical events from last 7 days...
This may take a moment...

Starting monitoring...

Press Ctrl+C to stop

[Poll #1] Checking for new events...
[OK] Event 7031 from Service Control Manager sent
[OK] Event 1000 from Application sent
[OK] Event 6008 from EventLog sent
...
```

---

## ⚙️ Configuration Options

| Parameter | Default | Description |
|-----------|---------|-------------|
| `HistoricalDays` | 7 | Number of days to import |
| `SkipHistorical` | false | Skip historical import |
| `MaxEventsPerPoll` | 50 | Max events per poll cycle |

---

## 🔍 How It Works

1. **On Startup:**
   - Sets the "last check time" to X days ago (e.g., 7 days)
   - First poll retrieves all matching events from the past X days
   - Sends them to the API (oldest first)

2. **After Initial Import:**
   - Continues polling every 10 seconds (configurable)
   - Only captures new events since last poll
   - Deduplication prevents sending the same event twice

---

## 💡 Use Cases

### See All Recent Service Failures
```powershell
# Import last 30 days to see all service crashes
powershell -ExecutionPolicy Bypass -File collector\event_monitor.ps1 -HistoricalDays 30
```

### Audit Security Events
```powershell
# Import last 90 days of security events
powershell -ExecutionPolicy Bypass -File collector\event_monitor.ps1 -HistoricalDays 90
```

### Fresh Start (No History)
```powershell
# Only monitor new events from now on
powershell -ExecutionPolicy Bypass -File collector\event_monitor.ps1 -SkipHistorical
```

---

## ⚠️ Important Notes

### Performance Considerations

- **Large time ranges** (30+ days) may take longer to import initially
- The first poll might take 30-60 seconds for large imports
- Subsequent polls are fast (only new events)

### Event Filtering

Historical import respects your event ID filters:
- If you're filtering specific event IDs (1000, 7031, etc.), only those will be imported
- If no filter is set, ALL events from the time range will be imported

### Deduplication

- Events are tracked by `LogName-RecordId` to prevent duplicates
- If you restart the monitor, it won't re-import the same events (they're already in the database)

---

## 🧪 Testing Historical Import

### Step 1: Clear the Database (Optional)
```bash
# If you want to start fresh
python backend/db_init.py
```

### Step 2: Start Monitor with Historical Import
```batch
start_event_monitor.bat
```

### Step 3: Check the Dashboard
1. Open: http://localhost:5000
2. Go to "Events" tab
3. You should see events from the past 7 days!

### Step 4: Verify Event Count
```powershell
powershell -ExecutionPolicy Bypass -File check_events.ps1
```

---

## 📈 Expected Results

After starting the monitor with historical import, you should see:

**Dashboard Statistics:**
- Total Events: 50+ (depending on your system activity)
- Events from the past 7 days
- Various event IDs (7031, 1000, 6008, etc.)

**Events Tab:**
- Sorted by timestamp
- Mix of old and new events
- Enriched with metadata from JSON

---

## 🔧 Troubleshooting

### "No historical events imported"

**Possible reasons:**
1. No matching events in the time range
2. Event ID filter is too restrictive
3. Logs don't have events for those IDs

**Solution:**
- Try a longer time range: `-HistoricalDays 30`
- Remove event ID filter (monitor all events)
- Check Windows Event Viewer manually to verify events exist

### "Import taking too long"

**Solution:**
- Reduce time range: `-HistoricalDays 1`
- Add event ID filter to reduce volume
- Increase `MaxEventsPerPoll` for faster import

### "Duplicate events"

**This shouldn't happen** due to deduplication, but if it does:
- Check that the monitor isn't running multiple times
- Verify `ProcessedEvents` hashtable is working

---

## 📚 Related Documentation

- `README.md` - Complete setup guide
- `START_HERE.md` - Quick start instructions
- `LIVE_MONITORING_GUIDE.md` - Advanced monitoring configuration
- `SYSTEM_TEST_RESULTS.md` - Test results

---

## 🎉 Summary

**You can now see historical Windows events in your dashboard!**

- ✅ Import events from the past 7 days (default)
- ✅ Customize the time range (1-90+ days)
- ✅ Skip historical import if you only want new events
- ✅ All events are enriched with metadata from JSON
- ✅ Deduplication prevents duplicates

**Just run `start_event_monitor.bat` and watch your dashboard fill with historical events!** 🚀

