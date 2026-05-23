import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
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
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  bool _loading = true;
  int _lastRemediationCount = 0;

  List<HistoryEntry> _history = [];
  int _total = 0;
  bool _hasMore = false;

  // Pagination
  static const _pageSize = 50;
  int _page = 0;

  // Filters
  String _filterStatus = 'all';
  String _search = '';
  String _sortCol = 'id';
  String _sortDir = 'DESC';

  // Date range
  DateTimeRange? _dateRange;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load({bool resetPage = true}) async {
    if (!mounted) return;
    if (resetPage) _page = 0;
    setState(() => _loading = true);
    try {
      final data = await _api.getHistory(
        limit: _pageSize,
        offset: _page * _pageSize,
        status: _filterStatus == 'all' ? null : _filterStatus,
        search: _search.isEmpty ? null : _search,
        sort: _sortCol,
        dir: _sortDir,
      );
      if (!mounted) return;
      setState(() {
        _history = data['items'] as List<HistoryEntry>;
        _total   = data['total'] as int;
        _hasMore = data['has_more'] as bool;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _history = []; _loading = false; });
    }
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _search = v;
      _load();
    });
  }

  void _onSort(String col) {
    setState(() {
      if (_sortCol == col) {
        _sortDir = _sortDir == 'DESC' ? 'ASC' : 'DESC';
      } else {
        _sortCol = col;
        _sortDir = 'DESC';
      }
    });
    _load();
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _dateRange,
      builder: (ctx, child) => Theme(
        data: AppTheme.dark,
        child: child!,
      ),
    );
    if (range != null) {
      setState(() => _dateRange = range);
      _load();
    }
  }

  void _clearDateRange() {
    setState(() => _dateRange = null);
    _load();
  }

  void _openExport() {
    final url = _api.getHistoryExportUrl(
      status: _filterStatus == 'all' ? null : _filterStatus,
      search: _search.isEmpty ? null : _search,
    );
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Export CSV', style: TextStyle(color: AppTheme.textPrimary)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Copy this URL and open it in your browser to download the CSV file:',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFF050510), borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border)),
            child: SelectableText(url,
                style: const TextStyle(color: AppTheme.accentGreen, fontSize: 11, fontFamily: 'monospace')),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('CSV URL copied to clipboard!'),
                backgroundColor: AppTheme.accentGreen,
                behavior: SnackBarBehavior.floating,
                margin: EdgeInsets.all(16),
              ));
            },
            icon: const Icon(Icons.copy, size: 14),
            label: const Text('Copy URL'),
          ),
        ],
      ),
    );
  }

  void _showOutput(HistoryEntry h) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 560),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                gradient: AppTheme.gradientSecondary,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(children: [
                StatusBadge(h.status),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  'Rule: ${h.ruleName ?? '#${h.ruleId}'} — Event ${h.eventId}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                )),
                IconButton(onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white, size: 16)),
              ]),
            ),
            Expanded(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Text('Remediation Time: ', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  Text(_fmtTs(h.timestamp), style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  const Text('Event Time: ', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  Text(_fmtTs(h.eventTimestamp), style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
                ]),
                const SizedBox(height: 12),
                const Text('Script Output:', style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Expanded(child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFF050510), borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.border)),
                  child: Scrollbar(child: SingleChildScrollView(
                    child: SelectableText(
                      h.output ?? '(no output)',
                      style: const TextStyle(color: Color(0xFF00ff88), fontSize: 11, fontFamily: 'monospace', height: 1.5),
                    ),
                  )),
                )),
              ]),
            )),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RemediationService>(
      builder: (ctx, remediationSvc, _) {
        if (remediationSvc.remediationCount > _lastRemediationCount) {
          _lastRemediationCount = remediationSvc.remediationCount;
          Future.microtask(_load);
        }
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            // ── Header ─────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: const BoxDecoration(gradient: AppTheme.gradientSecondary,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
              child: Row(children: [
                const Icon(Icons.history_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Remediation History',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14.5)),
                  if (!_loading)
                    Text('$_total record${_total == 1 ? '' : 's'} total',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 11)),
                ])),
                // Export CSV
                TextButton.icon(
                  onPressed: _openExport,
                  icon: const Icon(Icons.download_rounded, size: 14, color: Colors.white),
                  label: const Text('Export CSV', style: TextStyle(color: Colors.white, fontSize: 12)),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh, color: Colors.white, size: 18)),
              ]),
            ),

            // ── Filters bar ─────────────────────────────────────────────────
            Container(
              color: Colors.white.withValues(alpha: 0.015),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                // Search
                Expanded(
                  child: SizedBox(
                    height: 34,
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: _onSearchChanged,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search rule, event ID, source…',
                        hintStyle: const TextStyle(fontSize: 11, color: AppTheme.textDimmed),
                        prefixIcon: const Icon(Icons.search, size: 16, color: AppTheme.textDimmed),
                        contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.border)),
                        suffixIcon: _search.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 14),
                                onPressed: () { _searchCtrl.clear(); _search = ''; _load(); },
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Status chips
                for (final s in ['all', 'success', 'failed', 'suppressed'])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _FilterChip(
                      label: s, selected: _filterStatus == s,
                      onTap: () { setState(() => _filterStatus = s); _load(); },
                    ),
                  ),
                // Date range
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: _pickDateRange,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _dateRange != null ? AppTheme.accent.withValues(alpha: 0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _dateRange != null ? AppTheme.accent : AppTheme.border),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.date_range, size: 13,
                          color: _dateRange != null ? AppTheme.accent : AppTheme.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        _dateRange != null
                            ? '${_fmtDate(_dateRange!.start)} – ${_fmtDate(_dateRange!.end)}'
                            : 'Date',
                        style: TextStyle(fontSize: 11,
                            color: _dateRange != null ? AppTheme.accent : AppTheme.textMuted),
                      ),
                      if (_dateRange != null) ...[ 
                        const SizedBox(width: 4),
                        GestureDetector(onTap: _clearDateRange,
                            child: const Icon(Icons.close, size: 11, color: AppTheme.accent)),
                      ],
                    ]),
                  ),
                ),
              ]),
            ),

            // ── Table ────────────────────────────────────────────────────────
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                    gradient: AppTheme.panelGradient,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
                    border: Border.all(color: AppTheme.border),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.24), blurRadius: 24, offset: const Offset(0, 10))]),
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
                    : _history.isEmpty
                        ? const Center(child: Text('No history found', style: TextStyle(color: AppTheme.textMuted)))
                        : Column(children: [
                            Expanded(child: _HistoryTable(
                              history: _history,
                              sortCol: _sortCol,
                              sortDir: _sortDir,
                              onSort: _onSort,
                              onRowTap: _showOutput,
                            )),
                            // Pagination footer
                            _PaginationBar(
                              page: _page, pageSize: _pageSize, total: _total, hasMore: _hasMore,
                              onPrev: _page > 0 ? () { _page--; _load(resetPage: false); } : null,
                              onNext: _hasMore ? () { _page++; _load(resetPage: false); } : null,
                            ),
                          ]),
              ),
            ),
          ]),
        );
      },
    );
  }

  String _fmtTs(String? ts) {
    if (ts == null) return '—';
    try { return '${DateTime.parse(ts).toLocal()}'.substring(0, 16); } catch (_) { return ts.length > 16 ? ts.substring(0, 16) : ts; }
  }

  String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
}

