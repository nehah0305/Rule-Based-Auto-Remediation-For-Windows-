import 'package:flutter/material.dart';
import '../config/theme.dart';

class SimulationTimeline extends StatelessWidget {
  final List<Map<String, dynamic>> steps;
  const SimulationTimeline({super.key, required this.steps});

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Run the simulation to see step-by-step flow.',
            style: TextStyle(color: AppTheme.textMuted)),
      );
    }
    return Column(
      children: steps.asMap().entries.map((e) => _TimelineStep(
        index: e.key, step: e.value, isLast: e.key == steps.length - 1,
      )).toList(),
    );
  }
}

class _TimelineStep extends StatelessWidget {
  final int index;
  final Map<String, dynamic> step;
  final bool isLast;
  const _TimelineStep({required this.index, required this.step, required this.isLast});

  Color _statusColor(String s) {
    switch (s) {
      case 'completed': return AppTheme.accentGreen;
      case 'success':   return AppTheme.accentGreen;
      case 'failed':    return AppTheme.accentRed;
      case 'warning':   return AppTheme.accentYellow;
      case 'suppressed':return AppTheme.accentPurple;
      case 'simulated': return AppTheme.accent;
      default:          return AppTheme.accent;
    }
  }

  IconData _statusIcon(String s) {
    switch (s) {
      case 'completed':  return Icons.check_circle;
      case 'success':    return Icons.check_circle;
      case 'failed':     return Icons.cancel;
      case 'warning':    return Icons.warning_amber;
      case 'suppressed': return Icons.pause_circle;
      case 'simulated':  return Icons.science;
      default:           return Icons.radio_button_unchecked;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = step['status'] as String? ?? '';
    final color  = _statusColor(status);
    final phase  = step['phase']  as String? ?? '';
    final title  = step['title']  as String? ?? '';
    final detail = step['detail'] as String? ?? '';

    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Line + dot
        Column(children: [
          Icon(_statusIcon(status), color: color, size: 18),
          if (!isLast)
            Expanded(child: Container(width: 2, color: AppTheme.border.withValues(alpha: 0.5), margin: const EdgeInsets.symmetric(vertical: 2))),
        ]),
        const SizedBox(width: 12),
        // Content
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(phase.toUpperCase(),
                      style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(title,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600))),
              ]),
              if (detail.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(detail, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, height: 1.4)),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

class TerminalOutput extends StatelessWidget {
  final String output;
  const TerminalOutput({super.key, required this.output});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 280),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF050510),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          output.isEmpty ? 'No output yet.' : output,
          style: const TextStyle(
            fontFamily: 'monospace', fontSize: 11.5,
            color: Color(0xFF00ff88), height: 1.6,
          ),
        ),
      ),
    );
  }
}
