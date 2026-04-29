import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/api_service.dart';
import '../widgets/simulation_widgets.dart';
import '../widgets/badges.dart';

enum SimType { crash, diskspace, eventlog, auditevents, highcpu, servicecrash, rootCauseVariants }

class SimulationScreen extends StatefulWidget {
  const SimulationScreen({super.key});

  @override
  State<SimulationScreen> createState() => _SimulationScreenState();
}

class _SimulationScreenState extends State<SimulationScreen> {
  final _api = ApiService();
  SimType _type = SimType.crash;
  bool _running = false;
  List<Map<String, dynamic>> _timeline = [];
  String _terminalOutput = '';
  Map<String, dynamic> _metrics = {};
  List<dynamic> _resultCards = [];
  String _statusMsg = 'Waiting to run simulation.';

  // Crash sim params
  final _appName    = TextEditingController(text: 'DemoCrashApp');
  final _faultMod   = TextEditingController(text: 'ntdll.dll');
  final _exception  = TextEditingController(text: '0xc0000005');
  int _count = 1;
  String _profile = 'degraded';
  bool _retry = true, _verify = true;
  bool _livePlayback = true;
  double _playbackSpeed = 1.0;

  // Disk sim params
  int _diskCount = 1;
  String _diskProfile = 'degraded';
  bool _diskRetry = true, _diskVerify = true;

  // EventLog sim params
  int _elCount = 1;
  String _elProfile = 'degraded';
  bool _elRetry = true, _elVerify = true;

  // AuditEvents sim params
  int _aeCount = 1;
  String _aeProfile = 'degraded';
  bool _aeRetry = true, _aeVerify = true;

  @override
  void dispose() {
    _appName.dispose(); _faultMod.dispose(); _exception.dispose();
    super.dispose();
  }

