from flask import Flask, request, jsonify, render_template
import subprocess
import os
import json
import re
import random
from datetime import datetime, timedelta
from dotenv import load_dotenv

from db_init import init_db
import models

# Load environment variables from .env file
load_dotenv()

app = Flask(__name__)

# Ensure DB exists and migrations run
init_db()


@app.route('/')
def index():
    return render_template('index.html')


# ─────────────────────────────────────────────────────────────────────────────
#  Events
# ─────────────────────────────────────────────────────────────────────────────

@app.route('/api/events', methods=['GET', 'POST'])
def events():
    if request.method == 'GET':
        rows = models.get_events(limit=200)
        result = []
        for r in rows:
            result.append(dict(
                id=r[0], event_id=r[1], log_name=r[2], source=r[3],
                message=r[4], timestamp=r[5], category=r[6], severity=r[7],
                description=r[8], recommended_action=r[9],
                dedup_count=r[10] if len(r) > 10 else 1,
                last_seen=r[11] if len(r) > 11 else None,
                confidence_score=r[12] if len(r) > 12 else 0.0,
                correlation_id=r[13] if len(r) > 13 else None,
            ))
        return jsonify(result)

    data = request.get_json(force=True)
    event_row_id = models.add_event(
        data.get('event_id'),
        data.get('log_name'),
        data.get('source'),
        data.get('message'),
        data.get('timestamp'),
        data.get('category'),
        data.get('severity'),
        data.get('description'),
        data.get('recommended_action'),
        data.get('level'),
    )

    # Match rules — now returns list of tuples with cooldown_active flag at [-1]
    matched_tuples = models.match_rules_for_event(data)
    matched_info = []

    for r in matched_tuples:
        # r structure from match_rules_for_event:
        # [0-14] = rule cols, [15] = cooldown_active (bool), [16] = regex_captures (dict)
        cooldown_active = r[15] if len(r) > 15 else False
        regex_captures = r[16] if len(r) > 16 else {}
        rid = r[0]
        matched_info.append({
            'rule_id': rid,
            'rule_name': r[1],
            'remediation': r[5],
            'cooldown_active': cooldown_active,
        })
        # Auto-run only if auto_remediate=True AND not in cooldown
        if r[6] and not cooldown_active:
            models.run_remediation(event_row_id, rid, regex_captures=regex_captures)
        elif r[6] and cooldown_active:
            # Record a suppressed entry so the user can see it happened
            models.record_remediation(event_row_id, rid, 'suppressed',
                                      'Auto-remediation suppressed — rule cooldown active')

    return jsonify({'status': 'ok', 'event_id': event_row_id, 'matched': matched_info})


@app.route('/api/events/ensure', methods=['POST'])
def ensure_event():
    """Find or create a DB event row without triggering auto-remediation."""
    data = request.get_json(force=True)
    event_row_id = models.find_or_create_event(
        data.get('event_id'),
        data.get('log_name'),
        data.get('source'),
        data.get('message'),
        data.get('timestamp'),
        data.get('category'),
        data.get('severity'),
        data.get('description'),
        data.get('recommended_action'),
        data.get('level'),
    )
    return jsonify({'event_row_id': event_row_id})


@app.route('/api/events/<int:event_id>/matches', methods=['GET'])
def event_matches(event_id):
    ev = models.get_event(event_id)
    if not ev:
        return jsonify({'error': 'event not found'}), 404
    event_dict = {
        'event_id': ev[1], 'log_name': ev[2], 'source': ev[3],
        'message': ev[4], 'timestamp': ev[5], 'category': ev[6],
        'severity': ev[7], 'description': ev[8], 'recommended_action': ev[9],
    }
    matched_tuples = models.match_rules_for_event(event_dict)
    matched_info = []
    for r in matched_tuples:
        cooldown_active = r[15] if len(r) > 15 else False
        matched_info.append(dict(
            id=r[0], name=r[1], event_id=r[2], source=r[3],
            message_regex=r[4], remediation_script=r[5],
            auto_remediate=bool(r[6]), category=r[7], severity=r[8],
            description=r[9], recommended_action=r[10],
            script_type=r[11], priority=r[12], cooldown_minutes=r[13],
            stop_processing=bool(r[14]), cooldown_active=cooldown_active,
        ))
    return jsonify(matched_info)


# ─────────────────────────────────────────────────────────────────────────────
#  Rules
# ─────────────────────────────────────────────────────────────────────────────

def _rule_to_dict(r):
    return dict(
        id=r[0], name=r[1], event_id=r[2], source=r[3],
        message_regex=r[4], remediation_script=r[5],
        auto_remediate=bool(r[6]), category=r[7], severity=r[8],
        description=r[9], recommended_action=r[10],
        script_type=r[11] if len(r) > 11 else 'file',
        priority=r[12] if len(r) > 12 else 100,
        cooldown_minutes=r[13] if len(r) > 13 else 0,
        stop_processing=bool(r[14] if len(r) > 14 else 0),
    )


@app.route('/api/rules', methods=['GET', 'POST'])
def rules():
    if request.method == 'GET':
        rows = models.get_rules()
        return jsonify([_rule_to_dict(r) for r in rows])

    data = request.get_json(force=True)
    rid = models.add_rule(
        data.get('name'),
        data.get('event_id'),
        data.get('source'),
        data.get('message_regex'),
        data.get('remediation_script'),
        data.get('script_type', 'file'),
        data.get('auto_remediate', False),
        data.get('stop_processing', False),
        data.get('category'),
        data.get('severity'),
        data.get('description'),
        data.get('recommended_action'),
        data.get('priority', 100),
        data.get('cooldown_minutes', 0),
    )
    return jsonify({'status': 'created', 'rule_id': rid}), 201


@app.route('/api/rules/<int:rule_id>', methods=['GET', 'PUT', 'DELETE'])
def rule_detail(rule_id):
    if request.method == 'GET':
        r = models.get_rule(rule_id)
        if not r:
            return jsonify({'error': 'not found'}), 404
        return jsonify(_rule_to_dict(r))

    if request.method == 'PUT':
        data = request.get_json(force=True)
        ok = models.update_rule(
            rule_id,
            data.get('name'),
            data.get('event_id'),
            data.get('source'),
            data.get('message_regex'),
            data.get('remediation_script'),
            data.get('script_type'),
            data.get('auto_remediate'),
            data.get('stop_processing'),
            data.get('category'),
            data.get('severity'),
            data.get('description'),
            data.get('recommended_action'),
            data.get('priority'),
            data.get('cooldown_minutes'),
        )
        return jsonify({'status': 'updated' if ok else 'nochange'})

    if request.method == 'DELETE':
        models.delete_rule(rule_id)
        return jsonify({'status': 'deleted'})


