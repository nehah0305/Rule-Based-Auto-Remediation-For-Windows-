import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../services/api_service.dart';
import '../services/remediation_service.dart';
import '../models/event.dart';
import '../models/history_entry.dart';
import '../models/intelligence_summary.dart';
import '../widgets/stat_card.dart';
import '../widgets/badges.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _api = ApiService();
  bool _loading = true;
  int _lastRemediationCount = 0;  // Track previous remediation count

  List<AppEvent> _events = [];
  List<HistoryEntry> _history = [];
  IntelligenceSummary _intel = IntelligenceSummary();
  int _pendingApprovals = 0;
  int _totalRules = 0;
  int _manualReview = 0;

  @override
  void initState() { 
    super.initState(); 
    _load();
  }

  @override
  void dispose() {
    super.dispose();
  }


  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.getFilteredEvents(),
        _api.getHistory(),
        _api.getRules(),
        _api.getRequests(status: 'pending'),
        _api.getIntelligenceSummary(),
        _api.getManualReviewEvents(),
      ]);
      if (!mounted) return;
      setState(() {
        _events           = results[0] as List<AppEvent>;
        _history          = results[1] as List<HistoryEntry>;
        _totalRules       = (results[2] as List).length;
        _pendingApprovals = (results[3] as List).length;
        _intel            = results[4] as IntelligenceSummary;
        _manualReview     = (results[5] as List).length;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Build chart data
  Map<String, int> get _bySeverity {
    final m = <String, int>{};
    for (final e in _events) { m[(e.severity ?? 'Unknown')] = (m[e.severity ?? 'Unknown'] ?? 0) + 1; }
    return m;
  }

  Map<String, int> get _byCategory {
    final m = <String, int>{};
    for (final e in _events) { m[(e.category ?? 'Unknown')] = (m[e.category ?? 'Unknown'] ?? 0) + 1; }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RemediationService>(
      builder: (ctx, remediationSvc, _) {
        // Trigger reload ONLY when remediation count increases (new remediation)
        if (remediationSvc.remediationCount > _lastRemediationCount) {
          _lastRemediationCount = remediationSvc.remediationCount;
          Future.microtask(_load);
        }
        
        if (_loading) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.accent));
        }
        return RefreshIndicator(
          onRefresh: _load,
          color: AppTheme.accent,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            child: Container(
              decoration: BoxDecoration(
                gradient: AppTheme.panelGradient,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppTheme.border),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 30, offset: const Offset(0, 12))],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: const BoxDecoration(
                    gradient: AppTheme.gradientPrimary,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                  ),
                  child: const Row(children: [
                    Icon(Icons.dashboard_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('Dashboard Overview',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14.5)),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    LayoutBuilder(builder: (ctx, constraints) {
                      final cols = constraints.maxWidth > 700 ? 4 : 2;
                      return GridView.count(
                        crossAxisCount: cols, shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 16, mainAxisSpacing: 16,
                        childAspectRatio: constraints.maxWidth > 700 ? 2.4 : 2.0,
                        children: [
                          StatCard(label: 'Errors & Warnings', value: '${_events.length}',
                              icon: Icons.warning_amber_rounded, accentColor: AppTheme.accent),
                          StatCard(label: 'Active Rules', value: '$_totalRules',
                              icon: Icons.rule_rounded, accentColor: AppTheme.accentGreen),
                          StatCard(label: 'Pending Approvals', value: '$_pendingApprovals',
                              icon: Icons.schedule_rounded, accentColor: AppTheme.accentYellow),
                          StatCard(label: 'Remediations', value: '${_history.length}',
                              icon: Icons.history_rounded, accentColor: const Color(0xFF17a2b8)),
                        ],
                      );
                    }),
                    const SizedBox(height: 20),
                    if (_manualReview > 0) _ManualReviewBanner(count: _manualReview),
                    if (_manualReview > 0) const SizedBox(height: 16),
                    LayoutBuilder(builder: (ctx, constraints) {
                      final wide = constraints.maxWidth > 700;
                      final charts = [
                        _ChartCard(title: 'Events by Severity', gradient: AppTheme.gradientPrimary,
                            icon: Icons.pie_chart, child: _SeverityChart(data: _bySeverity)),
                        _ChartCard(title: 'Events by Category', gradient: AppTheme.gradientSuccess,
                            icon: Icons.bar_chart, child: _CategoryChart(data: _byCategory)),
                      ];
                      return wide
                          ? Row(children: charts.map((c) => Expanded(child: c)).toList()
                              .withSeparator(const SizedBox(width: 16)))
                          : Column(children: charts.withSeparator(const SizedBox(height: 16)));
                    }),
                    const SizedBox(height: 20),
                    _IntelligenceCard(intel: _intel),
                    const SizedBox(height: 20),
                    LayoutBuilder(builder: (ctx, constraints) {
                      final wide = constraints.maxWidth > 700;
                      final lists = [
                        _RecentEventsCard(events: _events.take(8).toList()),
                        _RecentRemediationsCard(history: _history.take(8).toList()),
                      ];
                      return wide
                          ? Row(crossAxisAlignment: CrossAxisAlignment.start,
                              children: lists.map((c) => Expanded(child: c)).toList()
                                  .withSeparator(const SizedBox(width: 16)))
                          : Column(children: lists.withSeparator(const SizedBox(height: 16)));
                    }),
                  ]),
                ),
              ]),
            ),
          ),
        );
      }, // End Consumer builder
    );
  }
}