  Future<void> _runSimulation() async {
    setState(() {
      _running = true; _timeline = []; _terminalOutput = ''; _metrics = {};
      _resultCards = []; _statusMsg = 'Running simulation…';
    });

    try {
      Map<String, dynamic> result;
      switch (_type) {
        case SimType.crash:
          result = await _api.runCrashSimulation({
            'app_name': _appName.text.trim(), 'module_name': _faultMod.text.trim(),
            'exception_code': _exception.text.trim(), 'count': _count,
            'profile': _profile, 'retry_on_failure': _retry, 'verify_recovery': _verify,
          });
          break;
        case SimType.diskspace:
          result = await _api.runDiskSimulation({
            'count': _diskCount, 'profile': _diskProfile,
            'retry_on_failure': _diskRetry, 'verify_recovery': _diskVerify,
          });
          break;
        case SimType.eventlog:
          result = await _api.runEventLogSimulation({
            'count': _elCount, 'profile': _elProfile,
            'retry_on_failure': _elRetry, 'verify_recovery': _elVerify,
          });
          break;
        case SimType.auditevents:
          result = await _api.runAuditEventsSimulation({
            'count': _aeCount, 'profile': _aeProfile,
            'retry_on_failure': _aeRetry, 'verify_recovery': _aeVerify,
          });
          break;
        case SimType.highcpu:
          final r = await _api.injectHighCpuAlert();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('High CPU Alert injected! Switch to Dashboard to see the live alert popup.')));
          }
          setState(() {
            _statusMsg = 'Alert injected. Check Dashboard for live popup.';
            _terminalOutput = r['script_output'] as String? ?? '';
            _running = false;
          });
          return;
        case SimType.servicecrash:
          final r = await _api.injectServiceCrash();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Service Crash Alert injected! Switch to Dashboard to see the live alert popup.')));
          }
          setState(() {
            _statusMsg = 'Alert injected. Check Dashboard for live popup.';
            _terminalOutput = r['script_output'] as String? ?? '';
            _running = false;
          });
          return;
        case SimType.rootCauseVariants:
          result = await _api.runRootCauseVariantSimulation({});
          break;
      }

      // Process result
      final summary = result['summary'] as Map<String, dynamic>? ?? {};
      final timeline = (result['timeline'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final events   = result['events'] as List? ?? [];
      final output   = result['latest_output'] as String? ?? result['terminal_output'] as String? ?? '';

      if (_livePlayback && timeline.isNotEmpty) {
        await _playTimeline(timeline);
      } else {
        setState(() => _timeline = timeline);
      }
      setState(() {
        _metrics      = summary;
        _resultCards  = events;
        _terminalOutput = output;
        _statusMsg    = _buildStatusMsg(summary);
        _running      = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() { _statusMsg = 'Error: $e'; _running = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Simulation error: $e')));
      }
    }
  }

  Future<void> _playTimeline(List<Map<String, dynamic>> steps) async {
    final delay = Duration(milliseconds: (750 / _playbackSpeed).round());
    for (final step in steps) {
      if (!mounted) return;
      setState(() => _timeline = [..._timeline, step]);
      await Future.delayed(delay);
    }
  }

  String _buildStatusMsg(Map<String, dynamic> s) {
    final resolved   = s['incident_resolved'] ?? 0;
    final unresolved = s['incident_unresolved'] ?? 0;
    final mttr       = s['mean_time_to_recover_seconds'] ?? 0;
    if (resolved == 0 && unresolved == 0) return 'Simulation completed.';
    return '$resolved resolved, $unresolved escalated${mttr > 0 ? ', MTTR: ${mttr}s' : ''}.';
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(children: [
      // Sim type selector
      _SimTypeSelector(selected: _type, onChanged: (t) => setState(() { _type = t; _timeline = []; _terminalOutput = ''; _metrics = {}; _resultCards = []; _statusMsg = 'Waiting to run simulation.'; })),
      const SizedBox(height: 16),
      Expanded(child: LayoutBuilder(builder: (ctx, constraints) {
        final wide = constraints.maxWidth > 800;
        return wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 320, child: _ControlPanel(
                  type: _type, running: _running, onRun: _runSimulation,
                  statusMsg: _statusMsg,
                  // crash params
                  appName: _appName, faultMod: _faultMod, exception: _exception,
                  count: _count, profile: _profile, retry: _retry, verify: _verify,
                  livePlayback: _livePlayback, playbackSpeed: _playbackSpeed,
                  onCountChanged: (v) => setState(() => _count = v),
                  onProfileChanged: (v) => setState(() => _profile = v),
                  onRetryChanged: (v) => setState(() => _retry = v),
                  onVerifyChanged: (v) => setState(() => _verify = v),
                  onLivePlaybackChanged: (v) => setState(() => _livePlayback = v),
                  onSpeedChanged: (v) => setState(() => _playbackSpeed = v),
                  // disk
                  diskCount: _diskCount, diskProfile: _diskProfile, diskRetry: _diskRetry, diskVerify: _diskVerify,
                  onDiskCountChanged: (v) => setState(() => _diskCount = v),
                  onDiskProfileChanged: (v) => setState(() => _diskProfile = v),
                  onDiskRetryChanged: (v) => setState(() => _diskRetry = v),
                  onDiskVerifyChanged: (v) => setState(() => _diskVerify = v),
                  // eventlog
                  elCount: _elCount, elProfile: _elProfile, elRetry: _elRetry, elVerify: _elVerify,
                  onElCountChanged: (v) => setState(() => _elCount = v),
                  onElProfileChanged: (v) => setState(() => _elProfile = v),
                  onElRetryChanged: (v) => setState(() => _elRetry = v),
                  onElVerifyChanged: (v) => setState(() => _elVerify = v),
                  // auditevents
                  aeCount: _aeCount, aeProfile: _aeProfile, aeRetry: _aeRetry, aeVerify: _aeVerify,
                  onAeCountChanged: (v) => setState(() => _aeCount = v),
                  onAeProfileChanged: (v) => setState(() => _aeProfile = v),
                  onAeRetryChanged: (v) => setState(() => _aeRetry = v),
                  onAeVerifyChanged: (v) => setState(() => _aeVerify = v),
                )),
                const SizedBox(width: 16),
                Expanded(child: _ResultPanel(type: _type, timeline: _timeline, metrics: _metrics, resultCards: _resultCards, output: _terminalOutput)),
              ])
            : SingleChildScrollView(child: Column(children: [
                _ControlPanel(
                  type: _type, running: _running, onRun: _runSimulation, statusMsg: _statusMsg,
                  appName: _appName, faultMod: _faultMod, exception: _exception,
                  count: _count, profile: _profile, retry: _retry, verify: _verify,
                  livePlayback: _livePlayback, playbackSpeed: _playbackSpeed,
                  onCountChanged: (v) => setState(() => _count = v),
                  onProfileChanged: (v) => setState(() => _profile = v),
                  onRetryChanged: (v) => setState(() => _retry = v),
                  onVerifyChanged: (v) => setState(() => _verify = v),
                  onLivePlaybackChanged: (v) => setState(() => _livePlayback = v),
                  onSpeedChanged: (v) => setState(() => _playbackSpeed = v),
                  diskCount: _diskCount, diskProfile: _diskProfile, diskRetry: _diskRetry, diskVerify: _diskVerify,
                  onDiskCountChanged: (v) => setState(() => _diskCount = v),
                  onDiskProfileChanged: (v) => setState(() => _diskProfile = v),
                  onDiskRetryChanged: (v) => setState(() => _diskRetry = v),
                  onDiskVerifyChanged: (v) => setState(() => _diskVerify = v),
                  elCount: _elCount, elProfile: _elProfile, elRetry: _elRetry, elVerify: _elVerify,
                  onElCountChanged: (v) => setState(() => _elCount = v),
                  onElProfileChanged: (v) => setState(() => _elProfile = v),
                  onElRetryChanged: (v) => setState(() => _elRetry = v),
                  onElVerifyChanged: (v) => setState(() => _elVerify = v),
                  aeCount: _aeCount, aeProfile: _aeProfile, aeRetry: _aeRetry, aeVerify: _aeVerify,
                  onAeCountChanged: (v) => setState(() => _aeCount = v),
                  onAeProfileChanged: (v) => setState(() => _aeProfile = v),
                  onAeRetryChanged: (v) => setState(() => _aeRetry = v),
                  onAeVerifyChanged: (v) => setState(() => _aeVerify = v),
                ),
                const SizedBox(height: 16),
                _ResultPanel(type: _type, timeline: _timeline, metrics: _metrics, resultCards: _resultCards, output: _terminalOutput),
              ]));
      })),
    ]),
  );
}