@app.route('/api/rules/<int:rule_id>/run', methods=['POST'])
def run_rule(rule_id):
    data = request.get_json(force=True)
    event_row_id = data.get('event_row_id')
    if not event_row_id:
        return jsonify({'error': 'event_row_id required'}), 400
    result = models.run_remediation(event_row_id, rule_id)
    return jsonify(result)


@app.route('/api/rules/<int:rule_id>/test', methods=['POST'])
def test_rule(rule_id):
    """Create a synthetic test event and run the rule against it."""
    rule = models.get_rule(rule_id)
    if not rule:
        return jsonify({'error': 'rule not found'}), 404
    event_row_id = models.add_event(
        event_id=rule[2] or 0,
        log_name='TestRun',
        source=rule[3] or 'TestSource',
        message=f'[Test Run] Manual test of rule: {rule[1]}',
        level='Test',
    )
    result = models.run_remediation(event_row_id, rule_id)
    return jsonify({
        'status': result.get('status'),
        'output': result.get('output'),
        'event_row_id': event_row_id,
    })


# ─────────────────────────────────────────────────────────────────────────────
#  History
# ─────────────────────────────────────────────────────────────────────────────

@app.route('/api/history', methods=['GET'])
def history():
    rows = models.get_history(limit=500)
    hist = []
    for h in rows:
        hist.append(dict(
            id=h[0], event_row_id=h[1], rule_id=h[2],
            status=h[3], output=h[4], timestamp=h[5],
            event_id=h[6], event_source=h[7],
            rule_name=h[8], event_timestamp=h[9],
        ))
    return jsonify(hist)


# ─────────────────────────────────────────────────────────────────────────────
#  Approvals / Requests
# ─────────────────────────────────────────────────────────────────────────────

@app.route('/api/requests', methods=['GET', 'POST'])
def requests_list():
    if request.method == 'GET':
        status = request.args.get('status')
        rows = models.get_requests(status)
        reqs = []
        for r in rows:
            reqs.append(dict(
                id=r[0], event_row_id=r[1], rule_id=r[2], status=r[3],
                requested_by=r[4], requested_at=r[5], processed_by=r[6],
                processed_at=r[7], decision_note=r[8],
                event_id=r[9], event_source=r[10], rule_name=r[11],
            ))
        return jsonify(reqs)

    data = request.get_json(force=True)
    if not data.get('event_row_id') or not data.get('rule_id'):
        return jsonify({'error': 'event_row_id and rule_id required'}), 400
    rid = models.create_remediation_request(
        data.get('event_row_id'), data.get('rule_id'),
        data.get('requested_by', 'web-ui'),
    )
    return jsonify({'status': 'requested', 'request_id': rid}), 201


@app.route('/api/requests/<int:req_id>/approve', methods=['POST'])
def approve_request(req_id):
    req = models.get_request(req_id)
    if not req:
        return jsonify({'error': 'not found'}), 404
    if req[3] != 'pending':
        return jsonify({'error': 'not pending'}), 400
    result = models.run_remediation(req[1], req[2])
    note = result.get('status', '')
    if result.get('output'):
        note += ': ' + (result.get('output')[:1000])
    processed_by = request.get_json(force=True).get('processed_by', 'admin')
    models.update_request_status(req_id, 'approved', processed_by, note)
    return jsonify({'status': 'approved', 'result': result})


@app.route('/api/requests/<int:req_id>/deny', methods=['POST'])
def deny_request(req_id):
    data = request.get_json(force=True)
    processed_by = data.get('processed_by', 'admin')
    note = data.get('note', 'denied by admin')
    models.update_request_status(req_id, 'denied', processed_by, note)
    return jsonify({'status': 'denied'})


# ─────────────────────────────────────────────────────────────────────────────
#  Event definitions & filtered events (CSV)
# ─────────────────────────────────────────────────────────────────────────────

@app.route('/api/event-definitions', methods=['GET'])
def event_definitions():
    return jsonify(models.get_all_event_definitions())


@app.route('/api/event-definitions/<int:event_id>', methods=['GET'])
def event_definition_detail(event_id):
    source = request.args.get('source')
    defn = models.get_event_definition(event_id, source)
    if not defn:
        return jsonify({'error': 'event definition not found'}), 404
    return jsonify(defn)


@app.route('/api/filtered-events', methods=['GET'])
def filtered_events():
    try:
        rows = models.read_filtered_events_csv()
        return jsonify(rows)
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/last-processed', methods=['GET'])
def last_processed():
    try:
        lp = models.get_last_processed()
        return jsonify(lp or {})
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/populate-rules', methods=['POST'])
def populate_rules():
    data = request.get_json(force=True) if request.is_json else {}
    overwrite = data.get('overwrite', False)
    try:
        count = models.populate_rules_from_json(overwrite=overwrite)
        return jsonify({'status': 'success', 'rules_created': count})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500


# ─────────────────────────────────────────────────────────────────────────────
#  Alert Intelligence summary
# ─────────────────────────────────────────────────────────────────────────────

@app.route('/api/intelligence/summary', methods=['GET'])
def intelligence_summary():
    """
    Returns aggregated Alert Intelligence metrics for the Dashboard card.
    """
    try:
        summary = models.get_intelligence_summary()
        return jsonify(summary)
    except Exception as e:
        return jsonify({'error': str(e)}), 500


# ─────────────────────────────────────────────────────────────────────────────
#  Simulations
# ─────────────────────────────────────────────────────────────────────────────

