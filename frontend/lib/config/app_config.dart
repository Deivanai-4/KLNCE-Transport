import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;

/// App-wide configuration constants for KLNCE Smart Transport System.
///
/// Set `API_BASE_URL` at build time for any deployed app:
///
/// `flutter build apk --release --dart-define=API_BASE_URL=https://api.example.com/api`
class AppConfig {
  static const String _configuredApiUrl =
      String.fromEnvironment('API_BASE_URL');
  static const String _webDevelopmentApiUrl = 'http://127.0.0.1:5000/api';
  static const String _emulatorDevelopmentApiUrl = 'http://10.0.2.2:5000/api';

  static String get apiBaseUrl {
    final configuredUrl = _configuredApiUrl.trim();
    if (configuredUrl.isNotEmpty) {
      return configuredUrl.replaceFirst(RegExp(r'/+$'), '');
    }

    if (kDebugMode) {
      return kIsWeb ? _webDevelopmentApiUrl : _emulatorDevelopmentApiUrl;
    }

    return '';
  }

  // ─── Maps ──────────────────────────────────────────────────────────────────
  static const String googleMapsApiKey = 'YOUR_GOOGLE_MAPS_API_KEY';

  // ─── College Location (KLNCE campus, Madurai) ─────────────────────────────
  static const double collegeLatitude = 9.8820;
  static const double collegeLongitude = 78.0802;
  static const String collegeName = 'KLNCE Campus, Madurai';

  // ─── Timing ───────────────────────────────────────────────────────────────
  static const int gpsUpdateIntervalSeconds = 10;
  static const int offlineSyncIntervalMinutes = 30;

  // ─── SharedPreferences Keys ───────────────────────────────────────────────
  static const String keyAuthToken = 'auth_token';
  static const String keyLastSync = 'last_sync_time';
  static const String keyCachedSchedule = 'klnce_offline_schedule';

  // Prevent instantiation.
  AppConfig._();
}