// ── Type selector ───────────────────────────────────────────────────────────
class _SimTypeSelector extends StatelessWidget {
  final SimType selected;
  final ValueChanged<SimType> onChanged;
  const _SimTypeSelector({required this.selected, required this.onChanged});

  static const _items = [
    (SimType.crash,       Icons.bug_report_rounded,        'Event 1000 – App Crash'),
    (SimType.diskspace,   Icons.storage_rounded,            'Event 2013 – Low Disk Space'),
    (SimType.eventlog,    Icons.article_rounded,            'Event 1100 – Event Log Shutdown'),
    (SimType.auditevents, Icons.gavel_rounded,             'Event 1101 – Audit Events Dropped'),
    (SimType.highcpu,     Icons.speed_rounded,              'Event 9999 – High CPU ⚡'),
    (SimType.servicecrash,Icons.settings_power_rounded,    'Event 7034 – Service Crash 🚨'),
    (SimType.rootCauseVariants, Icons.device_hub_rounded,  'Root Cause Variants 🎯'),
  ];

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Select Simulation Type', style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w500)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: _items.map((item) {
        final active = item.$1 == selected;
        return GestureDetector(
          onTap: () => onChanged(item.$1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: active ? AppTheme.accent.withOpacity(0.15) : AppTheme.bgCardAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: active ? AppTheme.accent : AppTheme.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(item.$2, size: 15, color: active ? AppTheme.accent : AppTheme.textMuted),
              const SizedBox(width: 8),
              Text(item.$3, style: TextStyle(color: active ? AppTheme.accent : AppTheme.textMuted, fontSize: 12, fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
            ]),
          ),
        );
      }).toList()),
    ]),
  );
}

