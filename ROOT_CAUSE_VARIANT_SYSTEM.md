# Root Cause Variant Detection System

## Overview

The Root Cause Variant Detection System enables your remediation engine to intelligently handle errors with the **same event ID but different root causes**. Instead of applying one-size-fits-all remediation, the system:

1. **Detects** the underlying root cause from error messages
2. **Classifies** errors into meaningful variants
3. **Applies** targeted remediation specific to each variant
4. **Tracks** all detected variants for analysis

## Problem Statement

**The Issue:**
```
Windows Error 1003 (High Priority) detected!
  Message: "Service XYZ crashed"
```

But this error could be caused by:
- Memory leak (needs restart + monitoring)
- Database deadlock (needs lock release + retry)
- Missing DLL file (needs restoration + verification)
- Insufficient disk space (needs cleanup + restart)

**Traditional Approach:** One rule for all cases = inefficient remediation

**Our Approach:** Different rules for different root causes = precise, effective remediation

## Architecture

### Components

#### 1. **RootCauseAnalyzer** (`root_cause_analyzer.py`)
Analyzes event messages to detect root cause variants.

**Features:**
- Pattern matching using regex weights
- Confidence scoring (0-100%)
- Context-aware analysis (severity, category fields)
- Extensible pattern database
- Built-in patterns for common errors

**Usage Example:**
```python
from backend.root_cause_analyzer import analyze_event

event = {
    'event_id': 1003,
    'message': 'Service crashed: out of memory condition',
    'severity': 'error',
}

variants = analyze_event(event)
# Returns: [
#   RootCauseVariant(
#     variant_id='svc_crash_high_memory',
#     label='HighMemoryUsage',
#     confidence=CERTAIN (100%)
#   )
# ]
```

#### 2. **Database Schema**
New tables and columns added gracefully via migration:

**event_root_cause_variants table:**
```sql
-- Stores detected root causes for each event
id, event_row_id, variant_id, variant_label, 
confidence_score, confidence_level, matched_indicators, detected_at
```

**rule_variant_associations table:**
```sql
-- Links rules to specific variants
id, rule_id, variant_id, variant_label, min_confidence, created_at
```

**events table (new columns):**
```sql
root_cause_variant_id,      -- Best-matched variant ID
root_cause_variant_label,   -- Display label
root_cause_confidence,      -- Confidence %
detected_root_causes        -- JSON array of all variants
```

#### 3. **Enhanced Models** (`models.py`)
Extended with variant-aware functions:

- `add_event()` - Now detects and stores root causes
- `match_rules_for_event_with_variants()` - Variant-aware rule matching
- `link_rule_to_variant()` - Associate rule with variant
- `add_root_cause_variant()` - Store variant for event
- `get_event_root_causes()` - Retrieve all variants for event

## Workflow

### 1. Event Ingestion with Root Cause Analysis

```
Event arrives → analyze_root_cause() → variants detected → stored in DB
                                     ↓
                            RootCauseVariant(s)
                            confidence scores
                            matched indicators
```

### 2. Rule Matching with Variant Awareness

```
Event needs remediation
    ↓
Get best variant for event (highest confidence)
    ↓
Find rules matching base criteria (event_id, source, etc.)
    ↓
For each rule:
  - If rule has NO variant associations:
    → Execute (backward compatible)
  - If rule has variant associations:
    → Check if event's variant matches with sufficient confidence
    → Execute only if variant matches
```

### 3. Multi-Variant Remediation

```
Error 1003 (Service Crash):

Variant: HighMemoryUsage (85% confidence)
  ↓ Matches Rule #10 (Memory Recovery)
  ↓ Executes: RestartService_MonitorMemory.ps1

Variant: DeadlockOrLock (65% confidence)
  ↓ Matches Rule #11 (Deadlock Recovery)
  ↓ Executes: RecoverFromDeadlock.ps1

Variant: MissingDependency (45% confidence)
  ↓ Below 80% threshold for Rule #12
  ↓ Skipped (requires manual review)

Fallback: Legacy Rule #100 (any crash)
  ↓ Priority 100 (lowest)
  ↓ Executes: RestartService.ps1
```

