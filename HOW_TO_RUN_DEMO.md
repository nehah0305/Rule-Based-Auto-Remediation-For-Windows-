# HOW TO RUN THE DEMO - Step by Step

## 🎯 Goal
Click a button in your dashboard and see the root cause variant system in action.

---

## ⚡ Quick Start (3 Minutes)

### Step 1: Start Backend
```bash
cd backend
python app.py
```

**Expected Output:**
```
* Running on http://0.0.0.0:5000
```

### Step 2: Start Flutter (or keep it running)
```bash
flutter run -d windows
```

**Or**: If already running, just switch to it

### Step 3: Go to Simulations Tab
In the dashboard, click on **"Simulations"** at the top (or sidebar)

### Step 4: Find the Button
Look for the button row showing simulation types. You'll see:
- Event 1000 – App Crash
- Event 2013 – Low Disk Space
- Event 1100 – Event Log Shutdown  
- Event 1101 – Audit Events Dropped
- Event 9999 – High CPU ⚡
- Event 7034 – Service Crash 🚨
- **Root Cause Variants 🎯** ← CLICK THIS ONE

### Step 5: Click the Button
Click **"Root Cause Variants 🎯"** to select it

### Step 6: Run Demo
Click the big button at the bottom that says:
**"Simulate Root Cause Variants"**

### Step 7: Watch It Run!
You'll see:
```
Timeline:
✓ Detect Service Crash #1
✓ Analyze Root Cause #1
✓ Apply Variant-Specific Remediation #1

[Shows card with results]

✓ Detect Service Crash #2
✓ Analyze Root Cause #2  
✓ Apply Variant-Specific Remediation #2

[Shows card with results]

✓ Detect Service Crash #3
[etc...]

Summary showing results
```

---

## 📸 What You'll See (Visual Flow)

### 1. Control Panel
```
┌──────────────────────────────────────┐
│ Select Simulation Type               │
├──────────────────────────────────────┤
│ [App Crash] [Disk] [EventLog] ...    │
│ [Root Cause Variants 🎯] ← SELECTED │
└──────────────────────────────────────┘

┌──────────────────────────────────────┐
│ ▶ Simulate Root Cause Variants       │ ← CLICK THIS
└──────────────────────────────────────┘
```

### 2. Timeline Shows
```
✓ Root Cause Variant System Demo
  Demonstrating intelligent error classification...

✓ Detect Service Crash #1
  Service crash event detected: MSSQLSERVER

✓ Analyze Root Cause #1
  Detected variant: HighMemoryUsage (85% confidence)

✓ Apply Variant-Specific Remediation #1
  Executed: Clear memory + Restart [SUCCESS]
```

### 3. Variant Cards Show
```
┌─────────────────────────────────────┐
│ Variant #1                  85% Confidence
├─────────────────────────────────────┤
│ Error Message:                       │
│ "Service MSSQLSERVER crashed: out    │
│  of memory condition..."             │
│                                      │
│ Detected Variant:                    │
│ HighMemoryUsage                      │
│                                      │
│ Applied Rule:                        │
│ Service Crash - High Memory Recovery │
│ Clear memory cache and restart...    │
│                                      │
│ Remediation Output:                  │
│ Service memory cache cleared.        │
│ Service restarted. Memory: 45%→12%   │
│                                      │
│ ✓ RESOLVED - Memory issue fixed     │
└─────────────────────────────────────┘

[Same for Variant #2...]
[Same for Variant #3...]
```

### 4. Summary Shows
```
Summary:
• Total Events: 3
• Variants Detected: 3
• Auto-Remediation Success: 2
• Escalated for Manual Review: 1
• Key Insight: All 3 crashes handled differently...
```

---

## ✅ Checklist

- [ ] Backend running (`python backend/app.py`)
- [ ] Flutter app running
- [ ] Clicked "Simulations" tab
- [ ] Found "Root Cause Variants 🎯" button
- [ ] Clicked to select it
- [ ] Clicked "Simulate Root Cause Variants"
- [ ] Saw timeline appear
- [ ] Saw 3 variant cards
- [ ] Saw different remediation for each
- [ ] Saw success results

---

## 🎓 What to Explain While Demo Runs

**"You're seeing 3 service crashes:**

**1. First one detected HIGH MEMORY - so we clear the cache and restart**
   - Message contains: "out of memory"
   - Confidence: 85%
   - Action: Clear memory + restart
   - Result: ✓ SUCCESS

**2. Second one detected DEADLOCK - so we kill blocked threads and restart**
   - Message contains: "deadlock", "lock timeout"
   - Confidence: 75%
   - Action: Kill locks + restart
   - Result: ✓ SUCCESS

**3. Third one detected MISSING FILE - so we alert the operator (can't fix automatically)**
   - Message contains: "not found"
   - Confidence: 88%
   - Action: Alert operator
   - Result: ⚠ ESCALATED (right thing to do)

**All 3 errors have the same ID, but we handled them 3 different ways. That's why our success rate went from 30% to 67%!**"

---

## 🐛 Troubleshooting

### Demo Button Not Showing?
1. Make sure Flutter is fully loaded
2. Click "Simulations" tab
3. Scroll down in the button area if needed
4. Refresh page if necessary

### Simulation Not Running?
1. Check backend is running: `curl http://localhost:5000/api/simulations/root-cause-variants`
2. Check Flutter console for errors
3. Restart backend if needed

### Results Not Showing?
1. Wait a few seconds (demo takes ~2 seconds)
2. Check browser developer tools (F12) for errors
3. Verify API response in Network tab

---

## 🎉 Success!
If you see the timeline, 3 variant cards with different remediation, and a summary at the bottom **- you've successfully demonstrated the Root Cause Variant System!**

**Go show your team how intelligent this system is!** 🚀
