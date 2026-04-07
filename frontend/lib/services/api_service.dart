import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/event.dart';
import '../models/rule.dart';
import '../models/history_entry.dart';
import '../models/approval_request.dart';
import '../models/alert.dart';
import '../models/intelligence_summary.dart';

class ApiService {
  final http.Client _client = http.Client();

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  Future<dynamic> _get(String path) async {
    final res = await _client.get(Uri.parse(ApiConfig.url(path)), headers: _headers);
    if (res.statusCode >= 400) throw Exception('GET $path failed: ${res.statusCode} ${res.body}');
    return jsonDecode(res.body);
  }

  Future<dynamic> _post(String path, [dynamic body]) async {
    final res = await _client.post(
      Uri.parse(ApiConfig.url(path)),
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    );
    if (res.statusCode >= 400) throw Exception('POST $path failed: ${res.statusCode} ${res.body}');
    return jsonDecode(res.body);
  }

  Future<dynamic> _put(String path, dynamic body) async {
    final res = await _client.put(
      Uri.parse(ApiConfig.url(path)),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (res.statusCode >= 400) throw Exception('PUT $path failed: ${res.statusCode} ${res.body}');
    return jsonDecode(res.body);
  }

  Future<dynamic> _delete(String path) async {
    final res = await _client.delete(Uri.parse(ApiConfig.url(path)), headers: _headers);
    if (res.statusCode >= 400) throw Exception('DELETE $path failed: ${res.statusCode} ${res.body}');
    return jsonDecode(res.body);
  }

  // ─── Events ────────────────────────────────────────────────────────────────
  Future<List<AppEvent>> getEvents() async {
    final data = await _get('/api/events') as List;
    return data.map((e) => AppEvent.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<AppEvent>> getFilteredEvents() async {
    final data = await _get('/api/filtered-events');
    if (data is List) {
      return data.map((e) => AppEvent.fromJson(e as Map<String, dynamic>)).toList();
    }
    return [];
  }

  Future<List<AppEvent>> getManualReviewEvents() async {
    final data = await _get('/api/events/manual-review') as List;
    return data.map((e) => AppEvent.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> dismissEventReview(int eventRowId) async {
    await _post('/api/events/$eventRowId/dismiss-review');
  }

  Future<List<dynamic>> getEventMatches(int eventRowId) async {
    return await _get('/api/events/$eventRowId/matches') as List;
  }

  Future<Map<String, dynamic>> ensureEvent(Map<String, dynamic> eventData) async {
    return await _post('/api/events/ensure', eventData) as Map<String, dynamic>;
  }

  // ─── Rules ─────────────────────────────────────────────────────────────────
  Future<List<Rule>> getRules() async {
    final data = await _get('/api/rules') as List;
    return data.map((r) => Rule.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<Rule> getRule(int ruleId) async {
    final data = await _get('/api/rules/$ruleId') as Map<String, dynamic>;
    return Rule.fromJson(data);
  }

  Future<Map<String, dynamic>> createRule(Map<String, dynamic> data) async {
    return await _post('/api/rules', data) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateRule(int ruleId, Map<String, dynamic> data) async {
    return await _put('/api/rules/$ruleId', data) as Map<String, dynamic>;
  }

  Future<void> deleteRule(int ruleId) async {
    await _delete('/api/rules/$ruleId');
  }

  Future<Map<String, dynamic>> runRule(int ruleId, int eventRowId) async {
    return await _post('/api/rules/$ruleId/run', {'event_row_id': eventRowId}) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> testRule(int ruleId) async {
    return await _post('/api/rules/$ruleId/test') as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> populateRulesFromJson() async {
    return await _post('/api/populate-rules', {}) as Map<String, dynamic>;
  }

  // ─── History ───────────────────────────────────────────────────────────────
  Future<List<HistoryEntry>> getHistory() async {
    final data = await _get('/api/history') as List;
    return data.map((h) => HistoryEntry.fromJson(h as Map<String, dynamic>)).toList();
  }

  // ─── Approvals/Requests ────────────────────────────────────────────────────
  Future<List<ApprovalRequest>> getRequests({String? status}) async {
    final path = status != null ? '/api/requests?status=$status' : '/api/requests';
    final data = await _get(path) as List;
    return data.map((r) => ApprovalRequest.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> approveRequest(int reqId) async {
    return await _post('/api/requests/$reqId/approve', {'processed_by': 'web-ui'}) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> denyRequest(int reqId, {String note = 'denied by admin'}) async {
    return await _post('/api/requests/$reqId/deny', {'processed_by': 'admin', 'note': note}) as Map<String, dynamic>;
  }

  // ─── Monitor ───────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getMonitorStatus() async {
    return await _get('/api/monitor/status') as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> triggerMonitorPoll() async {
    return await _post('/api/monitor/trigger') as Map<String, dynamic>;
  }

  // ─── Intelligence ──────────────────────────────────────────────────────────
  Future<IntelligenceSummary> getIntelligenceSummary() async {
    final data = await _get('/api/intelligence/summary') as Map<String, dynamic>;
    return IntelligenceSummary.fromJson(data);
  }

  // ─── Live Alerts ───────────────────────────────────────────────────────────
  Future<List<LiveAlert>> getLiveAlerts({int windowSeconds = 300}) async {
    final data = await _get('/api/alerts/live?window=$windowSeconds') as List;
    return data.map((a) => LiveAlert.fromJson(a as Map<String, dynamic>)).toList();
  }

  // ─── Simulations ───────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> runCrashSimulation(Map<String, dynamic> params) async {
    return await _post('/api/simulations/error1000/auto-fix', params) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> runDiskSimulation(Map<String, dynamic> params) async {
    return await _post('/api/simulations/lowdiskspace/auto-fix', params) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> runEventLogSimulation(Map<String, dynamic> params) async {
    return await _post('/api/simulations/eventlog/auto-fix', params) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> runAuditEventsSimulation(Map<String, dynamic> params) async {
    return await _post('/api/simulations/auditevents/auto-fix', params) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> injectHighCpuAlert() async {
    return await _post('/api/simulations/highcpu/inject') as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> remediateHighCpu(int eventRowId) async {
    return await _post('/api/simulations/highcpu/remediate', {'event_row_id': eventRowId}) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> injectServiceCrash() async {
    return await _post('/api/simulations/servicecrash/inject') as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> remediateServiceCrash(int eventRowId) async {
    return await _post('/api/simulations/servicecrash/remediate', {'event_row_id': eventRowId}) as Map<String, dynamic>;
  }
}