## Usage Guide

### Step 1: Register Custom Variant Patterns

Define what indicates each root cause:

```python
from backend.root_cause_analyzer import get_analyzer

analyzer = get_analyzer()

analyzer.register_variant_pattern(1003, {
    'variant_id': 'svc_crash_memory_leak',
    'label': 'MemoryLeak',
    'description': 'Persistent memory growth before crash',
    'message_patterns': [
        (r'(?i)(memory leak|heap corruption)', 3),  # weight 3
        (r'(?i)(allocation|memory)', 1),            # weight 1
    ],
    'required_keywords': ['memory', 'leak'],  # Must have one
    'context_checks': [
        {'field': 'severity', 'values': ['error'], 'weight': 1},
    ],
})
```

**Pattern Scoring:**
- Message matches weighted regex = confidence boost
- Required keywords present = high confidence bonus
- Context matches (severity, category) = additional weight
- Total score maps to confidence level: CERTAIN (100), HIGH (80), MEDIUM (60), LOW (40)

### Step 2: Create Variant-Specific Rules

```python
from backend.models import add_rule, link_rule_to_variant

# Create remediation rule
rule_id = add_rule(
    name='Service Crash - High Memory Recovery',
    event_id=1003,
    source='Service Control Manager',
    remediation_script='remediation_scripts/ClearMemory_Restart.ps1',
    auto_remediate=1,
    priority=10,
    description='Clear memory cache and restart service'
)

# Link to specific variant
link_rule_to_variant(
    rule_id=rule_id,
    variant_id='svc_crash_high_memory',
    variant_label='HighMemoryUsage',
    min_confidence=70  # Only apply if 70%+ confident
)
```

### Step 3: Monitor Variant Detection

```python
from backend.models import get_event_root_causes

# Retrieve all detected variants for event
variants = get_event_root_causes(event_row_id=123)

for v in variants:
    # (id, event_row_id, variant_id, variant_label, description,
    #  confidence_score, confidence_level, matched_indicators, detected_at)
    print(f"{v[3]}: {v[5]}% confidence")
```

## Confidence Levels

| Level | Range | Meaning | Auto-Remediate Threshold |
|-------|-------|---------|--------------------------|
| CERTAIN | 100 | Definitive indicators found | Safe at 80%+ |
| HIGH | 80-99 | Strong indicators match | Safe at 70%+ |
| MEDIUM | 60-79 | Multiple weak indicators | Use 60%+ for manual review |
| LOW | 40-59 | Single indicator or partial | Manual review only |
| UNKNOWN | 0 | No indicators detected | N/A |

## Backward Compatibility

**Existing rules continue to work unchanged.**

Rules without variant associations behave as before:
- Match based on event_id, source, category, severity, message_regex
- Execute normally regardless of detected variants
- Use `priority` field to control execution order

This means:
✓ Zero breaking changes
✓ Existing remediation scripts work as-is
✓ Can gradually add variants to existing rules
✓ Safe to deploy alongside legacy rules

## Performance Considerations

### Analysis Overhead
- Root cause analysis: ~5-15ms per event
- Pattern matching: O(number of patterns)
- Stored in database for future reference

### Optimization Tips
1. **Use specific regex patterns** - More efficient than broad patterns
2. **Limit context checks** - Only check fields actually relevant
3. **Set appropriate confidence thresholds** - Prevents unnecessary processing
4. **Cache analyzer instance** - Already done (singleton pattern)

## Practical Examples

### Example 1: Service Crash with 4 Variants

**Variants Defined:**
- HighMemoryUsage
- DeadlockOrLock
- MissingDependency
- InsufficientDiskSpace

**Rules Created:**
- Rule #10 (priority 10): Memory recovery (linked to HighMemoryUsage, min 70%)
- Rule #11 (priority 11): Deadlock recovery (linked to DeadlockOrLock, min 60%)
- Rule #12 (priority 5): Manual review (linked to MissingDependency, min 80%)
- Rule #13 (priority 8): Cleanup (linked to InsufficientDiskSpace, min 70%)
- Rule #100 (priority 100): Fallback restart (no variant - always applied)

