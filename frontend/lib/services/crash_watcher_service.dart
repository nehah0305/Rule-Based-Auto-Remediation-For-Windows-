import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';

/// Represents a detected real application crash from the Windows Event Log.
class AppCrashEvent {
  final int eventRowId;
  final String appName;
  final String message;
  final String timestamp;
  final int? ruleId;

  const AppCrashEvent({
    required this.eventRowId,
    required this.appName,
    required this.message,
    required this.timestamp,
    this.ruleId,
  });
}

/// Manages the "Watch for Crashes" mode.
///
/// When [isWatching] is true, this service polls `/api/appcrash/watch` every
/// 3 seconds — much faster than the 30-second background monitor — and fires
/// [onCrashDetected] with an [AppCrashEvent] the moment a real crash is found.
class CrashWatcherService extends ChangeNotifier {
  final ApiService _api;

  Timer? _pollTimer;
  bool _isWatching = false;
  bool _remediating = false;
  bool _remediated = false;
  AppCrashEvent? _detected;
  String? _remediationOutput;
  String? _error;

  // Track event IDs we have already surfaced so we don't re-fire for the
  // same crash on every poll.
  final Set<int> _seenEventRowIds = {};

  // ── Public state ───────────────────────────────────────────────────────────

  bool get isWatching    => _isWatching;
  bool get remediating   => _remediating;
  bool get remediated    => _remediated;
  AppCrashEvent? get detectedCrash => _detected;
  String? get remediationOutput    => _remediationOutput;
  String? get error                => _error;

  CrashWatcherService(this._api);

  // ── Watch control ──────────────────────────────────────────────────────────

  /// Arm the crash watcher. Starts polling every 3 seconds.
  void startWatching() {
    if (_isWatching) return;
    _isWatching   = true;
    _detected     = null;
    _remediated   = false;
    _remediating  = false;
    _remediationOutput = null;
    _error        = null;
    _seenEventRowIds.clear(); // Allow re-triggering for testing
    notifyListeners();

    // Immediate first poll, then every 3 seconds
    _poll();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  /// Disarm the crash watcher.
  void stopWatching() {
    _pollTimer?.cancel();
    _pollTimer   = null;
    _isWatching  = false;
    _detected    = null;
    _remediated  = false;
    _remediating = false;
    _error       = null;
    notifyListeners();
  }

  /// Reset after a crash is dismissed so we can watch for the next one.
  void reset() {
    _detected    = null;
    _remediated  = false;
    _remediating = false;
    _remediationOutput = null;
    _error       = null;
    _seenEventRowIds.clear(); // Allow re-triggering for testing
    notifyListeners();
    // Keep watching
    if (_isWatching && _pollTimer == null) {
      _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
    }
  }

  // ── Polling ────────────────────────────────────────────────────────────────

  Future<void> _poll() async {
    // Don't poll while a crash is already surfaced and waiting for user action
    if (_detected != null) return;

    try {
      final result = await _api.watchAppCrash(appName: 'notepad', windowSeconds: 60);
      final detected = result['detected'] as bool? ?? false;

      if (!detected) return;

      final eventRowId = result['event_row_id'] as int?;
      if (eventRowId == null || _seenEventRowIds.contains(eventRowId)) return;

      _seenEventRowIds.add(eventRowId);
      _detected = AppCrashEvent(
        eventRowId: eventRowId,
        appName:    (result['app_name'] as String?) ?? 'notepad',
        message:    (result['message']  as String?) ?? 'Application crashed.',
        timestamp:  (result['timestamp'] as String?) ?? DateTime.now().toIso8601String(),
        ruleId:     result['rule_id'] as int?,
      );
      _error = null;
      notifyListeners();

      // Stop the fast-poll timer — we have a crash; wait for user action.
      _pollTimer?.cancel();
      _pollTimer = null;
    } catch (e) {
      // Silently swallow poll errors; don't spam the UI
      debugPrint('[CrashWatcher] poll error: $e');
    }
  }

  // ── Remediation ────────────────────────────────────────────────────────────

  Future<void> remediate() async {
    final crash = _detected;
    if (crash == null || _remediating) return;

    _remediating = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _api.remediateAppCrash(
        eventRowId: crash.eventRowId,
        appName:    crash.appName,
      );
      _remediationOutput = result['output'] as String?;
      final status = result['status'] as String? ?? 'failed';

      if (status == 'success') {
        _remediated  = true;
        _remediating = false;
      } else {
        _error       = result['error'] as String? ?? 'Remediation failed. Check History tab for details.';
        _remediating = false;
      }
    } catch (e) {
      _error       = 'Error: $e';
      _remediating = false;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
