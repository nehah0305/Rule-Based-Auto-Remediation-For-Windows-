import 'package:flutter/foundation.dart';

class ApiConfig {
  /// Build-time override for a non-default backend address, e.g. when port
  /// 5000 is taken:  flutter run -d windows --dart-define=API_URL=http://localhost:5001
  static const String _envOverride = String.fromEnvironment('API_URL');

  /// In production the Flutter app is served by Flask on port 5000,
  /// so we use window.location.origin to construct the base URL.
  /// In dev (flutter run -d web-server) on port 8080, override explicitly.
  static String get base {
    if (_envOverride.isNotEmpty) return _envOverride;
    try {
      if (!kIsWeb) {
        return 'http://localhost:5000';
      }

      final origin = Uri.base.origin;
      // If running locally on localhost
      if (origin.contains('localhost') || origin.contains('127.0.0.1')) {
        return 'http://localhost:5000';
      }
      
      // If accessed via an alternate port (like a flutter dev server port)
      if (Uri.base.port > 10000 || Uri.base.port == 8080) {
        return '${Uri.base.scheme}://${Uri.base.host}:5000';
      }

      // Production: served by Flask (port 5000) or reverse proxy (80/443) — use same origin
      return origin;
    } catch (_) {
      return 'http://localhost:5000';
    }
  }

  static String url(String path) => '$base$path';
}
