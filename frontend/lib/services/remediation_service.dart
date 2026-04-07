import 'package:flutter/foundation.dart';

class RemediationService extends ChangeNotifier {
  /// Notifies listeners when a remediation has been completed.
  /// Used to auto-refresh History screens and Dashboard.
  
  int _remediationCount = 0;
  int get remediationCount => _remediationCount;
  
  void notifyRemediationCompleted() {
    _remediationCount++;
    notifyListeners();
  }
}