// ── Control Panel ───────────────────────────────────────────────────────────
class _ControlPanel extends StatelessWidget {
  final SimType type;
  final bool running;
  final VoidCallback onRun;
  final String statusMsg;
  // Crash
  final TextEditingController appName, faultMod, exception;
  final int count; final String profile; final bool retry, verify, livePlayback; final double playbackSpeed;
  final ValueChanged<int> onCountChanged; final ValueChanged<String> onProfileChanged;
  final ValueChanged<bool> onRetryChanged, onVerifyChanged, onLivePlaybackChanged;
  final ValueChanged<double> onSpeedChanged;
  // Disk
  final int diskCount; final String diskProfile; final bool diskRetry, diskVerify;
  final ValueChanged<int> onDiskCountChanged; final ValueChanged<String> onDiskProfileChanged;
  final ValueChanged<bool> onDiskRetryChanged, onDiskVerifyChanged;
  // EventLog
  final int elCount; final String elProfile; final bool elRetry, elVerify;
  final ValueChanged<int> onElCountChanged; final ValueChanged<String> onElProfileChanged;
  final ValueChanged<bool> onElRetryChanged, onElVerifyChanged;
  // AuditEvents
  final int aeCount; final String aeProfile; final bool aeRetry, aeVerify;
  final ValueChanged<int> onAeCountChanged; final ValueChanged<String> onAeProfileChanged;
  final ValueChanged<bool> onAeRetryChanged, onAeVerifyChanged;

