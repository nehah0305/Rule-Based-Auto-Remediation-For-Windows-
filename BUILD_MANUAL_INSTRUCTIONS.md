# FLUTTER BUILD INSTRUCTIONS - MANUAL 

Due to PowerShell/CMD.exe interaction issues, please follow these manual steps:

## **IMPORTANT: Use Command Prompt (CMD), NOT PowerShell**

### Step 1: Open Command Prompt **AS ADMINISTRATOR**
- Press `Windows Key`
- Type: `cmd`
- Right-click on "Command Prompt"
- Select "Run as administrator"

### Step 2: Run the Build Script
```cmd
cd c:\Users\bios\Desktop\unisys-ab\Rule-Based-Auto-Remediation-For-Windows-
build.bat
```

### What You Should See:
```
================================================================================
                      FLUTTER BUILD
================================================================================

Building Flutter web app...
This may take a few minutes...

Cleaning...
Getting dependencies...
Building...

(Wait 2-5 minutes...)

================================================================================
                    BUILD COMPLETE!
================================================================================

The app has been rebuilt successfully!
```

### If It Still Fails:

**Option 1: Manual Step-by-Step Build**
```cmd
cd c:\Users\bios\Desktop\unisys-ab\Rule-Based-Auto-Remediation-For-Windows-\frontend

REM Check git
where git

REM Get dependencies  
c:\flutter\bin\flutter.bat pub get

REM Build web
c:\flutter\bin\flutter.bat build web --release
```

**Option 2: Use Alternative Flutter Channel**
```cmd
c:\flutter\bin\flutter.bat channel stable
c:\flutter\bin\flutter.bat build web --release
```

---

## After Build Completes:

1. **Verify build succeeded**
   - Check that `frontend\build\web\main.dart.js` exists
   - File should be dated TODAY

2. **Test with browser**
   - Ensure Flask backend running: `python backend\app.py`
   - Open: http://localhost:5000
   - Go to **Simulation** tab
   - Click **"High CPU Alert"**
   - Click **"Auto-Remediate"**
   - Go to **History** tab
   - ✅ New entry should appear **IMMEDIATELY** without refresh!

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "git not found" | Install from https://git-scm.com/download/win then restart CMD |
| Build hangs | Reboot computer, try again in fresh CMD window |
| "flutter not found" | Verify C:\flutter\bin\flutter.bat exists |
| Dart compilation errors | Check Dart file syntax in frontend/lib/screens/ |
| Old build runs | Ctrl+Shift+R in browser to clear cache |

---

## Success Criteria

- [x] Dart files updated with Consumer<RemediationService>
- [ ] Flutter build completes without errors
- [ ] frontend/build/web/main.dart.js is updated (today's date)
- [ ] Backend running and serving app at http://localhost:5000
- [ ] Inject alert → Remediate → History auto-updates WITHOUT page refresh

Once ✅ all items, your remediation auto-refresh is WORKING!

---

**Current Status:**
✅ Code changes complete
✅ Git now installed
⏳ **Waiting: Run build.bat from CMD as Administrator**
