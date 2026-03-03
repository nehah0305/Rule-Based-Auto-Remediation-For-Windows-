# Reset and Recapture Events with Correct Levels

## Problem
The existing events in the CSV have incorrect level values (all showing as "Warning") because they were inferred from severity instead of being captured from the actual Windows Event Log level field.

## Solution
Reset the CSV and recapture events from Windows Event Log with the correct level information.

---

## 🚀 **Quick Fix Steps**

### **Step 1: Backup and Delete Old CSV**
```bash
# Navigate to backend/data folder
cd backend/data

# Rename the old CSV (backup)
ren errors_warnings.csv errors_warnings_old.csv
```

### **Step 2: Restart Event Monitor**
```batch
# Double-click this file:
start_event_monitor.bat
```

The event monitor will:
- ✅ Create a new `errors_warnings.csv` with correct headers
- ✅ Import historical events from the last 30 days
- ✅ Capture the actual Level (Error/Warning) from Windows Event Log
- ✅ Display progress as it imports events

### **Step 3: Wait for Import to Complete**
You'll see output like:
```
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
```

### **Step 4: Refresh Dashboard**
1. Open: http://localhost:5000
2. Click "Warnings & Errors" tab
3. Press F5 to refresh
4. ✅ Level column should now show correct Error/Warning values

---

## ✅ **Expected Result**

**Before:**
```
| ID | Level   | Event ID | Source |
|----|---------|----------|--------|
| 1  | Warning | 1013     | MsiInstaller |  ❌ WRONG (should be Error)
| 2  | Warning | 7001     | Service Control | ❌ WRONG (should be Error)
```

**After:**
```
| ID | Level | Event ID | Source |
|----|-------|----------|--------|
| 1  | Error | 1013     | MsiInstaller | ✅ CORRECT
| 2  | Error | 7001     | Service Control | ✅ CORRECT
| 3  | Warning | 10016  | DistributedCOM | ✅ CORRECT
```

---

## 📊 **What Gets Captured**

The event monitor now sends the actual `LevelDisplayName` from Windows Event Log:

**PowerShell Code:**
```powershell
$eventData = @{
    event_id = $Event.Id
    log_name = $Event.LogName
    source = $Event.ProviderName
    message = $Event.Message
    timestamp = $Event.TimeCreated
    level = $Event.LevelDisplayName  # ← This is the actual level from Windows
}
```

**Windows Event Log Levels:**
- **Level 2** → "Error" (red badge)
- **Level 3** → "Warning" (yellow badge)

---

## 🔧 **Alternative: Manual CSV Reset**

If you prefer to do it manually:

1. **Stop the event monitor** (Ctrl+C if running)

2. **Delete or rename the CSV:**
   ```
   backend/data/errors_warnings.csv → errors_warnings_old.csv
   ```

3. **Restart the event monitor:**
   ```batch
   start_event_monitor.bat
   ```

4. **Wait for historical import to complete**

5. **Refresh the dashboard**

---

## ✅ **Summary**

**Issue:** All events showing as "Warning" even though some are "Error" in Event Viewer

**Root Cause:** Level was inferred from severity instead of captured from actual Windows Event Log

**Solution:** Reset CSV and recapture events with actual level from Windows Event Log

**Time Required:** 2-5 minutes (depending on number of events)

**Result:** Level column will show correct Error/Warning values matching Windows Event Viewer

---

## 📝 **Note**

After recapturing, all new events will automatically have the correct level because:
1. ✅ Event monitor sends `$Event.LevelDisplayName` to API
2. ✅ Backend stores it in database and CSV
3. ✅ Dashboard displays it with color-coded badges
4. ✅ Matches exactly what you see in Windows Event Viewer Administrative Events