@app.route('/api/simulations/error1000', methods=['POST'])
def simulate_error1000():
    """
    Simulates the Event ID 1000 (Application Crash) auto-remediation flow.
    This endpoint never executes the real fix command; it demonstrates behavior
    for UI walkthroughs and demos.
    """
    data = request.get_json(silent=True) or {}
    try:
        count = int(data.get('count', 3))
    except (TypeError, ValueError):
        count = 3
    count = max(1, min(count, 10))

    now = datetime.utcnow()
    fix_script = 'sfc /scannow'
    description = 'Application Crash'

    events = []
    timeline = [
        {
            'phase': 'fetch',
            'title': 'Fetch Recent Errors',
            'status': 'completed',
            'detail': f'Collected {count} recent System log events for Event ID 1000 (Level 1/2).'
        }
    ]

    terminal_lines = [
        'Fetching recent errors for Event ID 1000...',
        f'Simulation mode ON: {fix_script} will not be executed on this machine.'
    ]

    for idx in range(count):
        event_time = now - timedelta(minutes=(idx + 1) * 4)
        message = (
            f'Faulting application name: DemoCrashApp{idx + 1}.exe, version: 1.0.{idx + 1}.0, '
            f'faulting module: ntdll.dll, exception code: 0xc0000005, process id: 0x{1000 + idx:04x}'
        )
        message_preview = message[:100] + ('...' if len(message) > 100 else '')

        events.append({
            'event_id': 1000,
            'time_created': event_time.isoformat() + 'Z',
            'source': 'Application Error',
            'description': description,
            'message': message,
            'message_preview': message_preview,
        })

        timeline.extend([
            {
                'phase': 'analyze',
                'title': f'Analyze Event {idx + 1}',
                'status': 'completed',
                'detail': f'Event ID 1000 at {event_time.isoformat()}Z classified as {description}.'
            },
            {
                'phase': 'remediate',
                'title': f'Apply Fix for Event {idx + 1}',
                'status': 'simulated',
                'detail': f'Would execute: {fix_script}'
            }
        ])

        terminal_lines.extend([
            f'Event ID: 1000 at {event_time.isoformat()}Z',
            f'Message: {message_preview}',
            f'Classified as: {description}',
            f'Executing Fix: {fix_script} [SIMULATED]',
            '-------------------'
        ])

    terminal_lines.append('Analysis and simulated fixes complete.')

    return jsonify({
        'scenario': 'Event ID 1000 - Application Crash',
        'event_id': 1000,
        'description': description,
        'fix_script': fix_script,
        'script_path': 'remediation_scripts/Error1000_ApplicationCrash.ps1',
        'simulation_mode': True,
        'generated_at': datetime.utcnow().isoformat() + 'Z',
        'events': events,
        'timeline': timeline,
        'terminal_output': '\n'.join(terminal_lines),
        'summary': {
            'events_detected': len(events),
            'events_analyzed': len(events),
            'fixes_simulated': len(events),
            'actual_fixes_executed': 0,
        }
    })


