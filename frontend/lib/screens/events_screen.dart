import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/api_service.dart';
import '../models/event.dart';
import '../widgets/badges.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});
  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  final _api = ApiService();
  bool _loading = true;
  List<AppEvent> _events = [];
  String _lastUpdated = '';
  String _searchQuery = '';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _events = await _api.getFilteredEvents();
      _lastUpdated = DateTime.now().toString().substring(0, 16);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  List<AppEvent> get _filtered {
    final q = _searchQuery.toLowerCase();
    if (q.isEmpty) return _events;
    return _events.where((e) =>
      (e.source ?? '').toLowerCase().contains(q) ||
      (e.message ?? '').toLowerCase().contains(q) ||
      (e.severity ?? '').toLowerCase().contains(q) ||
      (e.category ?? '').toLowerCase().contains(q) ||
      '${e.eventId}'.contains(q)
    ).toList();
  }

  Future<void> _dismissReview(int id) async {
    try {
      await _api.dismissEventReview(id);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _showMatches(AppEvent event) async {
    showDialog(
      context: context,
      builder: (_) => _MatchesDialog(api: _api, event: event),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        // Header card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            gradient: AppTheme.gradientWarning,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(
              'Warnings & Errors (Filtered)${_lastUpdated.isNotEmpty ? "  ·  $_lastUpdated" : ""}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
            )),
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh, color: Colors.white, size: 18),
                tooltip: 'Refresh'),
          ]),
        ),
        // Search + body
        Expanded(
          child: Container(
            decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                border: Border.all(color: AppTheme.border)),
            child: Column(children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: const InputDecoration(
                    hintText: 'Search events…',
                    prefixIcon: Icon(Icons.search, size: 18),
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ),
              // Table
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
                    : _EventsTable(events: _filtered, onDismiss: _dismissReview, onMatches: _showMatches),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _EventsTable extends StatelessWidget {
  final List<AppEvent> events;
  final Future<void> Function(int id) onDismiss;
  final void Function(AppEvent event) onMatches;

  const _EventsTable({required this.events, required this.onDismiss, required this.onMatches});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Center(child: Text('No warnings or errors yet', style: TextStyle(color: AppTheme.textMuted)));
    }
    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            columnSpacing: 16,
            headingRowColor: const WidgetStatePropertyAll(Color(0xFF181830)),
            dataRowColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.hovered) ? AppTheme.accent.withOpacity(0.05) : null),
            headingTextStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
            columns: const [
              DataColumn(label: Text('Level')),
              DataColumn(label: Text('Event ID')),
              DataColumn(label: Text('Source')),
              DataColumn(label: Text('Severity')),
              DataColumn(label: Text('Message')),
              DataColumn(label: Text('Timestamp')),
              DataColumn(label: Text('Conf')),
              DataColumn(label: Text('Dedup')),
              DataColumn(label: Text('Actions')),
            ],
            rows: events.map((e) => DataRow(cells: [
              DataCell(LevelBadge(e.needsManualReview ? 'Error' : 'Warning')),
              DataCell(Text('${e.eventId ?? '—'}',
                  style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w600, fontSize: 12))),
              DataCell(Text(e.source ?? '—', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                  overflow: TextOverflow.ellipsis)),
              DataCell(SeverityBadge(e.severity)),
              DataCell(SizedBox(width: 240, child: Tooltip(message: e.message ?? '',
                child: Text(e.message ?? '—',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                    maxLines: 2, overflow: TextOverflow.ellipsis)))),
              DataCell(Text(_fmtTs(e.timestamp), style: const TextStyle(color: AppTheme.textMuted, fontSize: 11))),
              DataCell(ConfidenceBadge(e.confidenceScore)),
              DataCell(e.dedupCount > 1
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: AppTheme.accentPurple.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12)),
                      child: Text('×${e.dedupCount}', style: const TextStyle(color: AppTheme.accentPurple, fontSize: 11, fontWeight: FontWeight.w700)))
                  : const Text('1', style: TextStyle(color: AppTheme.textDimmed, fontSize: 11))),
              DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                _ActionBtn(icon: Icons.link_rounded, label: 'Matches', color: AppTheme.accent,
                    onTap: () => onMatches(e)),
                if (e.needsManualReview && !e.dismissedReview) ...[
                  const SizedBox(width: 6),
                  _ActionBtn(icon: Icons.check, label: 'Dismiss', color: AppTheme.accentGreen,
                      onTap: () => onDismiss(e.id)),
                ],
              ])),
            ])).toList(),
          ),
        ),
      ),
    );
  }

  String _fmtTs(String? ts) {
    if (ts == null) return '—';
    try {
      final dt = DateTime.parse(ts);
      return '${dt.toLocal()}'.substring(0, 16);
    } catch (_) { return ts.length > 16 ? ts.substring(0, 16) : ts; }
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 13, color: color),
    label: Text(label, style: TextStyle(color: color, fontSize: 11)),
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
  );
}

// ── Matches Dialog ──────────────────────────────────────────────────────────
class _MatchesDialog extends StatefulWidget {
  final ApiService api;
  final AppEvent event;
  const _MatchesDialog({required this.api, required this.event});

  @override
  State<_MatchesDialog> createState() => _MatchesDialogState();
}

class _MatchesDialogState extends State<_MatchesDialog> {
  bool _loading = true;
  List<dynamic> _matches = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await widget.api.ensureEvent({
        'event_id': widget.event.eventId, 'log_name': widget.event.logName,
        'source': widget.event.source, 'message': widget.event.message,
        'timestamp': widget.event.timestamp, 'category': widget.event.category,
        'severity': widget.event.severity, 'description': widget.event.description,
        'recommended_action': widget.event.recommendedAction,
      });
      final rowId = res['event_row_id'] as int;
      _matches = await widget.api.getEventMatches(rowId);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: const BoxDecoration(gradient: AppTheme.gradientPrimary,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
          child: Row(children: [
            const Icon(Icons.link_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text('Matching Rules for Event ${widget.event.eventId}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white, size: 18)),
          ]),
        ),
        Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
            : _matches.isEmpty
                ? const Center(child: Text('No matching rules found', style: TextStyle(color: AppTheme.textMuted)))
                : ListView(padding: const EdgeInsets.all(16),
                    children: _matches.map((m) => _MatchCard(match: m as Map<String, dynamic>)).toList())),
      ]),
    ),
  );
}

class _MatchCard extends StatelessWidget {
  final Map<String, dynamic> match;
  const _MatchCard({required this.match});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppTheme.bgCardAlt, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(match['name'] as String? ?? 'Rule', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      const SizedBox(height: 6),
      Row(children: [
        SeverityBadge(match['severity'] as String?),
        const SizedBox(width: 8),
        CategoryBadge(match['category'] as String?),
      ]),
      if (match['description'] != null) ...[
        const SizedBox(height: 8),
        Text('${match['description']}', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
      ],
      if (match['recommended_action'] != null) ...[
        const SizedBox(height: 6),
        Text('Action: ${match['recommended_action']}',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
      ],
    ]),
  );
}
