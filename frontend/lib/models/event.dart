class AppEvent {
  final int id;
  final int? eventId;
  final String? logName;
  final String? source;
  final String? message;
  final String? timestamp;
  final String? category;
  final String? severity;
  final String? description;
  final String? recommendedAction;
  final int dedupCount;
  final String? lastSeen;
  final double confidenceScore;
  final String? correlationId;
  final String? sourceType;
  final bool remediated;
  final bool needsManualReview;
  final String? manualReviewReason;
  final bool dismissedReview;

  AppEvent({
    required this.id,
    this.eventId,
    this.logName,
    this.source,
    this.message,
    this.timestamp,
    this.category,
    this.severity,
    this.description,
    this.recommendedAction,
    this.dedupCount = 1,
    this.lastSeen,
    this.confidenceScore = 0.0,
    this.correlationId,
    this.sourceType,
    this.needsManualReview = false,
    this.manualReviewReason,
    this.dismissedReview = false,
  });

  static int _toInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  static double _toDouble(dynamic value, {double fallback = 0.0}) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  static bool _toBool(dynamic value, {bool fallback = false}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final v = value.trim().toLowerCase();
      if (v == 'true' || v == '1' || v == 'yes') return true;
      if (v == 'false' || v == '0' || v == 'no') return false;
    }
    return fallback;
  }

  static String? _toStringOrNull(dynamic value) {
    if (value == null) return null;
    final s = value.toString();
    return s.isEmpty ? null : s;
  }

  factory AppEvent.fromJson(Map<String, dynamic> j) => AppEvent(
    id:                  _toInt(j['id']),
    eventId:             j['event_id'] == null ? null : _toInt(j['event_id']),
    logName:             _toStringOrNull(j['log_name']),
    source:              _toStringOrNull(j['source']),
    message:             _toStringOrNull(j['message']),
    timestamp:           _toStringOrNull(j['timestamp']),
    category:            _toStringOrNull(j['category']),
    severity:            _toStringOrNull(j['severity']),
    description:         _toStringOrNull(j['description']),
    recommendedAction:   _toStringOrNull(j['recommended_action']),
    dedupCount:          _toInt(j['dedup_count'], fallback: 1),
    lastSeen:            _toStringOrNull(j['last_seen']),
    confidenceScore:     _toDouble(j['confidence_score']),
    correlationId:       _toStringOrNull(j['correlation_id']),
    sourceType:          _toStringOrNull(j['source_type']),
    needsManualReview:   _toBool(j['needs_manual_review']),
    manualReviewReason:  _toStringOrNull(j['manual_review_reason']),
    dismissedReview:     _toBool(j['dismissed_review']),
    remediated:           _toBool(j['remediated']),
  );
}
