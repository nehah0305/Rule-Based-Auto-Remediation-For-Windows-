from flask import Flask, request, jsonify, render_template
import subprocess
import os
import json
import re

from db_init import init_db
import models

app = Flask(__name__)

# Ensure DB exists
init_db()


@app.route('/')
def index():
    return render_template('index.html')


@app.route('/api/events', methods=['GET', 'POST'])
def events():
    if request.method == 'GET':
        rows = models.get_events(limit=200)
        events = [dict(id=r[0], event_id=r[1], log_name=r[2], source=r[3], message=r[4],
                      timestamp=r[5], category=r[6], severity=r[7], description=r[8],
                      recommended_action=r[9]) for r in rows]
        return jsonify(events)

    data = request.get_json(force=True)
    # expected keys: event_id, log_name, source, message, timestamp (optional)
    # The add_event function will automatically enrich with metadata from JSON
    event_row_id = models.add_event(
        data.get('event_id'),
        data.get('log_name'),
        data.get('source'),
        data.get('message'),
        data.get('timestamp'),
        data.get('category'),
        data.get('severity'),
        data.get('description'),
        data.get('recommended_action')
    )

    matched = models.match_rules_for_event(data)
    matched_info = []

    for r in matched:
        rid = r[0]
        remediation_script = r[5]
        matched_info.append({'rule_id': rid, 'rule_name': r[1], 'remediation': remediation_script})
        # Auto-run remediation if configured
        if r[6]:
            # Attempt to run PowerShell remediation script if present
            if remediation_script and os.path.exists(remediation_script):
                try:
                    proc = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', remediation_script], capture_output=True, text=True, timeout=60)
                    status = 'success' if proc.returncode == 0 else 'failed'
                    models.record_remediation(event_row_id, rid, status, proc.stdout + '\n' + proc.stderr)
                except Exception as e:
                    models.record_remediation(event_row_id, rid, 'error', str(e))
            else:
                models.record_remediation(event_row_id, rid, 'skipped', 'no script or missing file')

    return jsonify({'status': 'ok', 'event_id': event_row_id, 'matched': matched_info})


@app.route('/api/rules', methods=['GET', 'POST'])
def rules():
    if request.method == 'GET':
        rows = models.get_rules()
        rules = [dict(id=r[0], name=r[1], event_id=r[2], source=r[3], message_regex=r[4],
                     remediation_script=r[5], auto_remediate=bool(r[6]), category=r[7],
                     severity=r[8], description=r[9], recommended_action=r[10]) for r in rows]
        return jsonify(rules)

    data = request.get_json(force=True)
    rid = models.add_rule(
        data.get('name'),
        data.get('event_id'),
        data.get('source'),
        data.get('message_regex'),
        data.get('remediation_script'),
        data.get('auto_remediate', False),
        data.get('category'),
        data.get('severity'),
        data.get('description'),
        data.get('recommended_action')
    )
    return jsonify({'status': 'created', 'rule_id': rid}), 201


@app.route('/api/rules/<int:rule_id>', methods=['GET', 'PUT', 'DELETE'])
def rule_detail(rule_id):
    if request.method == 'GET':
        r = models.get_rule(rule_id)
        if not r:
            return jsonify({'error': 'not found'}), 404
        rule = dict(id=r[0], name=r[1], event_id=r[2], source=r[3], message_regex=r[4],
                   remediation_script=r[5], auto_remediate=bool(r[6]), category=r[7],
                   severity=r[8], description=r[9], recommended_action=r[10])
        return jsonify(rule)

    if request.method == 'PUT':
        data = request.get_json(force=True)
        ok = models.update_rule(
            rule_id,
            data.get('name'),
            data.get('event_id'),
            data.get('source'),
            data.get('message_regex'),
            data.get('remediation_script'),
            data.get('auto_remediate'),
            data.get('category'),
            data.get('severity'),
            data.get('description'),
            data.get('recommended_action')
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


@app.route('/api/history', methods=['GET'])
def history():
    rows = models.get_history(limit=500)
    hist = []
    for h in rows:
        hist.append(dict(id=h[0], event_row_id=h[1], rule_id=h[2], status=h[3], output=h[4], timestamp=h[5], event_id=h[6], event_source=h[7], rule_name=h[8], event_timestamp=h[9]))
    return jsonify(hist)


@app.route('/api/events/<int:event_id>/matches', methods=['GET'])
def event_matches(event_id):
    ev = models.get_event(event_id)
    if not ev:
        return jsonify({'error': 'event not found'}), 404
    event_dict = {'event_id': ev[1], 'log_name': ev[2], 'source': ev[3], 'message': ev[4],
                  'timestamp': ev[5], 'category': ev[6], 'severity': ev[7],
                  'description': ev[8], 'recommended_action': ev[9]}
    matched = models.match_rules_for_event(event_dict)
    matched_info = []
    for r in matched:
        matched_info.append(dict(id=r[0], name=r[1], event_id=r[2], source=r[3],
                                message_regex=r[4], remediation_script=r[5], auto_remediate=bool(r[6]),
                                category=r[7], severity=r[8], description=r[9],
                                recommended_action=r[10]))
    return jsonify(matched_info)


@app.route('/api/requests', methods=['GET', 'POST'])
def requests_list():
    if request.method == 'GET':
        status = request.args.get('status')
        rows = models.get_requests(status)
        reqs = []
        for r in rows:
            reqs.append(dict(id=r[0], event_row_id=r[1], rule_id=r[2], status=r[3], requested_by=r[4], requested_at=r[5], processed_by=r[6], processed_at=r[7], decision_note=r[8], event_id=r[9], event_source=r[10], rule_name=r[11]))
        return jsonify(reqs)

    data = request.get_json(force=True)
    if not data.get('event_row_id') or not data.get('rule_id'):
        return jsonify({'error': 'event_row_id and rule_id required'}), 400
    rid = models.create_remediation_request(data.get('event_row_id'), data.get('rule_id'), data.get('requested_by', 'web-ui'))
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


@app.route('/api/event-definitions', methods=['GET'])
def event_definitions():
    """Get all event definitions from the JSON file."""
    definitions = models.get_all_event_definitions()
    return jsonify(definitions)


@app.route('/api/event-definitions/<int:event_id>', methods=['GET'])
def event_definition_detail(event_id):
    """Get a specific event definition by event_id."""
    source = request.args.get('source')
    defn = models.get_event_definition(event_id, source)
    if not defn:
        return jsonify({'error': 'event definition not found'}), 404
    return jsonify(defn)


@app.route('/api/populate-rules', methods=['POST'])
def populate_rules():
    """Populate rules from the JSON event definitions file."""
    data = request.get_json(force=True) if request.is_json else {}
    overwrite = data.get('overwrite', False)

    try:
        count = models.populate_rules_from_json(overwrite=overwrite)
        return jsonify({'status': 'success', 'rules_created': count})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
