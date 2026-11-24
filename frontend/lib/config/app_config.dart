import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide configuration constants for KLNCE Smart Transport System.
///
/// PRODUCTION ARCHITECTURE:
///   Flutter App → https://klnce-transport.onrender.com/api → MongoDB Atlas
///
/// The app always uses the Render production URL in release builds.
/// In debug builds it also tries the production URL first, then falls back to
/// local development URLs only if production is unreachable.
class AppConfig {
  // ─── Production URL (single source of truth) ─────────────────────────────
  /// Deployed Render.com backend — this is the ONLY permanent backend URL.
  static const String renderProductionUrl =
      'https://klnce-transport.onrender.com/api';

  /// Alias for clarity.
  static const String productionApiUrl = renderProductionUrl;

  // ─── Local Development URLs (never used in release builds) ───────────────
  /// Developer's PC LAN IP — only works when phone & PC share the same Wi-Fi.
  static const String localWifiUrl = 'http://192.168.251.249:5000/api';

  /// Android Emulator host loopback.
  static const String emulatorUrl = 'http://10.0.2.2:5000/api';

  /// Web browser localhost.
  static const String webLocalhostUrl = 'http://127.0.0.1:5000/api';

  /// LocalTunnel dev URL — only works when `lt` tunnel is running on dev PC.
  static const String publicTunnelUrl = 'https://klnce-transport-api.loca.lt/api';

  // ─── Compile-time override (optional — set via --dart-define=API_BASE_URL=...)
  static const String _configuredApiUrl =
      String.fromEnvironment('API_BASE_URL');

  static const String keyCustomApiUrl = 'klnce_custom_api_url';
  static String? _customUrl;

  /// Whether the given URL is a local/dev address (not safe for production).
  static bool isDevelopmentUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('localhost') ||
        lower.contains('127.0.0.1') ||
        lower.contains('10.0.2.2') ||
        lower.contains('192.168.') ||
        lower.contains('172.16.') ||
        lower.contains('loca.lt');
  }

  /// True when running in a production configuration.
  /// Release mode → always true.
  /// Debug mode → true only if no dev URL is active.
  static bool get isProduction {
    if (kReleaseMode) return true;
    return !isDevelopmentUrl(apiBaseUrl);
  }

  /// Single invariant default API base URL for the entire application:
  /// Always points to the deployed Render cloud backend across Web, Android, iOS.
  static String get defaultApiUrl => productionApiUrl;

  /// The effective API base URL for the current build and runtime.
  ///
  /// Priority (highest → lowest):
  ///   1. Deliberate runtime override saved in SharedPreferences (via admin test dialog)
  ///   2. Explicit compile-time override via --dart-define=API_BASE_URL=...
  ///   3. Always the production Render cloud endpoint: https://klnce-transport.onrender.com/api
  static String get apiBaseUrl {
    // 1. Deliberate runtime override
    if (_customUrl != null && _customUrl!.isNotEmpty) {
      return _customUrl!;
    }

    // 2. Explicit compile-time override
    final configuredUrl = _configuredApiUrl.trim();
    if (configuredUrl.isNotEmpty) {
      return configuredUrl.replaceFirst(RegExp(r'/+$'), '');
    }

    // 3. Default: Always the production Render URL
    return productionApiUrl;
  }

  /// Web debug shortcut — for reference only, never used as silent override.
  static String get webDebugUrl => webLocalhostUrl;

  /// Load any saved custom URL override from SharedPreferences.
  /// Automatically purges stale localhost, LAN IP, and tunnel URLs.
  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in [keyCustomApiUrl, 'klnce_production_api_url']) {
        final saved = prefs.getString(key);
        if (saved != null) {
          final clean = saved.trim().replaceFirst(RegExp(r'/+$'), '');
          // Always discard stale localhost, LAN IP, or tunnel URLs so they
          // can NEVER silently hijack the application.
          if (isDevelopmentUrl(clean)) {
            await prefs.remove(key);
          } else if (clean.isNotEmpty && _customUrl == null) {
            _customUrl = clean;
          }
        }
      }
    } catch (_) {}
  }

  /// Save a custom server URL (used by the admin connection test dialog).
  /// Pass null to clear and revert to the production URL.
  static Future<void> setCustomApiUrl(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url == null || url.trim().isEmpty) {
      _customUrl = null;
      await prefs.remove(keyCustomApiUrl);
    } else {
      _customUrl = url.trim().replaceFirst(RegExp(r'/+$'), '');
      await prefs.setString(keyCustomApiUrl, _customUrl!);
    }
  }

  // ─── Maps ─────────────────────────────────────────────────────────────────
  static const String googleMapsApiKey = 'YOUR_GOOGLE_MAPS_API_KEY';

  // ─── College Location (KLNCE campus, Madurai) ─────────────────────────────
  static const double collegeLatitude = 9.8820;
  static const double collegeLongitude = 78.0802;
  static const String collegeName = 'KLNCE Campus, Madurai';

  // ─── Polling / sync intervals ─────────────────────────────────────────────
  static const int gpsUpdateIntervalSeconds = 10;
  static const int offlineSyncIntervalMinutes = 30;

  // ─── SharedPreferences Keys ───────────────────────────────────────────────
  static const String keyLastSync = 'last_sync_time';
  static const String keyCachedSchedule = 'klnce_offline_schedule';

  // Prevent instantiation.
  AppConfig._();
}
