"""
Unit tests for models.py — Task 5.

Focus areas called out by the task: the run_remediation() execution state
machine (running -> verifying -> success | failed | rolled_back |
verification_failed) and the new-event-type approval gating logic
(is_event_type_approved / create_approval_request / resolve_approval_request).
subprocess.run is mocked globally (see conftest.no_real_powershell) so no
real PowerShell script ever executes.

run_remediation() is asynchronous: it submits the job to a worker pool,
records the history row as 'running', and returns immediately. Tests
therefore assert on the immediate 'running' contract and then poll the
history row (wait_until) for the terminal state the worker settles it to.
"""
import sqlite3

from conftest import wait_until, REAL_SLEEP


def _raw_history_row(models_module, history_id):
    conn = sqlite3.connect(models_module.DB_PATH)
    try:
        c = conn.cursor()
        c.execute(
            'SELECT status, output, verification_started_at, verified_at, rollback_output, '
            'error_output FROM remediation_history WHERE id=?', (history_id,)
        )
        return c.fetchone()
    finally:
        conn.close()


# ─────────────────────────────────────────────────────────────────────────────
#  Rule CRUD
# ─────────────────────────────────────────────────────────────────────────────

def test_add_and_get_rule(models_module):
    rid = models_module.add_rule(
        name='Test Rule 7777', event_id=7777, source='Test Source',
        remediation_script='remediation_scripts/does_not_exist.ps1',
        auto_remediate=True, rollback_script='remediation_scripts/rollback.ps1',
        verification_timeout_sec=5,
    )
    rule = models_module.get_rule(rid)
    assert rule is not None
    assert rule[1] == 'Test Rule 7777'   # name
    assert rule[2] == 7777               # event_id
    assert rule[3] == 'Test Source'      # source
    assert bool(rule[6]) is True         # auto_remediate
    assert rule[16] == 'remediation_scripts/rollback.ps1'  # rollback_script
    assert rule[17] == 5                 # verification_timeout_sec


def test_toggle_rule_active(models_module):
    rid = models_module.add_rule(name='Toggle Me', event_id=8888, source='X')
    assert models_module.toggle_rule_active(rid, False) is True
    rule = models_module.get_rule(rid)
    # active isn't in get_rule's tuple by index in older shape checks, so
    # confirm via get_rules() which always includes it at index 15.
    matching = [r for r in models_module.get_rules() if r[0] == rid]
    assert matching and matching[0][15] == 0


# ─────────────────────────────────────────────────────────────────────────────
#  Regex-aware rule matching (Task 3)
# ─────────────────────────────────────────────────────────────────────────────

def test_regex_matching_requires_pattern_match(models_module):
    rid = models_module.add_rule(
        name='Regex Rule', event_id=9001, source='RegexSource',
        message_regex=r'(?i)disk is full', remediation_script='x.ps1',
        auto_remediate=False,
    )
    matching_event = {'event_id': 9001, 'source': 'RegexSource', 'message': 'WARNING: disk is FULL on C:'}
    non_matching_event = {'event_id': 9001, 'source': 'RegexSource', 'message': 'unrelated message'}

    matched = models_module.match_rules_for_event(matching_event)
    assert any(m[0] == rid for m in matched)

    matched_none = models_module.match_rules_for_event(non_matching_event)
    assert not any(m[0] == rid for m in matched_none)


def test_regex_capture_groups_are_cached_and_reusable(models_module):
    rid = models_module.add_rule(
        name='Capture Rule', event_id=9002, source='CaptureSource',
        message_regex=r'process (?P<proc>\w+\.exe) crashed', remediation_script='x.ps1',
    )
    event = {'event_id': 9002, 'source': 'CaptureSource', 'message': 'process notepad.exe crashed'}
    matched = models_module.match_rules_for_event(event)
    hit = next(m for m in matched if m[0] == rid)
    regex_captures = hit[-1]
    assert regex_captures.get('proc') == 'notepad.exe'


# ─────────────────────────────────────────────────────────────────────────────
#  Approval gating (new-event-type sign-off)
# ─────────────────────────────────────────────────────────────────────────────