@app.route('/api/simulations/error1000/auto-fix', methods=['POST'])
def simulate_error1000_auto_fix():
    """
    End-to-end crash simulation:
      1) creates synthetic Event ID 1000 entries,
      2) passes them through rule matching,
      3) triggers auto-remediation via run_remediation.
    """
    data = request.get_json(silent=True) or {}
    app_name = (data.get('app_name') or 'DemoCrashApp').strip()
    module_name = (data.get('module_name') or 'ntdll.dll').strip()
    exception_code = (data.get('exception_code') or '0xc0000005').strip()
    profile = (data.get('profile') or 'degraded').strip().lower()
    if profile not in ('stable', 'degraded', 'critical'):
        profile = 'degraded'

    retry_on_failure = bool(data.get('retry_on_failure', True))
    verify_recovery = bool(data.get('verify_recovery', True))

    try:
        count = int(data.get('count', 1))
    except (TypeError, ValueError):
        count = 1
    count = max(1, min(count, 5))

    script_path = os.path.abspath(os.path.join(
        os.path.dirname(__file__), '..', 'remediation_scripts', 'Error1000_ApplicationCrash.ps1'
    ))

    if not os.path.exists(script_path):
        return jsonify({'error': f'remediation script not found at {script_path}'}), 404

    # Ensure a dedicated auto-remediation rule for the simulation scenario exists.
    demo_rule = None
    for r in models.get_rules():
        if r[2] == 1000 and (r[3] or '').lower() == 'application error' and (r[5] or '') == script_path:
            demo_rule = r
            break

    if not demo_rule:
        rid = models.add_rule(
            name='AutoFix Demo - Event ID 1000 Application Crash',
            event_id=1000,
            source='Application Error',
            message_regex=None,
            remediation_script=script_path,
            script_type='file',
            auto_remediate=True,
            stop_processing=False,
            category='Application Crash',
            severity='Medium',
            description='Auto-fix rule for crash simulation demos.',
            recommended_action='Run script-based remediation for simulated crash events.',
            priority=20,
            cooldown_minutes=0,
        )
        demo_rule = models.get_rule(rid)

    demo_rule_id = demo_rule[0]

    now = datetime.utcnow()
    timeline = []
    events_summary = []
    totals = {
        'events_created': 0,
        'rules_matched': 0,
        'auto_remediations_run': 0,
        'auto_remediation_success': 0,
        'auto_remediation_failed': 0,
        'auto_remediation_suppressed': 0,
        'retries_performed': 0,
        'verification_failed': 0,
        'incident_resolved': 0,
        'incident_unresolved': 0,
        'mean_time_to_recover_seconds': 0,
    }
    mttr_samples = []

    timeline.append({
        'phase': 'prepare',
        'title': 'Prepare Simulation Environment',
        'status': 'completed',
        'detail': f'Using rule #{demo_rule_id} and script {script_path}. Profile: {profile.title()}.'
    })

    for idx in range(count):
        crash_time = now - timedelta(seconds=idx * 45)
        crash_message = (
            f'Faulting application name: {app_name}.exe, version: 1.0.{idx + 1}.0, '
            f'faulting module name: {module_name}, exception code: {exception_code}, '
            f'fault offset: 0x0000{(1200 + idx):04x}, process id: 0x{(5000 + idx):04x}'
        )

        event_payload = {
            'event_id': 1000,
            'log_name': 'Simulation',
            'source': 'Application Error',
            'message': crash_message,
            'timestamp': crash_time.isoformat(),
            'category': 'Application Crash',
            'severity': 'Medium',
            'description': 'Simulated application crash event',
            'recommended_action': 'Execute remediation for Event ID 1000',
            'level': 'Error',
        }

        event_row_id = models.add_event(
            event_payload['event_id'],
            event_payload['log_name'],
            event_payload['source'],
            event_payload['message'],
            event_payload['timestamp'],
            event_payload['category'],
            event_payload['severity'],
            event_payload['description'],
            event_payload['recommended_action'],
            event_payload['level'],
        )
        totals['events_created'] += 1

        timeline.append({
            'phase': 'detect',
            'title': f'Detect Crash Event {idx + 1}',
            'status': 'completed',
            'detail': f'Event row #{event_row_id} created for {app_name}.exe crash.'
        })

        severity_hint = 'High' if profile == 'critical' else ('Medium' if profile == 'degraded' else 'Low')
        timeline.append({
            'phase': 'triage',
            'title': f'Triage Event {idx + 1}',
            'status': 'completed',
            'detail': f'Crash signature {exception_code} in {module_name}; triage severity: {severity_hint}.'
        })

        matched_tuples = models.match_rules_for_event(event_payload)
        rule_matches = []
        remediation_results = []
        event_resolved = False
        event_start = datetime.utcnow()

        for r in matched_tuples:
            cooldown_active = r[15] if len(r) > 15 else False
            regex_captures = r[16] if len(r) > 16 else {}
            rule_info = {
                'rule_id': r[0],
                'rule_name': r[1],
                'auto_remediate': bool(r[6]),
                'cooldown_active': bool(cooldown_active),
            }
            rule_matches.append(rule_info)
            totals['rules_matched'] += 1

            if r[6] and not cooldown_active:
                max_attempts = 2 if retry_on_failure else 1
                last_status = 'failed'
                verification_ok = False
                for attempt in range(1, max_attempts + 1):
                    result = models.run_remediation(event_row_id, r[0], regex_captures=regex_captures)
                    totals['auto_remediations_run'] += 1

                    if result.get('status') == 'success':
                        totals['auto_remediation_success'] += 1
                    else:
                        totals['auto_remediation_failed'] += 1

                    # Simulate post-remediation health validation realism.
                    if verify_recovery and result.get('status') == 'success':
                        # More unstable profiles are less likely to pass first verification.
                        fail_chance = 0.05 if profile == 'stable' else (0.2 if profile == 'degraded' else 0.4)
                        # Make first attempt of critical incidents especially brittle.
                        if profile == 'critical' and attempt == 1:
                            fail_chance = max(fail_chance, 0.55)
                        verification_ok = random.random() > fail_chance
                    else:
                        verification_ok = (result.get('status') == 'success')

                    remediation_results.append({
                        'attempt': attempt,
                        'rule_id': r[0],
                        'rule_name': r[1],
                        'status': result.get('status'),
                        'verification_passed': verification_ok,
                        'output': result.get('output'),
                    })

                    last_status = result.get('status', 'failed')
                    timeline.append({
                        'phase': 'remediate',
                        'title': f'Auto-Remediate Event {idx + 1} (Attempt {attempt})',
                        'status': last_status,
                        'detail': f"Rule #{r[0]} execution status: {last_status}"
                    })

                    if verify_recovery:
                        verify_status = 'completed' if verification_ok else 'warning'
                        verify_detail = 'Health check passed: app process responsive and error burst stopped.' if verification_ok else 'Health check failed: crash signature still observed in telemetry window.'
                        timeline.append({
                            'phase': 'verify',
                            'title': f'Verify Recovery Event {idx + 1} (Attempt {attempt})',
                            'status': verify_status,
                            'detail': verify_detail
                        })

                    if last_status == 'success' and verification_ok:
                        event_resolved = True
                        break

                    if attempt < max_attempts:
                        totals['retries_performed'] += 1
                        timeline.append({
                            'phase': 'retry',
                            'title': f'Retry Remediation Event {idx + 1}',
                            'status': 'warning',
                            'detail': 'Automatic retry scheduled due to failed verification or script failure.'
                        })

                if verify_recovery and not event_resolved:
                    totals['verification_failed'] += 1
            elif r[6] and cooldown_active:
                models.record_remediation(
                    event_row_id,
                    r[0],
                    'suppressed',
                    'Auto-remediation suppressed - rule cooldown active'
                )
                totals['auto_remediation_suppressed'] += 1
                timeline.append({
                    'phase': 'remediate',
                    'title': f'Auto-Remediation Suppressed for Event {idx + 1}',
                    'status': 'suppressed',
                    'detail': f'Rule #{r[0]} suppressed due to cooldown.'
                })

        if event_resolved:
            totals['incident_resolved'] += 1
            mttr_samples.append((datetime.utcnow() - event_start).total_seconds())
            timeline.append({
                'phase': 'close',
                'title': f'Close Incident Event {idx + 1}',
                'status': 'completed',
                'detail': 'Incident resolved and monitored workload stabilized.'
            })
        else:
            totals['incident_unresolved'] += 1
            timeline.append({
                'phase': 'escalate',
                'title': f'Escalate Incident Event {idx + 1}',
                'status': 'failed',
                'detail': 'Incident remains unstable after remediation attempts. Manual escalation required.'
            })

        events_summary.append({
            'event_row_id': event_row_id,
            'timestamp': event_payload['timestamp'],
            'message': crash_message,
            'matches': rule_matches,
            'remediations': remediation_results,
            'resolved': event_resolved,
        })

    latest_output = ''
    if events_summary:
        rems = events_summary[-1].get('remediations') or []
        if rems:
            latest_output = rems[-1].get('output') or ''

    if mttr_samples:
        totals['mean_time_to_recover_seconds'] = round(sum(mttr_samples) / len(mttr_samples), 2)

    return jsonify({
        'scenario': 'Crash Lab - Event ID 1000 Auto-Fix',
        'simulation_mode': True,
        'event_id': 1000,
        'fix_script': 'sfc /scannow',
        'script_path': script_path,
        'rule_id': demo_rule_id,
        'app_name': app_name,
        'count': count,
        'profile': profile,
        'retry_on_failure': retry_on_failure,
        'verify_recovery': verify_recovery,
        'timeline': timeline,
        'events': events_summary,
        'latest_output': latest_output,
        'summary': totals,
    })


