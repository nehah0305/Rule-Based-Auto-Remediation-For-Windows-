import 'package:flutter/material.dart';
import '../config/theme.dart';

class SeverityBadge extends StatelessWidget {
  final String? severity;
  const SeverityBadge(this.severity, {super.key});

  @override
  Widget build(BuildContext context) {
    final s = severity ?? '';
    Color bg; IconData icon;
    switch (s.toLowerCase()) {
      case 'critical': bg = AppTheme.accentRed;    icon = Icons.error;             break;
      case 'high':     bg = const Color(0xFFfd7e14); icon = Icons.warning_amber;   break;
      case 'medium':   bg = AppTheme.accent;        icon = Icons.info_outline;     break;
      case 'low':      bg = AppTheme.textMuted;     icon = Icons.circle_outlined;  break;
      default:         bg = AppTheme.textDimmed;    icon = Icons.help_outline;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20),
        border: Border.all(color: bg.withValues(alpha: 0.6))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: bg),
        const SizedBox(width: 4),
        Text(s.isEmpty ? 'Unknown' : s,
            style: TextStyle(fontSize: 11, color: bg, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class StatusBadge extends StatelessWidget {
  final String? status;
  const StatusBadge(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final s = status ?? '';
    Color bg; IconData icon; String label;
    switch (s.toLowerCase()) {
      case 'success':    bg = AppTheme.accentGreen;  icon = Icons.check_circle; label = 'Success'; break;
      case 'failed':
      case 'error':      bg = AppTheme.accentRed;    icon = Icons.cancel;       label = s == 'failed' ? 'Failed' : 'Error'; break;
      case 'pending':    bg = AppTheme.accentYellow; icon = Icons.schedule;     label = 'Pending'; break;
      case 'approved':   bg = AppTheme.accentGreen;  icon = Icons.thumb_up;     label = 'Approved'; break;
      case 'denied':     bg = AppTheme.textMuted;    icon = Icons.block;        label = 'Denied'; break;
      case 'rejected':   bg = AppTheme.accentRed;    icon = Icons.block;        label = 'Rejected'; break;
      case 'skipped':    bg = AppTheme.accent;       icon = Icons.skip_next;    label = 'Skipped'; break;
      case 'suppressed': bg = AppTheme.accentPurple; icon = Icons.pause_circle; label = 'Suppressed'; break;
      case 'simulated':  bg = const Color(0xFF17a2b8); icon = Icons.science;   label = 'Simulated'; break;
      case 'completed':  bg = AppTheme.accentGreen;  icon = Icons.done_all;    label = 'Completed'; break;
      case 'warning':    bg = const Color(0xFFfd7e14); icon = Icons.warning;   label = 'Warning'; break;
      case 'executing':  bg = const Color(0xFF17a2b8); icon = Icons.play_circle_outline; label = 'Executing'; break;
      case 'verifying':  bg = AppTheme.accentYellow; icon = Icons.hourglass_top; label = 'Verifying'; break;
      case 'rolled_back': bg = const Color(0xFFfd7e14); icon = Icons.undo;     label = 'Rolled Back'; break;
      case 'verification_failed': bg = AppTheme.accentRed; icon = Icons.report_problem; label = 'Verify Failed'; break;
      case 'pending_approval': bg = AppTheme.accentYellow; icon = Icons.schedule; label = 'Pending Approval'; break;
      default:           bg = AppTheme.textDimmed;   icon = Icons.circle;      label = s.isEmpty ? '—' : s;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20),
        border: Border.all(color: bg.withValues(alpha: 0.6))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: bg),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: bg, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class ConfidenceBadge extends StatelessWidget {
  final double score;
  const ConfidenceBadge(this.score, {super.key});

  @override
  Widget build(BuildContext context) {
    if (score <= 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: AppTheme.textDimmed.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20)),
        child: const Text('—', style: TextStyle(fontSize: 11, color: AppTheme.textDimmed)),
      );
    }
    Color bg = score >= 70 ? AppTheme.accentRed
        : score >= 40 ? const Color(0xFFfd7e14)
        : AppTheme.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20),
        border: Border.all(color: bg.withValues(alpha: 0.5))),
      child: Text(score.toStringAsFixed(0),
          style: TextStyle(fontSize: 11, color: bg, fontWeight: FontWeight.w700)),
    );
  }
}

class CategoryBadge extends StatelessWidget {
  final String? category;
  const CategoryBadge(this.category, {super.key});

  @override
  Widget build(BuildContext context) {
    if (category == null || category!.isEmpty) {
      return const SizedBox.shrink();
    }
    final c = category!.toLowerCase();
    Color bg; IconData icon;
    if (c.contains('service') || c.contains('crash'))   { bg = const Color(0xFFe67e22); icon = Icons.settings; }
    else if (c.contains('disk') || c.contains('space'))  { bg = const Color(0xFF3498db); icon = Icons.storage; }
    else if (c.contains('secur') || c.contains('auth'))  { bg = AppTheme.accentRed;     icon = Icons.lock; }
    else if (c.contains('network') || c.contains('dns')) { bg = AppTheme.accent;         icon = Icons.lan; }
    else if (c.contains('memory') || c.contains('ram'))  { bg = AppTheme.accentPurple;  icon = Icons.memory; }
    else if (c.contains('cpu') || c.contains('high'))    { bg = const Color(0xFFe74c3c); icon = Icons.speed; }
    else if (c.contains('app') || c.contains('program')) { bg = AppTheme.accentGreen;   icon = Icons.apps; }
    else if (c.contains('audit') || c.contains('log'))   { bg = const Color(0xFF1abc9c); icon = Icons.article; }
    else { bg = AppTheme.textMuted; icon = Icons.label_outline; }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20),
        border: Border.all(color: bg.withValues(alpha: 0.4))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 10, color: bg),
        const SizedBox(width: 4),
        Text(category!, style: TextStyle(fontSize: 10, color: bg, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class LevelBadge extends StatelessWidget {
  final String? level;
  const LevelBadge(this.level, {super.key});

  @override
  Widget build(BuildContext context) {
    final l = (level ?? '').toLowerCase();
    Color bg; String label;
    if (l == 'error')        { bg = AppTheme.accentRed;           label = 'Error'; }
    else if (l == 'warning') { bg = AppTheme.accentYellow;         label = 'Warning'; }
    else                     { bg = AppTheme.textDimmed;            label = level ?? 'Unknown'; }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20),
        border: Border.all(color: bg.withValues(alpha: 0.6))),
      child: Text(label, style: TextStyle(fontSize: 11, color: bg, fontWeight: FontWeight.w600)),
    );
  }
}
