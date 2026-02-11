# Event Color Coding Guide

## ✅ Color-Coded Events System

Your dashboard now displays events with **color-coded badges** based on their **category** and **severity** for easy visual identification.

---

## 🎨 Severity Color Coding

Events are color-coded by severity level:

| Severity | Color | Badge Example | Description |
|----------|-------|---------------|-------------|
| **Critical** | 🔴 Red | ![Critical](https://via.placeholder.com/80x20/dc3545/ffffff?text=Critical) | Immediate attention required |
| **High** | 🟡 Yellow/Orange | ![High](https://via.placeholder.com/80x20/ffc107/000000?text=High) | Important issues |
| **Medium** | 🔵 Cyan | ![Medium](https://via.placeholder.com/80x20/0dcaf0/000000?text=Medium) | Moderate priority |
| **Low** | ⚪ Gray | ![Low](https://via.placeholder.com/80x20/6c757d/ffffff?text=Low) | Low priority |
| **Info** | ⚪ Light | ![Info](https://via.placeholder.com/80x20/f8f9fa/000000?text=Info) | Informational only |

---

## 🏷️ Category Color Coding

Events are also color-coded by category:

| Category | Color Gradient | Icon | Description |
|----------|----------------|------|-------------|
| **Service Failure** | 🔴 Red → Dark Red | 🛠️ | Service crashes, startup failures |
| **Disk Issue** | 🟠 Orange | 💾 | Disk errors, storage problems |
| **Security** | 🟣 Purple | 🔒 | Security events, authentication |
| **Network** | 🔵 Blue | 🌐 | Network connectivity issues |
| **System** | 🟠 Orange | ⚙️ | System-level events |
| **Application** | 🟢 Teal | 📱 | Application errors |
| **Memory** | 🔵 Dark Blue | 🧠 | Memory-related issues |
| **Driver** | 🔴 Dark Red | 🚗 | Driver failures |
| **Registry** | 🟢 Green | 📋 | Registry issues |
| **Unknown** | ⚪ Gray | 🏷️ | Uncategorized events |

---

## 📊 Where You'll See Color Coding

### 1. **Dashboard Tab**
- Recent Events section shows severity badges
- Charts display color-coded data

### 2. **Events Tab**
- Each event row has:
  - **Category badge** (colored by category)
  - **Severity badge** (colored by severity)
- Filter events by severity or category

### 3. **Event Catalog Tab**
- All event definitions show:
  - Category badges with icons
  - Severity badges
- Search and filter by category/severity

### 4. **Rules Tab**
- Rules display associated category and severity
- Color-coded for quick identification

---

## 🕐 Historical Time Span: 1 Month

The event monitor now imports events from the **last 30 days (1 month)** by default, with a limit of **10,000 events**.

### What This Means:
- ✅ When you start the monitor, it imports up to 10,000 matching events from the past 30 days
- ✅ You'll see a complete month of historical data in your dashboard
- ✅ After initial import, it continues monitoring new events in real-time
- ✅ No more 50-event limit - now imports ALL historical events (up to 10,000)

### Configuration:

**Default Settings:**
- Historical Days: 30 (1 month)
- Max Historical Events: 10,000
- Max Events Per Poll: 100 (for real-time monitoring)

**Files Updated:**
- `collector/event_monitor.ps1` - Default: `HistoricalDays = 30`, `MaxHistoricalEvents = 10000`
- `collector/event_monitor_config.ps1` - Default: `HistoricalDays = 30`, `MaxHistoricalEvents = 10000`
- `collector/monitor_config.json` - `"historical_days": 30`, `"max_historical_events": 10000`
- `start_event_monitor.bat` - Uses `-HistoricalDays 30 -MaxHistoricalEvents 10000`

### Custom Time Ranges:

```powershell
# Import last 7 days
powershell -ExecutionPolicy Bypass -File collector\event_monitor.ps1 -HistoricalDays 7

# Import last 60 days (2 months) with more events
powershell -ExecutionPolicy Bypass -File collector\event_monitor.ps1 -HistoricalDays 60 -MaxHistoricalEvents 20000

# Import last 90 days (3 months) with even more events
powershell -ExecutionPolicy Bypass -File collector\event_monitor.ps1 -HistoricalDays 90 -MaxHistoricalEvents 50000

# Import ALL events from last 30 days (no limit)
powershell -ExecutionPolicy Bypass -File collector\event_monitor.ps1 -HistoricalDays 30 -MaxHistoricalEvents 999999

# Skip historical import (new events only)
powershell -ExecutionPolicy Bypass -File collector\event_monitor.ps1 -SkipHistorical
```

---

## 🎯 Visual Examples

### Event Row Example:
```
ID: 123 | Event ID: 7031 | Source: Service Control Manager
Category: [🛠️ Service Failure] (Red gradient)
Severity: [⚠️ Critical] (Red badge)
Description: Service crashed unexpectedly
Timestamp: 2026-02-11 10:30:45
```

### Dashboard Chart Colors:
- **Severity Chart** (Doughnut): Red, Yellow, Cyan, Gray
- **Category Chart** (Bar): Various gradient colors per category

---

## 🔧 How to Use

### Filter by Severity:
1. Go to **Events** or **Event Catalog** tab
2. Use the **Severity** dropdown filter
3. Select: Critical, High, Medium, Low, or Info

### Filter by Category:
1. Go to **Events** or **Event Catalog** tab
2. Use the **Category** dropdown filter
3. Select from available categories

### Search:
- Type in the search box to find events by:
  - Event ID
  - Source
  - Category name
  - Severity level
  - Description

---

## 📝 Summary

✅ **Severity Color Coding** - Red (Critical) → Yellow (High) → Cyan (Medium) → Gray (Low)  
✅ **Category Color Coding** - 10 distinct color gradients with icons  
✅ **Historical Time Span** - 30 days (1 month) by default  
✅ **Customizable** - Change time range via parameters or config file  
✅ **Visual Filters** - Filter by severity and category  
✅ **Consistent Design** - Color coding across all tabs  

**Your dashboard now provides instant visual feedback on event importance and type!** 🎨