@app.route('/api/simulations/lowdiskspace', methods=['POST'])
def simulate_lowdiskspace():
    """
    Simulates the Event ID 2013 (Low Disk Space) detection flow.
    This endpoint demonstrates disk space monitoring behavior for UI walkthroughs.
    """
    data = request.get_json(silent=True) or {}
    try:
        count = int(data.get('count', 3))
    except (TypeError, ValueError):
        count = 3
    count = max(1, min(count, 10))

    now = datetime.utcnow()
    cleanup_script = 'Disk cleanup (Temp files, Recycle bin, Prefetch)'
    description = 'Low Disk Space'

    events = []
    timeline = [
        {
            'phase': 'fetch',
            'title': 'Check Disk Drives',
            'status': 'completed',
            'detail': f'Scanned {count} local drives for low disk space.'
        }
    ]

    terminal_lines = [
        'Checking local drives for low disk space...',
        'Minimum free space threshold: 5GB or 10%',
        '-------------------'
    ]

    for idx in range(count):
        drive_letter = chr(67 + idx)  # C, D, E, etc.
        check_time = now - timedelta(minutes=(idx + 1) * 3)
        total_gb = 500 + (idx * 100)
        free_gb = 3 + (idx * 0.5)  # Less than 5GB threshold
        free_pct = round((free_gb / total_gb) * 100, 2)
        
        message = f'Drive {drive_letter}: {free_gb} GB free of {total_gb} GB ({free_pct}% free)'
        
        events.append({
            'event_id': 2013,
            'time_created': check_time.isoformat() + 'Z',
            'source': 'Disk',
            'description': description,
            'message': message,
            'drive': f'{drive_letter}:',
            'free_gb': free_gb,
            'total_gb': total_gb,
            'free_pct': free_pct,
        })

        timeline.extend([
            {
                'phase': 'analyze',
                'title': f'Analyze Drive {drive_letter}',
                'status': 'completed',
                'detail': f'Event ID 2013 at {check_time.isoformat()}Z classified as {description}.'
            },
            {
                'phase': 'remediate',
                'title': f'Cleanup Drive {drive_letter}',
                'status': 'simulated',
                'detail': f'Would execute: {cleanup_script}'
            }
        ])

        terminal_lines.extend([
            f'Drive {drive_letter}: {free_gb} GB free of {total_gb} GB ({free_pct}% free)',
            f'[ALERT] Low disk space detected on {drive_letter}! Only {free_gb} GB free.',
            f'Executing Cleanup [SIMULATED]',
            '-------------------'
        ])

    terminal_lines.append('Disk space check and simulated cleanup complete.')

    return jsonify({
        'scenario': 'Event ID 2013 - Low Disk Space',
        'event_id': 2013,
        'description': description,
        'cleanup_script': cleanup_script,
        'script_path': 'remediation_scripts/LowDiskSpace_Remediation.ps1',
        'simulation_mode': True,
        'generated_at': datetime.utcnow().isoformat() + 'Z',
        'events': events,
        'timeline': timeline,
        'terminal_output': '\n'.join(terminal_lines),
        'summary': {
            'drives_checked': len(events),
            'drives_with_low_space': len(events),
            'cleanups_simulated': len(events),
            'actual_cleanups_executed': 0,
        }
    })


