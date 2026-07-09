import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Right-edge affordance for horizontally scrollable tables: a gradient fade
/// with a chevron that is visible exactly while more columns exist off-screen
/// to the right, and disappears once the user reaches the end. Complements
/// the persistent scrollbars — the fade sits where the clipped content is,
/// so operators can't mistake a cropped column for the end of the table.
class HorizontalScrollHint extends StatefulWidget {
  final ScrollController controller;
  const HorizontalScrollHint({super.key, required this.controller});

  @override
  State<HorizontalScrollHint> createState() => _HorizontalScrollHintState();
}

class _HorizontalScrollHintState extends State<HorizontalScrollHint> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_update);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_update);
    super.dispose();
  }

  void _update() {
    final c = widget.controller;
    final show = c.hasClients &&
        c.position.maxScrollExtent > 0 &&
        c.position.extentAfter > 2;
    if (show != _show && mounted) setState(() => _show = show);
  }

  @override
  Widget build(BuildContext context) {
    // Content size isn't known until after layout (and changes when rows
    // load), so re-evaluate once this frame has been laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _update();
    });
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _show ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          width: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.transparent,
                AppTheme.bgDeep.withValues(alpha: 0.85),
              ],
            ),
          ),
          child: const Center(
            child: Icon(Icons.chevron_right_rounded, size: 22, color: AppTheme.textMuted),
          ),
        ),
      ),
    );
  }
}
