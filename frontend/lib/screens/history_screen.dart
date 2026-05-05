import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../services/api_service.dart';
import '../services/remediation_service.dart';
import '../models/history_entry.dart';
import '../widgets/badges.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _api = ApiService();
  bool _loading = true;
  int _lastRemediationCount = 0;  // Track previous remediation count
  List<HistoryEntry> _history = [];
  String _filterStatus = 'all';

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
      final data = await _api.getHistory();
      if (!mounted) return;
      setState(() {
        _history = data;
        _loading = false;
      });
    } catch (_, __) {
      if (mounted) {
        setState(() {
        _history = [];
        _loading = false;
      });
      }
    }
  }

  List<HistoryEntry> get _filtered {
    if (_filterStatus == 'all') return _history;
    return _history.where((h) => (h.status ?? '') == _filterStatus).toList();
  }

  @override
  Widget build(BuildContext context) {
    final tableTheme = Theme.of(context).copyWith(
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(Colors.white.withValues(alpha: 0.04)),
        dataRowColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) {
            return AppTheme.accent.withValues(alpha: 0.05);
          }
          return Colors.transparent;
        }),
      ),
    );

    return Consumer<RemediationService>(
      builder: (ctx, remediationSvc, _) {
        // Trigger reload ONLY when remediation count increases (new remediation)
        if (remediationSvc.remediationCount > _lastRemediationCount) {
          _lastRemediationCount = remediationSvc.remediationCount;
          Future.microtask(_load);
        }
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: const BoxDecoration(gradient: AppTheme.gradientSecondary,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
              child: Row(children: [
                const Icon(Icons.history_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                const Expanded(child: Text('Remediation History',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14.5))),
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh, color: Colors.white, size: 18)),
              ]),
            ),
            Container(
              color: Colors.white.withValues(alpha: 0.015),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                const Text('Filter:', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                const SizedBox(width: 10),
                for (final s in ['all', 'success', 'failed', 'suppressed', 'simulated'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _FilterChip(label: s, selected: _filterStatus == s, onTap: () => setState(() => _filterStatus = s)),
                  ),
              ]),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                    gradient: AppTheme.panelGradient,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
                    border: Border.all(color: AppTheme.border),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.24), blurRadius: 24, offset: const Offset(0, 10))]),
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
                    : _filtered.isEmpty
                        ? const Center(child: Text('No history yet', style: TextStyle(color: AppTheme.textMuted)))
                        : Theme(data: tableTheme, child: _HistoryTable(history: _filtered)),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label; final bool selected; final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: selected ? AppTheme.accent.withValues(alpha: 0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? AppTheme.accent : AppTheme.border),
      ),
      child: Text(label, style: TextStyle(color: selected ? AppTheme.accent : AppTheme.textMuted, fontSize: 11, fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
    ),
  );
}

class _HistoryTable extends StatelessWidget {
  final List<HistoryEntry> history;
  const _HistoryTable({required this.history});

  @override
  Widget build(BuildContext context) => Scrollbar(
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columnSpacing: 16,
          headingTextStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
          headingRowHeight: 52,
          dataRowMinHeight: 56,
          dataRowMaxHeight: 74,
          horizontalMargin: 18,
          columns: const [
            DataColumn(label: Text('ID')),
            DataColumn(label: Text('Event ID')),
            DataColumn(label: Text('Rule')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Output')),
            DataColumn(label: Text('Event Time')),
            DataColumn(label: Text('Remediation Time')),
          ],
          rows: history.map((h) => DataRow(cells: [
            DataCell(Text('#${h.id}', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12))),
            DataCell(Text('${h.eventId ?? '—'}', style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w600))),
            DataCell(SizedBox(width: 180, child: Text(h.ruleName ?? 'Rule #${h.ruleId}',
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 11),
                maxLines: 2, overflow: TextOverflow.ellipsis))),
            DataCell(StatusBadge(h.status)),
            DataCell(SizedBox(width: 220, child: Tooltip(message: h.output ?? '',
                child: Text(h.output ?? '—',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontFamily: 'monospace'),
                    maxLines: 2, overflow: TextOverflow.ellipsis)))),
            DataCell(Text(_fmtTs(h.eventTimestamp), style: const TextStyle(color: AppTheme.textMuted, fontSize: 11))),
            DataCell(Text(_fmtTs(h.timestamp), style: const TextStyle(color: AppTheme.textMuted, fontSize: 11))),
          ])).toList(),
        ),
      ),
    ),
  );

  String _fmtTs(String? ts) {
    if (ts == null) return '—';
    try { return '${DateTime.parse(ts).toLocal()}'.substring(0, 16); } catch (_) { return ts.length > 16 ? ts.substring(0, 16) : ts; }
  }
}