@app.route('/api/simulations/lowdiskspace/auto-fix', methods=['POST'])
def simulate_lowdiskspace_auto_fix():
    """
    End-to-end disk space simulation:
      1) creates synthetic Event ID 2013 entries,
      2) passes them through rule matching,
      3) triggers auto-remediation via run_remediation.
    """
    data = request.get_json(silent=True) or {}
    profile = (data.get('profile') or 'degraded').strip().lower()
    if profile not in ('stable', 'degraded', 'critical'):
        profile = 'degraded'

    retry_on_failure = bool(data.get('retry_on_failure', True))
    verify_recovery = bool(data.get('verify_recovery', True))

    try:
        count = int(data.get('count', 1))
    except (TypeError, ValueError):
        count = 1
    count = max(1, min(count, 5))

    script_path = os.path.abspath(os.path.join(
        os.path.dirname(__file__), '..', 'remediation_scripts', 'LowDiskSpace_Remediation.ps1'
    ))

    if not os.path.exists(script_path):
        return jsonify({'error': f'remediation script not found at {script_path}'}), 404

    # Ensure a dedicated auto-remediation rule for the simulation scenario exists.
    demo_rule = None
    for r in models.get_rules():
        if r[2] == 2013 and (r[3] or '').lower() == 'disk' and (r[5] or '') == script_path:
            demo_rule = r
            break

    if not demo_rule:
        rid = models.add_rule(
            name='AutoFix Demo - Event ID 2013 Low Disk Space',
            event_id=2013,
            source='Disk',
            message_regex=None,
            remediation_script=script_path,
            script_type='file',
            auto_remediate=True,
            stop_processing=False,
            category='Low Disk Space',
            severity='Medium',
            description='Auto-fix rule for low disk space simulation demos.',
            recommended_action='Run script-based cleanup for simulated disk space issues.',
            priority=20,
            cooldown_minutes=0,
        )
        demo_rule = models.get_rule(rid)

    demo_rule_id = demo_rule[0]

    now = datetime.utcnow()
    timeline = []
    events_summary = []
    totals = {
        'events_created': 0,
        'rules_matched': 0,
        'auto_remediations_run': 0,
        'auto_remediation_success': 0,
        'auto_remediation_failed': 0,
        'auto_remediation_suppressed': 0,
        'retries_performed': 0,
        'verification_failed': 0,
        'incident_resolved': 0,
        'incident_unresolved': 0,
        'mean_time_to_recover_seconds': 0,
    }
    mttr_samples = []

    timeline.append({
        'phase': 'prepare',
        'title': 'Prepare Disk Space Simulation Environment',
        'status': 'completed',
        'detail': f'Using rule #{demo_rule_id} and script {script_path}. Profile: {profile.title()}.'
    })

    for idx in range(count):
        disk_time = now - timedelta(seconds=idx * 45)
        drive_letter = chr(67 + idx)  # C, D, E, etc.
        total_gb = 500 + (idx * 100)
        free_gb = 2 + (idx * 0.3)  # Critical low space
        
        disk_message = (
            f'Disk space on drive {drive_letter}: is running critically low. '
            f'{free_gb} GB free of {total_gb} GB total. Immediate cleanup recommended.'
        )

        event_payload = {
            'event_id': 2013,
            'log_name': 'Simulation',
            'source': 'Disk',
            'message': disk_message,
            'timestamp': disk_time.isoformat(),
            'category': 'Low Disk Space',
            'severity': 'Medium',
            'description': 'Simulated low disk space event',
            'recommended_action': 'Clean temporary files and logs',
            'level': 'Warning',
        }

        event_row_id = models.add_event(
            event_payload['event_id'],
            event_payload['log_name'],
            event_payload['source'],
            event_payload['message'],
            event_payload['timestamp'],
            event_payload['category'],
            event_payload['severity'],
            event_payload['description'],
            event_payload['recommended_action'],
            event_payload['level'],
        )
        totals['events_created'] += 1

        timeline.append({
            'phase': 'detect',
            'title': f'Detect Low Disk Space Event {idx + 1}',
            'status': 'completed',
            'detail': f'Event row #{event_row_id} created for drive {drive_letter}: disk space alert.'
        })

        severity_hint = 'High' if profile == 'critical' else ('Medium' if profile == 'degraded' else 'Low')
        timeline.append({
            'phase': 'triage',
            'title': f'Triage Event {idx + 1}',
            'status': 'completed',
            'detail': f'Drive {drive_letter}: with {free_gb}GB free; triage severity: {severity_hint}.'
        })

        matched_tuples = models.match_rules_for_event(event_payload)
        rule_matches = []
        remediation_results = []
        event_resolved = False
        event_start = datetime.utcnow()

        for r in matched_tuples:
            cooldown_active = r[15] if len(r) > 15 else False
            regex_captures = r[16] if len(r) > 16 else {}
            rule_info = {
                'rule_id': r[0],
                'rule_name': r[1],
                'auto_remediate': bool(r[6]),
                'cooldown_active': bool(cooldown_active),
            }
            rule_matches.append(rule_info)
            totals['rules_matched'] += 1

            if r[6] and not cooldown_active:
                max_attempts = 2 if retry_on_failure else 1
                last_status = 'failed'
                verification_ok = False
                for attempt in range(1, max_attempts + 1):
                    result = models.run_remediation(event_row_id, r[0], regex_captures=regex_captures)
                    totals['auto_remediations_run'] += 1

                    if result.get('status') == 'success':
                        totals['auto_remediation_success'] += 1
                    else:
                        totals['auto_remediation_failed'] += 1

                    # Simulate post-remediation verification.
                    if verify_recovery and result.get('status') == 'success':
                        fail_chance = 0.05 if profile == 'stable' else (0.15 if profile == 'degraded' else 0.35)
                        if profile == 'critical' and attempt == 1:
                            fail_chance = max(fail_chance, 0.45)
                        verification_ok = random.random() > fail_chance
                    else:
                        verification_ok = (result.get('status') == 'success')

                    remediation_results.append({
                        'attempt': attempt,
                        'rule_id': r[0],
                        'rule_name': r[1],
                        'status': result.get('status'),
                        'verification_passed': verification_ok,
                        'output': result.get('output'),
                    })

                    last_status = result.get('status', 'failed')
                    timeline.append({
                        'phase': 'remediate',
                        'title': f'Auto-Remediate Event {idx + 1} (Attempt {attempt})',
                        'status': last_status,
                        'detail': f"Rule #{r[0]} execution status: {last_status}"
                    })

                    if verify_recovery:
                        verify_status = 'completed' if verification_ok else 'warning'
                        verify_detail = 'Health check passed: disk space freed and I/O pressure reduced.' if verification_ok else 'Health check failed: disk space still critically low.'
                        timeline.append({
                            'phase': 'verify',
                            'title': f'Verify Recovery Event {idx + 1} (Attempt {attempt})',
                            'status': verify_status,
                            'detail': verify_detail
                        })

                    if last_status == 'success' and verification_ok:
                        event_resolved = True
                        break

                    if attempt < max_attempts:
                        totals['retries_performed'] += 1
                        timeline.append({
                            'phase': 'retry',
                            'title': f'Retry Remediation Event {idx + 1}',
                            'status': 'warning',
                            'detail': 'Automatic retry scheduled due to failed verification or script failure.'
                        })

                if verify_recovery and not event_resolved:
                    totals['verification_failed'] += 1
            elif r[6] and cooldown_active:
                models.record_remediation(
                    event_row_id,
                    r[0],
                    'suppressed',
                    'Auto-remediation suppressed - rule cooldown active'
                )
                totals['auto_remediation_suppressed'] += 1
                timeline.append({
                    'phase': 'remediate',
                    'title': f'Auto-Remediation Suppressed for Event {idx + 1}',
                    'status': 'suppressed',
                    'detail': f'Rule #{r[0]} suppressed due to cooldown.'
                })

        if event_resolved:
            totals['incident_resolved'] += 1
            mttr_samples.append((datetime.utcnow() - event_start).total_seconds())
            timeline.append({
                'phase': 'close',
                'title': f'Close Incident Event {idx + 1}',
                'status': 'completed',
                'detail': 'Disk space issue resolved and storage subsystem stabilized.'
            })
        else:
            totals['incident_unresolved'] += 1
            timeline.append({
                'phase': 'escalate',
                'title': f'Escalate Incident Event {idx + 1}',
                'status': 'failed',
                'detail': 'Disk space issue remains unresolved after cleanup attempts. Manual escalation required.'
            })

        events_summary.append({
            'event_row_id': event_row_id,
            'timestamp': event_payload['timestamp'],
            'message': disk_message,
            'drive': f'{drive_letter}:',
            'matches': rule_matches,
            'remediations': remediation_results,
            'resolved': event_resolved,
        })

    latest_output = ''
    if events_summary:
        rems = events_summary[-1].get('remediations') or []
        if rems:
            latest_output = rems[-1].get('output') or ''

    if mttr_samples:
        totals['mean_time_to_recover_seconds'] = round(sum(mttr_samples) / len(mttr_samples), 2)

    return jsonify({
        'scenario': 'Disk Space Lab - Event ID 2013 Auto-Fix',
        'simulation_mode': True,
        'event_id': 2013,
        'cleanup_script': 'Disk cleanup (Temp files, Recycle bin, Prefetch)',
        'script_path': script_path,
        'rule_id': demo_rule_id,
        'count': count,
        'profile': profile,
        'retry_on_failure': retry_on_failure,
        'verify_recovery': verify_recovery,
        'timeline': timeline,
        'events': events_summary,
        'latest_output': latest_output,
        'summary': totals,
    })


