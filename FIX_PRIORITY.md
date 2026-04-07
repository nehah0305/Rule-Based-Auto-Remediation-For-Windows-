# 🚀 QUICK FIX PRIORITY BOARD

## Phase 1: SECURITY LOCKDOWN (Do This First - No Excuses)

### P0.1: PowerShell Command Injection 🔴 CRITICAL
**Status:** Exploitable now  
**Location:** `backend/models.py` line ~758-830  
**Why:** Attacker can execute `cmd` as SYSTEM user  

**Current (VULNERABLE):**
```python
# In execute_remediation_script()
script_content = load_script(script_path)
# script_path could be: "C:\; del C:\* #"
cmd = f"powershell.exe -Command {script_path} {param1} {param2}"
os.system(cmd)  # Command injection!
```

**Fix (15 minutes):**
```python
import subprocess
# Use list (safe from injection)
cmd = [
    "powershell.exe", 
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", script_path,  # Separate from command, properly quoted
    "-ArgumentList", param1, param2  # Parameters as separate args
]
result = subprocess.run(cmd, capture_output=True, check=False)
```

---

### P0.2: Add Input Validation 🔴 CRITICAL
**Status:** Complete absence  
**Location:** `backend/app.py` (all POST endpoints)  
**Why:** Crashes, DoS, injection attacks  

**Current (NO VALIDATION):**
```python
@app.route('/api/events', methods=['POST'])
def create_event():
    data = request.json
    event = Event(
        name=data['name'],  # Could be 10MB!
        source=data['source'],  # Could contain SQL
        event_id=data.get('event_id')  # Could be wrong type
    )
    db.session.add(event)
    db.session.commit()
```

**Fix (30 minutes):**
```python
from marshmallow import Schema, fields, ValidationError

class EventSchema(Schema):
    name = fields.Str(required=True, validate=lambda x: len(x) <= 500)
    source = fields.Str(required=True, validate=lambda x: len(x) <= 200)
    event_id = fields.Int(required=False)
    timestamp = fields.DateTime(required=False)

event_schema = EventSchema()

@app.route('/api/events', methods=['POST'])
def create_event():
    try:
        data = event_schema.load(request.json)
    except ValidationError as err:
        return {"errors": err.messages}, 400
    
    event = Event(**data)
    db.session.add(event)
    db.session.commit()
    return jsonify(event.to_dict()), 201
```

---

### P0.3: Add HTTPS/TLS 🔴 CRITICAL
**Status:** All plaintext  
**Location:** Flask app initialization  
**Why:** Events and scripts sent unencrypted  

**Current (NO ENCRYPTION):**
```bash
python backend/app.py  # HTTP only, port 5000
```

**Fix (5 minutes):**
```bash
# Generate self-signed cert (one time):
openssl req -x509 -newkey rsa:4096 -nodes -out cert.pem -keyout key.pem -days 365

# Run with SSL:
python backend/app.py --ssl cert.pem key.pem

# Or in code:
app.run(
    host='0.0.0.0',
    port=5000,
    ssl_context=('cert.pem', 'key.pem')
)
```

---

### P0.4: Add Authentication 🔴 CRITICAL
**Status:** Anyone can do anything  
**Location:** All endpoints in `backend/app.py`  
**Why:** No access control  

**Current (NO AUTH):**
```python
@app.route('/api/rules', methods=['POST'])
def create_rule():
    # Anyone can create a rule that executes arbitrary code!
    rule = Rule(**request.json)
    db.session.add(rule)
    db.session.commit()
```

**Fix (1 hour - Simple API Key):**
```python
from functools import wraps

def require_api_key(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        token = request.headers.get('Authorization', '').replace('Bearer ', '')
        if not token or token != os.getenv('API_KEY'):
            return {"error": "Invalid API key"}, 401
        return f(*args, **kwargs)
    return decorated_function

@app.route('/api/rules', methods=['POST'])
@require_api_key  # Add this!
def create_rule():
    rule = Rule(**request.json)
    db.session.add(rule)
    db.session.commit()
```