// ── Sort-able table ────────────────────────────────────────────────────────────
class _HistoryTable extends StatelessWidget {
  final List<HistoryEntry> history;
  final String sortCol, sortDir;
  final void Function(String col) onSort;
  final void Function(HistoryEntry) onRowTap;
  const _HistoryTable({required this.history, required this.sortCol, required this.sortDir,
      required this.onSort, required this.onRowTap});

  @override
  Widget build(BuildContext context) => Scrollbar(
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columnSpacing: 16,
          headingTextStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
          headingRowHeight: 52,
          dataRowMinHeight: 52,
          dataRowMaxHeight: 64,
          horizontalMargin: 18,
          columns: [
            _sortCol('id',        'ID'),
            _sortCol('event_id',  'Event ID'),
            const DataColumn(label: Text('Rule')),
            _sortCol('status',    'Status'),
            const DataColumn(label: Text('Output')),
            _sortCol('timestamp', 'Remediation Time'),
            const DataColumn(label: Text('Event Time')),
          ],
          rows: history.map((h) => DataRow(
            onSelectChanged: (_) => onRowTap(h),
            cells: [
              DataCell(Text('#${h.id}', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12))),
              DataCell(Text('${h.eventId ?? '—'}',
                  style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w600))),
              DataCell(SizedBox(width: 180, child: Text(h.ruleName ?? 'Rule #${h.ruleId}',
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 11),
                  maxLines: 2, overflow: TextOverflow.ellipsis))),
              DataCell(StatusBadge(h.status)),
              DataCell(SizedBox(width: 200, child: Tooltip(
                message: h.output ?? '',
                child: Text(h.output ?? '—',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontFamily: 'monospace'),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ))),
              DataCell(Text(_fmtTs(h.timestamp), style: const TextStyle(color: AppTheme.textMuted, fontSize: 11))),
              DataCell(Text(_fmtTs(h.eventTimestamp), style: const TextStyle(color: AppTheme.textMuted, fontSize: 11))),
            ],
          )).toList(),
        ),
      ),
    ),
  );

  DataColumn _sortCol(String col, String label) => DataColumn(
    label: InkWell(
      onTap: () => onSort(col),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label),
        const SizedBox(width: 4),
        Icon(
          sortCol == col ? (sortDir == 'DESC' ? Icons.arrow_downward : Icons.arrow_upward) : Icons.unfold_more,
          size: 13,
          color: sortCol == col ? AppTheme.accent : AppTheme.textDimmed,
        ),
      ]),
    ),
  );

  String _fmtTs(String? ts) {
    if (ts == null) return '—';
    try { return '${DateTime.parse(ts).toLocal()}'.substring(0, 16); } catch (_) { return ts.length > 16 ? ts.substring(0, 16) : ts; }
  }
}

