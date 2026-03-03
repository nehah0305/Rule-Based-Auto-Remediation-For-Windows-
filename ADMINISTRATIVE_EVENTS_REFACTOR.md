# Administrative Events Refactor - Errors & Warnings Only

## ✅ **REFACTORING COMPLETE!**

### **What Changed:**
The project has been refocused from monitoring **all Windows events** to monitoring only **Errors and Warnings** (Administrative Events), matching the "Administrative Events" view in Windows Event Viewer.

---

## 🎯 **Key Changes**

### **1. Event Monitor - Source Filtering**
**Files Modified:**
- `collector/event_monitor.ps1`
- `collector/event_monitor_config.ps1`

**Changes:**
- ✅ Added `Level = @(2, 3)` filter to `Get-WinEvent` calls
  - **Level 2** = Error
  - **Level 3** = Warning
- ✅ Filters applied to both real-time polling AND historical import
- ✅ Updated display messages to show "Administrative Events"
- ✅ No longer captures informational events (Level 4)

**Before:**
```powershell
$filterHashtable = @{
    LogName = $LogName
    StartTime = $lastCheck
}
```

**After:**
```powershell
$filterHashtable = @{
    LogName = $LogName
    StartTime = $lastCheck
    Level = @(2, 3)  # Error and Warning only
}
```

---

### **2. Database & CSV - Single File**
**Files Modified:**
- `backend/models.py`

**Changes:**
- ✅ Removed `ALL_EVENTS_CSV` (all_events.csv)
- ✅ Removed `FILTERED_EVENTS_CSV` (filtered_events.csv)
- ✅ Created single `ERRORS_WARNINGS_CSV` (errors_warnings.csv)
- ✅ All events are now errors/warnings (filtered at source)
- ✅ Simplified CSV logic - no need to check severity/keywords

**Before:**
```python
ALL_EVENTS_CSV = 'data/all_events.csv'
FILTERED_EVENTS_CSV = 'data/filtered_events.csv'
```

**After:**
```python
ERRORS_WARNINGS_CSV = 'data/errors_warnings.csv'
```

---

### **3. Dashboard UI - Removed Events Tab**
**Files Modified:**
- `backend/templates/index.html`

**Changes:**
- ✅ Removed "Events" navigation tab
- ✅ Removed entire Events tab content
- ✅ Removed `loadEvents()` function and all references
- ✅ Updated dashboard to use `/api/filtered-events`
- ✅ Changed "Total Events" stat to "Errors & Warnings"
- ✅ Updated icon from bell to exclamation-triangle
- ✅ Charts now show only errors/warnings data

**Navigation Before:**
- Dashboard
- **Events** ← REMOVED
- Warnings & Errors
- Rules
- History
- Requests
- Event Catalog

**Navigation After:**
- Dashboard
- Warnings & Errors
- Rules
- History
- Requests
- Event Catalog

---

### **4. API Endpoints - No Changes Needed**
**Files:** `backend/app.py`

**Status:** ✅ No changes required
- `/api/events` - Still stores all events in database (now only errors/warnings)
- `/api/filtered-events` - Reads from new `errors_warnings.csv`
- All other endpoints work as before

---

## 📊 **What You'll See Now**

### **Event Monitor Output:**
```
========================================
Windows Event Monitor - Administrative Events
========================================
API Endpoint: http://localhost:5000/api/events
Monitoring Logs: System,Application
Event Levels: Error (2) + Warning (3)
Poll Interval: 10 seconds
Max Events/Poll: 100
Historical Import: Last 30 days
========================================

========================================
HISTORICAL IMPORT - Last 30 days
========================================

Importing from System...
  Found 1,234 events, importing...
  Progress: 50 events imported...
  Progress: 100 events imported...
  ...
  [OK] Imported 1,234 events from System

Importing from Application...
  Found 567 events, importing...
  [OK] Imported 567 events from Application

========================================
HISTORICAL IMPORT COMPLETE
Total events imported: 1,801
========================================

Starting real-time monitoring...

Press Ctrl+C to stop

[Poll #1] Monitoring active...
```

### **Dashboard:**
- **Errors & Warnings:** 1,801 (instead of "Total Events")
- **Charts:** Show only Error and Warning severity levels
- **Recent Events:** Only errors and warnings
- **No "Events" tab** - cleaner, focused interface

---

## 🚀 **How to Use**

### **Start Monitoring:**
```batch
Double-click: start_event_monitor.bat
```

### **What Gets Captured:**
✅ **Error Events (Level 2):**
- Service failures
- Application crashes
- System errors
- Driver errors
- Disk errors

✅ **Warning Events (Level 3):**
- Service warnings
- Resource warnings
- Configuration warnings
- Performance warnings

❌ **NOT Captured:**
- Informational events (Level 4)
- Verbose events (Level 5)
- Success Audit (Level 0)
- Failure Audit (Level 1)

---

## 📁 **File Structure**

### **Data Files:**
```
backend/data/
├── errors_warnings.csv    ← Single CSV for all errors/warnings
├── last_processed.json    ← Last processed event marker
└── rules.db               ← SQLite database
```

### **Old Files (Can be deleted):**
```
backend/data/
├── all_events.csv         ← No longer used
└── filtered_events.csv    ← No longer used
```

---

## ✅ **Summary**

**Your Request:**
> "Remove the events page - I don't want to focus on events. I only want to focus on the errors and warnings that are displayed in the administrative view in the event viewer. Make the changes such that this project doesn't read all the events in my system and only focuses on the errors and warnings. I don't want a separate events CSV file. Just make one CSV file that reads all the errors and warnings and displays them in the website."

**What Was Implemented:**
1. ✅ **Removed Events tab** from the dashboard
2. ✅ **Filter at source** - Only capture Error (Level 2) and Warning (Level 3) events
3. ✅ **Single CSV file** - `errors_warnings.csv` for all errors/warnings
4. ✅ **Updated dashboard** - Shows only errors/warnings statistics and charts
5. ✅ **Cleaner interface** - Focused on administrative events only

**Result:**
- 🎯 **Focused monitoring** - Only errors and warnings
- ⚡ **Better performance** - Less data to process
- 📊 **Cleaner dashboard** - No noise from informational events
- 💾 **Simplified storage** - Single CSV file
- 🔍 **Matches Event Viewer** - Same as "Administrative Events" view

**Just restart the event monitor and you'll only see errors and warnings!** 🚀

