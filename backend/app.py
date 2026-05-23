from flask import Flask, request, jsonify, render_template, send_from_directory, send_file
import subprocess
import os
import json
import re
import random
import logging
import logging.handlers
from datetime import datetime, timedelta
from dotenv import load_dotenv
import time

from db_init import init_db
import models
import event_log_monitor
import task_scheduler

# ─────────────────────────────────────────────────────────────────────────────
#  Input Validation & Security Configuration
# ─────────────────────────────────────────────────────────────────────────────

# CORS: Explicit whitelist of allowed origins (prevents CORS wildcard vulnerability)
# For development, allow all localhost origins. For production, restrict to specific URLs.
def is_allowed_origin(origin):
    """Check if origin is allowed (localhost for dev, whitelist for prod)."""
    if not origin:
        return True  # Allow same-origin requests
    
    # Allow localhost and 127.0.0.1 with any port for development
    if origin.startswith('http://localhost:') or origin.startswith('http://127.0.0.1:'):
        return True
    if origin.startswith('https://localhost:') or origin.startswith('https://127.0.0.1:'):
        return True
    
    # Production whitelist
    ALLOWED_ORIGINS = [
        'http://localhost:3000',
        'http://localhost:5000',
        'http://localhost:8080',
        'http://127.0.0.1:3000',
        'http://127.0.0.1:5000',
        'http://127.0.0.1:8080',
    ]
    
    return origin in ALLOWED_ORIGINS

def validate_input(data, schema):
    """Validate input data against schema."""
    if not isinstance(data, dict):
        raise ValueError('Input must be a JSON object')
    for field, rules in schema.items():
        value = data.get(field)
        if rules.get('required', False) and value is None:
            raise ValueError(f'Field {field} is required')
        if value is not None:
            max_len = rules.get('max_length')
            if max_len and isinstance(value, str) and len(value) > max_len:
                raise ValueError(f'Field {field} exceeds max length {max_len}')
            field_type = rules.get('type')
            if field_type and not isinstance(value, field_type):
                raise ValueError(f'Field {field} must be {field_type.__name__}')
    return True

# Load environment variables from .env file
env_path = os.path.join(os.path.dirname(__file__), '.env')
if not os.path.exists(env_path):
    env_path = os.path.join(os.path.dirname(__file__), '..', '.env')
load_dotenv(env_path)

# ── Unified log file shared with cli_process_event.py and Task Scheduler ─────
# Both the Flask server and the background CLI script write to this single file
# so the operator always has a complete, chronological audit trail.
_DATA_DIR = os.path.join(os.path.dirname(__file__), 'data')
os.makedirs(_DATA_DIR, exist_ok=True)
_UNIFIED_LOG = os.path.join(_DATA_DIR, 'remediation_system.log')

_file_handler = logging.handlers.RotatingFileHandler(
    _UNIFIED_LOG, maxBytes=5 * 1024 * 1024, backupCount=3, encoding='utf-8'
)
_file_handler.setFormatter(
    logging.Formatter('%(asctime)s [%(levelname)s] [FLASK] %(message)s')
)
logging.getLogger().addHandler(_file_handler)
logging.getLogger().setLevel(logging.INFO)
_log = logging.getLogger('app')
_log.info('Flask server starting up — unified log initialised.')

# Simple cache for filtered events to improve response time
_filtered_events_cache = {'data': None, 'timestamp': 0, 'ttl': 15}

# PERFORMANCE FIX #3: Cache for intelligence summary (30-second TTL)
_intelligence_summary_cache = {'data': None, 'timestamp': 0, 'ttl': 30}

# PERFORMANCE FIX #5: Cache event count to avoid expensive COUNT queries
_event_count_cache = {'count': None, 'timestamp': 0, 'ttl': 60}

app = Flask(__name__)

# CORS: Whitelist-based security (prevents origin reflection vulnerability)
@app.after_request
def add_cors_headers(response):
    """Add CORS headers only for allowed origins (SECURITY FIX)."""
    origin = request.headers.get('Origin', '')
    
    # SECURITY FIX: Only allow whitelisted origins (prevents CORS vulnerability)
    if is_allowed_origin(origin):
        if origin:
            response.headers['Access-Control-Allow-Origin'] = origin
        response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
        response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization, Accept'
        response.headers['Access-Control-Allow-Credentials'] = 'true'
        response.headers['Access-Control-Max-Age'] = '3600'
    
    return response

@app.route('/api/<path:path>', methods=['OPTIONS'])
def options_handler(path):
    """Handle CORS preflight for all /api/* routes (whitelist-based)."""
    response = jsonify({})
    origin = request.headers.get('Origin', '')
    
    # Only respond to allowed origins
    if is_allowed_origin(origin):
        if origin:
            response.headers['Access-Control-Allow-Origin'] = origin
        response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
        response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization, Accept'
        response.headers['Access-Control-Max-Age'] = '3600'
    
    return response, 200

# Ensure DB exists and migrations run
init_db()

# ── Event Monitor: polling vs. Task Scheduler mode ────────────────────────────
# Set USE_TASK_SCHEDULER=true in your .env (or system environment) when the
# Setup_EventTriggers.ps1 script has been run. In that mode Flask becomes a
# pure API server — Task Scheduler + cli_process_event.py handle detection.
_use_task_scheduler = os.getenv('USE_TASK_SCHEDULER', 'false').lower() in ('true', '1', 'yes')

if _use_task_scheduler:
    _log.info(
        'USE_TASK_SCHEDULER=true — background polling thread is DISABLED. '
        'Windows Task Scheduler is responsible for event detection.'
    )
    print('[INFO] Task Scheduler mode active — polling thread disabled.')
else:
    _log.info('USE_TASK_SCHEDULER not set — starting background polling thread.')
    try:
        event_log_monitor.start_monitor()
        print('[INFO] Event log monitoring thread started successfully.')
    except Exception as e:
        _log.warning(f'Failed to start event log monitor: {e}. Continuing without polling.')
        print(f'[WARNING] Event log monitor not available: {e}')


# â”€â”€â”€ Flutter Web Frontend â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# Serve the Flutter build output. If build/web doesn't exist yet (dev mode),
# fall back to the old index.html template.

import os as _os
_FLUTTER_BUILD = _os.path.join(_os.path.dirname(__file__), '..', 'frontend', 'build', 'web')
_FLUTTER_BUILD = _os.path.abspath(_FLUTTER_BUILD)

@app.route('/')
def index():
    if _os.path.isdir(_FLUTTER_BUILD):
        return send_from_directory(_FLUTTER_BUILD, 'index.html')
    return render_template('index.html')

@app.route('/<path:filename>')
def flutter_static(filename):
    """Serve Flutter's JS, fonts, assets, and canvaskit files."""
    if _os.path.isdir(_FLUTTER_BUILD):
        target = _os.path.join(_FLUTTER_BUILD, filename)
        if _os.path.isfile(target):
            return send_from_directory(_FLUTTER_BUILD, filename)
    return render_template('index.html'), 404



# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
#  Events
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

@app.route('/api/events', methods=['GET', 'POST'])
def events():
    if request.method == 'GET':
        # PERFORMANCE FIX #2: Add pagination support
        try:
            limit = min(int(request.args.get('limit', 50)), 100)  # Cap at 100 items
            offset = max(int(request.args.get('offset', 0)), 0)
        except (ValueError, TypeError):
            limit = 50
            offset = 0
        
        rows = models.get_events_paginated(offset=offset, limit=limit)
        
        # PERFORMANCE FIX #5: Cache count query (expensive on 166k+ events)
        global _event_count_cache
        now = time.time()
        if _event_count_cache['count'] is None or (now - _event_count_cache['timestamp']) > _event_count_cache['ttl']:
            _event_count_cache['count'] = models.count_events()
            _event_count_cache['timestamp'] = now
        total = _event_count_cache['count']
        
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
                source_type=r[14] if len(r) > 14 else 'api',
                needs_manual_review=bool(r[15]) if len(r) > 15 else False,
                manual_review_reason=r[16] if len(r) > 16 else None,
                dismissed_review=bool(r[17]) if len(r) > 17 else False,
            ))
        
        return jsonify({
            'events': result,
            'offset': offset,
            'limit': limit,
            'total': total,
            'has_more': (offset + limit) < total
        })

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

    # Match rules â€” now returns list of tuples with cooldown_active flag at [-1]
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
                                      'Auto-remediation suppressed â€” rule cooldown active')

    return jsonify({'status': 'ok', 'event_id': event_row_id, 'matched': matched_info})


@app.route('/api/events/manual-review', methods=['GET'])
def events_manual_review():
    """Return events that need manual intervention (no rule matched).
    
    PERFORMANCE FIX #2: Supports pagination to prevent loading all events.
    Default limit: 20 (can be overridden with ?limit=X&offset=Y)
    """
    try:
        limit = min(int(request.args.get('limit', 20)), 100)  # Default 20, cap at 100
        offset = max(int(request.args.get('offset', 0)), 0)
    except (ValueError, TypeError):
        limit = 20
        offset = 0
    
    rows = models.get_events_needing_review(limit=limit + offset)  # Get enough for pagination
    rows = rows[offset:offset + limit]  # Apply offset
    
    result = []
    for r in rows:
        result.append(dict(
            id=r[0], event_id=r[1], log_name=r[2], source=r[3],
            message=r[4], timestamp=r[5], category=r[6], severity=r[7],
            description=r[8], recommended_action=r[9],
            dedup_count=r[10], last_seen=r[11],
            confidence_score=r[12], correlation_id=r[13],
            source_type=r[14], manual_review_reason=r[15],
        ))
    return jsonify(result)


@app.route('/api/events/<int:event_row_id>/dismiss-review', methods=['POST'])
def dismiss_event_review(event_row_id):
    """Mark an event's manual review as acknowledged by the operator."""
    models.dismiss_manual_review(event_row_id)
    return jsonify({'status': 'dismissed', 'event_row_id': event_row_id})


@app.route('/api/monitor/status', methods=['GET'])
def monitor_status():
    """Return the current status of the Windows Event Log monitor thread."""
    try:
        status = event_log_monitor.get_status()
        return jsonify(status)
    except Exception as e:
        _log.error(f'Error getting monitor status: {str(e)}')
        return jsonify({
            'running': False,
            'last_poll': None,
            'events_ingested': 0,
            'error': str(e)
        }), 200  # Return 200 with error details instead of 404


@app.route('/api/health', methods=['GET'])
def health_check():
    """
    Basic health check endpoint - no dependencies.
    Returns 200 if Flask backend is running.
    """
    return jsonify({'status': 'ok', 'service': 'Flask Backend'}), 200


@app.route('/api/monitor/trigger', methods=['POST'])
def monitor_trigger():
    """Manually force a pull of the Windows Event Logs."""
    count = event_log_monitor.trigger_poll()
    return jsonify({'status': 'ok', 'events_ingested': count})


@app.route('/api/monitor/log', methods=['GET'])
def monitor_log():
    """
    Return the last N lines of the unified remediation_system.log file.
    Both Flask and the Task Scheduler CLI script write to this file, giving
    the Flutter dashboard a single chronological audit trail.
    """
    try:
        lines = int(request.args.get('lines', 200))
        lines = max(10, min(lines, 2000))
    except (ValueError, TypeError):
        lines = 200

    log_path = os.path.join(os.path.dirname(__file__), 'data', 'remediation_system.log')

    if not os.path.exists(log_path):
        return jsonify({'content': '(log file does not exist yet — run a poll or simulate an event first.)', 'lines': 0})

    try:
        with open(log_path, 'r', encoding='utf-8', errors='replace') as f:
            all_lines = f.readlines()
        tail = all_lines[-lines:]
        return jsonify({'content': ''.join(tail), 'lines': len(tail), 'total_lines': len(all_lines)})
    except Exception as e:
        return jsonify({'error': str(e)}), 500


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


# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
#  Rules
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
        active=int(r[15] if len(r) > 15 else 1),  # 1=enabled, 0=disabled
    )


@app.route('/api/rules', methods=['GET', 'POST'])
def rules():
    if request.method == 'GET':
        rows = models.get_rules()
        return jsonify([_rule_to_dict(r) for r in rows])

    try:
        data = request.get_json(force=True)
        
        # INPUT VALIDATION: Validate rule creation schema (PRIORITY 2 FIX)
        rule_schema = {
            'name': {'required': True, 'type': str, 'max_length': 256},
            'event_id': {'type': int},
            'source': {'type': str, 'max_length': 512},
            'message_regex': {'type': str, 'max_length': 1000},
            'remediation_script': {'type': str, 'max_length': 1024},
            'script_type': {'type': str, 'max_length': 50},
            'category': {'type': str, 'max_length': 256},
            'severity': {'type': str, 'max_length': 128},
            'description': {'type': str, 'max_length': 2048},
        }
        validate_input(data, rule_schema)
        
        # Validate regex if provided (ReDoS prevention)
        if data.get('message_regex'):
            try:
                re.compile(data['message_regex'])
            except re.error as e:
                return jsonify({'error': f'Invalid regex pattern: {str(e)}'}), 400
        
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
    except ValueError as e:
        return jsonify({'error': f'Validation error: {str(e)}'}), 400
    except Exception as e:
        _log.error(f'Error creating rule: {e}')
        return jsonify({'error': 'Failed to create rule'}), 500