@app.route('/api/simulations/eventlog', methods=['POST'])
def simulate_eventlog():
    """
    Simulates the Event ID 1100 (Event Log Shutdown) detection flow.
    This endpoint demonstrates event log service recovery behavior for UI walkthroughs.
    """
    data = request.get_json(silent=True) or {}
    try:
        count = int(data.get('count', 2))
    except (TypeError, ValueError):
        count = 2
    count = max(1, min(count, 5))

    now = datetime.utcnow()
    fix_script = 'Restart Event Log service and verify system integrity'
    description = 'Event Logging Failure'

    events = []
    timeline = [
        {
            'phase': 'detect',
            'title': 'Detect Event Log Service Shutdown',
            'status': 'completed',
            'detail': f'Detected {count} Event Log service shutdown incident(s).'
        }
    ]

    terminal_lines = [
        'Event Log Service Failure Detection',
        'Checking Event Log service status...',
        f'Simulation mode ON: Demonstrating service recovery.'
    ]

    for idx in range(count):
        shutdown_time = now - timedelta(minutes=(idx + 1) * 5)
        message = (
            f'The Event Logging service has shut down. '
            f'Service detected offline at {shutdown_time.strftime("%H:%M:%S")}. '
            f'System diagnostics initialized.'
        )
        message_preview = message[:100] + ('...' if len(message) > 100 else '')

        events.append({
            'event_id': 1100,
            'time_created': shutdown_time.isoformat() + 'Z',
            'source': 'EventLog',
            'description': description,
            'message': message,
            'message_preview': message_preview,
        })

        timeline.extend([
            {
                'phase': 'analyze',
                'title': f'Analyze Shutdown Event {idx + 1}',
                'status': 'completed',
                'detail': f'Event ID 1100 at {shutdown_time.isoformat()}Z classified as {description}.'
            },
            {
                'phase': 'remediate',
                'title': f'Remediate Service {idx + 1}',
                'status': 'simulated',
                'detail': f'Would execute: {fix_script}'
            }
        ])

        terminal_lines.extend([
            f'Event ID: 1100 at {shutdown_time.isoformat()}Z',
            f'Message: {message_preview}',
            f'Classified as: {description}',
            f'Executing Recovery: {fix_script} [SIMULATED]',
            '-------------------'
        ])

    terminal_lines.append('Event Log remediation and verification complete.')

    return jsonify({
        'scenario': 'Event ID 1100 - Event Log Shutdown',
        'event_id': 1100,
        'description': description,
        'fix_script': fix_script,
        'script_path': 'remediation_scripts/Error1100_EventLogShutdown.ps1',
        'simulation_mode': True,
        'generated_at': datetime.utcnow().isoformat() + 'Z',
        'events': events,
        'timeline': timeline,
        'terminal_output': '\n'.join(terminal_lines),
        'summary': {
            'events_detected': len(events),
            'events_analyzed': len(events),
            'remediations_simulated': len(events),
            'actual_remediations_executed': 0,
        }
    })