  const _ControlPanel({
    required this.type, required this.running, required this.onRun, required this.statusMsg,
    required this.appName, required this.faultMod, required this.exception,
    required this.count, required this.profile, required this.retry, required this.verify,
    required this.livePlayback, required this.playbackSpeed,
    required this.onCountChanged, required this.onProfileChanged,
    required this.onRetryChanged, required this.onVerifyChanged,
    required this.onLivePlaybackChanged, required this.onSpeedChanged,
    required this.diskCount, required this.diskProfile, required this.diskRetry, required this.diskVerify,
    required this.onDiskCountChanged, required this.onDiskProfileChanged,
    required this.onDiskRetryChanged, required this.onDiskVerifyChanged,
    required this.elCount, required this.elProfile, required this.elRetry, required this.elVerify,
    required this.onElCountChanged, required this.onElProfileChanged,
    required this.onElRetryChanged, required this.onElVerifyChanged,
    required this.aeCount, required this.aeProfile, required this.aeRetry, required this.aeVerify,
    required this.onAeCountChanged, required this.onAeProfileChanged,
    required this.onAeRetryChanged, required this.onAeVerifyChanged,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(child: Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      _ControlHeader(type: type),
      const SizedBox(height: 16),
      _buildParams(context),
      const SizedBox(height: 16),
      SizedBox(width: double.infinity, child: ElevatedButton.icon(
        onPressed: running ? null : onRun,
        icon: running ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.play_arrow_rounded, size: 18),
        label: Text(running ? 'Running…' : 'Run Simulation'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          backgroundColor: type == SimType.highcpu || type == SimType.servicecrash ? AppTheme.accentRed : AppTheme.accent,
        ),
      )),
      const SizedBox(height: 12),
      _StatusBox(message: statusMsg),
    ]),
  ));

  Widget _buildParams(BuildContext context) {
    switch (type) {
      case SimType.crash:
        return _CrashParams(appName: appName, faultMod: faultMod, exception: exception,
          count: count, profile: profile, retry: retry, verify: verify,
          livePlayback: livePlayback, playbackSpeed: playbackSpeed,
          onCountChanged: onCountChanged, onProfileChanged: onProfileChanged,
          onRetryChanged: onRetryChanged, onVerifyChanged: onVerifyChanged,
          onLivePlaybackChanged: onLivePlaybackChanged, onSpeedChanged: onSpeedChanged);
      case SimType.diskspace:
        return _GenericParams(label: 'Disk Space', count: diskCount, profile: diskProfile,
          retry: diskRetry, verify: diskVerify, maxCount: 5,
          onCountChanged: onDiskCountChanged, onProfileChanged: onDiskProfileChanged,
          onRetryChanged: onDiskRetryChanged, onVerifyChanged: onDiskVerifyChanged,
          script: 'LowDiskSpace_Remediation.ps1');
      case SimType.eventlog:
        return _GenericParams(label: 'Event Log', count: elCount, profile: elProfile,
          retry: elRetry, verify: elVerify, maxCount: 3,
          onCountChanged: onElCountChanged, onProfileChanged: onElProfileChanged,
          onRetryChanged: onElRetryChanged, onVerifyChanged: onElVerifyChanged,
          script: 'Error1100_EventLogShutdown.ps1');
      case SimType.auditevents:
        return _GenericParams(label: 'Audit Events', count: aeCount, profile: aeProfile,
          retry: aeRetry, verify: aeVerify, maxCount: 3,
          onCountChanged: onAeCountChanged, onProfileChanged: onAeProfileChanged,
          onRetryChanged: onAeRetryChanged, onVerifyChanged: onAeVerifyChanged,
          script: 'Error1101_AuditEventsDropped.ps1');
      case SimType.highcpu:
        return _LiveDemoParams(
          step1: 'Writes Event ID 9999 to Windows Application Log and registers it in the DB. The live alert popup will appear on Dashboard within 5 seconds.',
          step2: 'After the alert appears, click "Auto-Remediate Now" in the popup on the Dashboard tab.',
          script1: 'Simulate_HighCpuAlert.ps1', script2: 'Remediate_HighCpuAlert.ps1');
      case SimType.servicecrash:
        return _LiveDemoParams(
          step1: 'Writes Event ID 7034 (PrintSpooler crash) to Windows Application Log. The live alert popup will appear on Dashboard within 5 seconds.',
          step2: 'After the alert appears, click "Auto-Remediate Now" in the popup on the Dashboard tab. This runs Remediate_ServiceCrash.ps1.',
          script1: 'Simulate_ServiceCrash.ps1', script2: 'Remediate_ServiceCrash.ps1');
    }
  }
}

class _ControlHeader extends StatelessWidget {
  final SimType type;
  const _ControlHeader({required this.type});

  @override
  Widget build(BuildContext context) {
    final (gradient, icon, label) = switch (type) {
      SimType.crash       => (AppTheme.gradientPrimary, Icons.bug_report_rounded, 'Crash Lab Controls'),
      SimType.diskspace   => (AppTheme.gradientPrimary, Icons.storage_rounded, 'Disk Space Lab Controls'),
      SimType.eventlog    => (AppTheme.gradientPrimary, Icons.article_rounded, 'Event Log Lab Controls'),
      SimType.auditevents => (AppTheme.gradientPrimary, Icons.gavel_rounded, 'Audit Events Lab Controls'),
      SimType.highcpu     => (AppTheme.gradientHighCpu, Icons.speed_rounded, 'High CPU Alert Lab'),
      SimType.servicecrash=> (AppTheme.gradientWarning, Icons.settings_power_rounded, 'Service Crash Lab'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Icon(icon, color: Colors.white, size: 16),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
      ]),
    );
  }
}

