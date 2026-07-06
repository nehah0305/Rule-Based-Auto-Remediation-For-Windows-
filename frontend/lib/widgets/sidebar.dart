import 'package:flutter/material.dart';
import 'dart:ui';
import '../config/theme.dart';

enum AppTab { dashboard, events, rules, approvals, history, simulation, viewer, taskScheduler }

class AppSidebar extends StatefulWidget {
  final AppTab selected;
  final ValueChanged<AppTab> onSelect;
  const AppSidebar({super.key, required this.selected, required this.onSelect});

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  bool _collapsed = false;

  static const _items = [
    (AppTab.dashboard, Icons.dashboard_rounded, 'Dashboard'),
    (AppTab.events, Icons.warning_amber_rounded, 'Warnings & Errors'),
    (AppTab.rules, Icons.rule_rounded, 'Rules'),
    (AppTab.approvals, Icons.check_circle_outline, 'Approvals'),
    (AppTab.history, Icons.history_rounded, 'History'),
    (AppTab.viewer, Icons.event_rounded, 'Event Viewer'),
    (AppTab.simulation, Icons.science_rounded, 'Simulation'),
    (AppTab.taskScheduler, Icons.task_alt_rounded, 'Task Scheduler'),
  ];

  @override
  Widget build(BuildContext context) {
    final w = _collapsed ? 64.0 : 220.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: w,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.025),
        border: const Border(right: BorderSide(color: AppTheme.border)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 24)],
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Column(children: [
            // ── Header: adapts to the ACTUAL width so it never overflows,
            //    even mid-animation between collapsed and expanded states. ──
            Container(
              height: 80,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.white.withValues(alpha: 0.06), Colors.white.withValues(alpha: 0.02)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: const Border(bottom: BorderSide(color: AppTheme.border)),
              ),
              child: LayoutBuilder(builder: (context, cons) {
                final tight = cons.maxWidth < 150;
                final toggle = GestureDetector(
                  onTap: () => setState(() => _collapsed = !_collapsed),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Icon(_collapsed ? Icons.chevron_right : Icons.chevron_left,
                        color: AppTheme.textMuted, size: 18),
                  ),
                );
                final logo = Container(
                  width: tight ? 30 : 36,
                  height: tight ? 30 : 36,
                  decoration: BoxDecoration(
                    gradient: AppTheme.gradientPrimary,
                    borderRadius: BorderRadius.circular(tight ? 10 : 12),
                    boxShadow: [BoxShadow(color: AppTheme.accent.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: Icon(Icons.shield_rounded, color: Colors.white, size: tight ? 17 : 20),
                );
                if (tight) {
                  // Icon-rail layout: logo stacked above the expand toggle.
                  return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    logo,
                    const SizedBox(height: 6),
                    toggle,
                  ]);
                }
                return Row(children: [
                  logo,
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Remediation\nCenter',
                        maxLines: 2,
                        overflow: TextOverflow.clip,
                        softWrap: true,
                        style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w800, height: 1.15)),
                  ),
                  toggle,
                ]);
              }),
            ),
            // Nav items
            Expanded(
              child: ListView(padding: const EdgeInsets.symmetric(vertical: 12), children: [
                for (final item in _items)
                  _NavItem(
                    icon: item.$2, label: item.$3,
                    selected: widget.selected == item.$1,
                    collapsed: _collapsed,
                    onTap: () => widget.onSelect(item.$1),
                  ),
              ]),
            ),
            // Footer
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.02),
                border: const Border(top: BorderSide(color: AppTheme.border)),
              ),
              child: LayoutBuilder(builder: (context, cons) {
                final tight = cons.maxWidth < 150;
                if (tight) {
                  return const Center(child: Icon(Icons.security, color: AppTheme.textDimmed, size: 14));
                }
                return const Row(children: [
                  Icon(Icons.security, color: AppTheme.textDimmed, size: 14),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Unisys AB',
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        softWrap: false,
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                ]);
              }),
            ),
          ]),
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;
  const _NavItem({required this.icon, required this.label, required this.selected,
    required this.collapsed, required this.onTap});

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected;
    return LayoutBuilder(builder: (context, cons) {
      // Adapt to the actual width (not just the collapsed flag) so the row
      // never overflows while the sidebar width is animating.
      final tight = cons.maxWidth < 120;
      final iconBox = Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: active ? AppTheme.accent.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(widget.icon,
            size: 16,
            color: active ? AppTheme.accent : _hovered ? AppTheme.textPrimary : AppTheme.textMuted),
      );
      final item = MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit:  (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            padding: EdgeInsets.symmetric(horizontal: tight ? 0 : 14, vertical: 12),
            decoration: BoxDecoration(
              color: active ? AppTheme.accent.withValues(alpha: 0.14) : Colors.transparent,
              gradient: !active && _hovered
                  ? LinearGradient(colors: [Colors.white.withValues(alpha: 0.08), Colors.white.withValues(alpha: 0.03)])
                  : null,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: active ? AppTheme.accent.withValues(alpha: 0.45) : Colors.transparent),
              boxShadow: active ? [BoxShadow(color: AppTheme.accent.withValues(alpha: 0.16), blurRadius: 18, offset: const Offset(0, 6))] : null,
            ),
            child: Row(
              mainAxisAlignment: tight ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                iconBox,
                if (!tight) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        softWrap: false,
                        style: TextStyle(
                          color: active ? AppTheme.textPrimary : _hovered ? AppTheme.textPrimary : AppTheme.textMuted,
                          fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
      // Icon-only rail: show the label as a tooltip instead.
      return tight ? Tooltip(message: widget.label, waitDuration: const Duration(milliseconds: 350), child: item) : item;
    });
  }
}
