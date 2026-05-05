import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';
import '../services/api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Task Scheduler Screen
//  Shows the live status of the Windows Task Scheduler integration, lets the
//  operator install/verify tasks, monitor logs, and toggle the mode.
// ─────────────────────────────────────────────────────────────────────────────

class TaskSchedulerScreen extends StatefulWidget {
  const TaskSchedulerScreen({super.key});
  @override
  State<TaskSchedulerScreen> createState() => _TaskSchedulerScreenState();
}

class _TaskSchedulerScreenState extends State<TaskSchedulerScreen> {
  final _api = ApiService();

  bool _loadingStatus = true;
  Map<String, dynamic> _monitorStatus = {};
  String _logContent = '';
  bool _loadingLog = false;
  String? _error;

  // The 8 tasks registered by Setup_EventTriggers.ps1
  static const _registeredTasks = [
    _TaskInfo(id: 1000, log: 'Application', name: 'AutoRemediate_AppCrash_1000',      label: 'Application Crash',              icon: Icons.bug_report_rounded,         color: Color(0xFFff4e50)),
    _TaskInfo(id: 1001, log: 'Application', name: 'AutoRemediate_AppHang_1001',       label: 'Application Hang',               icon: Icons.pause_circle_rounded,        color: Color(0xFFfc913a)),
    _TaskInfo(id: 1026, log: 'Application', name: 'AutoRemediate_DotNetCrash_1026',   label: '.NET Runtime Crash',              icon: Icons.code_rounded,                color: Color(0xFF9d4edd)),
    _TaskInfo(id: 7034, log: 'System',      name: 'AutoRemediate_ServiceFail_7034',   label: 'Service Terminated (7034)',       icon: Icons.settings_rounded,            color: Color(0xFFff4e50)),
    _TaskInfo(id: 7031, log: 'System',      name: 'AutoRemediate_ServiceFail_7031',   label: 'Service Terminated (7031)',       icon: Icons.settings_rounded,            color: Color(0xFFfc913a)),
    _TaskInfo(id: 7000, log: 'System',      name: 'AutoRemediate_ServiceStart_7000',  label: 'Service Failed to Start',         icon: Icons.play_disabled_rounded,       color: Color(0xFFf9d423)),
    _TaskInfo(id: 11,   log: 'System',      name: 'AutoRemediate_DiskError_11',        label: 'Disk Controller Error',           icon: Icons.storage_rounded,             color: Color(0xFFfc913a)),
    _TaskInfo(id: 55,   log: 'System',      name: 'AutoRemediate_NTFSCorruption_55',  label: 'NTFS Corruption',                 icon: Icons.folder_off_rounded,          color: Color(0xFFff4e50)),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loadingStatus = true; _error = null; });
    try {
      final status = await _api.getMonitorStatus();
      if (mounted) setState(() { _monitorStatus = status; _loadingStatus = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loadingStatus = false; });
    }
  }

  Future<void> _loadLog() async {
    setState(() { _loadingLog = true; });
    try {
      final log = await _api.getUnifiedLog();
      if (mounted) setState(() { _logContent = log; _loadingLog = false; });
    } catch (e) {
      if (mounted) setState(() { _logContent = 'Error loading log: $e'; _loadingLog = false; });
    }
  }

  Future<void> _forcePoll() async {
    try {
      final result = await _api.triggerMonitorPoll();
      final count = result['events_ingested'] ?? 0;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✓ Immediate poll complete — $count new event(s) ingested.'),
          backgroundColor: AppTheme.accentGreen,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Poll failed: $e'),
          backgroundColor: AppTheme.accentRed,
        ));
      }
    }
  }

  void _copySetupCommand() {
    const cmd = r'powershell -ExecutionPolicy Bypass -File .\remediation_scripts\Setup_EventTriggers.ps1';
    Clipboard.setData(const ClipboardData(text: cmd));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Setup command copied to clipboard!'),
      backgroundColor: AppTheme.accent,
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.all(16),
      duration: Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Top status bar ─────────────────────────────────────────────────
        _StatusBanner(status: _monitorStatus, loading: _loadingStatus, error: _error, onRefresh: _load),
        const SizedBox(height: 20),

        // ── Two-column layout ───────────────────────────────────────────────
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Left: Task list + setup card
          Expanded(
            flex: 3,
            child: Column(children: [
              _SetupCard(onCopy: _copySetupCommand),
              const SizedBox(height: 16),
              _WatchedTasksCard(tasks: _registeredTasks),
            ]),
          ),
          const SizedBox(width: 16),
          // Right: Loop diagram + manual controls
          Expanded(
            flex: 2,
            child: Column(children: [
              _LoopDiagramCard(),
              const SizedBox(height: 16),
              _ManualControlsCard(
                onForcePoll: _forcePoll,
                onLoadLog: _loadLog,
                loadingLog: _loadingLog,
                logContent: _logContent,
              ),
            ]),
          ),
        ]),
      ]),
    );
  }
}

