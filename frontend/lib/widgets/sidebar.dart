import 'package:flutter/material.dart';
import '../config/theme.dart';

enum AppTab { dashboard, events, rules, approvals, history, simulation }

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
    (AppTab.dashboard,   Icons.dashboard_rounded,    'Dashboard'),
    (AppTab.events,      Icons.warning_amber_rounded, 'Warnings & Errors'),
    (AppTab.rules,       Icons.rule_rounded,          'Rules'),
    (AppTab.approvals,   Icons.check_circle_outline,  'Approvals'),
    (AppTab.history,     Icons.history_rounded,        'History'),
    (AppTab.simulation,  Icons.science_rounded,        'Simulation'),
  ];

  @override
  Widget build(BuildContext context) {
    final w = _collapsed ? 64.0 : 220.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: w,
      decoration: const BoxDecoration(
        color: Color(0xFF0d0d22),
        border: Border(right: BorderSide(color: AppTheme.border)),
      ),
      child: Column(children: [
        // Header
        Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
          child: Row(children: [
            const Icon(Icons.shield_rounded, color: AppTheme.accent, size: 24),
            if (!_collapsed) ...[
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Remediation\nCenter',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w700, height: 1.3)),
              ),
            ],
            GestureDetector(
              onTap: () => setState(() => _collapsed = !_collapsed),
              child: Icon(_collapsed ? Icons.chevron_right : Icons.chevron_left,
                  color: AppTheme.textMuted, size: 18),
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
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppTheme.border))),
          child: Row(children: [
            const Icon(Icons.security, color: AppTheme.textDimmed, size: 14),
            if (!_collapsed) const SizedBox(width: 8),
            if (!_collapsed)
              const Text('Unisys AB', style: TextStyle(color: AppTheme.textDimmed, fontSize: 11)),
          ]),
        ),
      ]),
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
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          padding: EdgeInsets.symmetric(horizontal: widget.collapsed ? 12 : 14, vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppTheme.accent.withOpacity(0.15)
                : _hovered ? AppTheme.accent.withOpacity(0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: active ? Border.all(color: AppTheme.accent.withOpacity(0.4)) : null,
          ),
          child: Row(children: [
            Icon(widget.icon,
                size: 18,
                color: active ? AppTheme.accent : _hovered ? AppTheme.textPrimary : AppTheme.textMuted),
            if (!widget.collapsed) ...[
              const SizedBox(width: 12),
              Text(widget.label, style: TextStyle(
                color: active ? AppTheme.accent : _hovered ? AppTheme.textPrimary : AppTheme.textMuted,
                fontSize: 13, fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
            ],
          ]),
        ),
      ),
    );
  }
}
