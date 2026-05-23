import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Enhanced Fluent Stat Card with animated numbers and smooth transitions
class FluentStatCard extends StatefulWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accentColor;
  final String? unit;
  final VoidCallback? onTap;
  final bool animate;

  const FluentStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accentColor = AppTheme.accent,
    this.unit,
    this.onTap,
    this.animate = true,
  });

  @override
  State<FluentStatCard> createState() => _FluentStatCardState();
}

class _FluentStatCardState extends State<FluentStatCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _controller = AnimationController(
        duration: const Duration(milliseconds: 600),
        vsync: this,
      );

      _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeIn),
      );

      _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
      );

      _controller.forward();
    }
  }

  @override
  void dispose() {
    if (widget.animate) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.bgCard,
              _isHovering ? AppTheme.bgCardAlt : AppTheme.bgCard,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: _isHovering ? widget.accentColor.withValues(alpha: 0.3) : AppTheme.border,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: _isHovering
              ? [
                  BoxShadow(
                    color: widget.accentColor.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          widget.label,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: widget.accentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          widget.icon,
                          color: widget.accentColor,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        widget.value,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                      ),
                      if (widget.unit != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          widget.unit!,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.animate) {
      return FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: child,
        ),
      );
    }

    return child;
  }
}

/// Enhanced compact stat badge
class FluentStatBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const FluentStatBadge({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