// ─── Data class ──────────────────────────────────────────────────────────────

class _TaskInfo {
  final int id;
  final String log;
  final String name;
  final String label;
  final IconData icon;
  final Color color;
  const _TaskInfo({required this.id, required this.log, required this.name,
    required this.label, required this.icon, required this.color});
}

// ─── Status Banner ───────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final Map<String, dynamic> status;
  final bool loading;
  final String? error;
  final VoidCallback onRefresh;
  const _StatusBanner({required this.status, required this.loading, this.error, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final isRunning   = status['thread_alive'] == true;
    final lastPoll    = status['last_poll'] as String?;
    final ingested    = status['events_ingested'] ?? 0;
    final interval    = status['poll_interval_s'] ?? 30;

    String modeLabel;
    Color  modeColor;
    IconData modeIcon;

    if (loading) {
      modeLabel = 'Checking status…';
      modeColor = AppTheme.textMuted;
      modeIcon  = Icons.hourglass_empty_rounded;
    } else if (error != null) {
      modeLabel = 'Backend unreachable';
      modeColor = AppTheme.accentRed;
      modeIcon  = Icons.error_outline_rounded;
    } else if (isRunning) {
      modeLabel = 'Polling Mode Active (every ${interval}s)';
      modeColor = AppTheme.accentYellow;
      modeIcon  = Icons.sync_rounded;
    } else {
      modeLabel = 'Task Scheduler Mode Active';
      modeColor = AppTheme.accentGreen;
      modeIcon  = Icons.task_alt_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: modeColor.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: modeColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(modeIcon, color: modeColor, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(modeLabel, style: TextStyle(color: modeColor, fontWeight: FontWeight.w700, fontSize: 14)),
          if (!loading && error == null) ...[
            const SizedBox(height: 2),
            Text(
              'Total ingested: $ingested event(s)  •  Last poll: ${_fmt(lastPoll)}',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
            ),
          ],
          if (error != null)
            Text(error!, style: const TextStyle(color: AppTheme.accentRed, fontSize: 11)),
        ])),
        IconButton(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded, size: 18, color: AppTheme.textMuted),
          tooltip: 'Refresh status',
        ),
      ]),
    );
  }

  String _fmt(String? ts) {
    if (ts == null) return 'Never';
    try { return '${DateTime.parse(ts).toLocal()}'.substring(0, 19); } catch (_) { return ts; }
  }
}

// ─── Setup Card ──────────────────────────────────────────────────────────────

