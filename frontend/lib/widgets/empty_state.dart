import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Centered empty-state placeholder: a faded icon above the message, with an
/// optional secondary hint line. Replaces the bare grey `Text` empty states
/// so "nothing here" reads as a designed state instead of a rendering gap.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? hint;
  const EmptyState({super.key, required this.icon, required this.message, this.hint});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.border),
          ),
          child: Icon(icon, size: 30, color: AppTheme.textDimmed),
        ),
        const SizedBox(height: 14),
        Text(message,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 13.5, fontWeight: FontWeight.w600)),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(hint!, style: const TextStyle(color: AppTheme.textDimmed, fontSize: 11.5)),
        ],
      ]),
    );
  }
}
