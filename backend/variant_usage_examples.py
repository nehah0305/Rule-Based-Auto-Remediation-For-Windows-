"""
Root Cause Variant System - Usage Examples

This module demonstrates how to use the root cause variant detection system
to handle errors with the same event_id but different root causes, and apply
targeted remediation for each variant.

OVERVIEW:
========
The system enables:
1. Automatic detection of root cause variants from error messages
2. Classification of similar errors into different categories
3. Assignment of different remediation rules per variant
4. Precise targeting of remediation efforts

EXAMPLE 1: Service Crash (Error 1003) with Multiple Root Causes
==============================================================

A Windows service can crash for many reasons:
- High Memory Usage (OOM)
- Resource Deadlock
- Missing Dependency
- File Permission Issue

The root cause analyzer detects which one occurred from the error message,
and then only applicable remediation rules run.
"""

from backend.root_cause_analyzer import get_analyzer, register_custom_variant
from backend.models import add_rule, link_rule_to_variant, add_event, match_rules_for_event_with_variants


def example_1_setup_service_crash_variants():
    """
    Setup variant detection and targeted remediation for Service Crash error.
    """
    print("[EXAMPLE 1] Setting up Service Crash (Error 1003) with variants...")
    
    # The analyzer already has default patterns for error 1003,
    # but you can register custom ones:
    
    analyzer = get_analyzer()
    
    # Add a custom variant pattern
    analyzer.register_variant_pattern(1003, {
        'variant_id': 'svc_crash_insufficient_disk',
        'label': 'InsufficientDiskSpace',
        'description': 'Service crash due to insufficient disk space',
        'message_patterns': [
            (r'(?i)(disk space|insufficient space|no space|disk full)', 3),
            (r'(?i)(failed to write|write failed|disk quota)', 2),
        ],
        'required_keywords': ['disk', 'space'],
        'context_checks': [
            {'field': 'severity', 'values': ['error', 'critical'], 'weight': 1},
        ],
    })
    
    print("✓ Registered custom variant pattern: InsufficientDiskSpace")


def example_2_create_variant_specific_rules():
    """
    Create remediation rules that target specific error variants.
    """
    print("\n[EXAMPLE 2] Creating variant-specific remediation rules...")
    
    # Rule 1: High Memory Usage variant
    # If service keeps crashing due to high memory, restart with memory monitor
    rule_id_memory = add_rule(
        name='Service Crash - High Memory Recovery',
        event_id=1003,
        source='Service Control Manager',
        message_regex=None,  # Will match any 1003 event
        remediation_script='remediation_scripts/RestartService_MonitorMemory.ps1',
        script_type='file',
        auto_remediate=1,
        category='Service',
        severity='error',
        priority=10,  # Higher priority (lower = higher)
        description='Clear memory and restart service when crash is due to high memory usage'
    )
    
    # Link this rule to the high memory variant
    # It will only run if event is classified as HighMemoryUsage with 70%+ confidence
    link_rule_to_variant(
        rule_id=rule_id_memory,
        variant_id='svc_crash_high_memory',
        variant_label='HighMemoryUsage',
        min_confidence=70
    )
    print(f"✓ Rule {rule_id_memory}: Service Crash - High Memory (linked to HighMemoryUsage)")
    
    # Rule 2: Deadlock/Lock variant
    # If service keeps deadlocking, apply deadlock detection and retry logic
    rule_id_deadlock = add_rule(
        name='Service Crash - Deadlock Recovery',
        event_id=1003,
        source='Service Control Manager',
        remediation_script='remediation_scripts/RecoverFromDeadlock.ps1',
        script_type='file',
        auto_remediate=1,
        category='Service',
        severity='error',
        priority=11,
        description='Kill blocked threads and restart service when crash is due to deadlock'
    )
    
    link_rule_to_variant(
        rule_id=rule_id_deadlock,
        variant_id='svc_crash_resource_lock',
        variant_label='DeadlockOrLock',
        min_confidence=60  # Lower threshold for this variant
    )
    print(f"✓ Rule {rule_id_deadlock}: Service Crash - Deadlock (linked to DeadlockOrLock)")
    
    # Rule 3: Missing Dependency variant
    # If service crashes due to missing file/DLL, attempt to restore it
    rule_id_missing = add_rule(
        name='Service Crash - Restore Missing Dependency',
        event_id=1003,
        source='Service Control Manager',
        remediation_script='remediation_scripts/RestoreMissingDependency.ps1',
        script_type='file',
        auto_remediate=0,  # Require approval for dependency restoration
        category='Service',
        severity='critical',
        priority=5,  # Highest priority
        description='Alert operator to restore missing files/dependencies'
    )
    
    link_rule_to_variant(
        rule_id=rule_id_missing,
        variant_id='svc_crash_missing_dependency',
        variant_label='MissingDependency',
        min_confidence=80  # High confidence threshold
    )
    print(f"✓ Rule {rule_id_missing}: Service Crash - Missing Dependency (linked to MissingDependency)")
    
    # Rule 4: Insufficient Disk Space variant (our custom one)
    rule_id_disk = add_rule(
        name='Service Crash - Free Disk Space',
        event_id=1003,
        source='Service Control Manager',
        remediation_script='remediation_scripts/FreeDiskSpace.ps1',
        script_type='file',
        auto_remediate=1,
        category='Service',
        severity='error',
        priority=8,
        description='Free disk space and restart service'
    )
    
    link_rule_to_variant(
        rule_id=rule_id_disk,
        variant_id='svc_crash_insufficient_disk',
        variant_label='InsufficientDiskSpace',
        min_confidence=70
    )
    print(f"✓ Rule {rule_id_disk}: Service Crash - Free Disk Space (linked to InsufficientDiskSpace)")