class _CrashParams extends StatelessWidget {
  final TextEditingController appName, faultMod, exception;
  final int count; final String profile; final bool retry, verify, livePlayback; final double playbackSpeed;
  final ValueChanged<int> onCountChanged; final ValueChanged<String> onProfileChanged;
  final ValueChanged<bool> onRetryChanged, onVerifyChanged, onLivePlaybackChanged;
  final ValueChanged<double> onSpeedChanged;

  const _CrashParams({
    required this.appName, required this.faultMod, required this.exception,
    required this.count, required this.profile, required this.retry, required this.verify,
    required this.livePlayback, required this.playbackSpeed,
    required this.onCountChanged, required this.onProfileChanged,
    required this.onRetryChanged, required this.onVerifyChanged,
    required this.onLivePlaybackChanged, required this.onSpeedChanged,
  });

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Simulates Event ID 1000 Application Crash, injects it into the engine, and auto-runs the fix.',
        style: TextStyle(color: AppTheme.textMuted, fontSize: 11, height: 1.5)),
    const SizedBox(height: 12),
    _SmallField('Application Name', appName),
    const SizedBox(height: 8),
    _SmallField('Faulting Module', faultMod),
    const SizedBox(height: 8),
    _SmallField('Exception Code', exception),
    const SizedBox(height: 8),
    _CountRow('Simulated Events', count, 1, 5, onCountChanged),
    const SizedBox(height: 8),
    _ProfileRow(profile, onProfileChanged),
    const SizedBox(height: 8),
    _CheckRow('Auto-retry on failed recovery', retry, onRetryChanged),
    _CheckRow('Verify recovery after each attempt', verify, onVerifyChanged),
    _CheckRow('Live step-by-step playback', livePlayback, onLivePlaybackChanged),
    const SizedBox(height: 8),
    _SpeedRow(playbackSpeed, onSpeedChanged),
    const SizedBox(height: 8),
    _ScriptInfo('remediation_scripts/Error1000_ApplicationCrash.ps1', 'sfc /scannow'),
  ]);
}

class _GenericParams extends StatelessWidget {
  final String label; final int count; final String profile; final bool retry, verify; final int maxCount;
  final ValueChanged<int> onCountChanged; final ValueChanged<String> onProfileChanged;
  final ValueChanged<bool> onRetryChanged, onVerifyChanged; final String script;

  const _GenericParams({
    required this.label, required this.count, required this.profile, required this.retry,
    required this.verify, required this.maxCount, required this.onCountChanged,
    required this.onProfileChanged, required this.onRetryChanged, required this.onVerifyChanged, required this.script,
  });

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('Simulates a realistic $label event, injects it into the remediation engine.',
        style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, height: 1.5)),
    const SizedBox(height: 12),
    _CountRow('Simulated Events', count, 1, maxCount, onCountChanged),
    const SizedBox(height: 8),
    _ProfileRow(profile, onProfileChanged),
    const SizedBox(height: 8),
    _CheckRow('Auto-retry on failed recovery', retry, onRetryChanged),
    _CheckRow('Verify recovery after each attempt', verify, onVerifyChanged),
    const SizedBox(height: 8),
    _ScriptInfo('remediation_scripts/$script', null),
  ]);
}

class _LiveDemoParams extends StatelessWidget {
  final String step1, step2, script1, script2;
  const _LiveDemoParams({required this.step1, required this.step2, required this.script1, required this.script2});

  @override
  Widget build(BuildContext context) => Column(children: [
    _StepBox(step: 1, label: 'Inject the Error', desc: step1, color: AppTheme.accentRed),
    const SizedBox(height: 12),
    _StepBox(step: 2, label: 'Remediate from Popup', desc: step2, color: AppTheme.accentGreen),
    const SizedBox(height: 12),
    _ScriptInfo(script1, null),
    const SizedBox(height: 4),
    _ScriptInfo(script2, null),
  ]);
}

class _StepBox extends StatelessWidget {
  final int step; final String label, desc; final Color color;
  const _StepBox({required this.step, required this.label, required this.desc, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
          child: Text('Step $step', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700))),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
      ]),
      const SizedBox(height: 6),
      Text(desc, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, height: 1.5)),
    ]),
  );
}