@app.route('/api/simulations/eventlog/auto-fix', methods=['POST'])
def simulate_eventlog_auto_fix():
    """
    End-to-end event log simulation:
      1) creates synthetic Event ID 1100 entries,
      2) passes them through rule matching,
      3) triggers auto-remediation via run_remediation.
    """
    data = request.get_json(silent=True) or {}
    profile = (data.get('profile') or 'degraded').strip().lower()
    if profile not in ('stable', 'degraded', 'critical'):
        profile = 'degraded'

    retry_on_failure = bool(data.get('retry_on_failure', True))
    verify_recovery = bool(data.get('verify_recovery', True))

    try:
        count = int(data.get('count', 1))
    except (TypeError, ValueError):
        count = 1
    count = max(1, min(count, 3))

    script_path = os.path.abspath(os.path.join(
        os.path.dirname(__file__), '..', 'remediation_scripts', 'Error1100_EventLogShutdown.ps1'
    ))

    if not os.path.exists(script_path):
        return jsonify({'error': f'remediation script not found at {script_path}'}), 404

    # Ensure a dedicated auto-remediation rule exists
    demo_rule = None
    for r in models.get_rules():
        if r[2] == 1100 and (r[3] or '').lower() == 'eventlog' and (r[5] or '') == script_path:
            demo_rule = r
            break

    if not demo_rule:
        rid = models.add_rule(
            name='AutoFix Demo - Event ID 1100 Event Log Shutdown',
            event_id=1100,
            source='EventLog',
            message_regex=None,
            remediation_script=script_path,
            script_type='file',
            auto_remediate=True,
            stop_processing=False,
            category='Event Logging Failure',
            severity='High',
            description='Auto-fix rule for event log shutdown simulation demos.',
            recommended_action='Run script-based recovery for simulated event log shutdown.',
            priority=25,
            cooldown_minutes=0,
        )
        demo_rule = models.get_rule(rid)

    demo_rule_id = demo_rule[0]

    now = datetime.utcnow()
    timeline = []
    events_summary = []
    totals = {
        'events_created': 0,
        'rules_matched': 0,
        'auto_remediations_run': 0,
        'auto_remediation_success': 0,
        'auto_remediation_failed': 0,
        'auto_remediation_suppressed': 0,
        'retries_performed': 0,
        'verification_failed': 0,
        'incident_resolved': 0,
        'incident_unresolved': 0,
        'mean_time_to_recover_seconds': 0,
    }
    mttr_samples = []

    timeline.append({
        'phase': 'prepare',
        'title': 'Prepare Event Log Simulation Environment',
        'status': 'completed',
        'detail': f'Using rule #{demo_rule_id} and script {script_path}. Profile: {profile.title()}.'
    })

    for idx in range(count):
        shutdown_time = now - timedelta(seconds=idx * 30)
        
        shutdown_message = (
            f'The Event Logging service has shut down unexpectedly. '
            f'Service Name: EventLog, Status: Stopped, Last known status: Running. '
            f'System health check initiated for {profile} profile.'
        )

        event_payload = {
            'event_id': 1100,
            'log_name': 'Simulation',
            'source': 'EventLog',
            'message': shutdown_message,
            'timestamp': shutdown_time.isoformat(),
            'category': 'Event Logging Failure',
            'severity': 'High',
            'description': 'Simulated event log service shutdown',
            'recommended_action': 'Restart the Event Log service and verify system integrity',
            'level': 'Error',
        }

        event_row_id = models.add_event(
            event_payload['event_id'],
            event_payload['log_name'],
            event_payload['source'],
            event_payload['message'],
            event_payload['timestamp'],
            event_payload['category'],
            event_payload['severity'],
            event_payload['description'],
            event_payload['recommended_action'],
            event_payload['level'],
        )
        totals['events_created'] += 1

        timeline.append({
            'phase': 'detect',
            'title': f'Detect Event Log Shutdown {idx + 1}',
            'status': 'completed',
            'detail': f'Event row #{event_row_id} created for event log service failure.'
        })

        severity_hint = 'Critical' if profile == 'critical' else ('High' if profile == 'degraded' else 'Medium')
        timeline.append({
            'phase': 'triage',
            'title': f'Triage Event {idx + 1}',
            'status': 'completed',
            'detail': f'Service shutdown severity: {severity_hint}; recovery attempt: {"Enabled" if retry_on_failure else "Disabled"}.'
        })

        matched_tuples = models.match_rules_for_event(event_payload)
        rule_matches = []
        remediation_results = []
        event_resolved = False
        event_start = datetime.utcnow()

        for r in matched_tuples:
            cooldown_active = r[15] if len(r) > 15 else False
            regex_captures = r[16] if len(r) > 16 else {}
            rule_info = {
                'rule_id': r[0],
                'rule_name': r[1],
                'auto_remediate': bool(r[6]),
                'cooldown_active': bool(cooldown_active),
            }
            rule_matches.append(rule_info)
            totals['rules_matched'] += 1

            if r[6] and not cooldown_active:
                max_attempts = 2 if retry_on_failure else 1
                last_status = 'failed'
                verification_ok = False
                for attempt in range(1, max_attempts + 1):
                    result = models.run_remediation(event_row_id, r[0], regex_captures=regex_captures)
                    totals['auto_remediations_run'] += 1

                    if result.get('status') == 'success':
                        totals['auto_remediation_success'] += 1
                    else:
                        totals['auto_remediation_failed'] += 1

                    # Simulate post-remediation verification
                    if verify_recovery and result.get('status') == 'success':
                        fail_chance = 0.08 if profile == 'stable' else (0.22 if profile == 'degraded' else 0.50)
                        if profile == 'critical' and attempt == 1:
                            fail_chance = max(fail_chance, 0.60)
                        verification_ok = random.random() > fail_chance
                    else:
                        verification_ok = (result.get('status') == 'success')

                    remediation_results.append({
                        'attempt': attempt,
                        'rule_id': r[0],
                        'rule_name': r[1],
                        'status': result.get('status'),
                        'verification_passed': verification_ok,
                        'output': result.get('output'),
                    })

                    last_status = result.get('status', 'failed')
                    timeline.append({
                        'phase': 'remediate',
                        'title': f'Auto-Remediate Event {idx + 1} (Attempt {attempt})',
                        'status': last_status,
                        'detail': f"Rule #{r[0]} execution status: {last_status}"
                    })

                    if verify_recovery:
                        verify_status = 'completed' if verification_ok else 'warning'
                        verify_detail = 'Service recovery verified: EventLog service online and responding.' if verification_ok else 'Service recovery failed: EventLog service still offline.'
                        timeline.append({
                            'phase': 'verify',
                            'title': f'Verify Recovery Event {idx + 1} (Attempt {attempt})',
                            'status': verify_status,
                            'detail': verify_detail
                        })

                    if last_status == 'success' and verification_ok:
                        event_resolved = True
                        break

                    if attempt < max_attempts:
                        totals['retries_performed'] += 1
                        timeline.append({
                            'phase': 'retry',
                            'title': f'Retry Remediation Event {idx + 1}',
                            'status': 'warning',
                            'detail': 'Automatic retry scheduled due to failed verification or script failure.'
                        })

                if verify_recovery and not event_resolved:
                    totals['verification_failed'] += 1
            elif r[6] and cooldown_active:
                models.record_remediation(
                    event_row_id,
                    r[0],
                    'suppressed',
                    'Auto-remediation suppressed - rule cooldown active'
                )
                totals['auto_remediation_suppressed'] += 1
                timeline.append({
                    'phase': 'remediate',
                    'title': f'Auto-Remediation Suppressed for Event {idx + 1}',
                    'status': 'suppressed',
                    'detail': f'Rule #{r[0]} suppressed due to cooldown.'
                })

        if event_resolved:
            totals['incident_resolved'] += 1
            mttr_samples.append((datetime.utcnow() - event_start).total_seconds())
            timeline.append({
                'phase': 'close',
                'title': f'Close Incident Event {idx + 1}',
                'status': 'completed',
                'detail': 'Event log service recovered and logging resumed.'
            })
        else:
            totals['incident_unresolved'] += 1
            timeline.append({
                'phase': 'escalate',
                'title': f'Escalate Incident Event {idx + 1}',
                'status': 'failed',
                'detail': 'Event log service recovery failed. Manual escalation required.'
            })

        events_summary.append({
            'event_row_id': event_row_id,
            'timestamp': event_payload['timestamp'],
            'message': shutdown_message,
            'matches': rule_matches,
            'remediations': remediation_results,
            'resolved': event_resolved,
        })

    latest_output = ''
    if events_summary:
        rems = events_summary[-1].get('remediations') or []
        if rems:
            latest_output = rems[-1].get('output') or ''

    if mttr_samples:
        totals['mean_time_to_recover_seconds'] = round(sum(mttr_samples) / len(mttr_samples), 2)

    return jsonify({
        'scenario': 'Event Log Lab - Event ID 1100 Auto-Fix',
        'simulation_mode': True,
        'event_id': 1100,
        'fix_script': 'Restart Event Log service and verify system integrity',
        'script_path': script_path,
        'rule_id': demo_rule_id,
        'count': count,
        'profile': profile,
        'retry_on_failure': retry_on_failure,
        'verify_recovery': verify_recovery,
        'timeline': timeline,
        'events': events_summary,
        'latest_output': latest_output,
        'summary': totals,
    })


# ─────────────────────────────────────────────────────────────────────────────
#  Server entry point
# ─────────────────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    host  = os.getenv('FLASK_HOST', '0.0.0.0')
    port  = int(os.getenv('FLASK_PORT', '5000'))
    debug = os.getenv('FLASK_DEBUG', 'True').lower() in ('true', '1', 'yes')

    print(f"Starting Flask server on {host}:{port}")
    print(f"Debug mode: {debug}")
    print(f"Access the dashboard at: http://localhost:{port}")

    app.run(host=host, port=port, debug=debug)
