"""
generate_rules_manifest.py
Scans remediation_scripts/ and produces backend/rules_manifest.json — a
declarative, hand-reviewable mapping of every remediation script to a
logical Event ID, Source, Priority, and Severity.

Run once (or whenever scripts are added/removed):
    python backend/generate_rules_manifest.py

db_init.py reads the resulting JSON at startup; it does not scan the
filesystem itself, so the manifest is the single source of truth and can
be hand-edited/reviewed like any other config file.
"""
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS_DIR = os.path.join(ROOT, 'remediation_scripts')
CATALOG_PATH = os.path.join(ROOT, 'windows_error_events.json')
OUTPUT_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'rules_manifest.json')

# Scripts that are not (event_id, source)-triggerable remediations and must
# never become rules: demo/injector scripts, test harnesses, templates, and
# known-broken/duplicate variants.
EXCLUDE = {
    'Setup_EventTriggers.ps1',
    'Simulate_HighCpuAlert.ps1',
    'Simulate_Real_Crash.ps1',
    'Simulate_ServiceCrash.ps1',
    'Test-RemediationRules.ps1',
    'sample_remediation.ps1',
    # Invoked directly by event_log_monitor's deep-system-repair escalation
    # path (core OS module crash), not via normal rule matching.
    'Remediate_SystemRepair_Fallback.ps1',
    'Remediate_SystemRepair_Fallback_v2.ps1',
    'Remediate_SystemRepair_Fallback_broken.ps1',
    # Generic catch-all predecessors superseded by specific Error<ID>_*.ps1
    # scripts that now give precise per-event-ID coverage for the same domain.
    'Remediate_AppLockerBlock.ps1',
    'Remediate_DiskIOError.ps1',
    'Remediate_FirewallService.ps1',
    'Remediate_MemoryExhaustion.ps1',
    'Remediate_ServiceCrash.ps1',
    'Remediate_AppCrash_Live.ps1',
}

# Scripts whose event ID can't be parsed from the filename.
EXPLICIT_EVENT_ID = {
    'LowDiskSpace_Remediation.ps1': 2013,
    'Remediate_HighCpuAlert.ps1': 9999,
}
EXPLICIT_SOURCE = {
    'LowDiskSpace_Remediation.ps1': 'Disk',
    'Remediate_HighCpuAlert.ps1': 'AutoRemediationDemo',
}

CATEGORY_KEYWORDS = [
    (('Disk', 'Volume', 'NTFS', 'Storage', 'Corruption', 'BadBlocks'), 'Disk & Storage'),
    (('Network', 'DNS', 'Dcom', 'DCOM', 'SecureChannel', 'TLS'), 'Networking'),
    (('Firewall', 'WFP'), 'Firewall'),
    (('AppLocker',), 'AppLocker'),
    (('Service',), 'Service Failure'),
    (('Memory', 'Pool', 'ResourceExhaustion'), 'Memory'),
    (('Privilege', 'Logon', 'AccessDenied'), 'Security & Privilege'),
    (('EventLog', 'AuditEvents'), 'Event Logging'),
    (('ApplicationCrash', 'ApplicationHang', 'DotNetRuntime', 'ApplicationFailed'), 'Application'),
    (('SystemReboot',), 'Boot & Power'),
    (('DomainController',), 'Active Directory'),
]

SEVERITY_KEYWORDS = [
    (('Corruption', 'BadBlocks', 'RebootDueToResource', 'DomainControllerUnreachable'), 'Critical'),
    (('Failure', 'Denied', 'Blocked', 'Timeout', 'PermissionDenied'), 'High'),
]


def infer_category(name: str) -> str:
    for keywords, cat in CATEGORY_KEYWORDS:
        if any(k.lower() in name.lower() for k in keywords):
            return cat
    return 'General'


def infer_severity(name: str) -> str:
    for keywords, sev in SEVERITY_KEYWORDS:
        if any(k.lower() in name.lower() for k in keywords):
            return sev
    return 'Medium'


def humanize(description_part: str) -> str:
    # "ApplicationFailedDueToMemoryLimits" -> "Application Failed Due To Memory Limits"
    spaced = re.sub(r'(?<!^)(?=[A-Z])', ' ', description_part)
    return spaced.strip()


def main():
    with open(CATALOG_PATH, encoding='utf-8') as f:
        catalog = json.load(f)
    # A few event IDs are legitimately ambiguous (e.g. 1001 = "Application Hang"
    # from Windows Error Reporting *or* a BugCheck-sourced system crash entry).
    # Prefer the source that matches what the actual script name targets.
    PREFERRED_SOURCE = {1001: 'Windows Error Reporting'}
    catalog_by_id = {}
    for d in catalog:
        eid = int(d['event_id'])
        if eid in catalog_by_id and PREFERRED_SOURCE.get(eid) not in (None, d['event_source']):
            continue
        catalog_by_id[eid] = d

    entries = []
    skipped = []
    for fname in sorted(os.listdir(SCRIPTS_DIR)):
        if not fname.endswith('.ps1'):
            continue
        if fname in EXCLUDE:
            continue

        event_id = EXPLICIT_EVENT_ID.get(fname)
        if event_id is None:
            m = re.match(r'^Error(\d+)_', fname)
            if not m:
                skipped.append(fname)
                continue
            event_id = int(m.group(1))

        catalog_defn = catalog_by_id.get(event_id)
        if catalog_defn:
            source = catalog_defn['event_source']
            category = catalog_defn.get('category') or infer_category(fname)
            severity = catalog_defn.get('severity') or infer_severity(fname)
            description = catalog_defn.get('description') or ''
            recommended_action = catalog_defn.get('recommended_action') or ''
        else:
            source = EXPLICIT_SOURCE.get(fname)  # None = match any source for this event_id
            category = infer_category(fname)
            severity = infer_severity(fname)
            name_part = re.sub(r'^Error\d+_', '', fname).removesuffix('.ps1')
            description = humanize(name_part)
            recommended_action = f'Run {fname} to remediate.'

        name_part = re.sub(r'^Error\d+_', '', fname).removesuffix('.ps1')
        rule_name = f'{category} - Event {event_id}' + (f' ({source})' if source else '')

        entries.append({
            'script': f'remediation_scripts/{fname}',
            'event_id': event_id,
            'source': source,
            'rule_name': rule_name,
            'category': category,
            'severity': severity,
            'description': description,
            'recommended_action': recommended_action,
            'priority': 100,
            'cooldown_minutes': 5,
            # Deliberately conservative: newly-onboarded scripts require an
            # operator to enable auto-remediation explicitly via the Rules
            # screen after reviewing what the script does. Only the 16
            # rules already live in rules.db keep their existing setting
            # (the loader never overwrites an existing rule's auto_remediate).
            'auto_remediate': False,
        })

    with open(OUTPUT_PATH, 'w', encoding='utf-8') as f:
        json.dump(entries, f, indent=2)

    print(f'Wrote {len(entries)} entries to {OUTPUT_PATH}')
    if skipped:
        print(f'Skipped (no parseable event ID, not in EXCLUDE or EXPLICIT_EVENT_ID): {skipped}')


if __name__ == '__main__':
    main()