// ── Manual Review Banner ────────────────────────────────────────────────────
class _ManualReviewBanner extends StatelessWidget {
  final int count;
  const _ManualReviewBanner({required this.count});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [AppTheme.accentRed.withValues(alpha: 0.18), AppTheme.accentRed.withValues(alpha: 0.06)],
      ),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppTheme.accentRed.withValues(alpha: 0.38)),
    ),
    child: Row(children: [
      const Icon(Icons.error_outline, color: AppTheme.accentRed, size: 22),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Manual Review Required',
            style: TextStyle(color: AppTheme.accentRed, fontWeight: FontWeight.w700, fontSize: 13)),
        Text('$count event(s) have no matching remediation rule — human action needed',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
      ])),
      TextButton(
        onPressed: () {},
        style: TextButton.styleFrom(
          backgroundColor: AppTheme.accentRed, foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Text('View Events', style: TextStyle(fontSize: 12)),
      ),
    ]),
  );
}

// ── Chart card wrapper ──────────────────────────────────────────────────────
class _ChartCard extends StatelessWidget {
  final String title;
  final LinearGradient gradient;
  final IconData icon;
  final Widget child;
  const _ChartCard({required this.title, required this.gradient, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.02), borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(gradient: gradient, borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
        child: Row(children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
        ]),
      ),
      Padding(padding: const EdgeInsets.all(20), child: child),
    ]),
  );
}

// ── Severity Pie Chart ──────────────────────────────────────────────────────
class _SeverityChart extends StatelessWidget {
  final Map<String, int> data;
  const _SeverityChart({required this.data});

  Color _colorForSeverity(String s) {
    switch (s.toLowerCase()) {
      case 'critical': return AppTheme.accentRed;
      case 'high':     return const Color(0xFFfd7e14);
      case 'medium':   return AppTheme.accent;
      case 'low':      return AppTheme.accentGreen;
      default:         return AppTheme.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox(height: 160, child: Center(child: Text('No data', style: TextStyle(color: AppTheme.textMuted))));
    final entries = data.entries.toList();
    return SizedBox(height: 180, child: Row(children: [
      Expanded(
        child: PieChart(PieChartData(
          sections: entries.map((e) => PieChartSectionData(
            value: e.value.toDouble(),
            color: _colorForSeverity(e.key),
            title: '${e.value}',
            titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
            radius: 64,
          )).toList(),
          sectionsSpace: 2,
          centerSpaceRadius: 28,
        )),
      ),
      const SizedBox(width: 16),
      Column(mainAxisAlignment: MainAxisAlignment.center,
          children: entries.map((e) => _Legend(label: e.key, color: _colorForSeverity(e.key), count: e.value)).toList()),
    ]));
  }
}

// ── Category Bar Chart ──────────────────────────────────────────────────────
class _CategoryChart extends StatelessWidget {
  final Map<String, int> data;
  const _CategoryChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox(height: 160, child: Center(child: Text('No data', style: TextStyle(color: AppTheme.textMuted))));
    final entries = data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(6).toList();
    const colors = [AppTheme.accent, AppTheme.accentGreen, AppTheme.accentPurple, AppTheme.accentOrange, AppTheme.accentRed, AppTheme.accentYellow];
    return SizedBox(height: 180, child: BarChart(BarChartData(
      barGroups: top.asMap().entries.map((e) => BarChartGroupData(x: e.key, barRods: [
        BarChartRodData(toY: e.value.value.toDouble(), color: colors[e.key % colors.length], width: 20, borderRadius: BorderRadius.circular(4)),
      ])).toList(),
      titlesData: FlTitlesData(
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true, reservedSize: 44,
          getTitlesWidget: (v, _) {
            final idx = v.toInt();
            if (idx >= top.length) return const SizedBox.shrink();
            final label = top[idx].key.length > 12 ? '${top[idx].key.substring(0, 10)}…' : top[idx].key;
            return Padding(padding: const EdgeInsets.only(top: 6),
                child: Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 9), textAlign: TextAlign.center));
          },
        )),
      ),
      borderData: FlBorderData(show: false),
      gridData: const FlGridData(drawVerticalLine: false, horizontalInterval: 1),
      barTouchData: BarTouchData(enabled: true,
          touchTooltipData: BarTouchTooltipData(getTooltipColor: (_) => AppTheme.bgCardAlt,
              getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                  '${top[group.x].key}\n${rod.toY.toInt()}',
                  const TextStyle(color: AppTheme.textPrimary, fontSize: 11)))),
    )));
  }
}

