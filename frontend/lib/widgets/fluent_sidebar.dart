import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../main.dart';

/// Enhanced Fluent Sidebar with smooth animations and better styling
class FluentSidebar extends StatefulWidget {
  final AppTab selected;
  final Function(AppTab) onSelect;

  const FluentSidebar({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  @override
  State<FluentSidebar> createState() => _FluentSidebarState();
}

class _FluentSidebarState extends State<FluentSidebar> {
  late Map<AppTab, bool> _hoveringTabs;

  @override
  void initState() {
    super.initState();
    _hoveringTabs = {for (var tab in AppTab.values) tab: false};
  }

  Color _getTabColor(AppTab tab) {
    if (tab == widget.selected) return AppTheme.accent;
    if (_hoveringTabs[tab]!) return AppTheme.accent.withValues(alpha: 0.6);
    return AppTheme.textMuted;
  }

  Color _getTabBackground(AppTab tab) {
    if (tab == widget.selected) return AppTheme.accent.withValues(alpha: 0.12);
    if (_hoveringTabs[tab]!) return Colors.white.withValues(alpha: 0.05);
    return Colors.transparent;
  }

  Icon _getTabIcon(AppTab tab) {
    return switch (tab) {
      AppTab.dashboard => Icon(Icons.dashboard_rounded, size: 20),
      AppTab.events => Icon(Icons.warning_rounded, size: 20),
      AppTab.rules => Icon(Icons.rule_rounded, size: 20),
      AppTab.approvals => Icon(Icons.approval_rounded, size: 20),
      AppTab.history => Icon(Icons.history_rounded, size: 20),
      AppTab.viewer => Icon(Icons.event_rounded, size: 20),
      AppTab.simulation => Icon(Icons.science_rounded, size: 20),
      AppTab.taskScheduler => Icon(Icons.schedule_rounded, size: 20),
    };
  }

  String _getTabLabel(AppTab tab) {
    return switch (tab) {
      AppTab.dashboard => 'Dashboard',
      AppTab.events => 'Events',
      AppTab.rules => 'Rules',
      AppTab.approvals => 'Approvals',
      AppTab.history => 'History',
      AppTab.viewer => 'Event Viewer',
      AppTab.simulation => 'Simulation',
      AppTab.taskScheduler => 'Tasks',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        border: Border(right: BorderSide(color: AppTheme.border, width: 1)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppTheme.gradientPrimary,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.shield_rounded, color: Colors.white),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Auto-Remediation',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const Text(
                  'Control Center',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          
          // Navigation Items
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              itemCount: AppTab.values.length,
              itemBuilder: (context, index) {
                final tab = AppTab.values[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: MouseRegion(
                    onEnter: (_) => setState(() => _hoveringTabs[tab] = true),
                    onExit: (_) => setState(() => _hoveringTabs[tab] = false),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: _getTabBackground(tab),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => widget.onSelect(tab),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            child: Row(
                              children: [
                                AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 200),
                                  style: TextStyle(
                                    color: _getTabColor(tab),
                                    fontSize: 20,
                                  ),
                                  child: _getTabIcon(tab),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 200),
                                    style: TextStyle(
                                      color: _getTabColor(tab),
                                      fontWeight: tab == widget.selected ? FontWeight.w600 : FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                    child: Text(_getTabLabel(tab)),
                                  ),
                                ),
                                if (tab == widget.selected)
                                  AnimatedOpacity(
                                    duration: const Duration(milliseconds: 200),
                                    opacity: 1.0,
                                    child: Container(
                                      width: 3,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        color: AppTheme.accent,
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Footer
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.bgCardAlt,
                border: Border.all(color: AppTheme.border, width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: AppTheme.gradientSuccess,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Backend Status', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
                        Text('Online', style: TextStyle(fontSize: 12, color: AppTheme.accentGreen, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

typedef AppSidebar = FluentSidebar;
