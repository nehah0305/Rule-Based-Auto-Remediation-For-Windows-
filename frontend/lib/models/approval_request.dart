class ApprovalRequest {
  final int id;
  final int eventRowId;
  final int? ruleId;
  final String? status;
  final String? requestedBy;
  final String? requestedAt;
  final String? processedBy;
  final String? processedAt;
  final String? decisionNote;
  final int? eventId;
  final String? eventSource;
  final String? ruleName;

  ApprovalRequest({
    required this.id,
    required this.eventRowId,
    this.ruleId,
    this.status,
    this.requestedBy,
    this.requestedAt,
    this.processedBy,
    this.processedAt,
    this.decisionNote,
    this.eventId,
    this.eventSource,
    this.ruleName,
  });

  factory ApprovalRequest.fromJson(Map<String, dynamic> j) => ApprovalRequest(
    id:           j['id'] as int,
    eventRowId:   j['event_row_id'] as int,
    ruleId:       j['rule_id'] as int?,
    status:       j['status'] as String?,
    requestedBy:  j['requested_by'] as String?,
    requestedAt:  j['requested_at'] as String?,
    processedBy:  j['processed_by'] as String?,
    processedAt:  j['processed_at'] as String?,
    decisionNote: j['decision_note'] as String?,
    eventId:      j['event_id'] as int?,
    eventSource:  j['event_source'] as String?,
    ruleName:     j['rule_name'] as String?,
  );
}

/// A new-event-type approval gate entry (`/api/approvals`).
/// Distinct from [ApprovalRequest], which backs the older generic
/// `/api/requests` request/approve/deny flow.
class ApprovalGateRequest {
  final int id;
  final int eventRowId;
  final String eventId;
  final String source;
  final int ruleId;
  final String ruleName;
  final String status;
  final String createdAt;
  final String? resolvedAt;
  final String? resolvedBy;
  final String? severity;
  /// Faulting application name (e.g. 'notepad.exe'). Empty for non-app events.
  final String appContext;

  ApprovalGateRequest({
    required this.id,
    required this.eventRowId,
    required this.eventId,
    required this.source,
    required this.ruleId,
    required this.ruleName,
    required this.status,
    required this.createdAt,
    this.resolvedAt,
    this.resolvedBy,
    this.severity,
    this.appContext = '',
  });

  factory ApprovalGateRequest.fromJson(Map<String, dynamic> j) => ApprovalGateRequest(
    id:          j['id'] as int,
    eventRowId:  j['event_row_id'] as int,
    eventId:     j['event_id']?.toString() ?? '',
    source:      j['source'] as String? ?? '',
    ruleId:      j['rule_id'] as int,
    ruleName:    j['rule_name'] as String? ?? '',
    status:      j['status'] as String? ?? 'pending',
    createdAt:   j['created_at'] as String? ?? '',
    resolvedAt:  j['resolved_at'] as String?,
    resolvedBy:  j['resolved_by'] as String?,
    severity:    j['severity'] as String?,
    appContext:  j['app_context'] as String? ?? '',
  );
}
