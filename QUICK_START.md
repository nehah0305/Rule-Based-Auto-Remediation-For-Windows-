# Root Cause Variant System - Quick Start Guide

## TL;DR - Get Running in 5 Minutes

### 1. **Database Migration** (Automatic)
```bash
cd backend
python db_init.py
```
Done! Tables created, columns added, all backward compatible.

### 2. **Define Root Causes** (5 minutes)
```python
from backend.root_cause_analyzer import get_analyzer

analyzer = get_analyzer()
analyzer.register_variant_pattern(1003, {
    'variant_id': 'high_memory',
    'label': 'HighMemoryUsage',
    'message_patterns': [(r'(?i)memory|heap', 3)],
    'required_keywords': ['memory'],
})
```

### 3. **Create Variant-Specific Rules** (5 minutes)
```python
from backend.models import add_rule, link_rule_to_variant

rule = add_rule(
    name='Fix High Memory',
    event_id=1003,
    remediation_script='ClearCache.ps1',
    auto_remediate=1,
    priority=10
)

link_rule_to_variant(
    rule_id=rule,
    variant_id='high_memory',
    min_confidence=70
)
```

Done! Your system now detects root causes and applies targeted fixes.

---

## Step-by-Step Implementation

### Step 1: Install & Migrate Database

```bash
# Navigate to backend
cd backend

# Initialize database (creates new tables, adds columns)
python db_init.py

# Output:
# Added column root_cause_variant_id to events table
# Added column root_cause_variant_label to events table
# Added column root_cause_confidence to events table
# Added column detected_root_causes to events table
# Initialized DB at ...
```

**What happened:**
- ✅ Migration is non-breaking
- ✅ Existing data unchanged
- ✅ Old rules continue working
- ✅ New tables created for variant tracking

### Step 2: Analyze Your Errors

Collect real error messages from your environment:

```
Service NetworkConnector crashed: out of memory, failed to allocate 2GB heap
Service Database crashed: lock timeout after 10 minutes waiting
Application Excel crashed: file not found - workbook.xlsm
```

**For each error, identify:**
- **Root cause keywords** - What actually failed
- **Key indicators** - Patterns that signify this cause
- **Confidence level** - How certain we can be

### Step 3: Register Error Variants

Create a variant pattern for each root cause:

```python
from backend.root_cause_analyzer import get_analyzer

analyzer = get_analyzer()

# Variant 1: High Memory
analyzer.register_variant_pattern(1003, {
    'variant_id': 'svc_crash_high_memory',
    'label': 'HighMemoryUsage',
    'description': 'Service ran out of memory',
    'message_patterns': [
        (r'(?i)(out of memory|heap|memory allocation)', 3),
        (r'(?i)(allocat|memory error)', 2),
        (r'memory', 1),
    ],
    'required_keywords': ['memory'],
    'context_checks': [
        {'field': 'severity', 'values': ['error', 'critical'], 'weight': 1},
    ],
})

# Variant 2: Deadlock
analyzer.register_variant_pattern(1003, {
    'variant_id': 'svc_crash_deadlock',
    'label': 'DeadlockOrLock',
    'description': 'Service lockup/deadlock',
    'message_patterns': [
        (r'(?i)(deadlock|lock timeout|blocked|wait)', 3),
    ],
    'required_keywords': ['deadlock', 'lock'],
})

# Variant 3: Missing File
analyzer.register_variant_pattern(1003, {
    'variant_id': 'svc_crash_missing_file',
    'label': 'MissingFile',
    'description': 'Required file not found',
    'message_patterns': [
        (r'(?i)(not found|missing|cannot find)', 3),
        (r'(?i)(file|dll|module)', 1),
    ],
    'required_keywords': ['not found'],
})
```

**Tips for effective patterns:**
- Use `(?i)` for case-insensitive matching
- Use high weight (3) for definitive indicators
- Use low weight (1) for supporting indicators
- Include message keywords as required
- Match against actual error messages in your logs

### Step 4: Create Remediation Rules

For each variant, create a specific remediation rule:

