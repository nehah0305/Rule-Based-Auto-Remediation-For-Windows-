import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/alert.dart';

class LiveAlertPopup extends StatefulWidget {
  final LiveAlert alert;
  final VoidCallback onDismiss;
  final VoidCallback onRemediate;

  const LiveAlertPopup({
    super.key,
    required this.alert,
    required this.onDismiss,
    required this.onRemediate,
  });

  @override
  State<LiveAlertPopup> createState() => _LiveAlertPopupState();
}

class _LiveAlertPopupState extends State<LiveAlertPopup> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slide;
  late Animation<double> _fade;
  bool _remediating = false;
  bool _remediated  = false;
  double _progress  = 0;

  bool get _isHighCpu => widget.alert.alertType == 'highcpu';

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _slide = Tween<Offset>(begin: const Offset(0, 1.5), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _fade  = Tween<double>(begin: 0, end: 1).animate(_ctrl);
    _ctrl.forward();
    if (widget.alert.remediated) {
      _remediated = true;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    await _ctrl.reverse();
    widget.onDismiss();
  }

  void _startRemediation() {
    setState(() { _remediating = true; _progress = 0; });
    _animateProgress();
    widget.onRemediate();
  }

  void _animateProgress() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      setState(() { _progress = (_progress + 0.12).clamp(0, 0.9); });
      if (_progress < 0.9 && _remediating) _animateProgress();
    });
  }

  void setRemediated() {
    setState(() { _remediated = true; _remediating = false; _progress = 1.0; });
  }

  LinearGradient get _headerGradient => _remediated
      ? AppTheme.gradientSuccess
      : _isHighCpu
          ? AppTheme.gradientHighCpu
          : const LinearGradient(colors: [Color(0xFFf7971e), Color(0xFFffd200)]);

  int? get _cpuPct {
    final msg = widget.alert.message ?? '';
    final m = RegExp(r'CPU:\s*(\d+)%').firstMatch(msg);
    return m != null ? int.tryParse(m.group(1)!) : null;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 28, right: 28,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: SizedBox(
            width: 380,
            child: Material(
              elevation: 24,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Header
                Container(
                  decoration: BoxDecoration(gradient: _headerGradient),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  child: Row(children: [
                    Text(_remediated ? '✅' : _isHighCpu ? '⚡' : '🚨',
                        style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        _remediated ? 'Incident Resolved'
                            : _isHighCpu ? 'High CPU Alert Detected'
                            : 'Service Crash Detected',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      Text(
                        '${widget.alert.alertType == 'highcpu' ? 'Event 9999' : 'Event 7034'} · ${widget.alert.source ?? ''}',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ])),
                    GestureDetector(
                      onTap: _dismiss,
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(14)),
                        child: const Icon(Icons.close, size: 15, color: Colors.white),
                      ),
                    ),
                  ]),
                ),
                // Body
                Container(
                  color: AppTheme.bgCard,
                  padding: const EdgeInsets.all(18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    // Message
                    Text(
                      _shortenMessage(widget.alert.message ?? ''),
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 12, height: 1.5),
                      maxLines: 3, overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    // CPU bar (only for high CPU)
                    if (_isHighCpu && _cpuPct != null) ...[
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('CPU Usage', style: TextStyle(color: AppTheme.textDimmed, fontSize: 11)),
                        Text('$_cpuPct%', style: const TextStyle(color: AppTheme.accentOrange, fontWeight: FontWeight.w700, fontSize: 12)),
                      ]),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (_cpuPct ?? 0) / 100,
                          minHeight: 6,
                          backgroundColor: Colors.white12,
                          valueColor: const AlwaysStoppedAnimation(AppTheme.accentOrange),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    // Timestamp
                    if (widget.alert.timestamp != null)
                      Text(_formatTs(widget.alert.timestamp!),
                          style: const TextStyle(color: AppTheme.textDimmed, fontSize: 10)),
                    const SizedBox(height: 14),
                    // Buttons
                    if (!_remediated) ...[
                      Row(children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: _remediating ? null : _startRemediation,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                gradient: _remediating ? null : AppTheme.gradientSuccess,
                                color: _remediating ? AppTheme.accentGreen.withValues(alpha: 0.4) : null,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(child: _remediating
                                  ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Text('⚡ Auto-Remediate Now',
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: _dismiss,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.07),
                              border: Border.all(color: AppTheme.border),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text('Dismiss', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                          ),
                        ),
                      ]),
                    ] else
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.accentGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.3)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.check_circle, color: AppTheme.accentGreen, size: 16),
                          const SizedBox(width: 8),
                          const Expanded(child: Text('Incident resolved successfully',
                              style: TextStyle(color: AppTheme.accentGreen, fontSize: 12, fontWeight: FontWeight.w600))),
                          GestureDetector(onTap: _dismiss,
                              child: const Icon(Icons.close, color: AppTheme.textMuted, size: 14)),
                        ]),
                      ),
                    // Progress bar during remediation
                    if (_remediating) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _progress,
                          minHeight: 6,
                          backgroundColor: Colors.white12,
                          valueColor: const AlwaysStoppedAnimation(AppTheme.accentGreen),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text('Executing remediation script…',
                          style: TextStyle(color: AppTheme.textDimmed, fontSize: 10)),
                    ],
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  String _shortenMessage(String msg) {
    if (msg.length > 160) return '${msg.substring(0, 160)}…';
    return msg;
  }

  String _formatTs(String ts) {
    try {
      final dt = DateTime.parse(ts);
      return '${dt.toLocal()}'.substring(0, 16);
    } catch (_) { return ts; }
  }
}
