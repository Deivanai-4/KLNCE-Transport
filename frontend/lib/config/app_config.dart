import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide configuration constants for KLNCE Smart Transport System.
class AppConfig {
  static const String _configuredApiUrl =
      String.fromEnvironment('API_BASE_URL');
  static const String _webDevelopmentApiUrl = 'http://127.0.0.1:5000/api';
  
  // Public HTTPS URL accessible from ANY mobile network (4G/5G, LTE, no Wi-Fi needed)
  static const String defaultPublicApiUrl =
      'https://ciao-michael-wireless-baltimore.trycloudflare.com/api';

  // Local LAN IP fallback
  static const String defaultLocalLanApiUrl = 'http://192.168.85.249:5000/api';

  static const String keyCustomApiUrl = 'custom_api_base_url';
  static String? _customApiUrl;

  /// Loads any user-saved backend URL from local device storage.
  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(keyCustomApiUrl);
      if (saved != null && saved.trim().isNotEmpty) {
        _customApiUrl = saved.trim().replaceFirst(RegExp(r'/+$'), '');
      }
    } catch (_) {}
  }

  /// Sets or clears a custom backend URL.
  static Future<void> setCustomApiUrl(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url == null || url.trim().isEmpty) {
      _customApiUrl = null;
      await prefs.remove(keyCustomApiUrl);
    } else {
      _customApiUrl = url.trim().replaceFirst(RegExp(r'/+$'), '');
      await prefs.setString(keyCustomApiUrl, _customApiUrl!);
    }
  }

  /// Active backend URL with intelligent fallbacks.
  static String get apiBaseUrl {
    // 1. Manually configured URL saved by user in app settings
    if (_customApiUrl != null && _customApiUrl!.isNotEmpty) {
      return _customApiUrl!;
    }

    // 2. Set at build time via --dart-define=API_BASE_URL=...
    final configuredUrl = _configuredApiUrl.trim();
    if (configuredUrl.isNotEmpty) {
      return configuredUrl.replaceFirst(RegExp(r'/+$'), '');
    }

    // 3. Web browser environment
    if (kIsWeb) {
      return _webDevelopmentApiUrl;
    }

    // 4. Default for physical mobile device (works on cellular/mobile data!)
    return defaultPublicApiUrl;
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
