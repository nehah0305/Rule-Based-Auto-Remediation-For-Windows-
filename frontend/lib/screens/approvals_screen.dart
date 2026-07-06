import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/api_service.dart';
import '../models/approval_request.dart';
import '../widgets/badges.dart';

class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});
  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  final _api = ApiService();
  bool _loading = true;
  List<ApprovalGateRequest> _all = [];
  String _filter = 'all';
  final Set<int> _acting = {};
  final _scrollController = ScrollController();
  final _verticalScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _api.getApprovals();
      if (mounted) setState(() { _all = data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _all = []; _loading = false; });
    }
  }

  List<ApprovalGateRequest> get _filtered {
    if (_filter == 'all') return _all;
    return _all.where((r) => r.status == _filter).toList();
  }

  Future<void> _approve(ApprovalGateRequest r) async {
    setState(() => _acting.add(r.id));
    try {
      await _api.approveApprovalRequest(r.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Approved — running remediation for Event ${r.eventId} (${r.ruleName}).'),
          backgroundColor: AppTheme.accentGreen,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Approve failed: $e'), backgroundColor: AppTheme.accentRed));
      }
    } finally {
      if (mounted) setState(() => _acting.remove(r.id));
    }
  }

  Future<void> _reject(ApprovalGateRequest r) async {
    setState(() => _acting.add(r.id));
    try {
      await _api.rejectApprovalRequest(r.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Rejected Event ${r.eventId} (${r.ruleName}).'),
          backgroundColor: AppTheme.textMuted,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reject failed: $e'), backgroundColor: AppTheme.accentRed));
      }
    } finally {
      if (mounted) setState(() => _acting.remove(r.id));
    }
  }

  String _fmtTs(String? ts) {
    if (ts == null || ts.isEmpty) return '—';
    try {
      final dt = DateTime.parse(ts);
      return '${dt.toLocal()}'.substring(0, 16);
    } catch (_) {
      return ts.length > 16 ? ts.substring(0, 16) : ts;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              gradient: AppTheme.gradientSecondary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.check_circle_outline, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Approval Queue', style: TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w800)),
              SizedBox(height: 2),
              Text('Operator sign-off for new event types before auto-remediation activates',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
            ]),
          ),
          _RefreshBtn(loading: _loading, onTap: _load),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          _FilterChip(label: 'All', value: 'all', selected: _filter, onTap: (v) => setState(() => _filter = v)),
          const SizedBox(width: 8),
          _FilterChip(label: 'Pending', value: 'pending', selected: _filter, onTap: (v) => setState(() => _filter = v)),
          const SizedBox(width: 8),
          _FilterChip(label: 'Approved', value: 'approved', selected: _filter, onTap: (v) => setState(() => _filter = v)),
          const SizedBox(width: 8),
          _FilterChip(label: 'Rejected', value: 'rejected', selected: _filter, onTap: (v) => setState(() => _filter = v)),
        ]),
        const SizedBox(height: 18),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              gradient: AppTheme.panelGradient,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
            ),
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
                : rows.isEmpty
                    ? const Center(
                        child: Text('No approval requests in this view.', style: TextStyle(color: AppTheme.textMuted)))
                    : Scrollbar(
                        controller: _verticalScrollController,
                        thumbVisibility: true,
                        trackVisibility: true,
                        child: SingleChildScrollView(
                          controller: _verticalScrollController,
                          scrollDirection: Axis.vertical,
                          child: Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        trackVisibility: true,
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.only(bottom: 12), // space for scrollbar
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 88),
                          child: DataTable(
                            columnSpacing: 20,
                            headingTextStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
                            headingRowHeight: 48,
                            dataRowMinHeight: 52,
                            dataRowMaxHeight: 64,
                            horizontalMargin: 18,
                            columns: const [
                              DataColumn(label: Text('Event ID')),
                              DataColumn(label: Text('Name')),
                              DataColumn(label: Text('Source')),
                              DataColumn(label: Text('Rule')),
                              DataColumn(label: Text('Severity')),
                              DataColumn(label: Text('Status')),
                              DataColumn(label: Text('Received')),
                              DataColumn(label: Text('Action')),
                            ],
                            rows: rows.map((r) => DataRow(cells: [
                              DataCell(Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppTheme.accent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(r.eventId,
                                    style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w700, fontSize: 12)),
                              )),
                              // Application column — the key new addition
                              DataCell(r.appContext.isNotEmpty
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppTheme.accentYellow.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(r.appContext,
                                          style: const TextStyle(
                                              color: AppTheme.accentYellow, fontWeight: FontWeight.w600, fontSize: 11.5)),
                                    )
                                  : const Text('—', style: TextStyle(color: AppTheme.textDimmed, fontSize: 12))),
                              DataCell(Text(r.source, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12))),
                              DataCell(SizedBox(width: 150, child: Text(r.ruleName,
                                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                                  overflow: TextOverflow.ellipsis))),
                              DataCell(SeverityBadge(r.severity)),
                              DataCell(StatusBadge(r.status)),
                              DataCell(Text(_fmtTs(r.createdAt), style: const TextStyle(color: AppTheme.textMuted, fontSize: 11.5))),
                              DataCell(r.status == 'pending'
                                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                                      _ActionBtn(
                                        label: 'Approve', color: AppTheme.accentGreen,
                                        loading: _acting.contains(r.id),
                                        onTap: () => _approve(r),
                                      ),
                                      const SizedBox(width: 8),
                                      _ActionBtn(
                                        label: 'Reject', color: AppTheme.accentRed,
                                        loading: _acting.contains(r.id),
                                        onTap: () => _reject(r),
                                      ),
                                    ])
                                  : Text(
                                      'Resolved ${_fmtTs(r.resolvedAt)}',
                                      style: const TextStyle(color: AppTheme.textDimmed, fontSize: 11.5),
                                    )),
                            ])).toList(),
                          ),
                        ),
                      ),
                    ), // Close horizontal Scrollbar
                        ),
                      ), // Close vertical Scrollbar
          ),
        ),
      ]),
    );
  }
}

class _RefreshBtn extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;
  const _RefreshBtn({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.refresh_rounded, size: 15, color: AppTheme.textPrimary),
          const SizedBox(width: 6),
          const Text('Refresh', style: TextStyle(color: AppTheme.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String value;
  final String selected;
  final void Function(String) onTap;
  const _FilterChip({required this.label, required this.value, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isSelected = value == selected;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accent : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: isSelected ? AppTheme.accent : AppTheme.border),
        ),
        child: Text(label,
            style: TextStyle(
              color: isSelected ? Colors.white : AppTheme.textMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            )),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final bool loading;
  final VoidCallback onTap;
  const _ActionBtn({required this.label, required this.color, required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(loading ? '…' : label,
            style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