**Or (2-3 hours - Proper JWT):**
```python
import jwt

# Client gets token:
POST /api/auth/login { "username": "admin", "password": "..." }
Response: { "token": "eyJ0eXAiOiJKV1QiLCJhbGc..." }

# Client uses token:
GET /api/events
Authorization: Bearer eyJ0eXAiOiJKV1QiLCJhbGc...

# Server validates:
def verify_token(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        token = request.headers.get('Authorization', '').replace('Bearer ', '')
        try:
            payload = jwt.decode(token, 'secret_key', algorithms=['HS256'])
            request.user = payload
        except:
            return {"error": "Invalid token"}, 401
        return f(*args, **kwargs)
    return decorated_function
```

---

### P0.5: Fix Silent Failures 🔴 CRITICAL
**Status:** Errors silently ignored  
**Location:** `backend/event_log_monitor.py` and everywhere  
**Why:** System breaks, nobody knows  

**Current (SILENCE IS FAIL):**
```python
def poll_events():
    try:
        events = get_events_from_windows()
        process_events(events)
    except Exception as e:
        pass  # 🤦 WRONG!
```

**Fix (10 minutes):**
```python
import logging
from logging.handlers import RotatingFileHandler

# Setup logging EARLY
log_handler = RotatingFileHandler('logs/app.log', maxBytes=10*1024*1024, backupCount=5)
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[log_handler, logging.StreamHandler()]
)
logger = logging.getLogger(__name__)

def poll_events():
    try:
        logger.info("Starting event poll")
        events = get_events_from_windows()
        logger.info(f"Retrieved {len(events)} events")
        process_events(events)
        logger.info("Poll completed successfully")
    except Exception as e:
        logger.error(f"Poll failed: {e}", exc_info=True)  # exc_info = full traceback
        # Could also email alert
```

---

## Phase 2: OPERATIONAL STABILITY (4-6 hours)

### P1.1: Add Database Indexes
**Location:** `backend/models.py` (table definitions)  
**Why:** Slow with 10K+ events  

```python
# In models.py
class Event(db.Model):
    __tablename__ = 'events'
    
    id = db.Column(db.Integer, primary_key=True)
    event_id = db.Column(db.Integer, index=True)  # ADD THIS LINE
    timestamp = db.Column(db.DateTime, index=True)  # ADD THIS LINE
    source = db.Column(db.String(200), index=True)  # ADD THIS LINE

# Or from command line:
sqlite3 rules.db "CREATE INDEX idx_event_id ON events(event_id)"
sqlite3 rules.db "CREATE INDEX idx_timestamp ON events(timestamp)"
```

---

### P1.2: Add Cooldown Window
**Location:** Add to `models.py`  
**Why:** Prevent event storms causing 1000 remediations/second  

```python
from datetime import datetime, timedelta

def should_remediate(rule, event):
    """Check if rule should remediate, respecting cooldown"""
    
    # Only remediate once per 5 minutes per rule per event source
    cutoff = datetime.utcnow() - timedelta(minutes=5)
    
    recent_remediation = db.session.query(Remediation).filter(
        Remediation.rule_id == rule.id,
        Remediation.event_source == event.source,
        Remediation.timestamp > cutoff
    ).first()
    
    return recent_remediation is None  # Safe to remediate

# Use in remediation engine:
for rule in matching_rules:
    if should_remediate(rule, event):
        execute_remediation(rule, event)
```

---

### P1.3: Add Pagination
**Location:** `backend/app.py` (history endpoint)  
**Why:** Prevent 50MB JSON responses  

```python
@app.route('/api/history')
def get_history():
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 50, type=int)
    
    if per_page > 500:  # Sanity check
        per_page = 500
    
    query = db.session.query(Remediation)
    total = query.count()
    
    items = query.offset((page - 1) * per_page).limit(per_page).all()
    
    return jsonify({
        'items': [item.to_dict() for item in items],
        'total': total,
        'page': page,
        'pages': (total + per_page - 1) // per_page
    })
```

