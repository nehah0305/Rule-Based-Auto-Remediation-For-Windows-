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
