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
  List<ApprovalRequest> _requests = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _requests = await _api.getRequests(status: 'pending');
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _approve(int id) async {
    try {
      await _api.approveRequest(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request approved and remediation executed!')));
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _deny(int id) async {
    try {
      await _api.denyRequest(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request denied.')));
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: const BoxDecoration(gradient: AppTheme.gradientWarning,
              borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
          child: Row(children: [
            const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            const Expanded(child: Text('Pending Approval Requests',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14))),
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh, color: Colors.white, size: 18)),
          ]),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(color: AppTheme.bgCard,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                border: Border.all(color: AppTheme.border)),
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
                : _requests.isEmpty
                    ? _EmptyState()
                    : _ApprovalsTable(requests: _requests, onApprove: _approve, onDeny: _deny),
          ),
        ),
      ]),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.inbox_rounded, size: 48, color: AppTheme.textDimmed),
    SizedBox(height: 12),
    Text('No pending approval requests',
        style: TextStyle(color: AppTheme.textMuted, fontSize: 14)),
  ]));
}

class _ApprovalsTable extends StatelessWidget {
  final List<ApprovalRequest> requests;
  final Future<void> Function(int) onApprove;
  final Future<void> Function(int) onDeny;
  const _ApprovalsTable({required this.requests, required this.onApprove, required this.onDeny});

  @override
  Widget build(BuildContext context) => Scrollbar(
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columnSpacing: 16,
          headingRowColor: const WidgetStatePropertyAll(Color(0xFF181830)),
          headingTextStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
          columns: const [
            DataColumn(label: Text('ID')),
            DataColumn(label: Text('Event ID')),
            DataColumn(label: Text('Rule')),
            DataColumn(label: Text('Requested By')),
            DataColumn(label: Text('Requested At')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Actions')),
          ],
          rows: requests.map((r) => DataRow(cells: [
            DataCell(Text('#${r.id}', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12))),
            DataCell(Text('${r.eventId ?? '—'}', style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w600))),
            DataCell(SizedBox(width: 180, child: Text(r.ruleName ?? 'Rule #${r.ruleId}',
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                maxLines: 2, overflow: TextOverflow.ellipsis))),
            DataCell(Text(r.requestedBy ?? '—', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12))),
            DataCell(Text(_fmtTs(r.requestedAt), style: const TextStyle(color: AppTheme.textMuted, fontSize: 11))),
            DataCell(StatusBadge(r.status)),
            DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
              _Btn(label: 'Approve', icon: Icons.thumb_up_rounded, color: AppTheme.accentGreen, onTap: () => onApprove(r.id)),
              const SizedBox(width: 8),
              _Btn(label: 'Deny', icon: Icons.thumb_down_rounded, color: AppTheme.accentRed, onTap: () => onDeny(r.id)),
            ])),
          ])).toList(),
        ),
      ),
    ),
  );

  String _fmtTs(String? ts) {
    if (ts == null) return '—';
    try { return '${DateTime.parse(ts).toLocal()}'.substring(0, 16); } catch (_) { return ts; }
  }
}

class _Btn extends StatelessWidget {
  final String label; final IconData icon; final Color color; final VoidCallback onTap;
  const _Btn({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 13, color: color),
    label: Text(label, style: TextStyle(color: color, fontSize: 11)),
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
  );
}
