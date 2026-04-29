import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../services/crash_watcher_service.dart';
import '../services/remediation_service.dart';

// ─── Crash Watcher Panel (Dashboard card) ────────────────────────────────────
/// A pulsing, armed-state panel that lives on the Dashboard.
/// Toggle "Watch for Crashes" → polls real Windows Event Log every 3s.
class CrashWatcherPanel extends StatelessWidget {
  const CrashWatcherPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CrashWatcherService>(
      builder: (ctx, watcher, _) {
        if (watcher.detectedCrash != null) {
          return _CrashDetectedCard(watcher: watcher);
        }
        return _WatchToggleCard(watcher: watcher);
      },
    );
  }
}

// ─── Toggle card (armed/disarmed state) ──────────────────────────────────────
class _WatchToggleCard extends StatelessWidget {
  final CrashWatcherService watcher;
  const _WatchToggleCard({required this.watcher});

  @override
  Widget build(BuildContext context) {
    final watching = watcher.isWatching;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: watching
              ? const Color(0xFFef4444).withValues(alpha: 0.6)
              : AppTheme.border,
          width: watching ? 1.5 : 1.0,
        ),
        boxShadow: watching
            ? [BoxShadow(color: const Color(0xFFef4444).withValues(alpha: 0.15), blurRadius: 20, spreadRadius: 2)]
            : [],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header ─────────────────────────────────────────────────────────
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            gradient: watching
                ? const LinearGradient(colors: [Color(0xFF7f1d1d), Color(0xFF991b1b), Color(0xFFdc2626)])
                : const LinearGradient(colors: [Color(0xFF1e1e2e), Color(0xFF2a2a40)]),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(children: [
            _PulsingDot(active: watching),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  watching ? '🔴 Watching for Crashes…' : '🛡️ Crash Watcher',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                ),
                Text(
                  watching
                      ? 'Monitoring notepad.exe — crash Notepad to trigger'
                      : 'Real-time Windows Event Log monitoring',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ]),
            ),
            _WatchToggleSwitch(watching: watching, watcher: watcher),
          ]),
        ),
        // ── Body ───────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!watching) ...[
              // Disarmed: show instructions
              _InstructionStep(num: '1', text: 'Toggle "Watch for Crashes" to arm the watcher'),
              const SizedBox(height: 8),
              _InstructionStep(num: '2', text: 'Open Notepad (Win + R → notepad)'),
              const SizedBox(height: 8),
              _InstructionStep(num: '3', text: 'Kill Notepad via Task Manager → End Task'),
              const SizedBox(height: 8),
              _InstructionStep(num: '4', text: 'Watch the crash popup appear instantly ⚡'),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.accent.withValues(alpha: 0.25)),
                ),
                child: const Row(children: [
                  Icon(Icons.info_outline, color: AppTheme.accent, size: 14),
                  SizedBox(width: 8),
                  Expanded(child: Text(
                    'Detection reads from real Windows Application Event Log (Event ID 1000). Remediation actually relaunches the app.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11, height: 1.4),
                  )),
                ]),
              ),
            ] else ...[
              // Armed: show live status
              Row(children: [
                const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFef4444)),
                ),
                const SizedBox(width: 12),
                const Text('Polling every 3 seconds…', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              ]),
              const SizedBox(height: 12),
              _StatusRow(icon: Icons.search, label: 'Monitoring', value: 'notepad.exe', color: const Color(0xFFef4444)),
              const SizedBox(height: 6),
              _StatusRow(icon: Icons.event_note, label: 'Event ID', value: '1000 (Application Error)', color: AppTheme.accent),
              const SizedBox(height: 6),
              _StatusRow(icon: Icons.timer_outlined, label: 'Look-back window', value: '60 seconds', color: AppTheme.accentGreen),
            ],
          ]),
        ),
      ]),
    );
  }
}

// ─── Crash detected card (the "popup inside the card") ───────────────────────
class _CrashDetectedCard extends StatelessWidget {
  final CrashWatcherService watcher;
  const _CrashDetectedCard({required this.watcher});

