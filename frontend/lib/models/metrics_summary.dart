class MttrPoint {
  final String date;
  final double mttrSeconds;
  final int count;

  MttrPoint({required this.date, required this.mttrSeconds, required this.count});

  factory MttrPoint.fromJson(Map<String, dynamic> j) => MttrPoint(
    date:        j['date'] as String? ?? '',
    mttrSeconds: (j['mttr_seconds'] as num?)?.toDouble() ?? 0.0,
    count:       (j['count'] as num?)?.toInt() ?? 0,
  );
}

class MetricsSummary {
  final double successRatePct;
  final int totalAttempts;
  final int totalSuccessful;
  final double? mttrSeconds;
  final String mttrHuman;
  final List<MttrPoint> mttrTimeseries;
  final int autoCount;
  final int manualApprovalCount;
  final double autoPct;

  MetricsSummary({
    this.successRatePct = 0,
    this.totalAttempts = 0,
    this.totalSuccessful = 0,
    this.mttrSeconds,
    this.mttrHuman = 'N/A',
    this.mttrTimeseries = const [],
    this.autoCount = 0,
    this.manualApprovalCount = 0,
    this.autoPct = 0,
  });

  factory MetricsSummary.fromJson(Map<String, dynamic> j) {
    final successRate = j['success_rate'] as Map<String, dynamic>? ?? {};
    final mttr = j['mttr'] as Map<String, dynamic>? ?? {};
    final autoVsManual = j['auto_vs_manual'] as Map<String, dynamic>? ?? {};
    final series = (j['mttr_timeseries'] as List<dynamic>? ?? [])
        .map((e) => MttrPoint.fromJson(e as Map<String, dynamic>))
        .toList();

    return MetricsSummary(
      successRatePct:      (successRate['success_rate_pct'] as num?)?.toDouble() ?? 0,
      totalAttempts:        (successRate['total_attempts'] as num?)?.toInt() ?? 0,
      totalSuccessful:      (successRate['total_successful'] as num?)?.toInt() ?? 0,
      mttrSeconds:          (mttr['mttr_seconds'] as num?)?.toDouble(),
      mttrHuman:            mttr['mttr_human'] as String? ?? 'N/A',
      mttrTimeseries:       series,
      autoCount:            (autoVsManual['auto_count'] as num?)?.toInt() ?? 0,
      manualApprovalCount:  (autoVsManual['manual_approval_count'] as num?)?.toInt() ?? 0,
      autoPct:              (autoVsManual['auto_pct'] as num?)?.toDouble() ?? 0,
    );
  }
}
