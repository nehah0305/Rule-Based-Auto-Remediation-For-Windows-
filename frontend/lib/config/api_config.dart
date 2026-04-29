import 'package:flutter/foundation.dart';

class ApiConfig {
  /// In production the Flutter app is served by Flask on port 5000,
  /// so we use window.location.origin to construct the base URL.
  /// In dev (flutter run -d web-server) on port 8080, override explicitly.
  static String get base {
    try {
      if (!kIsWeb) {
        return 'http://localhost:5000';
      }

      final origin = Uri.base.origin;
      // If running locally via flutter dev server, point to Flask explicitly
      if (origin.contains('localhost') || origin.contains('127.0.0.1')) {
        return 'http://localhost:5000';
      }
      // Production: served by Flask — use same origin
      return origin;
    } catch (_) {
      return 'http://localhost:5000';
    }
  }

  static String url(String path) => '$base$path';
}