def example_3_demonstrate_variant_detection():
    """
    Demonstrate how events are classified into variants.
    """
    print("\n[EXAMPLE 3] Demonstrating variant detection in action...")
    
    # Event 1: High Memory scenario
    event1 = {
        'event_id': 1003,
        'source': 'Service Control Manager',
        'message': 'Service MSSQLSERVER crashed due to out of memory condition. Memory allocation failed.',
        'severity': 'error',
        'category': 'Service',
    }
    
    from backend.root_cause_analyzer import analyze_event
    variants1 = analyze_event(event1)
    
    print(f"\nEvent: Service crash in MSSQLSERVER")
    print(f"Message: '{event1['message']}'")
    print(f"Detected Variants:")
    for v in variants1:
        print(f"  - {v.label} ({v.confidence.name}, {v.confidence.value}%)")
    
    # Event 2: Deadlock scenario
    event2 = {
        'event_id': 1003,
        'source': 'Service Control Manager',
        'message': 'The service encountered a deadlock condition when acquiring database lock.',
        'severity': 'error',
        'category': 'Service',
    }
    
    variants2 = analyze_event(event2)
    
    print(f"\nEvent: Service crash with deadlock")
    print(f"Message: '{event2['message']}'")
    print(f"Detected Variants:")
    for v in variants2:
        print(f"  - {v.label} ({v.confidence.name}, {v.confidence.value}%)")
    
    # Event 3: Missing file scenario
    event3 = {
        'event_id': 1003,
        'source': 'Service Control Manager',
        'message': 'Cannot initialize service - file not found: mscoree.dll',
        'severity': 'critical',
        'category': 'Service',
    }
    
    variants3 = analyze_event(event3)
    
    print(f"\nEvent: Service crash with missing dependency")
    print(f"Message: '{event3['message']}'")
    print(f"Detected Variants:")
    for v in variants3:
        print(f"  - {v.label} ({v.confidence.name}, {v.confidence.value}%)")


def example_4_application_error_variants():
    """
    Setup for Application Error (1000) with variants.
    """
    print("\n[EXAMPLE 4] Setting up Application Error (1000) variants...")
    
    # Create rules for different application crash root causes
    
    # Unhandled exception variant
    rule_exc = add_rule(
        name='App Crash - Unhandled Exception Handler',
        event_id=1000,
        message_regex=r'(?i)(exception|error code|access violation)',
        remediation_script='remediation_scripts/CaptureExceptionLogs.ps1',
        auto_remediate=0,
        category='Application',
        severity='error',
        priority=20,
        description='Flag for analysis when unhandled exception occurs'
    )
    
    link_rule_to_variant(
        rule_id=rule_exc,
        variant_id='app_crash_exception',
        variant_label='UnhandledException',
        min_confidence=70
    )
    print(f"✓ Rule for UnhandledException variant")
    
    # Plugin failure variant
    rule_plugin = add_rule(
        name='App Crash - Disable Problematic Plugin',
        event_id=1000,
        message_regex=r'(?i)(plugin|extension|add-on)',
        remediation_script='remediation_scripts/DisablePlugin.ps1',
        auto_remediate=1,
        category='Application',
        severity='error',
        priority=15,
        description='Disable crashing plugin and alert user'
    )
    
    link_rule_to_variant(
        rule_id=rule_plugin,
        variant_id='app_crash_plugin_failure',
        variant_label='PluginFailure',
        min_confidence=75
    )
    print(f"✓ Rule for PluginFailure variant")


def example_5_backward_compatibility():
    """
    Demonstrate that the old rule system still works without variants.
    """
    print("\n[EXAMPLE 5] Backward compatibility - rules without variants...")
    
    # Old-style rule (no variant associations) still works
    # It will match and execute as before, regardless of detected variants
    rule_legacy = add_rule(
        name='Legacy Service Watchdog',
        event_id=1003,
        source='Service Control Manager',
        remediation_script='remediation_scripts/RestartService.ps1',
        auto_remediate=1,
        priority=100,  # Low priority, only runs if no variant-specific rules match
        description='Fallback rule: restart any crashing service'
    )
    
    print(f"✓ Legacy rule {rule_legacy} will match any Service Crash regardless of variant")
    print("  (Runs only if no variant-specific rules apply)")


if __name__ == '__main__':
    print("="*70)
    print("ROOT CAUSE VARIANT SYSTEM - USAGE EXAMPLES")
    print("="*70)
    
    example_1_setup_service_crash_variants()
    example_2_create_variant_specific_rules()
    example_3_demonstrate_variant_detection()
    example_4_application_error_variants()
    example_5_backward_compatibility()
    
    print("\n" + "="*70)
    print("SUMMARY")
    print("="*70)
    print("""
The root cause variant system enables:

1. INTELLIGENT DETECTION
   - Analyzes error messages to identify root causes
   - Classifies errors into meaningful categories
   - Assigns confidence scores to detections

2. TARGETED REMEDIATION
   - Different rules for different root causes
   - Only applicable remediation runs
   - Reduces false positives and wasted effort

3. CLEAN INTEGRATION
   - Works with existing rule engine
   - Backward compatible (old rules still work)
   - No breaking changes to current system

4. EXTENSIBLE DESIGN
   - Register custom variant patterns
   - Add new root causes easily
   - Configure confidence thresholds per rule

BEST PRACTICES:
- Set min_confidence high (70-80%) for auto-remediation rules
- Use lower thresholds (40-60%) for alert/report rules
- Register custom patterns for your environment
- Test variant detection before deploying rules
""")
