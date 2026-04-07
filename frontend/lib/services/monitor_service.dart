import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';

class MonitorService extends ChangeNotifier {
  final ApiService _api;
  Timer? _timer;
  Map<String, dynamic> _status = {};

  Map<String, dynamic> get status => _status;
  bool get isRunning => _status['running'] == true;
  String get lastPoll => (_status['last_poll'] as String?) ?? '';

  MonitorService(this._api) {
    _startPolling();
  }

  void _startPolling() {
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _poll());
    _poll();
  }

  Future<void> _poll() async {
    try {
      _status = await _api.getMonitorStatus();
      notifyListeners();
    } catch (_) {}
  }

  Future<Map<String, dynamic>> triggerSync() async {
    final result = await _api.triggerMonitorPoll();
    await _poll();
    return result;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