class _SetupCard extends StatelessWidget {
  final VoidCallback onCopy;
  const _SetupCard({required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return _Card(
      headerGradient: AppTheme.gradientPurple,
      headerIcon: Icons.install_desktop_rounded,
      headerTitle: 'Setup Task Scheduler (One-Time)',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
          'Run this command once from your project root as Administrator. '
          'It will self-elevate and register all 8 watchdog tasks automatically.',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 12, height: 1.6),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0d0d1f),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(children: [
            const Icon(Icons.terminal_rounded, size: 14, color: AppTheme.accentPurple),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                r'powershell -ExecutionPolicy Bypass -File .\remediation_scripts\Setup_EventTriggers.ps1',
                style: TextStyle(color: AppTheme.accentGreen, fontSize: 11, fontFamily: 'monospace'),
              ),
            ),
            IconButton(
              onPressed: onCopy,
              icon: const Icon(Icons.copy_rounded, size: 15, color: AppTheme.textMuted),
              tooltip: 'Copy to clipboard',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        _Step(num: '1', text: 'Run the command above in any terminal (UAC prompt will appear)'),
        _Step(num: '2', text: 'Click "Yes" to allow Administrator access'),
        _Step(num: '3', text: 'Add USE_TASK_SCHEDULER=true to your .env file'),
        _Step(num: '4', text: 'Restart Flask — the polling thread will be disabled automatically'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.accentGreen.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.25)),
          ),
          child: const Row(children: [
            Icon(Icons.verified_rounded, size: 14, color: AppTheme.accentGreen),
            SizedBox(width: 8),
            Expanded(child: Text(
              'Verify: Open Task Scheduler → Task Scheduler Library → AutoRemediation',
              style: TextStyle(color: AppTheme.accentGreen, fontSize: 11),
            )),
          ]),
        ),
      ]),
    );
  }
}

class _Step extends StatelessWidget {
  final String num;
  final String text;
  const _Step({required this.num, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 18, height: 18,
        decoration: BoxDecoration(
          color: AppTheme.accentPurple.withValues(alpha: 0.2),
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.accentPurple.withValues(alpha: 0.5)),
        ),
        child: Center(child: Text(num, style: const TextStyle(color: AppTheme.accentPurple, fontSize: 9, fontWeight: FontWeight.w700))),
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12))),
    ]),
  );
}

// ─── Watched Tasks Card ───────────────────────────────────────────────────────

class _WatchedTasksCard extends StatelessWidget {
  final List<_TaskInfo> tasks;
  const _WatchedTasksCard({required this.tasks});

  @override
  Widget build(BuildContext context) {
    return _Card(
      headerGradient: AppTheme.gradientInfo,
      headerIcon: Icons.list_alt_rounded,
      headerTitle: '8 Watched Event Triggers',
      child: Column(
        children: tasks.map((t) => _TaskRow(task: t)).toList(),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final _TaskInfo task;
  const _TaskRow({required this.task});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AppTheme.bgCardAlt,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppTheme.border),
    ),
    child: Row(children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: task.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(task.icon, color: task.color, size: 16),
      ),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(task.label, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
        Text('${task.name}  •  Log: ${task.log}', style: const TextStyle(color: AppTheme.textDimmed, fontSize: 10)),
      ])),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: task.color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: task.color.withValues(alpha: 0.3)),
        ),
        child: Text('ID ${task.id}', style: TextStyle(color: task.color, fontSize: 10, fontWeight: FontWeight.w700)),
      ),
    ]),
  );
}

// ─── Loop Diagram Card ───────────────────────────────────────────────────────

class _LoopDiagramCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _Card(
      headerGradient: AppTheme.gradientSuccess,
      headerIcon: Icons.loop_rounded,
      headerTitle: 'The Perfect Loop',
      child: Column(children: [
        _LoopStep(icon: Icons.error_outline_rounded,  color: AppTheme.accentRed,    title: 'Error Fires',        sub: 'Windows Event Log receives critical/error event'),
        _Arrow(),
        _LoopStep(icon: Icons.task_alt_rounded,       color: AppTheme.accentYellow, title: 'Task Scheduler',     sub: 'Instantly wakes — zero polling delay, zero idle CPU'),
        _Arrow(),
        _LoopStep(icon: Icons.psychology_rounded,     color: AppTheme.accentPurple, title: 'Python Detective',   sub: 'cli_process_event.py — Root Cause Variant analysis'),
        _Arrow(),
        _LoopStep(icon: Icons.terminal_rounded,       color: AppTheme.accent,       title: 'PowerShell Muscle',  sub: 'Specific remediation script executes the exact fix'),
        _Arrow(),
        _LoopStep(icon: Icons.bar_chart_rounded,      color: AppTheme.accentGreen,  title: 'Dashboard Updated',  sub: 'Event + result logged to DB — visible in Flutter UI'),
      ]),
    );
  }
}

