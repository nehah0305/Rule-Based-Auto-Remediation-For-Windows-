import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Windows 11 Fluent Design Card with hover effect and smooth animations
class FluentCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double? height;
  final Color? backgroundColor;
  final bool interactive;
  final BorderRadius? borderRadius;
  final List<BoxShadow>? shadows;

  const FluentCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.height,
    this.backgroundColor,
    this.interactive = true,
    this.borderRadius,
    this.shadows,
  });

  @override
  State<FluentCard> createState() => _FluentCardState();
}

class _FluentCardState extends State<FluentCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _shadowAnimation;
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _shadowAnimation = Tween<double>(begin: 0.2, end: 0.35).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onEnter() {
    if (widget.interactive && widget.onTap != null) {
      setState(() => _isHovering = true);
      _controller.forward();
    }
  }

  void _onExit() {
    if (widget.interactive && widget.onTap != null) {
      setState(() => _isHovering = false);
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _onEnter(),
      onExit: (_) => _onExit(),
      cursor: widget.interactive && widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: AnimatedBuilder(
          animation: _shadowAnimation,
          builder: (context, child) {
            return Container(
              height: widget.height,
              decoration: BoxDecoration(
                color: widget.backgroundColor ?? AppTheme.bgCard,
                borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
                border: Border.all(
                  color: _isHovering ? AppTheme.accent.withValues(alpha: 0.3) : AppTheme.border,
                  width: 1,
                ),
                boxShadow: widget.shadows ?? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: _shadowAnimation.value),
                    blurRadius: _isHovering ? 16 : 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onTap,
                  borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
                  child: Padding(
                    padding: widget.padding,
                    child: widget.child,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
