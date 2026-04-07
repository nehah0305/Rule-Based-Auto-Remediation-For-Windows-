class HistoryEntry {
  final int id;
  final int eventRowId;
  final int? ruleId;
  final String? status;
  final String? output;
  final String? timestamp;
  final int? eventId;
  final String? eventSource;
  final String? ruleName;
  final String? eventTimestamp;

  HistoryEntry({
    required this.id,
    required this.eventRowId,
    this.ruleId,
    this.status,
    this.output,
    this.timestamp,
    this.eventId,
    this.eventSource,
    this.ruleName,
    this.eventTimestamp,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> j) {
    // Handle event_id which might be string or int from the backend
    int? eventId;
    if (j['event_id'] != null) {
      final val = j['event_id'];
      eventId = val is int ? val : int.tryParse(val.toString());
    }
    
    return HistoryEntry(
      id:             j['id'] as int,
      eventRowId:     j['event_row_id'] as int,
      ruleId:         j['rule_id'] as int?,
      status:         j['status'] as String?,
      output:         j['output'] as String?,
      timestamp:      j['timestamp'] as String?,
      eventId:        eventId,
      eventSource:    j['event_source'] as String? ?? j['source'] as String?,
      ruleName:       j['rule_name'] as String?,
      eventTimestamp: j['event_timestamp'] as String?,
    );
  }
}
