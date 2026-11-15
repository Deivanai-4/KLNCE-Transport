import 'package:shared_preferences/shared_preferences.dart';

/// App-wide configuration constants for KLNCE Smart Transport System.
///
/// Uses one permanent production public HTTPS backend URL across all platforms
/// (Android mobile app, Web, Wi-Fi, and Cellular 4G/5G mobile data).
class AppConfig {
  /// Permanent Production API Base URL (Public HTTPS)
  /// Works across all networks without requiring local IP or Wi-Fi configuration.
  static const String productionApiUrl =
      'https://klnce-transport-api.loca.lt/api';

  static const String _configuredApiUrl =
      String.fromEnvironment('API_BASE_URL');

  static const String keyCustomApiUrl = 'klnce_production_api_url';
  static String? _customProductionUrl;

  /// Loads any custom production override (if configured).
  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
      final saved = prefs.getString(keyCustomApiUrl);
      if (saved != null && saved.trim().isNotEmpty) {
        _customProductionUrl = saved.trim().replaceFirst(RegExp(r'/+$'), '');
      }
    } catch (_) {}
  }

  /// Sets or clears the production URL.
  static Future<void> setCustomApiUrl(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url == null || url.trim().isEmpty) {
      _customProductionUrl = null;
      await prefs.remove(keyCustomApiUrl);
    } else {
      _customProductionUrl = url.trim().replaceFirst(RegExp(r'/+$'), '');
      await prefs.setString(keyCustomApiUrl, _customProductionUrl!);
    }
  }

  /// Active backend URL — strictly public HTTPS production endpoint.
  /// Works identically on Wi-Fi and mobile data.
  static String get apiBaseUrl {
    if (_customProductionUrl != null && _customProductionUrl!.isNotEmpty) {
      return _customProductionUrl!;
    }

    final configuredUrl = _configuredApiUrl.trim();
    if (configuredUrl.isNotEmpty) {
      return configuredUrl.replaceFirst(RegExp(r'/+$'), '');
    }

    return productionApiUrl;
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
  static const String keyLastSync = 'last_sync_time';
  static const String keyCachedSchedule = 'klnce_offline_schedule';

  // Prevent instantiation.
  AppConfig._();
}
