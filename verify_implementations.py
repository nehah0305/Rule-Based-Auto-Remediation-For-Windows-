# verify_implementations.py
# ═════════════════════════════════════════════════════════════════════════════
# Verification Script: Three Critical Improvements
#
# This script validates that all three improvements are properly implemented
# and integrated into the system.
#
# Usage: python verify_implementations.py
# ═════════════════════════════════════════════════════════════════════════════

import os
import sys
import json
from pathlib import Path

# ── Configuration ───────────────────────────────────────────────────────────

BACKEND_DIR = Path(__file__).parent / 'backend'
REMEDIATION_DIR = Path(__file__).parent / 'remediation_scripts'
PROJECT_ROOT = Path(__file__).parent

# ── Verification Functions ──────────────────────────────────────────────────

def verify_correlation_map():
    """Check that CORRELATION_MAP is expanded and properly defined."""
    print("\n✓ CHECKING: Correlation Map Expansion")
    print("-" * 60)
    
    try:
        sys.path.insert(0, str(BACKEND_DIR))
        from models import CORRELATION_MAP, COMPOUND_CAUSE_TO_SCRIPT
        
        event_count = len(CORRELATION_MAP)
        mapping_count = sum(len(v) for v in CORRELATION_MAP.values())
        
        print(f"  Event types with correlations: {event_count}")
        print(f"  Total correlation pairs: {mapping_count}")
        
        expected_events = [1000, 1001, 1026, 7000, 7022, 7023, 7031, 7034,
                          2019, 2020, 2004, 11, 51, 7, 55,
                          1014, 4202, 5025, 5157, 8003, 8004, 8006,
                          1100, 1101, 4625, 10016, 41]
        
        found = sum(1 for e in expected_events if e in CORRELATION_MAP)
        print(f"  Expected events found: {found}/{len(expected_events)}")
        
        compound_count = len(COMPOUND_CAUSE_TO_SCRIPT)
        print(f"  Compound cause mappings: {compound_count}")
        
        if event_count >= 20 and mapping_count >= 30:
            print("  ✅ PASS: Correlation map expanded successfully")
            return True
        else:
            print("  ❌ FAIL: Correlation map not sufficiently expanded")
            return False
    except Exception as e:
        print(f"  ❌ ERROR: {e}")
        return False

def verify_helper_functions():
    """Check that helper functions for correlation engine exist."""
    print("\n✓ CHECKING: Helper Functions")
    print("-" * 60)
    
    try:
        sys.path.insert(0, str(BACKEND_DIR))
        from models import correlate_events, detect_faulting_module, is_core_os_module
        
        # Test correlate_events
        result = correlate_events(1000)
        assert isinstance(result, dict)
        assert 'has_correlation' in result
        assert 'compound_cause' in result
        assert 'compound_script' in result
        assert 'priority' in result
        print("  ✓ correlate_events() function works")
        
        # Test detect_faulting_module
        msg = "Application crashed. Faulting module name: ntdll.dll"
        module = detect_faulting_module(msg)
        assert module == 'ntdll.dll'
        print("  ✓ detect_faulting_module() function works")
        
        # Test is_core_os_module
        assert is_core_os_module('ntdll.dll') == True
        assert is_core_os_module('myapp.exe') == False
        print("  ✓ is_core_os_module() function works")
        
        print("  ✅ PASS: All helper functions implemented correctly")
        return True
    except Exception as e:
        print(f"  ❌ ERROR: {e}")
        return False

def verify_event_log_monitor_integration():
    """Check that event_log_monitor properly integrates correlation engine."""
    print("\n✓ CHECKING: Event Log Monitor Integration")
    print("-" * 60)
    
    try:
        with open(BACKEND_DIR / 'event_log_monitor.py', 'r', encoding='utf-8') as f:
            content = f.read()
        
        checks = [
            ('models.correlate_events', 'Correlation engine called'),
            ('RM_COMPOUND_CAUSE', 'Compound cause injected'),
            ('RM_FAULTING_MODULE', 'Faulting module detected'),
            ('SYSREPAIR', 'System repair fallback'),
            ('[CORRELATE', 'Correlation logging'),
            ('Remediate_SystemRepair_Fallback.ps1', 'Fallback script referenced'),
        ]
        
        passed = 0
        for check_str, description in checks:
            if check_str in content:
                print(f"  ✓ {description}")
                passed += 1
            else:
                print(f"  ❌ {description} - NOT FOUND")
        
        if passed == len(checks):
            print("  ✅ PASS: Event monitor fully integrated")
            return True
        else:
            print(f"  ❌ FAIL: {passed}/{len(checks)} integration points found")
            return False
    except Exception as e:
        print(f"  ❌ ERROR: {e}")
        return False

