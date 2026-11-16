import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide configuration constants for KLNCE Smart Transport System.
class AppConfig {
  /// Local PC IP on Wi-Fi (Direct connection — no tunnel needed)
  static const String localWifiUrl = 'http://192.168.110.249:5000/api';

  /// Android Emulator host loopback address
  static const String emulatorUrl = 'http://10.0.2.2:5000/api';

  /// Web localhost address
  static const String webLocalhostUrl = 'http://127.0.0.1:5000/api';

  /// Public HTTPS tunnel URL (active localtunnel for mobile testing)
  static const String publicTunnelUrl = 'https://klnce-transport-api.loca.lt/api';

  /// Primary production / mobile testing API URL
  static const String productionApiUrl = publicTunnelUrl;

  static const String _configuredApiUrl =
      String.fromEnvironment('API_BASE_URL');

  static const String keyCustomApiUrl = 'klnce_production_api_url';
  static String? _customProductionUrl;

  /// Default API URL tailored to the current platform (localtunnel for mobile, localhost for web)
  static String get defaultApiUrl {
    if (kIsWeb) {
      return webLocalhostUrl;
    }
    return publicTunnelUrl;
  }

  /// Loads any custom server override saved in SharedPreferences.
  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(keyCustomApiUrl);
      if (saved != null && saved.trim().isNotEmpty) {
        _customProductionUrl = saved.trim().replaceFirst(RegExp(r'/+$'), '');
      }
    } catch (_) {}
  }

  /// Sets or clears the custom API URL.
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

  /// Active backend URL — uses custom override if saved, otherwise platform default.
  static String get apiBaseUrl {
    if (_customProductionUrl != null && _customProductionUrl!.isNotEmpty) {
      return _customProductionUrl!;
    }

    final configuredUrl = _configuredApiUrl.trim();
    if (configuredUrl.isNotEmpty) {
      return configuredUrl.replaceFirst(RegExp(r'/+$'), '');
    }

    return defaultApiUrl;
  }

  // ─── Maps ──────────────────────────────────────────────────────────────────
  static const String googleMapsApiKey = 'YOUR_GOOGLE_MAPS_API_KEY';

  // ─── College Location (KLNCE campus, Madurai) ──────────────────────────────
  static const double collegeLatitude = 9.8820;
  static const double collegeLongitude = 78.0802;
  static const String collegeName = 'KLNCE Campus, Madurai';

  // ─── Timing ────────────────────────────────────────────────────────────────
  static const int gpsUpdateIntervalSeconds = 10;
  static const int offlineSyncIntervalMinutes = 30;

  // ─── SharedPreferences Keys ────────────────────────────────────────────────
  static const String keyLastSync = 'last_sync_time';
  static const String keyCachedSchedule = 'klnce_offline_schedule';

  // Prevent instantiation.
  AppConfig._();
}
