# Rule-Based Auto Remediation (Windows)

Lightweight PoC dashboard and collector for auto-remediation driven by Windows Event Logs.

## Features
- **Event Monitoring**: Collect and monitor Windows Event Log entries
- **Rule-Based Remediation**: Define rules to automatically remediate common issues
- **Event Definitions**: Pre-loaded with 40+ common Windows error events from `windows_error_events.json`
- **Metadata Enrichment**: Events are automatically enriched with category, severity, description, and recommended actions
- **Approval Workflow**: Manual approval process for sensitive remediation actions
- **Web Dashboard**: Modern, responsive UI for managing events, rules, and remediation history

## Quick Start

### 1. Setup Python Environment
```bash
python -m venv .venv
.\.venv\Scripts\activate
pip install -r backend\requirements.txt
```

### 2. Initialize Database
```bash
python backend\db_init.py
```

### 3. Start the Backend
```bash
python backend\app.py
```

### 4. Open the Dashboard
Navigate to: http://localhost:5000/

### 5. Import Event Rules from JSON
- Click on the "Rules" tab in the dashboard
- Click the "Import from JSON" button to automatically create rules from the `windows_error_events.json` file
- This will import rules for all events marked as `auto_remediate_candidate: true`

Alternatively, use the API:
```bash
curl -X POST -H "Content-Type: application/json" http://localhost:5000/api/populate-rules
```

### 6. Run the Event Collector
```powershell
powershell -ExecutionPolicy Bypass -File collector\collector.ps1 -MaxEvents 5 -LogName System
```

## Event Definitions

The `windows_error_events.json` file contains definitions for 40+ common Windows error events including:
- **Service Failures** (Event IDs: 7031, 7034, 7000, 7001, etc.)
- **Disk Issues** (Event IDs: 2013, 51, 55, etc.)
- **Application Crashes** (Event IDs: 1000, 1001, 1026)
- **Driver Failures** (Event IDs: 219, 4101)
- **Security Events** (Event IDs: 4625, 4740)
- **Network Issues** (Event IDs: 4201, 4227, 5719)
- **System Crashes** (Event IDs: 6008, 41, 1001)
- And more...

Each event definition includes:
- `event_id`: Windows Event ID
- `event_source`: Event source/provider name
- `category`: Event category (e.g., "Service Failure", "Disk I/O Error")
- `severity`: Severity level (Critical, High, Medium, Low, Info)
- `description`: Human-readable description
- `recommended_action`: Suggested remediation action
- `auto_remediate_candidate`: Whether this event is suitable for auto-remediation

## API Endpoints

### Events
- `GET /api/events` - List all events
- `POST /api/events` - Create a new event (automatically enriched with metadata from JSON)
- `GET /api/events/<id>/matches` - Get matching rules for an event

### Rules
- `GET /api/rules` - List all rules
- `POST /api/rules` - Create a new rule
- `GET /api/rules/<id>` - Get a specific rule
- `PUT /api/rules/<id>` - Update a rule
- `DELETE /api/rules/<id>` - Delete a rule
- `POST /api/rules/<id>/run` - Manually run a rule

### Event Definitions
- `GET /api/event-definitions` - Get all event definitions from JSON
- `GET /api/event-definitions/<event_id>?source=<source>` - Get a specific event definition
- `POST /api/populate-rules` - Populate rules from JSON file

### Approvals
- `GET /api/requests` - List remediation requests
- `POST /api/requests` - Create a remediation request
- `POST /api/requests/<id>/approve` - Approve a request
- `POST /api/requests/<id>/deny` - Deny a request

### History
- `GET /api/history` - Get remediation history

## Notes
- This is a starter scaffold. Enhance with authentication, persistent job execution, better rule language, and safe execution controls before using in production.
- The approval workflow allows manual review of remediation actions before execution
- Events are automatically enriched with metadata from the JSON file when ingested
- Rules can be manually created or imported from the JSON file