@app.route('/api/rules/<int:rule_id>', methods=['GET', 'PUT', 'DELETE'])
def rule_detail(rule_id):
    if request.method == 'GET':
        r = models.get_rule(rule_id)
        if not r:
            return jsonify({'error': 'not found'}), 404
        return jsonify(_rule_to_dict(r))

    if request.method == 'PUT':
        try:
            data = request.get_json(force=True)
            
            # INPUT VALIDATION (PRIORITY 2 FIX)
            rule_schema = {
                'name': {'required': True, 'type': str, 'max_length': 256},
                'event_id': {'type': int},
                'source': {'type': str, 'max_length': 512},
                'message_regex': {'type': str, 'max_length': 1000},
                'remediation_script': {'type': str, 'max_length': 1024},
                'script_type': {'type': str, 'max_length': 50},
                'category': {'type': str, 'max_length': 256},
                'severity': {'type': str, 'max_length': 128},
                'description': {'type': str, 'max_length': 2048},
            }
            validate_input(data, rule_schema)
            
            # Validate regex if provided (ReDoS prevention)
            if data.get('message_regex'):
                try:
                    re.compile(data['message_regex'])
                except re.error as e:
                    return jsonify({'error': f'Invalid regex pattern: {str(e)}'}), 400
            
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
        except ValueError as e:
            return jsonify({'error': f'Validation error: {str(e)}'}), 400
        except Exception as e:
            _log.error(f'Error updating rule: {e}')
            return jsonify({'error': 'Failed to update rule'}), 500

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


@app.route('/api/rules/<int:rule_id>/toggle', methods=['POST'])
def toggle_rule(rule_id):
    """Enable or disable a rule."""
    data   = request.get_json(force=True) or {}
    active = bool(data.get('active', True))
    ok     = models.toggle_rule_active(rule_id, active)
    if not ok:
        return jsonify({'error': 'rule not found'}), 404
    return jsonify({'id': rule_id, 'active': active})


@app.route('/api/rules/stats', methods=['GET'])
def rules_stats():
    """Return hit counts and last hit times for all rules."""
    return jsonify(models.get_rule_hit_counts())


@app.route('/api/tasks/status', methods=['GET'])
def tasks_status():
    """Query real Windows Task Scheduler tasks via schtasks."""
    import subprocess, json as _json
    task_names = [
        'AutoRemediate_AppCrash_1000',
        'AutoRemediate_AppHang_1001',
        'AutoRemediate_DotNetCrash_1026',
        'AutoRemediate_ServiceFail_7034',
        'AutoRemediate_ServiceFail_7031',
        'AutoRemediate_ServiceStart_7000',
        'AutoRemediate_DiskError_11',
        'AutoRemediate_NTFSCorruption_55',
    ]
    results = []
    for name in task_names:
        try:
            out = subprocess.run(
                ['schtasks', '/query', '/tn', name, '/fo', 'LIST', '/v'],
                capture_output=True, text=True, timeout=8
            )
            if out.returncode != 0:
                results.append({'name': name, 'installed': False})
                continue
            info = {'name': name, 'installed': True}
            for line in out.stdout.splitlines():
                if 'Status:' in line:
                    info['status'] = line.split(':', 1)[-1].strip()
                elif 'Last Run Time:' in line:
                    info['last_run'] = line.split(':', 1)[-1].strip()
                elif 'Next Run Time:' in line:
                    info['next_run'] = line.split(':', 1)[-1].strip()
                elif 'Last Result:' in line:
                    info['last_result'] = line.split(':', 1)[-1].strip()
                elif 'Scheduled Task State:' in line:
                    info['enabled'] = 'Enabled' in line
            results.append(info)
        except Exception as e:
            results.append({'name': name, 'installed': False, 'error': str(e)})
    return jsonify(results)


# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
#  History
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

@app.route('/api/history', methods=['GET'])
def history():
    try:
        limit  = min(max(int(request.args.get('limit',  50)),  1), 200)
        offset = max(int(request.args.get('offset', 0)), 0)
        status = request.args.get('status', None)
        search = request.args.get('search', None)
        sort_col = request.args.get('sort', 'id')
        sort_dir = request.args.get('dir', 'DESC')

        rows  = models.get_history(limit=limit, offset=offset, status=status,
                                   search=search, sort_col=sort_col, sort_dir=sort_dir)
        total = models.get_history_count(status=status, search=search)

        hist = []
        for h in rows:
            hist.append(dict(
                id=h[0], event_row_id=h[1], rule_id=h[2],
                status=h[3], output=h[4], timestamp=h[5],
                event_id=h[6], event_source=h[7],
                rule_name=h[8], event_timestamp=h[9],
            ))
        return jsonify({'items': hist, 'total': total, 'has_more': offset + limit < total})
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/history/export', methods=['GET'])
def history_export():
    """Export full remediation history as CSV."""
    try:
        fmt    = request.args.get('format', 'csv')
        status = request.args.get('status', None)
        search = request.args.get('search', None)
        rows   = models.get_history(limit=10000, offset=0, status=status, search=search)
        if fmt == 'csv':
            import io, csv as csv_mod
            buf = io.StringIO()
            writer = csv_mod.writer(buf)
            writer.writerow(['ID', 'Event ID', 'Rule', 'Status', 'Output', 'Remediation Time', 'Event Time', 'Source'])
            for h in rows:
                writer.writerow([h[0], h[6], h[8], h[3],
                                 (h[4] or '')[:500], h[5], h[9], h[7]])
            from flask import Response
            return Response(
                buf.getvalue(),
                mimetype='text/csv',
                headers={'Content-Disposition': 'attachment; filename=remediation_history.csv'}
            )
        return jsonify([dict(id=h[0], event_id=h[6], rule_name=h[8], status=h[3],
                             output=h[4], timestamp=h[5]) for h in rows])
    except Exception as e:
        return jsonify({'error': str(e)}), 500




@app.route('/api/events/<int:event_row_id>/history', methods=['GET'])
def event_history(event_row_id):
    try:
        rows = models.get_event_history(event_row_id)
        hist = []
        for h in rows:
            def safe_int(val):
                if val is None: return None
                if isinstance(val, int): return val
                try: return int(val)
                except (ValueError, TypeError): return None
            def safe_str(val):
                return str(val) if val else None
                
            hist.append(dict(
                id=safe_int(h[0]),
                event_row_id=safe_int(h[1]),
                rule_id=safe_int(h[2]),
                status=safe_str(h[3]),
                output=safe_str(h[4]),
                timestamp=safe_str(h[5]),
                event_id=safe_int(h[6]),
                event_source=safe_str(h[7]),
                rule_name=safe_str(h[8]),
                event_timestamp=safe_str(h[9]),
            ))
        return jsonify(hist)
    except Exception as e:
        _log.error(f'Event history error: {e}')
        return jsonify({'error': str(e)}), 500


# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
#  Approvals / Requests
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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


# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
#  Event definitions & filtered events (CSV)
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
    """Get filtered events with caching to improve response time."""
    global _filtered_events_cache
    now = time.time()
    
    # Return cached data if still valid
    if (_filtered_events_cache['data'] is not None and 
        (now - _filtered_events_cache['timestamp']) < _filtered_events_cache['ttl']):
        return jsonify(_filtered_events_cache['data'])
    
    try:
        rows = models.read_filtered_events_csv()
        _filtered_events_cache['data'] = rows
        _filtered_events_cache['timestamp'] = now
        return jsonify(rows)
    except Exception as e:
        import traceback
        traceback.print_exc()
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


# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
#  Alert Intelligence summary
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

@app.route('/api/intelligence/summary', methods=['GET'])
def intelligence_summary():
    """
    Returns aggregated Alert Intelligence metrics for the Dashboard card.
    PERFORMANCE FIX #3: Caches results for 30 seconds to reduce query load.
    PERFORMANCE FIX #5: Uses cached event count to avoid expensive queries.
    """
    try:
        global _intelligence_summary_cache
        now = time.time()
        
        # Return cached result if available and not expired
        if (_intelligence_summary_cache['data'] is not None and 
            (now - _intelligence_summary_cache['timestamp']) < _intelligence_summary_cache['ttl']):
            return jsonify(_intelligence_summary_cache['data'])
        
        # Fetch fresh data (using cached count internally)
        summary = models.get_intelligence_summary()
        
        # Update cache
        _intelligence_summary_cache['data'] = summary
        _intelligence_summary_cache['timestamp'] = now
        
        return jsonify(summary)
    except Exception as e:
        _log.error(f'Intelligence summary error: {e}')
        return jsonify({'error': str(e)}), 500


@app.route('/api/dashboard-stats', methods=['GET'])
def dashboard_stats():
    """Returns real aggregated stats for the dashboard."""
    try:
        stats = models.get_dashboard_stats()
        return jsonify(stats)
    except Exception as e:
        _log.error(f'Dashboard stats error: {e}')
        return jsonify({'error': str(e)}), 500


# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
#  Simulations
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

@app.route('/api/simulations/preferences/<sim_type>', methods=['GET'])
def get_simulation_preference(sim_type):
    """Get stored preference for a simulation type."""
    pref = models.get_simulation_preference(sim_type)
    if pref:
        return jsonify({'has_preference': True, 'preference': pref})
    return jsonify({'has_preference': False})


@app.route('/api/simulations/preferences/<sim_type>', methods=['POST'])
def set_simulation_preference(sim_type):
    """Set/update preference for a simulation type."""
    data = request.get_json(force=True)
    run_script = data.get('run_script', False)
    auto_remediate = data.get('auto_remediate', False)
    
    models.set_simulation_preference(sim_type, run_script, auto_remediate)
    return jsonify({'status': 'ok', 'simulation_type': sim_type})


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


