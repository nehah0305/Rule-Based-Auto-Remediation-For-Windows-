"""
Flask API integration tests (Task 5) — uses app.test_client() against the
same isolated temp-file SQLite DB as test_models.py. subprocess.run is
mocked globally via conftest.no_real_powershell.
"""
import json

from conftest import wait_until


def test_health(client):
    resp = client.get('/api/health')
    assert resp.status_code == 200
    assert resp.get_json()['status'] == 'ok'


def test_get_rules_returns_manifest_onboarded_rules(client):
    resp = client.get('/api/rules')
    assert resp.status_code == 200
    rules = resp.get_json()
    assert isinstance(rules, list)
    # rules_manifest.json onboards 50+ rules on top of whatever's hand-seeded;
    # this is really asserting the Task 1 manifest loader actually ran.
    assert len(rules) >= 50


def test_rule_crud_lifecycle(client):
    create_resp = client.post('/api/rules', json={
        'name': 'API Test Rule',
        'event_id': 5555,
        'source': 'API Test Source',
        'remediation_script': 'remediation_scripts/does_not_exist.ps1',
        'auto_remediate': False,
        'rollback_script': 'remediation_scripts/rollback.ps1',
        'verification_timeout_sec': 30,
    })
    assert create_resp.status_code == 201
    rule_id = create_resp.get_json()['rule_id']

    get_resp = client.get(f'/api/rules/{rule_id}')
    assert get_resp.status_code == 200
    rule = get_resp.get_json()
    assert rule['name'] == 'API Test Rule'
    assert rule['event_id'] == 5555
    assert rule['rollback_script'] == 'remediation_scripts/rollback.ps1'
    assert rule['verification_timeout_sec'] == 30

    put_resp = client.put(f'/api/rules/{rule_id}', json={'name': 'API Test Rule Renamed'})
    assert put_resp.status_code == 200

    get_resp2 = client.get(f'/api/rules/{rule_id}')
    assert get_resp2.get_json()['name'] == 'API Test Rule Renamed'

    delete_resp = client.delete(f'/api/rules/{rule_id}')
    assert delete_resp.status_code == 200

    get_resp3 = client.get(f'/api/rules/{rule_id}')
    assert get_resp3.status_code == 404


def test_create_rule_rejects_invalid_regex(client):
    resp = client.post('/api/rules', json={
        'name': 'Bad Regex Rule',
        'event_id': 6666,
        'message_regex': '(unclosed',
    })
    assert resp.status_code == 400
    assert 'regex' in resp.get_json()['error'].lower()


def test_metrics_endpoint_shape(client):
    resp = client.get('/api/metrics')
    assert resp.status_code == 200
    data = resp.get_json()
    assert set(['success_rate', 'mttr', 'mttr_timeseries', 'auto_vs_manual', 'generated_at']) <= set(data.keys())
    assert 'success_rate_pct' in data['success_rate']
    assert 'mttr_seconds' in data['mttr']
    assert 'auto_count' in data['auto_vs_manual']


def test_approvals_endpoint_lifecycle(client, models_module, no_real_powershell):
    no_real_powershell.return_value.returncode = 0
    no_real_powershell.return_value.stdout = 'ok'
    no_real_powershell.return_value.stderr = ''

    event_row_id = models_module.add_event(
        event_id=7001, log_name='System', source='API Gate Source', message='needs approval'
    )
    rid = models_module.add_rule(
        name='API Gated Rule', event_id=7001, source='API Gate Source',
        remediation_script='# fake script', script_type='inline', verification_timeout_sec=1,
    )
    req_id = models_module.create_approval_request(event_row_id, 7001, 'API Gate Source', rid, 'API Gated Rule')

    list_resp = client.get('/api/approvals?status=pending')
    assert list_resp.status_code == 200
    assert any(r['id'] == req_id for r in list_resp.get_json())

    approve_resp = client.post(f'/api/approvals/{req_id}/approve', json={'resolved_by': 'tester'})
    assert approve_resp.status_code == 200
    assert approve_resp.get_json()['status'] == 'approved'

    assert models_module.is_event_type_approved('7001', 'API Gate Source') is True

    # Re-approving an already-resolved request should be rejected, not silently re-run.
    second_attempt = client.post(f'/api/approvals/{req_id}/approve', json={'resolved_by': 'tester'})
    assert second_attempt.status_code == 400


def test_approvals_reject_does_not_mark_event_type_approved(client, models_module):
    event_row_id = models_module.add_event(
        event_id=7002, log_name='System', source='API Reject Source', message='needs approval'
    )
    rid = models_module.add_rule(name='API Reject Rule', event_id=7002, source='API Reject Source')
    req_id = models_module.create_approval_request(event_row_id, 7002, 'API Reject Source', rid, 'API Reject Rule')

    resp = client.post(f'/api/approvals/{req_id}/reject', json={'resolved_by': 'tester'})
    assert resp.status_code == 200
    assert resp.get_json()['status'] == 'rejected'
    assert models_module.is_event_type_approved('7002', 'API Reject Source') is False
