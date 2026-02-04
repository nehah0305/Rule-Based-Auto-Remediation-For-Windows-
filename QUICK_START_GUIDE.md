# Quick Start Guide - Windows Error Events Integration

## Getting Started in 5 Minutes

### Step 1: Install Dependencies
```bash
# Create virtual environment
python -m venv .venv

# Activate virtual environment
.\.venv\Scripts\activate

# Install requirements
pip install -r backend\requirements.txt
```

### Step 2: Initialize Database
```bash
python backend\db_init.py
```

You should see:
```
Initialized DB at D:\Programming\Unisys\Rule-Based-Auto-Remediation-For-Windows-\backend\rules.db
```

### Step 3: Import Rules from JSON (Option A - Web UI)
```bash
# Start the backend server
python backend\app.py
```

Then:
1. Open your browser to http://localhost:5000
2. Click on the **"Rules"** tab
3. Click the **"Import from JSON"** button
4. Confirm the import

You should see a success message showing how many rules were created!

### Step 3: Import Rules from JSON (Option B - Command Line)
```bash
# Run the populate script
python backend\populate_rules.py
```

Follow the prompts:
- Choose option **1** to add new rules (recommended for first time)
- The script will show you how many rules were created

### Step 4: Explore the Dashboard

#### Events Tab
- View all collected Windows events
- See **Category**, **Severity**, and **Description** for each event
- Click **"Rules"** button to see which rules match an event

#### Rules Tab
- View all imported rules
- See severity levels with color-coded badges:
  - 🔴 **Critical** (red)
  - 🟡 **High** (yellow)
  - 🔵 **Medium** (blue)
  - ⚪ **Low** (gray)
- Edit rules to add remediation scripts
- Enable auto-remediation for specific rules

#### Approvals Tab
- Review pending remediation requests
- Approve or deny remediation actions
- See execution results

#### History Tab
- View past remediation attempts
- Check success/failure status
- Review execution output

### Step 5: Collect Real Events
```powershell
# Run the collector to send events from Windows Event Log
powershell -ExecutionPolicy Bypass -File collector\collector.ps1 -MaxEvents 10 -LogName System
```

The collector will:
1. Read the latest 10 events from the System log
2. Send them to the API
3. Events will be automatically enriched with metadata from the JSON file
4. Matching rules will be identified

### Step 6: Enable Auto-Remediation (Optional)

⚠️ **Important**: Only enable auto-remediation after thorough testing!

1. Go to the **Rules** tab
2. Click **Edit** on a rule
3. Add a PowerShell remediation script path (e.g., `remediation_scripts\restart_service.ps1`)
4. Check **"Enable Auto-Remediation"**
5. Click **Save Rule**

Now when matching events occur, the remediation will run automatically!

## Understanding the JSON File

The `windows_error_events.json` file contains 40+ event definitions. Each entry looks like:

```json
{
    "event_id": 7031,
    "event_source": "Service Control Manager",
    "category": "Service Failure",
    "severity": "High",
    "description": "A Windows service terminated unexpectedly.",
    "recommended_action": "Restart the affected service",
    "auto_remediate_candidate": true
}
```

### Key Fields:
- **event_id**: Windows Event ID number
- **event_source**: The source/provider of the event
- **category**: Logical grouping (e.g., "Service Failure", "Disk I/O Error")
- **severity**: Impact level (Critical, High, Medium, Low, Info)
- **description**: What the event means
- **recommended_action**: What should be done
- **auto_remediate_candidate**: Whether this event is safe for auto-remediation

### Events Marked for Auto-Remediation:
Only 10 events are marked as `auto_remediate_candidate: true`:
1. **7031** - Service terminated unexpectedly
2. **7034** - Service terminated without reporting status
3. **7000** - Service failed to start
4. **7001** - Service failed due to dependency
5. **2013** - Low disk space
6. **1000** - Application crash
7. **1001** - Application hang
8. **1026** - .NET runtime crash

These are considered safe for automated remediation with proper scripts.

## Common Tasks

### Add a Custom Event Definition
Edit `windows_error_events.json` and add:
```json
{
    "event_id": 1234,
    "event_source": "MyApplication",
    "category": "Custom Category",
    "severity": "Medium",
    "description": "My custom event description",
    "recommended_action": "Restart MyApplication service",
    "auto_remediate_candidate": true
}
```

Then re-import rules via the dashboard.

### Create a Remediation Script
Create a PowerShell script in `remediation_scripts\`:

```powershell
# restart_service.ps1
param([string]$ServiceName = "MyService")

try {
    Restart-Service -Name $ServiceName -Force
    Write-Output "Successfully restarted $ServiceName"
    exit 0
} catch {
    Write-Error "Failed to restart $ServiceName: $_"
    exit 1
}
```

Then add the script path to your rule.

### Test a Rule Manually
1. Go to **Events** tab
2. Click **"Rules"** on an event
3. Click **"Request"** on a matching rule
4. Go to **Approvals** tab
5. Click **"Approve"** to execute

### View API Documentation
All API endpoints are documented in the README.md file.

## Troubleshooting

### No rules imported?
- Check that `windows_error_events.json` exists in the root directory
- Verify the JSON is valid (use a JSON validator)
- Check the console for error messages

### Events not enriched?
- Ensure the event_id and source match entries in the JSON file
- Check that the JSON file is being loaded (look for console messages)

### Remediation not running?
- Verify the PowerShell script path is correct
- Check that the script has execute permissions
- Review the History tab for error messages

## Next Steps

1. ✅ Import rules from JSON
2. ✅ Collect some events
3. ✅ Review the enriched event data
4. ✅ Create remediation scripts for common issues
5. ✅ Test remediation manually via the Approvals workflow
6. ✅ Enable auto-remediation for low-risk events
7. ✅ Monitor the History tab for results

## Support

For issues or questions:
- Check the `INTEGRATION_SUMMARY.md` for technical details
- Review the `README.md` for API documentation
- Check the browser console for JavaScript errors
- Check the Python console for backend errors