class _Legend extends StatelessWidget {
  final String label; final Color color; final int count;
  const _Legend({required this.label, required this.color, required this.count});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 6),
      Text('$label ($count)', style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
    ]),
  );
}

// ── Intelligence Card ───────────────────────────────────────────────────────
class _IntelligenceCard extends StatelessWidget {
  final IntelligenceSummary intel;
  const _IntelligenceCard({required this.intel});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(14),
        border: const Border(left: BorderSide(color: AppTheme.accentPurple, width: 4),
            top: BorderSide(color: AppTheme.border), right: BorderSide(color: AppTheme.border),
            bottom: BorderSide(color: AppTheme.border))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [AppTheme.accentPurple.withOpacity(0.2), AppTheme.accentPurple.withOpacity(0.05)]),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        ),
        child: const Row(children: [
          Icon(Icons.psychology_rounded, color: Color(0xFFc77dff), size: 18),
          SizedBox(width: 8),
          Text('Alert Intelligence Summary', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
          Spacer(),
          Text('Auto-updated every 5s', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(builder: (ctx, constraints) {
          final cols = constraints.maxWidth > 500 ? 4 : 2;
          return GridView.count(
            crossAxisCount: cols, shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12, mainAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              _IntelMetric(value: '${intel.totalEvents}',   label: 'Total Unique Events',          color: const Color(0xFFc77dff)),
              _IntelMetric(value: '${intel.totalSuppressed}', label: 'Duplicates Collapsed',       color: const Color(0xFF00d4ff)),
              _IntelMetric(value: intel.avgConfidence.toStringAsFixed(1), label: 'Avg Confidence', color: const Color(0xFFffaa00)),
              _IntelMetric(value: '${intel.cooldownRules}',   label: 'Rules with Cooldown',        color: AppTheme.accent),
            ],
          );
        }),
      ),
    ]),
  );
}

class _IntelMetric extends StatelessWidget {
  final String value; final String label; final Color color;
  const _IntelMetric({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25))),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(value, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 10), textAlign: TextAlign.center),
    ]),
  );
}

// ── Recent Events ───────────────────────────────────────────────────────────
class _RecentEventsCard extends StatelessWidget {
  final List<AppEvent> events;
  const _RecentEventsCard({required this.events});

  @override
  Widget build(BuildContext context) => _ActivityCard(
    title: 'Recent Events', icon: Icons.schedule_rounded, gradient: AppTheme.gradientInfo,
    child: events.isEmpty
        ? const Padding(padding: EdgeInsets.all(16), child: Text('No events', style: TextStyle(color: AppTheme.textMuted)))
        : Column(children: events.map((e) => _EventTile(event: e)).toList()),
  );
}

class _EventTile extends StatelessWidget {
  final AppEvent event;
  const _EventTile({required this.event});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border.withOpacity(0.5)))),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Event ${event.eventId ?? '?'} — ${event.source ?? ''}',
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(event.message ?? '', style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ])),
      const SizedBox(width: 8),
      SeverityBadge(event.severity),
    ]),
  );
}

// ── Recent Remediations ─────────────────────────────────────────────────────
class _RecentRemediationsCard extends StatelessWidget {
  final List<HistoryEntry> history;
  const _RecentRemediationsCard({required this.history});

  @override
  Widget build(BuildContext context) => _ActivityCard(
    title: 'Recent Remediations', icon: Icons.task_alt_rounded, gradient: AppTheme.gradientSecondary,
    child: history.isEmpty
        ? const Padding(padding: EdgeInsets.all(16), child: Text('No remediations', style: TextStyle(color: AppTheme.textMuted)))
        : Column(children: history.map((h) => _RemediationTile(entry: h)).toList()),
  );
}

class _RemediationTile extends StatelessWidget {
  final HistoryEntry entry;
  const _RemediationTile({required this.entry});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border.withOpacity(0.5)))),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(entry.ruleName ?? 'Rule #${entry.ruleId}',
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        Text('Event ${entry.eventId ?? '?'} — ${entry.eventSource ?? ''}',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
      ])),
      const SizedBox(width: 8),
      StatusBadge(entry.status),
    ]),
  );
}

class _ActivityCard extends StatelessWidget {
  final String title; final IconData icon;
  final LinearGradient gradient; final Widget child;
  const _ActivityCard({required this.title, required this.icon, required this.gradient, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(gradient: gradient, borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
        child: Row(children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
      ),
      child,
    ]),
  );
}

// Util
extension ListSep<T extends Widget> on List<T> {
  List<Widget> withSeparator(Widget sep) {
    final r = <Widget>[];
    for (var i = 0; i < length; i++) { r.add(this[i]); if (i < length - 1) r.add(sep); }
    return r;
  }
}
