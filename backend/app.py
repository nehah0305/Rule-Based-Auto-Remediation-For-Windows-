from flask import Flask, request, jsonify, render_template
import subprocess
import os
import json
import re
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