  @override
  Widget build(BuildContext context) {
    final crash       = watcher.detectedCrash!;
    final remediated  = watcher.remediated;
    final remediating = watcher.remediating;
    final error       = watcher.error;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: remediated
              ? AppTheme.accentGreen.withValues(alpha: 0.6)
              : const Color(0xFFef4444).withValues(alpha: 0.7),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (remediated ? AppTheme.accentGreen : const Color(0xFFef4444)).withValues(alpha: 0.2),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Alert header ───────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            gradient: remediated
                ? AppTheme.gradientSuccess
                : const LinearGradient(colors: [Color(0xFF7f1d1d), Color(0xFFdc2626), Color(0xFFf97316)]),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(children: [
            Text(remediated ? '✅' : '💥', style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                remediated ? 'Application Restarted!' : 'Application Crash Detected!',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
              ),
              Text(
                '${crash.appName}.exe • Event ID 1000 • Windows Application Log',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ])),
            if (!remediated)
              GestureDetector(
                onTap: () => watcher.reset(),
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.close, size: 15, color: Colors.white),
                ),
              ),
          ]),
        ),
        // ── Body ───────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Crash message
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0a0a0a),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('CRASH SIGNATURE', style: TextStyle(color: Color(0xFFef4444), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                const SizedBox(height: 6),
                Text(
                  crash.message.length > 200 ? '${crash.message.substring(0, 200)}…' : crash.message,
                  style: const TextStyle(fontFamily: 'monospace', color: Color(0xFFfca5a5), fontSize: 10.5, height: 1.5),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            // Timestamp
            Row(children: [
              const Icon(Icons.schedule, color: AppTheme.textDimmed, size: 12),
              const SizedBox(width: 4),
              Text(_formatTs(crash.timestamp), style: const TextStyle(color: AppTheme.textDimmed, fontSize: 10)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFef4444).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFef4444).withValues(alpha: 0.4)),
                ),
                child: const Text('LIVE DETECTION', style: TextStyle(color: Color(0xFFef4444), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
              ),
            ]),
            const SizedBox(height: 16),

            // Error banner
            if (error != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.accentRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.accentRed.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: AppTheme.accentRed, size: 14),
                  const SizedBox(width: 8),
                  Expanded(child: Text(error, style: const TextStyle(color: AppTheme.accentRed, fontSize: 11))),
                ]),
              ),
              const SizedBox(height: 12),
            ],

            // Remediation output (post-remediation)
            if (watcher.remediationOutput != null && remediated) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF050510),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.3)),
                ),
                child: Text(
                  watcher.remediationOutput!,
                  style: const TextStyle(fontFamily: 'monospace', color: Color(0xFF4ade80), fontSize: 10.5, height: 1.5),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Action buttons
            if (!remediated) ...[
              Row(children: [
                Expanded(
                  child: _RemediateButton(remediating: remediating, onTap: () async {
                    final remSvc = context.read<RemediationService>();
                    await watcher.remediate();
                    remSvc.notifyRemediationCompleted();
                  }),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: watcher.reset,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      border: Border.all(color: AppTheme.border),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('Dismiss', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                  ),
                ),
              ]),
            ] else ...[
              // Success state
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.accentGreen.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.check_circle, color: AppTheme.accentGreen, size: 18),
                  const SizedBox(width: 10),
                  const Expanded(child: Text(
                    'notepad.exe restarted successfully. Check History tab for full log.',
                    style: TextStyle(color: AppTheme.accentGreen, fontSize: 12, fontWeight: FontWeight.w600, height: 1.4),
                  )),
                  GestureDetector(
                    onTap: watcher.stopWatching,
                    child: const Icon(Icons.close, color: AppTheme.textMuted, size: 14),
                  ),
                ]),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  String _formatTs(String ts) {
    try {
      final dt = DateTime.parse(ts).toLocal();
      return '${dt.year}-${_p(dt.month)}-${_p(dt.day)}  ${_p(dt.hour)}:${_p(dt.minute)}:${_p(dt.second)}';
    } catch (_) {
      return ts;
    }
  }

  String _p(int n) => n.toString().padLeft(2, '0');
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  final bool active;
  const _PulsingDot({required this.active});
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.7, end: 1.3).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return Container(
        width: 10, height: 10,
        decoration: BoxDecoration(color: AppTheme.textDimmed, shape: BoxShape.circle),
      );
    }
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 10, height: 10,
        decoration: const BoxDecoration(color: Color(0xFFef4444), shape: BoxShape.circle),
      ),
    );
  }
}

class _WatchToggleSwitch extends StatelessWidget {
  final bool watching;
  final CrashWatcherService watcher;
  const _WatchToggleSwitch({required this.watching, required this.watcher});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => watching ? watcher.stopWatching() : watcher.startWatching(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 52, height: 28,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: watching ? const Color(0xFFef4444) : Colors.white12,
          borderRadius: BorderRadius.circular(14),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: watching ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22, height: 22,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

class _RemediateButton extends StatelessWidget {
  final bool remediating;
  final VoidCallback onTap;
  const _RemediateButton({required this.remediating, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: remediating ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          gradient: remediating ? null : const LinearGradient(colors: [Color(0xFF059669), Color(0xFF10b981)]),
          color: remediating ? AppTheme.accentGreen.withValues(alpha: 0.3) : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: remediating
              ? const Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                  SizedBox(width: 8),
                  Text('Restarting App…', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                ])
              : const Text('⚡ Restart Application', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
        ),
      ),
    );
  }
}

class _InstructionStep extends StatelessWidget {
  final String num;
  final String text;
  const _InstructionStep({required this.num, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 20, height: 20,
        decoration: BoxDecoration(
          color: AppTheme.accent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
        ),
        child: Center(child: Text(num, style: const TextStyle(color: AppTheme.accent, fontSize: 10, fontWeight: FontWeight.w700))),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12, height: 1.4))),
    ]);
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatusRow({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, color: color, size: 13),
      const SizedBox(width: 6),
      Text('$label: ', style: const TextStyle(color: AppTheme.textDimmed, fontSize: 11)),
      Text(value, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    ]);
  }
}