// ── Pagination bar ─────────────────────────────────────────────────────────────
class _PaginationBar extends StatelessWidget {
  final int page, pageSize, total;
  final bool hasMore;
  final VoidCallback? onPrev, onNext;
  const _PaginationBar({required this.page, required this.pageSize, required this.total,
      required this.hasMore, this.onPrev, this.onNext});

  @override
  Widget build(BuildContext context) {
    final from = total == 0 ? 0 : page * pageSize + 1;
    final to   = (page * pageSize + pageSize).clamp(0, total);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: AppTheme.border))),
      child: Row(children: [
        Text('Showing $from–$to of $total',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        const Spacer(),
        _PagBtn(icon: Icons.chevron_left, onTap: onPrev, label: 'Prev'),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: AppTheme.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6), border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4))),
          child: Text('Page ${page + 1}', style: const TextStyle(color: AppTheme.accent, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 8),
        _PagBtn(icon: Icons.chevron_right, onTap: onNext, label: 'Next'),
      ]),
    );
  }
}

class _PagBtn extends StatelessWidget {
  final IconData icon; final VoidCallback? onTap; final String label;
  const _PagBtn({required this.icon, this.onTap, required this.label});

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 16),
    label: Text(label, style: const TextStyle(fontSize: 12)),
    style: TextButton.styleFrom(
      foregroundColor: onTap != null ? AppTheme.accent : AppTheme.textDimmed,
      backgroundColor: onTap != null ? AppTheme.accent.withValues(alpha: 0.08) : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}

// ── Filter chip ─────────────────────────────────────────────────────────────────
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
      child: Text(label, style: TextStyle(
          color: selected ? AppTheme.accent : AppTheme.textMuted,
          fontSize: 11, fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
    ),
  );
}