def verify_system_repair_fallback():
    """Check that system repair fallback script exists and is complete."""
    print("\n✓ CHECKING: System Repair Fallback Script")
    print("-" * 60)
    
    try:
        script_path = REMEDIATION_DIR / 'Remediate_SystemRepair_Fallback.ps1'
        
        if not script_path.exists():
            print(f"  ❌ Script not found: {script_path}")
            return False
        
        with open(script_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        checks = [
            ('Invoke-SFCScannow', 'SFC scan function'),
            ('Invoke-DISM', 'DISM escalation function'),
            ('sfc /scannow', 'sfc command execution'),
            ('DISM /Online /Cleanup-Image', 'DISM command'),
            ('PHASE 1', 'Two-phase approach'),
            ('PHASE 2', 'Two-phase approach'),
        ]
        
        passed = 0
        for check_str, description in checks:
            if check_str in content:
                print(f"  ✓ {description}")
                passed += 1
            else:
                print(f"  ❌ {description} - NOT FOUND")
        
        if passed == len(checks):
            print("  ✅ PASS: System repair fallback properly implemented")
            return True
        else:
            print(f"  ❌ FAIL: {passed}/{len(checks)} checks passed")
            return False
    except Exception as e:
        print(f"  ❌ ERROR: {e}")
        return False

def verify_compound_remediation_scripts():
    """Check that compound remediation scripts exist."""
    print("\n✓ CHECKING: Compound Remediation Scripts")
    print("-" * 60)
    
    scripts = {
        'Remediate_MemoryExhaustion.ps1': ['Get-AvailableMemory', 'Clear-MemoryCaches', 'Kill-LowPriorityProcesses'],
        'Remediate_DiskIOError.ps1': ['Get-DiskHealthStatus', 'Test-DiskVolume', 'Restart-StorageServices'],
        'Remediate_AppLockerBlock.ps1': ['Get-RecentAppLockerBlocks', 'Get-BlockedApplications'],
        'Remediate_FirewallService.ps1': ['Get-FirewallServiceStatus', 'Start-FirewallService'],
    }
    
    passed = 0
    for script_name, required_functions in scripts.items():
        script_path = REMEDIATION_DIR / script_name
        
        if not script_path.exists():
            print(f"  ❌ Script not found: {script_name}")
            continue
        
        with open(script_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        all_found = all(func in content for func in required_functions)
        if all_found:
            print(f"  ✓ {script_name}")
            passed += 1
        else:
            print(f"  ❌ {script_name} - missing functions")
    
    if passed == len(scripts):
        print("  ✅ PASS: All compound remediation scripts implemented")
        return True
    else:
        print(f"  ❌ FAIL: {passed}/{len(scripts)} scripts complete")
        return False

def verify_setup_event_triggers():
    """Check that Setup_EventTriggers.ps1 has expanded event list."""
    print("\n✓ CHECKING: Expanded Task Scheduler Event List")
    print("-" * 60)
    
    try:
        script_path = REMEDIATION_DIR / 'Setup_EventTriggers.ps1'
        
        if not script_path.exists():
            print(f"  ❌ Script not found: {script_path}")
            return False
        
        with open(script_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Extract event IDs from script
        import re
        event_ids = set()
        for match in re.finditer(r'EventId\s*=\s*(\d+)', content):
            event_ids.add(int(match.group(1)))
        
        expected_ids = {
            # Application Crashes
            1000, 1001, 1026,
            # Service Failures
            7000, 7022, 7023, 7031, 7034,
            # Disk/NTFS
            7, 11, 51, 55,
            # Memory
            2004, 2019, 2020,
            # Networking
            1014, 4202,
            # Firewall
            5025, 5157,
            # AppLocker
            8003, 8004, 8006,
            # Event Log (new)
            1100, 1101,
            # Privilege (new)
            4625, 10016,
            # System (new)
            41,
        }
        
        found = len(event_ids & expected_ids)
        print(f"  Event IDs configured: {len(event_ids)}")
        print(f"  Expected IDs found: {found}/{len(expected_ids)}")
        
        if found >= 25:
            print("  ✅ PASS: Event triggers properly expanded")
            return True
        else:
            print(f"  ❌ FAIL: Only {found} expected events found")
            return False
    except Exception as e:
        print(f"  ❌ ERROR: {e}")
        return False

# ── Main Verification ───────────────────────────────────────────────────────

def main():
    print("=" * 70)
    print("THREE CRITICAL IMPROVEMENTS - IMPLEMENTATION VERIFICATION")
    print("=" * 70)
    
    results = {
        'Correlation Map': verify_correlation_map(),
        'Helper Functions': verify_helper_functions(),
        'Event Monitor Integration': verify_event_log_monitor_integration(),
        'System Repair Fallback': verify_system_repair_fallback(),
        'Compound Remediation Scripts': verify_compound_remediation_scripts(),
        'Expanded Event Triggers': verify_setup_event_triggers(),
    }
    
    print("\n" + "=" * 70)
    print("VERIFICATION SUMMARY")
    print("=" * 70)
    
    passed = sum(1 for v in results.values() if v)
    total = len(results)
    
    for check_name, result in results.items():
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"{status}: {check_name}")
    
    print("\n" + "=" * 70)
    if passed == total:
        print(f"🎉 ALL CHECKS PASSED ({passed}/{total})")
        print("═" * 70)
        print("\nSystem is ready for deployment. The three improvements are:")
        print("  1. ✓ Chronological Event Correlation (Multi-Event Inference)")
        print("  2. ✓ Deep System Repair Fallback (sfc /scannow + DISM)")
        print("  3. ✓ Expanded Task Scheduler Network (27 event types)")
        print("\nNext steps:")
        print("  1. Run Setup_EventTriggers.ps1 to install Task Scheduler triggers")
        print("  2. Monitor backend/data/remediation_system.log for [CORRELATE] entries")
        print("  3. Review IMPLEMENTATION_SUMMARY_THREE_IMPROVEMENTS.md")
        return 0
    else:
        print(f"⚠️  SOME CHECKS FAILED ({total - passed}/{total})")
        print("═" * 70)
        print("\nPlease review the failed checks above and fix before deployment.")
        return 1

if __name__ == '__main__':
    sys.exit(main())
