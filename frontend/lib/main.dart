import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/theme.dart';
import 'services/api_service.dart';
import 'services/alert_polling_service.dart';
import 'services/monitor_service.dart';
import 'services/remediation_service.dart';
import 'widgets/sidebar.dart';
import 'widgets/header.dart';
import 'widgets/live_alert_popup.dart';
import 'screens/dashboard_screen.dart';
import 'screens/events_screen.dart';
import 'screens/rules_screen.dart';
import 'screens/approvals_screen.dart';
import 'screens/history_screen.dart';
import 'screens/simulation_screen.dart';

void main() {
  runApp(const RemediationApp());
}

class RemediationApp extends StatelessWidget {
  const RemediationApp({super.key});

  @override
  Widget build(BuildContext context) {
    final api        = ApiService();
    final alertSvc   = AlertPollingService(api);
    final monitorSvc = MonitorService(api);
    final remediationSvc = RemediationService();

    return MultiProvider(
      providers: [
        Provider<ApiService>.value(value: api),
        ChangeNotifierProvider<AlertPollingService>.value(value: alertSvc),
        ChangeNotifierProvider<MonitorService>.value(value: monitorSvc),
        ChangeNotifierProvider<RemediationService>.value(value: remediationSvc),
      ],
      child: MaterialApp(
        title: 'Auto-Remediation Control Center',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: const AppShell(),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppTab _tab = AppTab.dashboard;

  static const _titles = {
    AppTab.dashboard:  'Dashboard',
    AppTab.events:     'Warnings & Errors',
    AppTab.rules:      'Rules',
    AppTab.approvals:  'Approvals',
    AppTab.history:    'Remediation History',
    AppTab.simulation: 'Simulation Lab',
  };

  Widget _screen(AppTab tab) => switch (tab) {
    AppTab.dashboard   => const DashboardScreen(),
    AppTab.events      => const EventsScreen(),
    AppTab.rules       => const RulesScreen(),
    AppTab.approvals   => const ApprovalsScreen(),
    AppTab.history     => const HistoryScreen(),
    AppTab.simulation  => const SimulationScreen(),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Main layout
          Row(children: [
            AppSidebar(
              selected: _tab,
              onSelect: (t) => setState(() => _tab = t),
            ),
            Expanded(
              child: Column(children: [
                AppHeader(
                  title: _titles[_tab]!,
                  onRefreshAll: () => setState(() {}),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, anim) =>
                        FadeTransition(opacity: anim, child: child),
                    child: KeyedSubtree(
                      key: ValueKey(_tab),
                      child: _screen(_tab),
                    ),
                  ),
                ),
              ]),
            ),
          ]),
          // Live alert popup — floated over everything
          _LiveAlertLayer(),
        ],
      ),
    );
  }
}

class _LiveAlertLayer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<AlertPollingService>(
      builder: (ctx, alertSvc, _) {
        final alert = alertSvc.activeAlert;
        if (alert == null) return const SizedBox.shrink();
        return LiveAlertPopup(
          key: ValueKey(alert.id),
          alert: alert,
          onDismiss: alertSvc.dismissPopup,
          onRemediate: () async {
            final api = ctx.read<ApiService>();
            final remediationSvc = ctx.read<RemediationService>();
            try {
              if (alert.alertType == 'highcpu') {
                await api.remediateHighCpu(alert.id);
              } else {
                await api.remediateServiceCrash(alert.id);
              }
              alertSvc.markRemediated(alert.id);
              
              // Notify all listeners (History screen, Dashboard, etc.) that remediation happened
              remediationSvc.notifyRemediationCompleted();
              
              // Keep alert refreshing to ensure latest state
              await alertSvc.forceRefresh();
              
              // Show success notification
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('✓ Remediation executed successfully! Check History tab for details.'),
                    duration: Duration(seconds: 5),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: Color(0xFF059669),
                    margin: EdgeInsets.all(16),
                  ),
                );
              }
            } catch (e) {
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx)
                    .showSnackBar(SnackBar(
                      content: Text('Remediation error: $e'),
                      duration: const Duration(seconds: 4),
                      backgroundColor: const Color(0xFFDC2626),
                    ));
              }
            }
          },
        );
      },
    );
  }
}