class _LoopStep extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String sub;
  const _LoopStep({required this.icon, required this.color, required this.title, required this.sub});

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Icon(icon, color: color, size: 18),
    ),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
      Text(sub,   style: const TextStyle(color: AppTheme.textMuted,   fontSize: 10, height: 1.4)),
    ])),
  ]);
}

class _Arrow extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 16, top: 3, bottom: 3),
    child: const Icon(Icons.arrow_downward_rounded, size: 14, color: AppTheme.textDimmed),
  );
}

// ─── Manual Controls Card ────────────────────────────────────────────────────

class _ManualControlsCard extends StatefulWidget {
  final Future<void> Function() onForcePoll;
  final Future<void> Function() onLoadLog;
  final bool loadingLog;
  final String logContent;
  const _ManualControlsCard({
    required this.onForcePoll,
    required this.onLoadLog,
    required this.loadingLog,
    required this.logContent,
  });

  @override
  State<_ManualControlsCard> createState() => _ManualControlsCardState();
}

class _ManualControlsCardState extends State<_ManualControlsCard> {
  bool _polling = false;

  Future<void> _poll() async {
    setState(() => _polling = true);
    await widget.onForcePoll();
    if (mounted) setState(() => _polling = false);
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      headerGradient: AppTheme.gradientWarning,
      headerIcon: Icons.tune_rounded,
      headerTitle: 'Manual Controls',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Force poll button
        _ControlButton(
          icon: Icons.bolt_rounded,
          label: 'Force Immediate Poll',
          sub: 'Manually trigger one event-log poll cycle right now',
          color: AppTheme.accent,
          loading: _polling,
          onTap: _poll,
        ),
        const SizedBox(height: 10),
        // Load log button
        _ControlButton(
          icon: Icons.article_rounded,
          label: 'Load Unified Log',
          sub: 'View remediation_system.log (shared by Flask + CLI)',
          color: AppTheme.accentPurple,
          loading: widget.loadingLog,
          onTap: widget.onLoadLog,
        ),
        // Log viewer
        if (widget.logContent.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            height: 200,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0a0a18),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border),
            ),
            child: Scrollbar(
              child: SingleChildScrollView(
                child: SelectableText(
                  widget.logContent,
                  style: const TextStyle(
                    color: AppTheme.accentGreen,
                    fontSize: 10,
                    fontFamily: 'monospace',
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        // Log file locations info
        _InfoBox(
          icon: Icons.folder_open_rounded,
          color: AppTheme.accentYellow,
          lines: [
            'Unified log: backend/data/remediation_system.log',
            'Crash log:   backend/data/task_scheduler_crash.log',
          ],
        ),
      ]),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final Color color;
  final bool loading;
  final VoidCallback onTap;
  const _ControlButton({required this.icon, required this.label, required this.sub,
    required this.color, required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: loading ? null : onTap,
    borderRadius: BorderRadius.circular(10),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        loading
          ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: color))
          : Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
          Text(sub,   style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
        ])),
        Icon(Icons.chevron_right_rounded, color: color.withValues(alpha: 0.5), size: 16),
      ]),
    ),
  );
}

class _InfoBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final List<String> lines;
  const _InfoBox({required this.icon, required this.color, required this.lines});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 8),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines.map((l) => Text(l,
          style: TextStyle(color: color.withValues(alpha: 0.85), fontSize: 10, fontFamily: 'monospace'))).toList(),
      )),
    ]),
  );
}

// ─── Shared card shell ───────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final LinearGradient headerGradient;
  final IconData headerIcon;
  final String headerTitle;
  final Widget child;
  const _Card({required this.headerGradient, required this.headerIcon,
    required this.headerTitle, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppTheme.bgCard,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppTheme.border),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Header
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: headerGradient,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
        ),
        child: Row(children: [
          Icon(headerIcon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(headerTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
      ),
      // Body
      Padding(padding: const EdgeInsets.all(16), child: child),
    ]),
  );
}