@app.route('/api/simulations/auditevents', methods=['POST'])
def simulate_auditevents():
    """
    Simulates the Event ID 1101 (Audit Events Dropped) detection flow.
    This endpoint demonstrates audit log recovery behavior for UI walkthroughs.
    """
    data = request.get_json(silent=True) or {}
    try:
        count = int(data.get('count', 2))
    except (TypeError, ValueError):
        count = 2
    count = max(1, min(count, 5))

    now = datetime.utcnow()
    fix_script = 'Increase audit log size and check system resources'
    description = 'Audit Events Dropped'

    events = []
    timeline = [
        {
            'phase': 'detect',
            'title': 'Detect Dropped Audit Events',
            'status': 'completed',
            'detail': f'Detected {count} audit event drop incident(s).'
        }
    ]

    terminal_lines = [
        'Audit Events Dropped Detection',
        'Checking audit log capacity...',
        f'Simulation mode ON: Demonstrating audit log recovery.'
    ]

    for idx in range(count):
        drop_time = now - timedelta(minutes=(idx + 1) * 6)
        message = (
            f'Audit events have been dropped by the transport. '
            f'Event log capacity exceeded at {drop_time.strftime("%H:%M:%S")}. '
            f'Audit system detection triggered.'
        )
        message_preview = message[:100] + ('...' if len(message) > 100 else '')

        events.append({
            'event_id': 1101,
            'time_created': drop_time.isoformat() + 'Z',
            'source': 'EventLog',
            'description': description,
            'message': message,
            'message_preview': message_preview,
        })

        timeline.extend([
            {
                'phase': 'analyze',
                'title': f'Analyze Audit Drop Event {idx + 1}',
                'status': 'completed',
                'detail': f'Event ID 1101 at {drop_time.isoformat()}Z classified as {description}.'
            },
            {
                'phase': 'remediate',
                'title': f'Remediate Audit Log {idx + 1}',
                'status': 'simulated',
                'detail': f'Would execute: {fix_script}'
            }
        ])

        terminal_lines.extend([
            f'Event ID: 1101 at {drop_time.isoformat()}Z',
            f'Message: {message_preview}',
            f'Classified as: {description}',
            f'Executing Recovery: {fix_script} [SIMULATED]',
            '-------------------'
        ])

    terminal_lines.append('Audit log remediation and verification complete.')

    return jsonify({
        'scenario': 'Event ID 1101 - Audit Events Dropped',
        'event_id': 1101,
        'description': description,
        'fix_script': fix_script,
        'script_path': 'remediation_scripts/Error1101_AuditEventsDropped.ps1',
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


@app.route('/api/simulations/auditevents/auto-fix', methods=['POST'])
def simulate_auditevents_auto_fix():
    """
    End-to-end audit events simulation:
      1) creates synthetic Event ID 1101 entries,
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
        os.path.dirname(__file__), '..', 'remediation_scripts', 'Error1101_AuditEventsDropped.ps1'
    ))

    if not os.path.exists(script_path):
        return jsonify({'error': f'remediation script not found at {script_path}'}), 404

    # Ensure a dedicated auto-remediation rule exists
    demo_rule = None
    for r in models.get_rules():
        if r[2] == 1101 and (r[3] or '').lower() == 'eventlog' and (r[5] or '') == script_path:
            demo_rule = r
            break

    if not demo_rule:
        rid = models.add_rule(
            name='AutoFix Demo - Event ID 1101 Audit Events Dropped',
            event_id=1101,
            source='EventLog',
            message_regex=None,
            remediation_script=script_path,
            script_type='file',
            auto_remediate=True,
            stop_processing=False,
            category='Audit Events Dropped',
            severity='High',
            description='Auto-fix rule for audit events dropped simulation demos.',
            recommended_action='Run script-based recovery for simulated audit log issues.',
            priority=24,
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
        'title': 'Prepare Audit Events Recovery Environment',
        'status': 'completed',
        'detail': f'Using rule #{demo_rule_id} and script {script_path}. Profile: {profile.title()}.'
    })

    for idx in range(count):
        drop_time = now - timedelta(seconds=idx * 25)
        
        audit_message = (
            f'Audit events have been dropped by the transport. '
            f'Insufficient audit log buffer space detected. '
            f'Recovery action initiated for {profile} profile.'
        )

        event_payload = {
            'event_id': 1101,
            'log_name': 'Simulation',
            'source': 'EventLog',
            'message': audit_message,
            'timestamp': drop_time.isoformat(),
            'category': 'Audit Events Dropped',
            'severity': 'High',
            'description': 'Simulated audit events dropped event',
            'recommended_action': 'Increase audit log size and ensure sufficient disk space',
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
            'title': f'Detect Audit Drop Event {idx + 1}',
            'status': 'completed',
            'detail': f'Event row #{event_row_id} created for audit log capacity issue.'
        })

        severity_hint = 'Critical' if profile == 'critical' else ('High' if profile == 'degraded' else 'Medium')
        timeline.append({
            'phase': 'triage',
            'title': f'Triage Event {idx + 1}',
            'status': 'completed',
            'detail': f'Audit drop severity: {severity_hint}; recovery attempt: {"Enabled" if retry_on_failure else "Disabled"}.'
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
                        fail_chance = 0.10 if profile == 'stable' else (0.25 if profile == 'degraded' else 0.55)
                        if profile == 'critical' and attempt == 1:
                            fail_chance = max(fail_chance, 0.65)
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
                        verify_detail = 'Audit log capacity restored and audit pipeline resumed.' if verification_ok else 'Audit log capacity still insufficient.'
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
                'detail': 'Audit log capacity restored and auditing resumed.'
            })
        else:
            totals['incident_unresolved'] += 1
            timeline.append({
                'phase': 'escalate',
                'title': f'Escalate Incident Event {idx + 1}',
                'status': 'failed',
                'detail': 'Audit log recovery failed. Manual escalation required.'
            })

        events_summary.append({
            'event_row_id': event_row_id,
            'timestamp': event_payload['timestamp'],
            'message': audit_message,
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
        'scenario': 'Audit Events Lab - Event ID 1101 Auto-Fix',
        'simulation_mode': True,
        'event_id': 1101,
        'fix_script': 'Increase audit log size and check system resources',
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


# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
#  High CPU Alert â€” Live Demo Simulation
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

_HIGHCPU_EVENT_ID  = 9999
_HIGHCPU_SOURCE    = 'AutoRemediationDemo'
_HIGHCPU_CATEGORY  = 'High CPU Alert'


def _ensure_highcpu_rule():
    """Return (or lazily create) the remediation rule for the HighCPU demo."""
    script_path = os.path.abspath(os.path.join(
        os.path.dirname(__file__), '..', 'remediation_scripts',
        'Remediate_HighCpuAlert.ps1'
    ))
    for r in models.get_rules():
        if r[2] == _HIGHCPU_EVENT_ID and (r[3] or '').lower() == _HIGHCPU_SOURCE.lower():
            return r
    rid = models.add_rule(
        name='AutoFix Demo - Event ID 9999 High CPU Alert',
        event_id=_HIGHCPU_EVENT_ID,
        source=_HIGHCPU_SOURCE,
        message_regex=None,
        remediation_script=script_path,
        script_type='file',
        auto_remediate=False,          # We drive this manually from the pop-up
        stop_processing=False,
        category=_HIGHCPU_CATEGORY,
        severity='High',
        description='Auto-fix rule for the High CPU Alert live demo.',
        recommended_action='Run CPU throttle remediation script.',
        priority=10,
        cooldown_minutes=0,
    )
    return models.get_rule(rid)


@app.route('/api/simulations/highcpu/inject', methods=['POST'])
def highcpu_inject():
    """
    Step 1 of the live alert demo:
      - Runs Simulate_HighCpuAlert.ps1 to write a real Windows Event Log entry.
      - Adds the event to the DB so the dashboard can detect it.
      - Returns {status, event_row_id, script_output}.
    """
    inject_script = os.path.abspath(os.path.join(
        os.path.dirname(__file__), '..', 'remediation_scripts',
        'Simulate_HighCpuAlert.ps1'
    ))

    script_output = ''
    if os.path.exists(inject_script):
        try:
            proc = subprocess.run(
                ['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                 '-File', inject_script],
                capture_output=True, text=True, timeout=30
            )
            script_output = (proc.stdout + proc.stderr).strip()
        except Exception as exc:
            script_output = f'Script execution error: {exc}'
    else:
        script_output = f'[INFO] Inject script not found at {inject_script}; DB event still created.'

    now = datetime.utcnow()
    cpu_pct = random.randint(92, 100)
    message = (
        f'[HIGH CPU ALERT] Simulated CPU spike detected. '
        f'Process: DemoWorkload.exe, CPU: {cpu_pct}%, '
        f'Duration: >30 seconds sustained above 90% threshold. '
        f'Timestamp: {now.isoformat()}Z'
    )

    event_row_id = models.add_event(
        event_id=_HIGHCPU_EVENT_ID,
        log_name='Simulation',
        source=_HIGHCPU_SOURCE,
        message=message,
        timestamp=now.isoformat(),
        category=_HIGHCPU_CATEGORY,
        severity='High',
        description='Simulated High CPU Alert â€” DemoWorkload.exe spike to ' + str(cpu_pct) + '%',
        recommended_action='Run CPU throttle remediation (Remediate_HighCpuAlert.ps1)',
        level='Error',
    )

    # Ensure the remediation rule exists so the live alert pop-up can use it
    rule = _ensure_highcpu_rule()
    rule_id = rule[0] if rule else None

    return jsonify({
        'status': 'ok',
        'event_row_id': event_row_id,
        'event_id': _HIGHCPU_EVENT_ID,
        'source': _HIGHCPU_SOURCE,
        'message': message,
        'cpu_pct': cpu_pct,
        'rule_id': rule_id,
        'script_output': script_output,
        'timestamp': now.isoformat() + 'Z',
    })


@app.route('/api/simulations/highcpu/remediate', methods=['POST'])
def highcpu_remediate():
    """
    Step 2 of the live alert demo:
      - Receives {event_row_id} from the pop-up.
      - Ensures the remediation rule exists.
      - Calls models.run_remediation() which executes Remediate_HighCpuAlert.ps1.
      - Returns {status, output, event_row_id, rule_id}.
    """
    data = request.get_json(silent=True) or {}
    event_row_id = data.get('event_row_id')
    if not event_row_id:
        return jsonify({'error': 'event_row_id is required'}), 400

    rule = _ensure_highcpu_rule()
    if not rule:
        return jsonify({'error': 'Could not create/find remediation rule'}), 500

    rule_id = rule[0]
    result = models.run_remediation(event_row_id, rule_id)

    return jsonify({
        'status': result.get('status', 'unknown'),
        'output': result.get('output', ''),
        'event_row_id': event_row_id,
        'rule_id': rule_id,
    })


# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
#  Service Crash â€” Live Demo Simulation  (Event ID 7034)
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

_SVCCRASH_EVENT_ID = 7034
_SVCCRASH_SOURCE   = 'AutoRemediationDemo'
_SVCCRASH_CATEGORY = 'Service Crash'


def _ensure_svccrash_rule():
    """Return (or lazily create) the remediation rule for the ServiceCrash demo."""
    script_path = os.path.abspath(os.path.join(
        os.path.dirname(__file__), '..', 'remediation_scripts',
        'Remediate_ServiceCrash.ps1'
    ))
    for r in models.get_rules():
        if r[2] == _SVCCRASH_EVENT_ID and (r[3] or '').lower() == _SVCCRASH_SOURCE.lower():
            return r
    rid = models.add_rule(
        name='AutoFix Demo - Event ID 7034 Service Crash',
        event_id=_SVCCRASH_EVENT_ID,
        source=_SVCCRASH_SOURCE,
        message_regex=None,
        remediation_script=script_path,
        script_type='file',
        auto_remediate=False,          # Driven manually from the pop-up
        stop_processing=False,
        category=_SVCCRASH_CATEGORY,
        severity='High',
        description='Auto-fix rule for the Service Crash live demo.',
        recommended_action='Run service restart remediation script.',
        priority=11,
        cooldown_minutes=0,
    )
    return models.get_rule(rid)


@app.route('/api/simulations/servicecrash/inject', methods=['POST'])
def servicecrash_inject():
    """
    Step 1 of the Service Crash live alert demo:
      - Runs Simulate_ServiceCrash.ps1 to write a real Windows Event Log entry.
      - Adds the event to the DB so the dashboard can detect it.
      - Returns {status, event_row_id, script_output}.
    """
    inject_script = os.path.abspath(os.path.join(
        os.path.dirname(__file__), '..', 'remediation_scripts',
        'Simulate_ServiceCrash.ps1'
    ))

    script_output = ''
    if os.path.exists(inject_script):
        try:
            proc = subprocess.run(
                ['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                 '-File', inject_script],
                capture_output=True, text=True, timeout=30
            )
            script_output = (proc.stdout + proc.stderr).strip()
        except Exception as exc:
            script_output = f'Script execution error: {exc}'
    else:
        script_output = f'[INFO] Inject script not found at {inject_script}; DB event still created.'

    now = datetime.utcnow()
    crash_count = random.randint(1, 4)
    message = (
        f'[SERVICE CRASH ALERT] The Print Spooler (PrintSpooler) service terminated unexpectedly. '
        f'It has done this {crash_count} time(s). '
        f'Process: PrintSpooler.exe, '
        f'The following corrective action will be taken in 60000 milliseconds: Restart the service. '
        f'Timestamp: {now.isoformat()}Z'
    )

    event_row_id = models.add_event(
        event_id=_SVCCRASH_EVENT_ID,
        log_name='Simulation',
        source=_SVCCRASH_SOURCE,
        message=message,
        timestamp=now.isoformat(),
        category=_SVCCRASH_CATEGORY,
        severity='High',
        description=f'Simulated Service Crash â€” PrintSpooler crashed {crash_count} time(s)',
        recommended_action='Run service restart remediation (Remediate_ServiceCrash.ps1)',
        level='Error',
    )

    # Ensure the remediation rule exists so the live alert pop-up can use it
    rule = _ensure_svccrash_rule()
    rule_id = rule[0] if rule else None

    return jsonify({
        'status': 'ok',
        'event_row_id': event_row_id,
        'event_id': _SVCCRASH_EVENT_ID,
        'source': _SVCCRASH_SOURCE,
        'message': message,
        'crash_count': crash_count,
        'rule_id': rule_id,
        'script_output': script_output,
        'timestamp': now.isoformat() + 'Z',
    })


@app.route('/api/simulations/servicecrash/remediate', methods=['POST'])
def servicecrash_remediate():
    """
    Step 2 of the Service Crash live alert demo:
      - Receives {event_row_id} from the pop-up.
      - Ensures the remediation rule exists.
      - Calls models.run_remediation() which executes Remediate_ServiceCrash.ps1.
      - Returns {status, output, event_row_id, rule_id}.
    """
    data = request.get_json(silent=True) or {}
    event_row_id = data.get('event_row_id')
    if not event_row_id:
        return jsonify({'error': 'event_row_id is required'}), 400

    rule = _ensure_svccrash_rule()
    if not rule:
        return jsonify({'error': 'Could not create/find remediation rule'}), 500

    rule_id = rule[0]
    result = models.run_remediation(event_row_id, rule_id)

    return jsonify({
        'status': result.get('status', 'unknown'),
        'output': result.get('output', ''),
        'event_row_id': event_row_id,
        'rule_id': rule_id,
    })


@app.route('/api/alerts/live', methods=['GET'])
def live_alerts():
    """
    Polled every 5 s by the dashboard's live-alert system.
    Returns High/Critical-severity simulation events from the last 5 minutes
    that were injected via the HighCPU demo, enriched with remediation status.
    """
    try:
        window_seconds = int(request.args.get('window', 300))   # default 5 min
        cutoff = (datetime.utcnow() - timedelta(seconds=window_seconds)).isoformat()

        # Fetch recent events from DB
        all_events = models.get_events(limit=500)
        recent_history = models.get_history(limit=200)

        # Index remediated event_row_ids
        remediated_ids = set()
        for h in recent_history:
            if h[3] == 'success':          # h[3] = status column
                remediated_ids.add(h[1])   # h[1] = event_row_id

        alerts = []
        for ev in all_events:
            # ev columns: id, event_id, log_name, source, message, timestamp,
            #             category, severity, description, recommended_action,
            #             dedup_count, last_seen, confidence_score, correlation_id,
            #             source_type, needs_manual_review, manual_review_reason, dismissed_review
            ev_id        = ev[0]
            event_id     = ev[1]
            log_name     = ev[2]
            source       = ev[3]
            message      = ev[4]
            timestamp    = ev[5]
            category     = ev[6]
            severity     = ev[7]
            description  = ev[8]

            # Only surface High/Critical severity simulation injections
            if severity not in ('High', 'Critical'):
                continue
            if log_name != 'Simulation':
                continue
            # Accept both HighCPU and ServiceCrash demo sources
            if source not in (_HIGHCPU_SOURCE, _SVCCRASH_SOURCE):
                continue
            # Only within the time window
            if timestamp and timestamp < cutoff:
                continue

            # Route to the correct rule helper based on source
            if source == _SVCCRASH_SOURCE and event_id == _SVCCRASH_EVENT_ID:
                rule = _ensure_svccrash_rule()
                alert_type = 'servicecrash'
            else:
                rule = _ensure_highcpu_rule()
                alert_type = 'highcpu'
            rule_id = rule[0] if rule else None

            alerts.append({
                'id':            ev_id,
                'event_id':      event_id,
                'source':        source,
                'category':      category,
                'severity':      severity,
                'message':       message,
                'description':   description,
                'timestamp':     timestamp,
                'log_name':      log_name,
                'remediated':    ev_id in remediated_ids,
                'rule_id':       rule_id,
                'alert_type':    alert_type,
            })

        # Most-recent first
        alerts.sort(key=lambda a: a.get('timestamp') or '', reverse=True)
        return jsonify(alerts[:20])

    except Exception as exc:
        import traceback
        traceback.print_exc()
        return jsonify({'error': str(exc)}), 500


# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
#  Root Cause Variant Simulation - Demonstrates variant detection & remediation
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

@app.route('/api/simulations/root-cause-variants', methods=['POST'])
def simulate_root_cause_variants():
    """
    Demonstrates the Root Cause Variant System in action.
    
    Simulates the SAME ERROR ID (Service Crash 1003) with DIFFERENT ROOT CAUSES,
    showing how the system detects each variant and applies targeted remediation.
    
    This endpoint:
    1. Creates 3 service crash events (same ID, different root causes)
    2. Analyzes each to detect the variant
    3. Shows matched rules (variant-specific)
    4. Displays different remediations for each
    5. Shows success/progress in UI
    """
    from root_cause_analyzer import analyze_event as analyze_root_cause
    
    now = datetime.utcnow()
    timeline = []
    variant_simulations = []
    
    timeline.append({
        'phase': 'start',
        'title': 'Root Cause Variant System Demo',
        'status': 'in_progress',
        'detail': 'Demonstrating intelligent error classification and targeted remediation'
    })
    
    # â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    # VARIANT 1: HIGH MEMORY CRASH
    # â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    
    event_time_1 = now - timedelta(minutes=5)
    event_message_1 = 'Service MSSQLSERVER crashed: out of memory condition, heap allocation failed'
    
    event_1 = {
        'event_id': 1003,
        'source': 'Service Control Manager',
        'message': event_message_1,
        'severity': 'error',
        'category': 'Service',
    }
    
    # Detect root cause
    variants_1 = analyze_root_cause(event_1)
    best_variant_1 = variants_1[0] if variants_1 else None
    
    # Add event to database
    event_row_id_1 = models.add_event(
        event_id=1003,
        log_name='System',
        source='Service Control Manager',
        message=event_message_1,
        timestamp=event_time_1.isoformat(),
        category='Service',
        severity='error',
    )
    
    timeline.extend([
        {
            'phase': 'detect',
            'title': 'Detect Service Crash #1',
            'status': 'completed',
            'detail': f'Service crash event detected: MSSQLSERVER'
        },
        {
            'phase': 'analyze',
            'title': 'Analyze Root Cause #1',
            'status': 'completed',
            'detail': f'Detected variant: {best_variant_1.label if best_variant_1 else "Unknown"} ({"85% confidence" if best_variant_1 else "N/A"})'
        }
    ])
    
    variant_simulations.append({
        'variant_number': 1,
        'error_message': event_message_1,
        'detected_variant': {
            'label': best_variant_1.label if best_variant_1 else 'Unknown',
            'confidence': best_variant_1.confidence.value if best_variant_1 else 0,
            'indicators': best_variant_1.matched_indicators if best_variant_1 else [],
        },
        'matched_rule': {
            'name': 'Service Crash - High Memory Recovery',
            'action': 'Clear memory cache and restart with monitoring',
            'script': 'ClearMemory_RestartService.ps1',
        },
        'remediation': {
            'status': 'success',
            'output': 'Service memory cache cleared. Service restarted successfully. Memory usage: 45% -> 12%',
        },
        'result': 'âœ“ RESOLVED - Memory issue fixed'
    })
    
    timeline.append({
        'phase': 'remediate',
        'title': 'Apply Variant-Specific Remediation #1',
        'status': 'completed',
        'detail': 'Executed: Clear memory + Restart with monitoring [SUCCESS]'
    })
    
    # â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    # VARIANT 2: DEADLOCK CRASH
    # â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    
    event_time_2 = now - timedelta(minutes=3)
    event_message_2 = 'Service DatabaseServer crashed: lock timeout waiting for database resource, deadlock detected'
    
    event_2 = {
        'event_id': 1003,
        'source': 'Service Control Manager',
        'message': event_message_2,
        'severity': 'error',
        'category': 'Service',
    }
    
    # Detect root cause
    variants_2 = analyze_root_cause(event_2)
    best_variant_2 = variants_2[0] if variants_2 else None
    
    # Add event to database
    event_row_id_2 = models.add_event(
        event_id=1003,
        log_name='System',
        source='Service Control Manager',
        message=event_message_2,
        timestamp=event_time_2.isoformat(),
        category='Service',
        severity='error',
    )
    
    timeline.extend([
        {
            'phase': 'detect',
            'title': 'Detect Service Crash #2',
            'status': 'completed',
            'detail': f'Service crash event detected: DatabaseServer'
        },
        {
            'phase': 'analyze',
            'title': 'Analyze Root Cause #2',
            'status': 'completed',
            'detail': f'Detected variant: {best_variant_2.label if best_variant_2 else "Unknown"} ({"75% confidence" if best_variant_2 else "N/A"})'
        }
    ])
    
    variant_simulations.append({
        'variant_number': 2,
        'error_message': event_message_2,
        'detected_variant': {
            'label': best_variant_2.label if best_variant_2 else 'Unknown',
            'confidence': best_variant_2.confidence.value if best_variant_2 else 0,
            'indicators': best_variant_2.matched_indicators if best_variant_2 else [],
        },
        'matched_rule': {
            'name': 'Service Crash - Deadlock Recovery',
            'action': 'Kill locked threads and restart',
            'script': 'RecoverFromDeadlock.ps1',
        },
        'remediation': {
            'status': 'success',
            'output': 'Killed 3 blocked threads. Released lock. Service restarted. Queries resumed.',
        },
        'result': 'âœ“ RESOLVED - Deadlock broken and recovered'
    })
    
    timeline.append({
        'phase': 'remediate',
        'title': 'Apply Variant-Specific Remediation #2',
        'status': 'completed',
        'detail': 'Executed: Kill locked threads + Restart [SUCCESS]'
    })
    
    # â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    # VARIANT 3: MISSING DEPENDENCY CRASH
    # â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    
    event_time_3 = now - timedelta(minutes=1)
    event_message_3 = 'Service WebApp crashed: critical file not found - mscoree.dll missing from system'
    
    event_3 = {
        'event_id': 1003,
        'source': 'Service Control Manager',
        'message': event_message_3,
        'severity': 'critical',
        'category': 'Service',
    }
    
    # Detect root cause
    variants_3 = analyze_root_cause(event_3)
    best_variant_3 = variants_3[0] if variants_3 else None
    
    # Add event to database
    event_row_id_3 = models.add_event(
        event_id=1003,
        log_name='System',
        source='Service Control Manager',
        message=event_message_3,
        timestamp=event_time_3.isoformat(),
        category='Service',
        severity='critical',
    )
    
    timeline.extend([
        {
            'phase': 'detect',
            'title': 'Detect Service Crash #3',
            'status': 'completed',
            'detail': f'Service crash event detected: WebApp'
        },
        {
            'phase': 'analyze',
            'title': 'Analyze Root Cause #3',
            'status': 'completed',
            'detail': f'Detected variant: {best_variant_3.label if best_variant_3 else "Unknown"} ({"88% confidence" if best_variant_3 else "N/A"})'
        }
    ])
    
    variant_simulations.append({
        'variant_number': 3,
        'error_message': event_message_3,
        'detected_variant': {
            'label': best_variant_3.label if best_variant_3 else 'Unknown',
            'confidence': best_variant_3.confidence.value if best_variant_3 else 0,
            'indicators': best_variant_3.matched_indicators if best_variant_3 else [],
        },
        'matched_rule': {
            'name': 'Service Crash - Restore Missing Dependency',
            'action': 'Alert operator to restore missing system file',
            'script': 'AlertMissingDependency.ps1',
        },
        'remediation': {
            'status': 'alerted',
            'output': 'ALERT: Missing critical file detected. Operator notified. Awaiting manual intervention.',
        },
        'result': 'âš  ESCALATED - Manual intervention required'
    })
    
    timeline.append({
        'phase': 'remediate',
        'title': 'Escalation for Variant #3',
        'status': 'completed',
        'detail': 'Alert sent to operator for missing dependency'
    })
    
    timeline.append({
        'phase': 'complete',
        'title': 'Simulation Complete',
        'status': 'completed',
        'detail': 'All 3 variants detected and handled with targeted remediation'
    })
    
    return jsonify({
        'scenario': 'Root Cause Variant System Demonstration',
        'subtitle': 'Same Error ID (1003) - Different Root Causes - Targeted Remediation',
        'event_id': 1003,
        'simulation_mode': True,
        'description': 'Demonstrates how the system intelligently detects different root causes for the same error and applies targeted fixes.',
        'generated_at': now.isoformat() + 'Z',
        'timeline': timeline,
        'variants': variant_simulations,
        'summary': {
            'total_events': 3,
            'variants_detected': 3,
            'auto_remediation_success': 2,
            'escalated_for_manual_review': 1,
            'time_to_resolve_avg_seconds': 45,
            'key_insight': 'All 3 crashes handled differently based on root cause - achieved 67% auto-remediation rate'
        }
    })


# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
#  Real Application Crash Detection & Remediation
#  Detects actual crashes of monitored apps (e.g. notepad.exe) via Windows
#  Event ID 1000 in the Application log, and relaunches them for real.
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

import base64 as _base64
import subprocess as _subprocess
import shutil as _shutil


# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
#  Server entry point
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€




# ─────────────────────────────────────────────────────────────────────────────
#  Task Scheduler Management
# ─────────────────────────────────────────────────────────────────────────────

@app.route('/api/tasks', methods=['GET', 'POST'])
def tasks():
    """List all scheduled tasks or create a new one."""
    if request.method == 'GET':
        result = task_scheduler.list_tasks()
        return jsonify(result)
    
    elif request.method == 'POST':
        data = request.get_json(force=True)
        result = task_scheduler.create_task(
            task_name=data.get('task_name'),
            display_name=data.get('display_name'),
            description=data.get('description', ''),
            task_type=data.get('task_type'),
            script_path=data.get('script_path'),
            script_content=data.get('script_content'),
            schedule_type=data.get('schedule_type', 'once'),
            schedule_value=data.get('schedule_value', ''),
        )
        return jsonify(result), 201 if result.get('success') else 400


@app.route('/api/tasks/<int:task_id>', methods=['GET', 'PUT', 'DELETE'])
def task_detail(task_id):
    """Get, update, or delete a specific task."""
    if request.method == 'GET':
        result = task_scheduler.get_task(task_id)
        return jsonify(result), 200 if result.get('success') else 404
    
    elif request.method == 'PUT':
        data = request.get_json(force=True)
        result = task_scheduler.update_task(
            task_id=task_id,
            display_name=data.get('display_name'),
            description=data.get('description'),
            schedule_type=data.get('schedule_type'),
            schedule_value=data.get('schedule_value'),
            script_content=data.get('script_content'),
        )
        return jsonify(result)
    
    elif request.method == 'DELETE':
        result = task_scheduler.delete_task(task_id)
        return jsonify(result)


@app.route('/api/tasks/<int:task_id>/enable', methods=['POST'])
def enable_task(task_id):
    """Enable a scheduled task."""
    result = task_scheduler.enable_task(task_id)
    return jsonify(result)


@app.route('/api/tasks/<int:task_id>/disable', methods=['POST'])
def disable_task(task_id):
    """Disable a scheduled task."""
    result = task_scheduler.disable_task(task_id)
    return jsonify(result)


@app.route('/api/tasks/<int:task_id>/run', methods=['POST'])
def run_task(task_id):
    """Run a task immediately."""
    result = task_scheduler.run_task_now(task_id)
    return jsonify(result)


@app.route('/api/tasks/<int:task_id>/logs', methods=['GET'])
def task_logs(task_id):
    """Get execution logs for a task."""
    limit = int(request.args.get('limit', 50))
    result = task_scheduler.get_task_logs(task_id, limit=limit)
    return jsonify(result)


@app.route('/api/tasks/<int:task_id>/register-windows', methods=['POST'])
def register_task_windows(task_id):
    """Register a task with Windows Task Scheduler."""
    data = task_scheduler.get_task(task_id)
    if not data.get('success'):
        return jsonify({'error': 'Task not found'}), 404
    
    task = data.get('task')
    result = task_scheduler.register_task_with_windows(
        task_name=task.get('task_name'),
        script_path=task.get('script_path'),
        schedule_type=task.get('schedule_type'),
        schedule_value=task.get('schedule_value'),
    )
    return jsonify(result)


if __name__ == '__main__':
    host  = os.getenv('FLASK_HOST', '0.0.0.0')
    port  = int(os.getenv('FLASK_PORT', '5000'))
    debug = os.getenv('FLASK_DEBUG', 'True').lower() in ('true', '1', 'yes')

    print(f"Starting Flask server on {host}:{port}")
    print(f"Debug mode: {debug}")
    print(f"Access the dashboard at: http://localhost:{port}")

    app.run(host=host, port=port, debug=debug, use_reloader=False)

