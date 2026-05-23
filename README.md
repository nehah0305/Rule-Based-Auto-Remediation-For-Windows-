# 🛡️ Rule-Based Auto-Remediation For Windows

> **An intelligent, zero-friction system that monitors your Windows Event Logs and automatically fixes common system issues the moment they happen.**

Welcome to the Auto-Remediation platform! This system works like a silent IT administrator living inside your computer. It watches for crashes, service failures, and network drops, and instantly runs targeted PowerShell scripts to fix them before you even notice something broke.

---

## 🎯 What is this?

- **Real-Time Monitoring**: It watches your Windows Event Log silently in the background.
- **Smart Rule Matching**: When an error occurs (like an App Crash or a Service Failure), it matches it against a set of intelligent rules.
- **Auto-Remediation**: If it finds a match, it automatically executes a PowerShell script to fix it.
- **Beautiful Command Center**: It provides a stunning, premium web dashboard to let you monitor system health, view remediation history, and easily create your own custom rules.

---

## 📦 Prerequisites (You only need 1 thing!)

To run this system, you only need:
- **Python 3.9+** installed and added to your system PATH.

*(Note: You do **NOT** need to install Flutter or Dart! The beautiful user interface is already pre-built and packaged inside the `frontend/build/web` directory, ready to serve.)*

---

## 🚀 The 1-Minute Quick Start

We have made this as frictionless as possible. Follow these three steps to get up and running immediately.

### Step 1: Install & Setup
Run the included setup script. This will automatically install the required Python packages, initialize your local database, and load over 60 default remediation rules.

1. Open your terminal or command prompt.
2. Navigate to this project folder.
3. Run the setup script:
   ```cmd
   .\setup.bat
   ```
*(Alternatively, just double-click `setup.bat` from your File Explorer!)*

### Step 2: Start the System
Once setup is complete, start the backend server and the web dashboard:

1. Double-click on:
   ```cmd
   build_scripts\start_flutter_app.bat
   ```
*(This script will launch the Python backend which securely serves the web UI.)*

### Step 3: Open the Dashboard
Open your favorite web browser and navigate to the command center:
👉 **http://localhost:5000**

You are now in control!

---

## 💥 See It In Action (Simulate a Crash)

Want to see the auto-remediation engine actually work without breaking your real system? We have included a safe simulation script that fakes an Application Crash so you can see it auto-remediate instantly.

1. Keep your Dashboard open at `http://localhost:5000` (navigate to the **Events** or **History** tab).
2. Open PowerShell as Administrator in the project directory.
3. Run the crash simulator:
   ```powershell
   .\simulate_crash.ps1
   ```
4. **Watch the dashboard!** Within seconds, the system will detect the simulated crash, analyze it, and run the designated fix (which you will see pop up live in the History tab).

---

## 🎛️ Under the Hood: 24/7 Silent Monitoring

By default, you can click the **Start Polling** button inside the Web Dashboard to turn the monitoring on while the dashboard is open.

However, if you want the system to silently protect your computer 24/7 (even when the dashboard is closed, and without requiring a terminal window to stay open), run this script as **Administrator**:

```powershell
powershell -ExecutionPolicy Bypass -File remediation_scripts\Setup_EventTriggers.ps1
```

This installs stealthy Windows Task Scheduler triggers that instantly wake up the remediation engine the exact millisecond a bad event happens. **This utilizes 0% CPU while idle!**

---

## 📁 Where is everything?

If you want to poke around or customize the system, here is where everything lives:

- **`backend/app.py`**: The main brain. Starts the web server and the API.
- **`backend/models.py`**: Contains all database interactions and rule-matching logic.
- **`remediation_scripts/`**: A library of over 60+ PowerShell scripts ready to fix almost any Windows issue.
- **`windows_error_events.json`**: The dictionary of known Windows errors and their metadata.
- **`frontend/`**: The source code for the Flutter Dashboard (only needed if you want to modify the UI).

---

## 🛠️ Modifying the UI (For Developers)

If you are a developer and want to edit the beautiful Flutter interface:

1. Install [Flutter](https://flutter.dev/docs/get-started/install) (3.0+).
2. Open the `frontend` folder in your IDE (like VS Code).
3. Run `flutter run -d chrome` to start the development server.
4. The frontend is configured to proxy API requests to `localhost:5000` automatically.
5. When you are done making changes, build a new production web app by running:
   ```cmd
   build_scripts\rebuild_app.bat
   ```

---

## 🐛 Troubleshooting

- **The Dashboard won't load (`localhost refused to connect`)**
  Ensure you have started the backend by running `build_scripts\start_flutter_app.bat`. Check the terminal window for any Python errors (like missing dependencies).
  
- **I see Python errors during setup**
  Make sure you have installed Python 3.9+ and checked the box that says "Add Python to PATH" during the Windows installation.

- **Scripts are failing to run**
  Windows restricts PowerShell scripts by default. Open an Administrator PowerShell and run:
  `Set-ExecutionPolicy RemoteSigned`

---
**Maintained By**: Unisys Development Team