class _ResultPanel extends StatelessWidget {
  final List<Map<String, dynamic>> timeline;
  final Map<String, dynamic> metrics;
  final List<dynamic> resultCards;
  final String output;
  const _ResultPanel({required this.timeline, required this.metrics, required this.resultCards, required this.output});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(child: Column(children: [
    // Metrics grid
    if (metrics.isNotEmpty) ...[
      _MetricsGrid(metrics: metrics),
      const SizedBox(height: 16),
    ],
    // Timeline
    _CardWrap(title: 'Execution Timeline', icon: Icons.timeline_rounded, gradient: AppTheme.gradientSuccess,
      badge: metrics.isNotEmpty ? '${(metrics['incident_resolved'] ?? 0)} resolved' : 'No run yet',
      child: SimulationTimeline(steps: timeline)),
    const SizedBox(height: 16),
    // Result cards
    if (resultCards.isNotEmpty) ...[
      _CardWrap(title: 'Event + Rule Results', icon: Icons.fact_check_rounded, gradient: AppTheme.gradientInfo,
        child: Column(children: resultCards.map((c) => _EventResultCard(data: c as Map<String, dynamic>)).toList())),
      const SizedBox(height: 16),
    ],
    // Terminal output
    _CardWrap(title: 'Simulated Script Output', icon: Icons.terminal_rounded, gradient: AppTheme.gradientSecondary,
      child: TerminalOutput(output: output)),
  ]));
}

class _MetricsGrid extends StatelessWidget {
  final Map<String, dynamic> metrics;
  const _MetricsGrid({required this.metrics});

  @override
  Widget build(BuildContext context) => GridView.count(
    crossAxisCount: 4, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
    crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 2.0,
    children: [
      _Metric('Resolved', '${metrics['incident_resolved'] ?? 0}', AppTheme.accentGreen),
      _Metric('Escalated', '${metrics['incident_unresolved'] ?? 0}', AppTheme.accentRed),
      _Metric('Retries', '${metrics['retries_performed'] ?? 0}', AppTheme.accentYellow),
      _Metric('MTTR (s)', '${metrics['mean_time_to_recover_seconds'] ?? 0}', AppTheme.accent),
    ],
  );
}

class _Metric extends StatelessWidget {
  final String label, value; final Color color;
  const _Metric(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25))),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w800)),
      Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 10), textAlign: TextAlign.center),
    ]),
  );
}

class _EventResultCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _EventResultCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final resolved = data['resolved'] as bool? ?? false;
    final rems = data['remediations'] as List? ?? [];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgCardAlt, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: resolved ? AppTheme.accentGreen.withOpacity(0.4) : AppTheme.accentRed.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          StatusBadge(resolved ? 'completed' : 'failed'),
          const SizedBox(width: 8),
          Expanded(child: Text('Event #${data['event_row_id']}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
        ]),
        if (rems.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...rems.map((r) {
            final m = r as Map<String, dynamic>;
            return Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(children: [
              StatusBadge(m['status'] as String?),
              const SizedBox(width: 6),
              Text('${m['rule_name']} (attempt ${m['attempt']})',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            ]));
          }),
        ],
      ]),
    );
  }
}

class _CardWrap extends StatelessWidget {
  final String title; final IconData icon; final LinearGradient gradient;
  final String? badge; final Widget child;
  const _CardWrap({required this.title, required this.icon, required this.gradient, this.badge, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(gradient: gradient, borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
        child: Row(children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))),
          if (badge != null)
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
              child: Text(badge!, style: const TextStyle(color: Colors.white70, fontSize: 11))),
        ]),
      ),
      Padding(padding: const EdgeInsets.all(16), child: child),
    ]),
  );
}

