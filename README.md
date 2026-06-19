# 🛡️ Rule-Based Auto-Remediation for Windows

An intelligent system that watches your Windows Event Log in real time and automatically runs PowerShell scripts to fix common issues (app crashes, service failures, disk errors) the moment they happen — before you even notice.

A web-based dashboard lets you monitor system health, view remediation history, and manage rules.

---

## 🧠 How It Works

1. **Monitor** — A background thread polls the Windows Event Log continuously.
2. **Match** — Incoming events are matched against a library of rules (e.g. Event ID 1000 = App Crash).
3. **Remediate** — If a rule is matched, the corresponding PowerShell script runs automatically.
4. **Dashboard** — A Flutter web UI (served at `localhost:5000`) gives you full visibility and control.

---

## ✅ Prerequisites

| Requirement | Notes |
|---|---|
| **Python 3.9+** | Must be on your system PATH |
| **Flutter SDK** | Only needed if you want to modify the UI |
| **Git** | Only needed to install Flutter from source |

> **You do NOT need Flutter to run the app.** The UI is pre-built and served by the Python backend.

---

## 🚀 Running the App

### 1. Install Python dependencies

```powershell
cd backend
pip install -r requirements.txt
```

### 2. Initialize the database

Only needed on first run (or if `rules.db` is missing):

```powershell
python db_init.py
```

### 3. Start the backend

```powershell
python app.py
```

Wait until you see:
```
Starting Flask server on 0.0.0.0:5000
```

### 4. Open the dashboard

Go to **http://localhost:5000** in your browser. Done!

---

## 💥 Simulate a Crash (Demo)

Want to see auto-remediation in action without breaking anything real?

1. Open the dashboard and go to the **Events** or **History** tab.
2. In a PowerShell window (run as **Administrator**), from the project root:

```powershell
.\simulate_crash.ps1
```

3. Watch the dashboard — the system will detect the fake crash and log the remediation within seconds.

---

## ⚙️ 24/7 Silent Protection (Optional)

By default, monitoring only runs while `app.py` is active.

To enable always-on protection via **Windows Task Scheduler** (zero CPU when idle, survives reboots):

```powershell
# Run as Administrator
powershell -ExecutionPolicy Bypass -File remediation_scripts\Setup_EventTriggers.ps1
```

This registers Windows event triggers that wake the remediation engine the instant a bad event fires.

---

## 🗂️ Project Structure

```
.
├── backend/
│   ├── app.py              # Flask server + all API routes
│   ├── db_init.py          # Database schema setup & migrations
│   ├── models.py           # Rule matching, DB queries
│   ├── event_log_monitor.py# Background Windows Event Log poller
│   ├── requirements.txt    # Python dependencies
│   └── data/               # SQLite DB + logs (auto-created)
├── frontend/               # Flutter source (only for UI development)
├── remediation_scripts/    # 60+ PowerShell remediation scripts
├── simulate_crash.ps1      # Safe crash simulator for demos
└── windows_error_events.json # Known Windows error metadata
```

---

## 🛠️ Modifying the UI (Developers Only)

Only needed if you want to change the Flutter frontend:

### Install Flutter

```powershell
# One-time setup using Git
mkdir C:\tools; cd C:\tools
git clone https://github.com/flutter/flutter.git -b stable
[System.Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\tools\flutter\bin", "User")
# Restart your terminal, then:
flutter doctor
```

### Run in development mode

```powershell
cd frontend
flutter run -d chrome
```

The Flutter dev server proxies API calls to `localhost:5000` automatically (keep `app.py` running).

### Deploy your changes

```powershell
cd frontend
flutter build web --release
```

Then copy `frontend/build/web/` contents to `backend/static/` and restart `app.py`.

---

## 🐛 Troubleshooting

| Problem | Fix |
|---|---|
| `localhost:5000` not loading | Make sure `python app.py` is still running in the terminal |
| Python errors on startup | Confirm Python 3.9+ is installed and on PATH |
| PowerShell scripts blocked | Run `Set-ExecutionPolicy RemoteSigned` as Administrator |
| `flutter` not recognized | Flutter is not installed or not on PATH — see the Flutter install steps above |

---

*Maintained by the Unisys Development Team.*