def test_new_event_type_is_not_approved_by_default(models_module):
    assert models_module.is_event_type_approved('12345', 'Never Seen Source') is False


def test_approval_gate_lifecycle(models_module):
    event_row_id = models_module.add_event(
        event_id=12346, log_name='System', source='Gate Source',
        message='test event needing approval',
    )
    rid = models_module.add_rule(name='Gated Rule', event_id=12346, source='Gate Source')

    req_id = models_module.create_approval_request(event_row_id, 12346, 'Gate Source', rid, 'Gated Rule')
    pending = models_module.get_approval_requests(status='pending')
    assert any(r[0] == req_id for r in pending)

    models_module.resolve_approval_request(req_id, 'approved', resolved_by='tester')
    models_module.mark_event_type_approved(12346, 'Gate Source', approved_by='tester')

    assert models_module.is_event_type_approved('12346', 'Gate Source') is True
    resolved = models_module.get_approval_request(req_id)
    assert resolved[6] == 'approved'


# ─────────────────────────────────────────────────────────────────────────────
#  History date-range filtering
# ─────────────────────────────────────────────────────────────────────────────

def test_get_history_date_range_filter(models_module):
    event_row_id = models_module.add_event(
        event_id=3001, log_name='System', source='DateFilter', message='m'
    )
    rid = models_module.add_rule(name='Date Filter Rule', event_id=3001, source='DateFilter')
    h_old = models_module.record_remediation(event_row_id, rid, 'success', 'old run')
    h_new = models_module.record_remediation(event_row_id, rid, 'success', 'new run')

    conn = sqlite3.connect(models_module.DB_PATH)
    conn.execute('UPDATE remediation_history SET timestamp=? WHERE id=?', ('2020-01-01T10:00:00', h_old))
    conn.execute('UPDATE remediation_history SET timestamp=? WHERE id=?', ('2020-02-01T10:00:00', h_new))
    conn.commit()
    conn.close()

    window = dict(date_from='2020-01-15T00:00:00', date_to='2020-02-15T00:00:00')
    ids = {r[0] for r in models_module.get_history(limit=100, **window)}
    assert h_new in ids and h_old not in ids
    assert models_module.get_history_count(**window) == 1

    earlier = dict(date_from='2019-12-31T00:00:00', date_to='2020-01-15T00:00:00')
    ids_old = {r[0] for r in models_module.get_history(limit=100, **earlier)}
    assert h_old in ids_old and h_new not in ids_old


# ─────────────────────────────────────────────────────────────────────────────
#  run_remediation() closed-loop state machine (Task 2)
# ─────────────────────────────────────────────────────────────────────────────

def test_run_remediation_no_script_is_skipped(models_module):
    event_row_id = models_module.add_event(event_id=1, log_name='System', source='NoScript', message='m')
    rid = models_module.add_rule(name='No Script Rule', event_id=1, source='NoScript', remediation_script=None)

    result = models_module.run_remediation(event_row_id, rid)
    assert result['status'] == 'skipped'


def test_run_remediation_success_verifies_with_no_recurrence(models_module, no_real_powershell):
    no_real_powershell.return_value.returncode = 0
    no_real_powershell.return_value.stdout = 'did the fix'
    no_real_powershell.return_value.stderr = ''

    event_row_id = models_module.add_event(
        event_id=2001, log_name='System', source='HappyPath', message='original failure'
    )
    rid = models_module.add_rule(
        name='Happy Path Rule', event_id=2001, source='HappyPath',
        remediation_script='# fake script', script_type='inline', verification_timeout_sec=1,
    )

    result = models_module.run_remediation(event_row_id, rid)
    # The call returns immediately — the job is submitted, the history row is
    # 'running', and the worker + closed-loop verifier settle the real outcome
    # asynchronously (running -> verifying -> success).
    assert result['status'] == 'running'
    history_id = result['history_id']

    ok = wait_until(lambda: _raw_history_row(models_module, history_id)[0] == 'success', timeout=3)
    assert ok, f'expected success, got {_raw_history_row(models_module, history_id)}'
    final = _raw_history_row(models_module, history_id)
    assert final[3] is not None  # verified_at set


