class IntelligenceSummary {
  final int totalEvents;
  final int totalSuppressed;
  final double avgConfidence;
  final int cooldownRules;
  final int needsReview;

  IntelligenceSummary({
    this.totalEvents = 0,
    this.totalSuppressed = 0,
    this.avgConfidence = 0.0,
    this.cooldownRules = 0,
    this.needsReview = 0,
  });

  factory IntelligenceSummary.fromJson(Map<String, dynamic> j) => IntelligenceSummary(
    totalEvents:     (j['total_events'] as num?)?.toInt() ?? 0,
    totalSuppressed: (j['total_suppressed'] as num?)?.toInt() ?? 0,
    avgConfidence:   (j['avg_confidence'] as num?)?.toDouble() ?? 0.0,
    cooldownRules:   (j['cooldown_rules'] as num?)?.toInt() ?? 0,
    needsReview:     (j['needs_review'] as num?)?.toInt() ?? 0,
  );
}
