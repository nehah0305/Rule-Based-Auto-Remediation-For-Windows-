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

  factory AppEvent.fromJson(Map<String, dynamic> j) => AppEvent(
    id:                  j['id'] as int,
    eventId:             j['event_id'] as int?,
    logName:             j['log_name'] as String?,
    source:              j['source'] as String?,
    message:             j['message'] as String?,
    timestamp:           j['timestamp'] as String?,
    category:            j['category'] as String?,
    severity:            j['severity'] as String?,
    description:         j['description'] as String?,
    recommendedAction:   j['recommended_action'] as String?,
    dedupCount:          (j['dedup_count'] as num?)?.toInt() ?? 1,
    lastSeen:            j['last_seen'] as String?,
    confidenceScore:     (j['confidence_score'] as num?)?.toDouble() ?? 0.0,
    correlationId:       j['correlation_id'] as String?,
    sourceType:          j['source_type'] as String?,
    needsManualReview:   j['needs_manual_review'] as bool? ?? false,
    manualReviewReason:  j['manual_review_reason'] as String?,
    dismissedReview:     j['dismissed_review'] as bool? ?? false,
  );
}
