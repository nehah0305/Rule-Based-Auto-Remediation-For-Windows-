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
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: AppTheme.gradientPrimary,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: AppTheme.accent.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: const Icon(Icons.shield_rounded, color: Colors.white, size: 20),
            ),
            if (!_collapsed) ...[
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Remediation\nCenter',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w800, height: 1.15)),
              ),
            ],
            GestureDetector(
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
            ),
          ]),
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
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            border: const Border(top: BorderSide(color: AppTheme.border)),
          ),
          child: Row(children: [
            const Icon(Icons.security, color: AppTheme.textDimmed, size: 14),
            if (!_collapsed) ...[
              const SizedBox(width: 8),
              const Text('Unisys AB', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ]),
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
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          padding: EdgeInsets.symmetric(horizontal: widget.collapsed ? 12 : 14, vertical: 12),
          decoration: BoxDecoration(
            color: active ? AppTheme.accent.withValues(alpha: 0.14) : Colors.transparent,
            gradient: !active && _hovered
                ? LinearGradient(colors: [Colors.white.withValues(alpha: 0.08), Colors.white.withValues(alpha: 0.03)])
                : null,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: active ? AppTheme.accent.withValues(alpha: 0.45) : Colors.transparent),
            boxShadow: active ? [BoxShadow(color: AppTheme.accent.withValues(alpha: 0.16), blurRadius: 18, offset: const Offset(0, 6))] : null,
          ),
          child: Row(children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: active ? AppTheme.accent.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(widget.icon,
                  size: 16,
                  color: active ? AppTheme.accent : _hovered ? AppTheme.textPrimary : AppTheme.textMuted),
            ),
            if (!widget.collapsed) ...[
              const SizedBox(width: 12),
              Text(widget.label, style: TextStyle(
                color: active ? AppTheme.textPrimary : _hovered ? AppTheme.textPrimary : AppTheme.textMuted,
                fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
            ],
          ]),
        ),
      ),
    );
  }
}
