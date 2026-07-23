import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../services/api_service.dart';
import '../services/monitor_service.dart';
import '../services/alert_polling_service.dart';

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback? onRefreshAll;

  const AppHeader({super.key, required this.title, this.onRefreshAll});

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        border: const Border(bottom: BorderSide(color: AppTheme.border)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.16), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(children: [
        // Title — ellipsizes instead of pushing the action cluster off-screen
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
            const SizedBox(height: 2),
            const Text('Automated system remediation and management',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5, height: 1.2)),
          ]),
        ),
        const SizedBox(width: 12),
        // Action cluster — scales down as a unit on narrow windows instead of
        // overflowing (the buttons stay fully visible and clickable).
        Expanded(
          flex: 2,
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                // Monitor status pill
                Consumer<MonitorService>(
                  builder: (_, monitor, __) => _MonitorPill(monitor: monitor),
                ),
                const SizedBox(width: 12),
                // Refresh button
                _HeaderBtn(
                  icon: Icons.refresh_rounded, label: 'Refresh All',
                  color: AppTheme.textPrimary,
                  onTap: onRefreshAll,
                ),
                const SizedBox(width: 8),
                // Inject Error button
                Consumer<AlertPollingService>(
                  builder: (_, alertSvc, __) => _InjectBtn(alertSvc: alertSvc),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _MonitorPill extends StatelessWidget {
  final MonitorService monitor;
  const _MonitorPill({required this.monitor});

  @override
  Widget build(BuildContext context) {
    final running = monitor.isRunning;
    final dot = running ? AppTheme.accentGreen : const Color(0xFF6c757d);
    final last = monitor.lastPoll.isNotEmpty
        ? monitor.lastPoll.substring(0, monitor.lastPoll.length > 16 ? 16 : monitor.lastPoll.length)
        : '';
    return GestureDetector(
      onTap: () async {
        final api = context.read<ApiService>();
        try {
          final r = await api.triggerMonitorPoll();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Sync complete — ${r['events_ingested'] ?? 0} events ingested'),
              duration: const Duration(seconds: 3),
            ));
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('Sync failed: $e')));
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: 8, height: 8,
            decoration: BoxDecoration(
              color: running ? dot : dot,
              shape: BoxShape.circle,
              boxShadow: running ? [BoxShadow(color: dot.withValues(alpha: 0.6), blurRadius: 6)] : null,
            ),
          ),
          const SizedBox(width: 8),
          Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Event Monitor', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w500)),
            if (last.isNotEmpty)
              Text(last, style: const TextStyle(color: AppTheme.textDimmed, fontSize: 9)),
          ]),
        ]),
      ),
    );
  }
}

class _InjectBtn extends StatefulWidget {
  final AlertPollingService alertSvc;
  const _InjectBtn({required this.alertSvc});

  @override
  State<_InjectBtn> createState() => _InjectBtnState();
}

class _InjectBtnState extends State<_InjectBtn> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return _HeaderBtn(
      icon: Icons.bolt_rounded,
      label: _loading ? 'Injecting…' : 'Inject Error',
      color: AppTheme.accentRed,
      gradient: AppTheme.gradientDanger,
      onTap: _loading ? null : _inject,
    );
  }

  Future<void> _inject() async {
    setState(() => _loading = true);
    try {
      await context.read<ApiService>().injectHighCpuAlert();
      await widget.alertSvc.forceRefresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('High CPU Alert injected — check Dashboard for live popup')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Injection failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

class _HeaderBtn extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final LinearGradient? gradient;
  final VoidCallback? onTap;
  const _HeaderBtn({required this.icon, required this.label, required this.color, this.gradient, this.onTap});

  @override
  State<_HeaderBtn> createState() => _HeaderBtnState();
}

class _HeaderBtnState extends State<_HeaderBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            gradient: widget.gradient != null && (_hovered || widget.label.contains('Inject'))
                ? widget.gradient : null,
            color: widget.gradient == null ? (_hovered ? AppTheme.bgCardAlt : Colors.white.withValues(alpha: 0.025)) : null,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: widget.color.withValues(alpha: 0.32)),
            boxShadow: _hovered ? [BoxShadow(color: widget.color.withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(0, 6))] : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(widget.icon, size: 14, color: widget.color),
            const SizedBox(width: 6),
            Text(widget.label, style: TextStyle(color: widget.color, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}