// Shared helpers ─────────────────────────────────────────────────────────────
class _SmallField extends StatelessWidget {
  final String label; final TextEditingController ctrl;
  const _SmallField(this.label, this.ctrl);

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
    const SizedBox(height: 4),
    TextField(controller: ctrl, style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
        decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8))),
  ]);
}

class _CountRow extends StatelessWidget {
  final String label; final int value, min, max; final ValueChanged<int> onChanged;
  const _CountRow(this.label, this.value, this.min, this.max, this.onChanged);

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11))),
    IconButton(onPressed: value > min ? () => onChanged(value - 1) : null, icon: const Icon(Icons.remove, size: 16)),
    Text('$value', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
    IconButton(onPressed: value < max ? () => onChanged(value + 1) : null, icon: const Icon(Icons.add, size: 16)),
  ]);
}

class _ProfileRow extends StatelessWidget {
  final String value; final ValueChanged<String> onChanged;
  const _ProfileRow(this.value, this.onChanged);

  @override
  Widget build(BuildContext context) => Row(children: [
    const Expanded(child: Text('Incident Profile', style: TextStyle(color: AppTheme.textMuted, fontSize: 11))),
    DropdownButton<String>(
      value: value, dropdownColor: AppTheme.bgCardAlt,
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
      underline: const SizedBox(),
      items: const [
        DropdownMenuItem(value: 'stable', child: Text('Stable')),
        DropdownMenuItem(value: 'degraded', child: Text('Degraded')),
        DropdownMenuItem(value: 'critical', child: Text('Critical')),
      ],
      onChanged: (v) => v != null ? onChanged(v) : null,
    ),
  ]);
}

class _CheckRow extends StatelessWidget {
  final String label; final bool value; final ValueChanged<bool> onChanged;
  const _CheckRow(this.label, this.value, this.onChanged);

  @override
  Widget build(BuildContext context) => CheckboxListTile(
    value: value, onChanged: (v) => onChanged(v ?? value),
    title: Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
    dense: true, contentPadding: EdgeInsets.zero, visualDensity: VisualDensity.compact,
  );
}

class _SpeedRow extends StatelessWidget {
  final double value; final ValueChanged<double> onChanged;
  const _SpeedRow(this.value, this.onChanged);

  @override
  Widget build(BuildContext context) => Row(children: [
    const Expanded(child: Text('Playback Speed', style: TextStyle(color: AppTheme.textMuted, fontSize: 11))),
    DropdownButton<double>(
      value: value, dropdownColor: AppTheme.bgCardAlt,
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
      underline: const SizedBox(),
      items: const [
        DropdownMenuItem(value: 1.35, child: Text('Fast')),
        DropdownMenuItem(value: 1.0, child: Text('Normal')),
        DropdownMenuItem(value: 0.7, child: Text('Detailed')),
      ],
      onChanged: (v) => v != null ? onChanged(v) : null,
    ),
  ]);
}

class _ScriptInfo extends StatelessWidget {
  final String script; final String? command;
  const _ScriptInfo(this.script, this.command);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(color: AppTheme.bgCardAlt, borderRadius: BorderRadius.circular(8)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('Script: ', style: TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.w600)),
        Expanded(child: Text(script, style: const TextStyle(color: AppTheme.accent, fontSize: 10, fontFamily: 'monospace'),
            overflow: TextOverflow.ellipsis)),
      ]),
      if (command != null) ...[
        const SizedBox(height: 2),
        Row(children: [
          const Text('Fix: ', style: TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.w600)),
          Text(command!, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 10, fontFamily: 'monospace')),
        ]),
      ],
    ]),
  );
}

class _StatusBox extends StatelessWidget {
  final String message;
  const _StatusBox({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: AppTheme.accent.withOpacity(0.1), borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.accent.withOpacity(0.3))),
    child: Row(children: [
      const Icon(Icons.info_outline, color: AppTheme.accent, size: 14),
      const SizedBox(width: 8),
      Expanded(child: Text(message, style: const TextStyle(color: AppTheme.accent, fontSize: 11))),
    ]),
  );
}
