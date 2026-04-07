class LiveAlert {
  final int id;
  final int? eventId;
  final String? source;
  final String? category;
  final String? severity;
  final String? message;
  final String? description;
  final String? timestamp;
  final String? logName;
  final bool remediated;
  final int? ruleId;
  final String? alertType;

  LiveAlert({
    required this.id,
    this.eventId,
    this.source,
    this.category,
    this.severity,
    this.message,
    this.description,
    this.timestamp,
    this.logName,
    this.remediated = false,
    this.ruleId,
    this.alertType,
  });

  factory LiveAlert.fromJson(Map<String, dynamic> j) => LiveAlert(
    id:          j['id'] as int,
    eventId:     j['event_id'] as int?,
    source:      j['source'] as String?,
    category:    j['category'] as String?,
    severity:    j['severity'] as String?,
    message:     j['message'] as String?,
    description: j['description'] as String?,
    timestamp:   j['timestamp'] as String?,
    logName:     j['log_name'] as String?,
    remediated:  j['remediated'] as bool? ?? false,
    ruleId:      j['rule_id'] as int?,
    alertType:   j['alert_type'] as String?,
  );
}