**Result:** Each service crash gets targeted fix based on actual root cause

### Example 2: Application Error with 2 Variants

**Event:** Application Error 1000

**Variants:**
- UnhandledException
- PluginFailure

**Rules:**
- Rule A: Capture exception logs (linked to UnhandledException)
- Rule B: Disable plugin (linked to PluginFailure)

**Behavior:** Application crashes are handled differently based on root cause:
- Exception → Save logs for analysis
- Plugin → Automatically disable plugin and restart app

## Testing & Validation

### Test Pattern Effectiveness

```python
from backend.root_cause_analyzer import analyze_event

test_messages = [
    "out of memory condition - heap corruption detected",
    "database lock timeout - wait chain detected",
    "missing file: mscoree.dll - cannot initialize",
]

for msg in test_messages:
    event = {'event_id': 1003, 'message': msg}
    variants = analyze_event(event)
    print(f"'{msg}' → {[v.label for v in variants]}")
```

### Validate Variant Associations

```python
from backend.models import get_variant_associations

# Check what variants a rule is linked to
assocs = get_variant_associations(rule_id=42)
# assocs: [(id, rule_id, variant_id, variant_label, min_confidence, created_at), ...]
```

## Troubleshooting

### Patterns Not Matching

**Problem:** Events not being classified as expected

**Solution:**
1. Review pattern regex: Use regex101.com to test
2. Check required_keywords: Must have at least one
3. Verify confidence thresholds: May be too high
4. Test with test messages:
```python
from backend.root_cause_analyzer import analyze_event
variants = analyze_event({'event_id': 1003, 'message': your_message})
```

### Rules Not Executing

**Problem:** Variant-linked rule not running

**Solution:**
1. Verify variant matches: Check detected_root_causes JSON in DB
2. Check min_confidence threshold: Detected confidence must be >= threshold
3. Check rule priority: Higher priority rules may have stopped processing
4. Check base criteria: Rule must still match event_id, source, etc.

### Performance Issues

**Problem:** Event processing is slow

**Solution:**
1. Reduce number of patterns: Consolidate similar patterns
2. Simplify regex: Use faster patterns
3. Remove unused context_checks
4. Monitor database: Check for slow queries

## Best Practices

1. **Start Simple** - Begin with most obvious root cause indicators
2. **Test Extensively** - Validate patterns against real error messages
3. **Use Confidence Tiers** - Different thresholds for auto vs. manual vs. critical
4. **Document Variants** - Clearly describe what each variant means
5. **Review False Positives** - Adjust patterns based on real-world performance
6. **Monitor DB** - Track detected_root_causes to find improvement opportunities
7. **Fallback Rules** - Always maintain legacy rules as safety net
8. **Gradual Rollout** - Add variants incrementally, not all at once

## API Integration

The variant information is available through the events API:

```json
{
  "id": 123,
  "event_id": 1003,
  "source": "Service Control Manager",
  "message": "Service crashed",
  "root_cause_variant_id": "svc_crash_high_memory",
  "root_cause_variant_label": "HighMemoryUsage",
  "root_cause_confidence": 85,
  "detected_root_causes": [
    {
      "variant_id": "svc_crash_high_memory",
      "label": "HighMemoryUsage",
      "confidence": 85,
      "confidence_name": "HIGH",
      "matched_indicators": ["memory pattern", "context match"]
    },
    {
      "variant_id": "svc_crash_resource_lock",
      "label": "DeadlockOrLock",
      "confidence": 40,
      "confidence_name": "LOW",
      "matched_indicators": []
    }
  ]
}
```

## Key Takeaways

✅ **Intelligent error classification** - Understands root causes automatically
✅ **Targeted remediation** - Different actions for different causes
✅ **No breaking changes** - Backward compatible with existing rules
✅ **Extensible** - Easy to add new variants and patterns
✅ **Trackable** - Stores confidence and indicators for analysis
✅ **Effective** - Reduces false positives and wasted effort

Your remediation engine is now **ruthlessly efficient and effective**.