---

### P1.4: Add Rate Limiting
**Location:** `backend/app.py` (top)  
**Why:** Prevent DoS attacks  

```bash
pip install Flask-Limiter
```

```python
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

limiter = Limiter(
    app=app,
    key_func=get_remote_address,
    default_limits=["200 per day", "50 per hour"]
)

@app.route('/api/events', methods=['POST'])
@limiter.limit("10 per minute")  # Max 10 events/minute
def create_event():
    ...
```

---

### P1.5: Fix Event Watermark Persistence
**Location:** `backend/event_log_monitor.py`  
**Why:** Prevent duplicate remediations  

**Current (SAVE AT END ONLY):**
```python
def poll_events():
    events = get_all_events()  # 1000 events
    for event in events:
        process_event(event)
    save_watermark()  # Saved at END - if crashes, lost all progress!
```

**Fix (SAVE AFTER EACH):**
```python
def poll_events():
    events = get_all_events()
    for event in events:
        process_event(event)
        save_watermark(event.timestamp)  # Saved immediately for each event
```

---

## Phase 3: TESTING & OBSERVABILITY (4-6 hours)

### P2.1: Add Unit Tests (Start Small)
**Location:** Create `backend/tests/` directory  

```python
# backend/tests/test_models.py
import pytest
from backend.models import Event, db

def test_event_creation():
    event = Event(name="Test", source="System", event_id=1000)
    assert event.name == "Test"
    assert event.event_id == 1000

def test_event_validation():
    # Should reject invalid data
    with pytest.raises(ValueError):
        event = Event(name="X" * 1000)  # Too long

# Run:
pytest backend/tests/ -v
```

---

### P2.2: Add Health Check Endpoint
**Location:** `backend/app.py`  

```python
@app.route('/health', methods=['GET'])
def health_check():
    """Verify system is operational"""
    
    checks = {
        'status': 'healthy',
        'database': 'unknown',
        'monitor': 'unknown',
        'timestamp': datetime.utcnow().isoformat()
    }
    
    # Check database
    try:
        db.session.query(Event).first()
        checks['database'] = 'ok'
    except Exception as e:
        checks['database'] = f'error: {e}'
        checks['status'] = 'degraded'
    
    # Check if monitor is recent
    last_poll = get_last_poll_time()
    if datetime.utcnow() - last_poll > timedelta(minutes=5):
        checks['monitor'] = 'stale'
        checks['status'] = 'degraded'
    else:
        checks['monitor'] = 'ok'
    
    http_code = 200 if checks['status'] == 'healthy' else 503
    return jsonify(checks), http_code

# Monitor this endpoint:
curl http://localhost:5000/health
```

---

## Summary: Quick Wins Checklist

```
SECURITY LOCKDOWN (2-3 days):
□ Fix PowerShell injection (15 min)
□ Add input validation (30 min)
□ Add HTTPS (5 min)
□ Add API auth (1-3 hours)
□ Fix logging (10 min)

STABILITY (1 day):
□ Add DB indexes (30 min)
□ Add cooldown (1 hour)
□ Add pagination (1 hour)
□ Add rate limiting (30 min)
□ Fix watermark (1 hour)

OBSERVABILITY (1-2 days):
□ Add health check (1 hour)
□ Add unit tests (4+ hours)
□ Add logging framework (1 hour)
□ Add metrics (1+ hour)

TOTAL: ~20-25 hours = 3-4 days solid work

PAYOFF: Secure, stable, observable system
```

---

## Which Should You DID FIRST?

**Honest Assessment:**
1. **PowerShell injection** - 15 min, critical security
2. **Input validation** - 30 min, critical security  
3. **API auth** - 3 hours, critical for multi-user
4. **Logging** - 10 min, helps everything
5. **Health check** - 1 hour, operational visibility

**Total: 5 hours gets you 80% of the benefit**

**Do these 5 things before deploying to production or more users.**
