import 'dart:async';
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
import 'screens/event_viewer_screen.dart';
import 'screens/task_scheduler_screen.dart';

void main() {
  // Task 6 — global error boundary: a widget that fails to build anywhere
  // in the tree renders this small inline card instead of taking down the
  // whole app with Flutter's default red screen of death.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    // ignore: avoid_print
    print('[UI ERROR] ${details.exceptionAsString()}');
  };
  ErrorWidget.builder = (FlutterErrorDetails details) => _ErrorBoundaryWidget(details: details);

  runApp(const RemediationApp());
}

class _ErrorBoundaryWidget extends StatelessWidget {
  final FlutterErrorDetails details;
  const _ErrorBoundaryWidget({required this.details});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF1A0000),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFE74856), size: 20),
          const SizedBox(height: 6),
          const Text(
            'This section failed to render.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFE74856), fontSize: 11, fontWeight: FontWeight.w600),
          ),
          if (details.exception.toString().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              details.exception.toString(),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFB4B4B4), fontSize: 9.5),
            ),
          ],
        ],
      ),
    );
  }
}

class RemediationApp extends StatelessWidget {
  const RemediationApp({super.key});

  @override
  Widget build(BuildContext context) {
    // create: (not .value) so the providers OWN these services — they are
    // built once, survive rebuilds of this widget, and get dispose() called
    // when the tree unmounts, which cancels the polling timers. The previous
    // .value wiring constructed new services on every build and never
    // disposed the old ones, leaking their periodic timers.
    return MultiProvider(
      providers: [
        Provider<ApiService>(create: (_) => ApiService()),
        ChangeNotifierProvider<AlertPollingService>(
            create: (ctx) => AlertPollingService(ctx.read<ApiService>())),
        ChangeNotifierProvider<MonitorService>(
            create: (ctx) => MonitorService(ctx.read<ApiService>())),
        ChangeNotifierProvider<RemediationService>(create: (_) => RemediationService()),
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
  Timer? _approvalTimer;
  int _lastSeenApprovalId = 0;

  @override
  void initState() {
    super.initState();
    _startApprovalPolling();
  }

  @override
  void dispose() {
    _approvalTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkApprovals() async {
    try {
      if (!mounted) return;
      final api = context.read<ApiService>();
      final res = await api.getApprovals(status: 'pending');
      int maxId = 0;
      for (final req in res) {
        if (req.id > maxId) maxId = req.id;
      }
      
      if (_lastSeenApprovalId == 0) {
        _lastSeenApprovalId = maxId;
      } else if (maxId > _lastSeenApprovalId) {
        _lastSeenApprovalId = maxId;
        final newest = res.reduce((a, b) => a.id > b.id ? a : b);
        final appName = newest.appContext.isNotEmpty ? newest.appContext : 'an application';
        final eventLabel = newest.eventId.isNotEmpty ? 'Event ${newest.eventId}' : 'an event';
        final msg = '🔔 Approval Required — $appName crashed ($eventLabel, ${newest.source}). Operator sign-off needed.';
        if (mounted) {
          final messenger = ScaffoldMessenger.of(context);
          messenger.showSnackBar(
            SnackBar(
              content: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Small close "x" on the top-left of the message box
                  InkWell(
                    onTap: () => messenger.hideCurrentSnackBar(),
                    borderRadius: BorderRadius.circular(10),
                    child: const Padding(
                      padding: EdgeInsets.only(right: 10, top: 2),
                      child: Icon(Icons.close, size: 16, color: Colors.black87),
                    ),
                  ),
                  Expanded(child: Text(msg)),
                ],
              ),
              backgroundColor: AppTheme.accentYellow.withValues(alpha: 0.9),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 10),
              action: SnackBarAction(
                label: 'View', backgroundColor: Colors.black26, textColor: Colors.white,
                onPressed: () => setState(() => _tab = AppTab.approvals),
              ),
            ),
          );
        }
      }
    } catch (_) {}
  }

  void _startApprovalPolling() {
    _checkApprovals();
    _approvalTimer = Timer.periodic(const Duration(seconds: 10), (_) => _checkApprovals());
  }

  static const _titles = {
    AppTab.dashboard: 'Dashboard',
    AppTab.events: 'Warnings & Errors',
    AppTab.rules: 'Rules',
    AppTab.approvals: 'Approvals',
    AppTab.history: 'Remediation History',
    AppTab.viewer: 'Event Viewer',
    AppTab.simulation: 'Simulation Lab',
    AppTab.taskScheduler: 'Task Scheduler',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: AppTheme.appBackground),
              child: const _AmbientBackdrop(),
            ),
          ),
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
                  child: IndexedStack(
                    index: _tab.index,
                    children: const [
                      DashboardScreen(),
                      EventsScreen(),
                      RulesScreen(),
                      ApprovalsScreen(),
                      HistoryScreen(),
                      SimulationScreen(),
                      EventViewerScreen(),
                      TaskSchedulerScreen(),
                    ],
                  ),
                ),
              ]),
            ),
          ]),
          _LiveAlertLayer(),
        ],
      ),
    );
  }
}

class _AmbientBackdrop extends StatelessWidget {
  const _AmbientBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: const [
        Positioned(top: -80, right: -40, child: _GlowBlob(color: Color(0x144A9EFF), size: 240)),
        Positioned(top: 140, left: -90, child: _GlowBlob(color: Color(0x1024D0A3), size: 200)),
        Positioned(bottom: -100, right: 120, child: _GlowBlob(color: Color(0x10AA6CFF), size: 260)),
      ],
    );
  }
}

class _GlowBlob extends StatelessWidget {
  final Color color;
  final double size;

  const _GlowBlob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: color, blurRadius: 40, spreadRadius: 4)],
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
                      content: Text('Failed: $e'),
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