def test_run_remediation_failed_script_is_terminal_immediately(models_module, no_real_powershell):
    no_real_powershell.return_value.returncode = 1
    no_real_powershell.return_value.stdout = ''
    no_real_powershell.return_value.stderr = 'boom'

    event_row_id = models_module.add_event(event_id=2002, log_name='System', source='FailPath', message='m')
    rid = models_module.add_rule(
        name='Fail Path Rule', event_id=2002, source='FailPath',
        remediation_script='# fake script', script_type='inline',
    )

    result = models_module.run_remediation(event_row_id, rid)
    # Submission succeeds immediately; the worker settles the row to 'failed'
    # (a non-zero exit is a known-bad outcome — no verification phase).
    assert result['status'] == 'running'
    history_id = result['history_id']

    ok = wait_until(lambda: _raw_history_row(models_module, history_id)[0] == 'failed', timeout=3)
    assert ok, f'expected failed, got {_raw_history_row(models_module, history_id)}'
    final = _raw_history_row(models_module, history_id)
    assert 'boom' in (final[5] or '')  # stderr captured into error_output


def test_run_remediation_rolls_back_on_recurrence(models_module, monkeypatch, no_real_powershell):
    no_real_powershell.return_value.returncode = 0
    no_real_powershell.return_value.stdout = 'fixed it (allegedly)'
    no_real_powershell.return_value.stderr = ''

    # Give the background verifier a small *real* window instead of the
    # session-wide instant no-op, so the main thread can win the race and
    # insert the "recurrence" event before the worker checks for it.
    monkeypatch.setattr(models_module.time, 'sleep', lambda *_a, **_kw: REAL_SLEEP(0.3))

    event_row_id = models_module.add_event(
        event_id=2003, log_name='System', source='FlappyPath', message='original failure'
    )
    rid = models_module.add_rule(
        name='Flappy Rule', event_id=2003, source='FlappyPath',
        remediation_script='# fake script', script_type='inline',
        rollback_script='# fake rollback script',
        verification_timeout_sec=1,
    )

    result = models_module.run_remediation(event_row_id, rid)
    assert result['status'] == 'running'
    history_id = result['history_id']

    # The same problem fires again almost immediately — the "fix" didn't hold.
    # (run_started_at is captured at submission time, so this recurrence is
    # inside the verification window even though the worker runs async.)
    models_module.add_event(event_id=2003, log_name='System', source='FlappyPath',
                             message='original failure recurring')

    ok = wait_until(lambda: _raw_history_row(models_module, history_id)[0] == 'rolled_back', timeout=3)
    assert ok, f'expected rolled_back, got {_raw_history_row(models_module, history_id)}'
    final = _raw_history_row(models_module, history_id)
    assert final[4] is not None  # rollback_output populated
    assert 'success' in final[4].lower() or 'mocked' in final[4].lower() or 'fake' in final[4].lower()


def test_run_remediation_verification_failed_without_rollback_script(models_module, monkeypatch, no_real_powershell):
    no_real_powershell.return_value.returncode = 0
    no_real_powershell.return_value.stdout = 'fixed it (allegedly)'
    no_real_powershell.return_value.stderr = ''
    monkeypatch.setattr(models_module.time, 'sleep', lambda *_a, **_kw: REAL_SLEEP(0.3))

    event_row_id = models_module.add_event(
        event_id=2004, log_name='System', source='NoRollbackPath', message='original failure'
    )
    rid = models_module.add_rule(
        name='No Rollback Rule', event_id=2004, source='NoRollbackPath',
        remediation_script='# fake script', script_type='inline',
        rollback_script=None, verification_timeout_sec=1,
    )

    result = models_module.run_remediation(event_row_id, rid)
    history_id = result['history_id']
    models_module.add_event(event_id=2004, log_name='System', source='NoRollbackPath',
                             message='original failure recurring again')

    ok = wait_until(lambda: _raw_history_row(models_module, history_id)[0] == 'verification_failed', timeout=3)
    assert ok, f'expected verification_failed, got {_raw_history_row(models_module, history_id)}'
