# 🛡️ Rule-Based Auto-Remediation for Windows

An intelligent system that watches your Windows Event Log in real time and automatically runs PowerShell scripts to fix common issues (app crashes, service failures, disk errors) the moment they happen — before you even notice.

A Flutter desktop app gives you a live dashboard: system health, pending operator approvals, remediation history, and full rule management.

---

## 🧠 How It Works

1. **Monitor** — A background thread polls the Windows Event Log continuously.
2. **Match** — Incoming events are matched against a library of 50+ rules (e.g. Event ID 1000 = App Crash).
3. **Gate** — The first time a new (event, app) combination appears, it's held for **operator approval**. Approve once, and that exact combination auto-remediates forever after.
4. **Remediate** — The matched PowerShell script runs (restart the app/service, clear resources, etc.), followed by closed-loop verification.
5. **Dashboard** — The Flutter desktop UI gives full visibility and control.

---

## ✅ Prerequisites

| Requirement | Notes |
|---|---|
| **Windows 10 / 11** | The Event Log + PowerShell integration is Windows-only |
| **Python 3.10+** | On PATH. Check with `python --version` |
| **PowerShell** | Built into Windows (5.1 is fine) |
| **Flutter SDK** | For the desktop UI. Needs Windows desktop support: Visual Studio with the **"Desktop development with C++"** workload |
| **Administrator PowerShell** | Only for the crash/service **simulation scripts** (they write real Windows Event Log entries) |

---

## 🚀 Quickstart (fresh clone → running app)

From the project root, in PowerShell:

```powershell
# 1. One-time setup: checks your environment, creates .venv, installs deps, creates .env
powershell -ExecutionPolicy Bypass -File setup.ps1

# 2. Start the backend (terminal 1) — keep it running
powershell -ExecutionPolicy Bypass -File run_backend.ps1

# 3. Start the desktop app (terminal 2)
powershell -ExecutionPolicy Bypass -File run_frontend.ps1
```

That's it. The database is created and seeded with all rules automatically on first backend start — no manual DB step needed.

**Port 5000 already taken?** Set `FLASK_PORT=5001` in `.env`, then start the UI with:
```powershell
powershell -ExecutionPolicy Bypass -File run_frontend.ps1 -ApiUrl http://localhost:5001
```

---

## 💥 Simulate a Crash (Demo)

Run these from an **Administrator** PowerShell in the project root, with the backend running:

```powershell
# Application crash (Event 1000) — kills the app, writes the event, remediation relaunches it
.\simulate_crash.ps1 -AppName "notepad"
.\simulate_crash.ps1 -AppName "winword"     # any of: excel, powerpnt, msedge, mspaint, ...

# Service crash (Event 7034) — Print Spooler by default; remediation restarts the service
.\remediation_scripts\Simulate_ServiceCrash.ps1

# One injector for EVERY active rule (shows real action + risk level per rule)
.\remediation_scripts\Test-RemediationRules.ps1 -List
.\remediation_scripts\Test-RemediationRules.ps1 -EventId 7031 -Force -TriggerPoll
```

The first crash of a given app shows up under **Approvals** — click Approve, and that app auto-remediates on every future crash.

---

## ⚙️ 24/7 Silent Protection (Optional)

By default, monitoring only runs while the backend is active. For always-on protection via **Windows Task Scheduler** (zero CPU when idle, survives reboots):

```powershell
# Run as Administrator
powershell -ExecutionPolicy Bypass -File remediation_scripts\Setup_EventTriggers.ps1
```

Then set `USE_TASK_SCHEDULER=true` in `.env` and restart the backend.

---

## 🗂️ Project Structure

```
.
├── setup.ps1               # One-time environment setup (run first)
├── run_backend.ps1         # Starts Flask backend with preflight checks
├── run_frontend.ps1        # Starts the Flutter desktop app
├── .env.example            # Configuration template (copied to .env by setup)
├── backend/
│   ├── app.py              # Flask server + all API routes
│   ├── db_init.py          # DB schema setup & migrations (runs automatically)
│   ├── models.py           # Rule matching, remediation engine, DB queries
│   ├── event_log_monitor.py# Background Windows Event Log poller
│   ├── rules_manifest.json # Seed data: all rules (loaded on first start)
│   ├── requirements.txt    # Python dependencies
│   ├── tests/              # Backend test suite (pytest)
│   └── data/               # Logs + CSV exports (auto-created, not in git)
├── frontend/               # Flutter app (Windows desktop + web)
├── remediation_scripts/    # 60+ PowerShell remediation & simulation scripts
├── simulate_crash.ps1      # Safe crash simulator for demos
└── windows_error_events.json # Known Windows error metadata
```

`backend/rules.db` (your local event history, approvals, and rule tweaks) is intentionally **not** in git — every clone starts with a clean, fully-seeded database.

---

## 🖥️ UI Development

```powershell
cd frontend
flutter run -d windows          # desktop app with hot reload
```

Optional web build — the backend automatically serves `frontend/build/web/` at `http://localhost:5000` when it exists:

```powershell
cd frontend
flutter build web --release
```

---

## ⚠️ Known Limitations

- **English Windows only (for real events).** Rule matching keys on English provider names ("Application Error", "Service Control Manager") and message text ("Faulting application name: …"). On non-English Windows, *real* events won't match — the simulation scripts still work, since they write English text.
- **Microsoft Store (UWP) apps** can be crash-simulated but usually can't be auto-relaunched (they require package-identity launch).
- **Antivirus** may flag simulation scripts (they terminate processes by design). Add an exclusion for the project folder if needed.

---

## 🐛 Troubleshooting

| Problem | Fix |
|---|---|
| `run_backend.ps1` says port in use | Set `FLASK_PORT` in `.env`; start UI with `-ApiUrl http://localhost:<port>` |
| Python errors on startup | Confirm Python 3.10+ on PATH, re-run `setup.ps1` |
| PowerShell scripts blocked | Use `powershell -ExecutionPolicy Bypass -File <script>` as shown above |
| `flutter` not recognized | Install the Flutter SDK and add it to PATH (`flutter doctor` must pass) |
| Simulations don't create events | Run them from an **Administrator** PowerShell |
| Desktop build fails | In Visual Studio Installer, add the "Desktop development with C++" workload |
