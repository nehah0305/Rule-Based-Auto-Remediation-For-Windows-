import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/alert.dart';
import '../services/api_service.dart';

class AlertPollingService extends ChangeNotifier {
  final ApiService _api;
  Timer? _timer;
  List<LiveAlert> _alerts = [];
  LiveAlert? _activeAlert;
  bool _popupDismissed = false;
  Set<int> _seenIds = {};

  List<LiveAlert> get alerts => _alerts;
  LiveAlert? get activeAlert => _activeAlert;

  AlertPollingService(this._api) {
    _startPolling();
  }

  void _startPolling() {
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
    _poll(); // immediate first poll
  }

  Future<void> _poll() async {
    try {
      final fresh = await _api.getLiveAlerts();
      _alerts = fresh;
      // Surface the newest non-remediated alert we haven't shown yet
      for (final a in fresh) {
        if (!a.remediated && !_seenIds.contains(a.id)) {
          _seenIds.add(a.id);
          _activeAlert = a;
          _popupDismissed = false;
          notifyListeners();
          return;
        }
      }
      // Update remediation state of active alert
      if (_activeAlert != null) {
        final match = fresh.where((a) => a.id == _activeAlert!.id).toList();
        if (match.isNotEmpty && match.first.remediated) {
          _activeAlert = match.first;
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  void dismissPopup() {
    _popupDismissed = true;
    _activeAlert = null;
    notifyListeners();
  }

  void markRemediated(int alertId) {
    _activeAlert = null;
    notifyListeners();
  }

  Future<void> forceRefresh() => _poll();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