```python
from backend.models import add_rule, link_rule_to_variant

# Rule for Memory variant
rule_memory = add_rule(
    name='Service Crash - Memory Recovery',
    event_id=1003,
    source='Service Control Manager',
    remediation_script='remediation_scripts/ClearMemory_Restart.ps1',
    auto_remediate=1,
    priority=10,
    category='Service',
    severity='error',
)

link_rule_to_variant(
    rule_id=rule_memory,
    variant_id='svc_crash_high_memory',
    variant_label='HighMemoryUsage',
    min_confidence=70  # Only apply if 70%+ confident
)

# Rule for Deadlock variant
rule_deadlock = add_rule(
    name='Service Crash - Deadlock Recovery',
    event_id=1003,
    source='Service Control Manager',
    remediation_script='remediation_scripts/KillLockedProcesses.ps1',
    auto_remediate=1,
    priority=11,
    category='Service',
    severity='error',
)

link_rule_to_variant(
    rule_id=rule_deadlock,
    variant_id='svc_crash_deadlock',
    variant_label='DeadlockOrLock',
    min_confidence=60  # More permissive for locks
)

# Rule for Missing File variant
rule_missing = add_rule(
    name='Service Crash - Report Missing Dependency',
    event_id=1003,
    source='Service Control Manager',
    remediation_script='remediation_scripts/AlertDependencyMissing.ps1',
    auto_remediate=0,  # Require manual approval
    priority=5,
    category='Service',
    severity='critical',
)

link_rule_to_variant(
    rule_id=rule_missing,
    variant_id='svc_crash_missing_file',
    variant_label='MissingFile',
    min_confidence=80  # High confidence for alerting
)

# Legacy fallback rule (no variant - applies to any crash)
rule_fallback = add_rule(
    name='Service Crash - Emergency Restart',
    event_id=1003,
    source='Service Control Manager',
    remediation_script='remediation_scripts/RestartService.ps1',
    auto_remediate=1,
    priority=100,  # Lowest priority
    category='Service',
    severity='error',
)
# NOT linked to any variant - executes if no variant-specific rules apply
```

**Key Decision Points:**

| Factor | Setting | Rationale |
|--------|---------|-----------|
| **Auto-remediate** | 1 (high confidence) or 0 (manual) | Don't auto-fix if risk is high |
| **Min-confidence** | 70-100 for auto, 40-60 for alerts | Match confidence to action type |
| **Priority** | Lower number = higher priority | Run best match first |
| **Severity** | Should match event severity | Maintain audit trail |

### Step 5: Test Variant Detection

```python
from backend.root_cause_analyzer import analyze_event

# Test message 1
event1 = {
    'event_id': 1003,
    'message': 'Service crashed: out of memory, heap allocation failed',
    'severity': 'error',
}
variants1 = analyze_event(event1)
print(f"Event 1: {[v.label for v in variants1]}")
# Output: ['HighMemoryUsage']

# Test message 2
event2 = {
    'event_id': 1003,
    'message': 'Service deadlock detected - lock timeout waiting for database',
    'severity': 'error',
}
variants2 = analyze_event(event2)
print(f"Event 2: {[v.label for v in variants2]}")
# Output: ['DeadlockOrLock']

# Test message 3
event3 = {
    'event_id': 1003,
    'message': 'Cannot initialize - file not found: dependencies.dll',
    'severity': 'critical',
}
variants3 = analyze_event(event3)
print(f"Event 3: {[v.label for v in variants3]}")
# Output: ['MissingFile']
```

### Step 6: Verify Remediation Works

```python
from backend.models import add_event, match_rules_for_event_with_variants

# Create an event
event_id = add_event(
    event_id=1003,
    log_name='System',
    source='Service Control Manager',
    message='Service crashed: out of memory, heap allocation failed'
)

# Get event details
event = models.get_event(event_id)

# Create event dict
event_dict = {
    'event_id': event[1],
    'source': event[3],
    'message': event[4],
    'severity': event[6],
}

# Find matching rules
matched_rules = match_rules_for_event_with_variants(event_dict)

print(f"Matched {len(matched_rules)} rules:")
for rule in matched_rules:
    print(f"  - {rule[1]} (priority: {rule[12]})")
    # rule[1] = name, rule[12] = priority
```

### Step 7: Monitor & Adjust

Check the database to see detected variants:

```sql
-- Show recent events with variants
SELECT 
    id, 
    event_id, 
    message,
    root_cause_variant_label,
    root_cause_confidence
FROM events
WHERE detected_root_causes IS NOT NULL
ORDER BY id DESC
LIMIT 10;

-- Show which variants were detected for each event
SELECT 
    id,
    event_id,
    detected_root_causes
FROM events
WHERE detected_root_causes IS NOT NULL
ORDER BY id DESC
LIMIT 5;
```

**Look for:**
- ✅ Correct variants being detected
- ❌ False positives (wrong variant)
- ❌ False negatives (no variant detected)
- ✓ Confidence scores matching expectations

**Adjust if needed:**
```python
# If patterns not working, refine them
analyzer.variant_patterns[1003][0]['message_patterns'] = [
    (r'(?i)(new pattern)', 3),
]
```

---

## Common Patterns (Copy-Paste Ready)

### Pattern: File/Dependency Error
```python
'message_patterns': [
    (r'(?i)(not found|missing|cannot find)', 3),
    (r'(?i)(file|dll|module|module not found)', 2),
    (r'(?i)(0x[0-9a-f]{8})', 1),  # Error codes
],
'required_keywords': ['not found', 'missing'],
```

### Pattern: Memory/Resource Error
```python
'message_patterns': [
    (r'(?i)(out of memory|insufficient memory|heap corruption)', 3),
    (r'(?i)(memory|allocation|allocate)', 2),
    (r'(?i)(om|oom)', 1),
],
'required_keywords': ['memory'],
```

### Pattern: Timeout/Lock Error
```python
'message_patterns': [
    (r'(?i)(timeout|deadlock|lock|blocked|wait)', 3),
    (r'(?i)(acquire|release|mutex|semaphore)', 2),
],
'required_keywords': ['timeout', 'deadlock', 'lock'],
```

### Pattern: Permission/Access Error
```python
'message_patterns': [
    (r'(?i)(access denied|permission|unauthorized)', 3),
    (r'(?i)(0x5|0x80070005)', 2),  # Windows error codes
],
'required_keywords': ['access', 'denied', 'permission'],
```

---

## Troubleshooting

### Problem: Variants not being detected
```python
# 1. Test pattern directly
import re
message = "your error message here"
pattern = r'(?i)(pattern here)'
if re.search(pattern, message):
    print("Pattern matches!")
else:
    print("Pattern doesn't match - refine it")

# 2. Check confidence calculation
from backend.root_cause_analyzer import analyze_event
variants = analyze_event({'event_id': 1003, 'message': message})
print(f"Detected: {[v.label for v in variants]}")

# 3. Verify required_keywords are in message
print(word in message.lower() for word in ['keyword1', 'keyword2'])
```

### Problem: Wrong variant being detected
```python
# Lower the weight for that pattern
# Or add more specific required_keywords
# Or increase min_confidence threshold for that variant's rule
```

### Problem: Rules not executing
```python
# Check rule_variant_associations
from backend.models import get_variant_associations
assocs = get_variant_associations(rule_id=42)
print(assocs)

# Verify variant ID matches
# Verify min_confidence threshold is met
```

---

## Best Practices Checklist

- [ ] Analyzed 10+ real error messages from your logs
- [ ] Identified distinct root causes for each error
- [ ] Created 2-5 variants per error type
- [ ] Tested patterns against real messages
- [ ] Set appropriate min_confidence thresholds
- [ ] Created specific remediation scripts
- [ ] Verified backward compatibility
- [ ] Set up monitoring/dashboards
- [ ] Documented custom patterns
- [ ] Trained team on new system

---

## Files Reference

| File | Purpose |
|------|---------|
| `root_cause_analyzer.py` | Root cause detection engine |
| `variant_usage_examples.py` | Example implementations |
| `test_backward_compatibility.py` | Validation tests |
| `ROOT_CAUSE_VARIANT_SYSTEM.md` | Full documentation |
| `QUICK_START.md` | This file |

---

## Support & Validation

Run the backward compatibility tests:
```bash
python backend/test_backward_compatibility.py
```

Expected output:
```
✓ Test 1 PASSED
✓ Test 2 PASSED
✓ Test 3 PASSED
✓ Test 4 PASSED
✓ Test 5 PASSED
✓ Test 6 PASSED

✅ ALL TESTS PASSED - System is backward compatible!
```

---

**You're now ready to deploy intelligent, targeted error remediation! 🚀**
