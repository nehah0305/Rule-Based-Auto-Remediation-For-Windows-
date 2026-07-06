"""
populate_regex_patterns.py
Task 3 — populates message_regex for the pre-existing active rules.

Patterns are deliberately broad/high-recall (verified against this
system's own captured event history in `events`, see the query used to
build this list) rather than tightly matching one exact phrasing: the goal
is to add regex as a genuine matching dimension without silently dropping
real-world event variants that the (event_id, source) match alone would
have caught before. Two rules (1100/EventLog, 1101/EventLog, 2013/Disk)
are deliberately left without a regex — their remediation scripts don't
parse the message at all, so a regex there would only add mismatch risk
for zero benefit.

Only fills in rules where message_regex is currently NULL/empty; never
overwrites a regex an operator has since configured by hand via the UI.

Run once:
    python backend/populate_regex_patterns.py
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import models

# (event_id, source) -> regex. Case-insensitive by convention (models.py
# compiles with re.DOTALL; patterns below embed (?i) for case-insensitivity
# since Get-WinEvent message casing varies by Windows build).
PATTERNS = {
    (7000, 'service control manager'): r'(?i)service failed to start',
    (7001, 'service control manager'): r'(?i)service.*depend',
    (7031, 'service control manager'): r'(?i)service.*terminated unexpectedly',
    (7034, 'service control manager'): r'(?i)service.*terminated unexpectedly',
    (1000, 'application error'): r'(?i)faulting application name',
    (1001, 'windows error reporting'): r'(?i)(faulting application name|application name|not responding|hang)',
    (1026, '.net runtime'): r'(?i)(application|process)\s*name|unhandled exception',
    (2004, 'resource-exhaustion-detector'): r'(?i)(memory|handles|commit|resource).*exhaust',
    (2019, 'srv'): r'(?i)nonpaged pool',
    (2020, 'srv'): r'(?i)paged pool',
    (26, 'application'): r'(?i)memory',
    (41, 'kernel-power'): r'(?i)(resource exhaustion|memory limits|low memory|clean(ly)? shutting down|unexpectedly)',
}


def main():
    rules = models.get_rules()
    updated = 0
    skipped_existing = 0
    for r in rules:
        rid, name, event_id, source, message_regex = r[0], r[1], r[2], r[3], r[4]
        if message_regex:
            skipped_existing += 1
            continue
        key = (event_id, (source or '').lower())
        pattern = PATTERNS.get(key)
        if not pattern:
            continue
        models.update_rule(rid, name=name, message_regex=pattern)
        print(f'  Rule {rid} ({name}): message_regex = {pattern!r}')
        updated += 1

    print(f'\nUpdated {updated} rule(s). {skipped_existing} already had a regex (left untouched).')


if __name__ == '__main__':
    main()
