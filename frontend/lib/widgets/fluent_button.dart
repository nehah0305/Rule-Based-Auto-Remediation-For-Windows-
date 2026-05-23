import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Enhanced Fluent Button with ripple and smooth transitions
class FluentButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool isDisabled;
  final Color? backgroundColor;
  final ButtonVariant variant;
  final double? width;

  const FluentButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.isDisabled = false,
    this.backgroundColor,
    this.variant = ButtonVariant.primary,
    this.width,
  });

  @override
  State<FluentButton> createState() => _FluentButtonState();
}

enum ButtonVariant { primary, secondary, danger, success }

class _FluentButtonState extends State<FluentButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 150), vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _getBackgroundColor() {
    if (widget.isDisabled) return AppTheme.border;
    switch (widget.variant) {
      case ButtonVariant.primary:
        return widget.backgroundColor ?? AppTheme.accent;
      case ButtonVariant.secondary:
        return AppTheme.bgCardAlt;
      case ButtonVariant.danger:
        return AppTheme.accentRed;
      case ButtonVariant.success:
        return AppTheme.accentGreen;
    }
  }

  Color _getTextColor() {
    if (widget.variant == ButtonVariant.secondary) return AppTheme.textPrimary;
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: ScaleTransition(
        scale: Tween<double>(begin: 1.0, end: 0.96).animate(_controller),
        child: ElevatedButton(
          onPressed: widget.isDisabled || widget.isLoading ? null : () {
            _controller.forward().then((_) => _controller.reverse());
            widget.onPressed();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: _getBackgroundColor(),
            foregroundColor: _getTextColor(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            elevation: 0,
          ),
          child: widget.isLoading
              ? SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(_getTextColor()),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, size: 16),
                      const SizedBox(width: 8),
                    ],
                    Text(widget.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Animated Status Badge with pulse effect
class FluentStatusBadge extends StatefulWidget {
  final String label;
  final BadgeStatus status;
  final VoidCallback? onTap;

  const FluentStatusBadge({
    super.key,
    required this.label,
    required this.status,
    this.onTap,
  });

  @override
  State<FluentStatusBadge> createState() => _FluentStatusBadgeState();
}

enum BadgeStatus { active, pending, completed, error, warning }

class _FluentStatusBadgeState extends State<FluentStatusBadge> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Color _getStatusColor() {
    switch (widget.status) {
      case BadgeStatus.active:
        return AppTheme.accentGreen;
      case BadgeStatus.pending:
        return AppTheme.accentYellow;
      case BadgeStatus.completed:
        return AppTheme.accentGreen;
      case BadgeStatus.error:
        return AppTheme.accentRed;
      case BadgeStatus.warning:
        return AppTheme.accentOrange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _getStatusColor().withValues(alpha: 0.15),
          border: Border.all(color: _getStatusColor(), width: 1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: Tween<double>(begin: 1.0, end: 1.3).animate(
                CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
              ),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _getStatusColor(),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              widget.label,
              style: TextStyle(
                color: _getStatusColor(),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
