# Rule-Based Auto Remediation (Windows)

Lightweight PoC dashboard and collector for auto-remediation driven by Windows Event Logs.

Quick start
1. Create a Python virtualenv and install requirements:
   - python -m venv .venv
   - .\.venv\Scripts\activate
   - pip install -r backend\requirements.txt
2. Start the backend:
   - python backend\app.py
3. Open the dashboard: http://localhost:5000/
4. Add a rule using curl or Postman:
   - curl -X POST -H "Content-Type: application/json" -d "{\"name\":\"Sample\",\"event_id\":7045,\"remediation_script\":\"remediation_scripts\\sample_remediation.ps1\",\"auto_remediate\":true}" http://localhost:5000/api/rules
5. Run the collector to send events:
   - powershell -ExecutionPolicy Bypass -File collector\collector.ps1 -MaxEvents 5 -LogName System

Notes
- This is a starter scaffold. Enhance with authentication, persistent job execution, better rule language, and safe execution controls before using in production.
- Added simple approval workflow: manual remediation requests are created from the Events -> Matches dialog using the "Request" button; open the Approvals tab to approve or deny requests (admin action).
