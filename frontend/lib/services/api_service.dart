import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException ($statusCode): $message';
}

/// Central HTTP client for all KLNCE Transport API calls.
///
/// Production flow (always used in release builds, and in debug when
/// production is reachable):
///   App → https://klnce-transport.onrender.com/api → MongoDB Atlas
///
/// Debug-only automatic fallback order (when production is unreachable):
///   1. Render production URL
///   2. LocalTunnel dev URL  (requires `lt` running on dev PC)
///   3. LAN Wi-Fi IP         (requires phone & PC on same Wi-Fi)
///   4. Android emulator IP
///   5. Web localhost
///
/// NO fallback occurs in release/production mode.
class ApiService {
  static const _tokenKey = 'klnce_jwt_token';
  static String? _cachedToken;

  /// The resolved working endpoint (null = use production default).
  /// Only set during debug when production is unreachable.
  static String? _activeFallbackUrl;

  /// Broadcasts human-readable status to connection indicator widgets.
  static final ValueNotifier<String?> statusNotifier =
      ValueNotifier<String?>(null);

  // ── Token management ──────────────────────────────────────────────────────

  static String? get savedToken => _cachedToken;

  static Future<void> saveToken(String token) async {
    _cachedToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  static Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedToken = prefs.getString(_tokenKey);
  }

  static Future<void> clearToken() async {
    _cachedToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  // ── URL resolution ────────────────────────────────────────────────────────

  /// The active base URL.
  /// In release mode: always the production URL.
  /// In debug mode: production URL unless a working fallback was auto-detected.
  static String get baseUrl {
    // Release mode: never use a dev URL under any circumstance.
    if (kReleaseMode) {
      _activeFallbackUrl = null;
      return AppConfig.productionApiUrl;
    }

    // Debug mode: use the last known-working URL if production was unreachable.
    if (_activeFallbackUrl != null && _activeFallbackUrl!.isNotEmpty) {
      return _activeFallbackUrl!;
    }

    return AppConfig.apiBaseUrl; // Returns production URL by default
  }

  static Uri _uriFor(String endpoint, [String? overrideBase]) {
    final base = overrideBase ?? baseUrl;
    if (base.isEmpty) {
      throw ApiException(503, 'Server URL is not configured.');
    }
    final raw = '$base$endpoint';
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasAuthority) {
      throw ApiException(503, 'Invalid server address: $base');
    }
    return uri;
  }

  // ── Health check ──────────────────────────────────────────────────────────

  /// Ping /health to verify backend reachability.
  /// Handles Render cold-start window (up to 45 seconds) seamlessly.
  static Future<bool> testHealth([String? candidateUrl]) async {
    // If a specific candidate was supplied by the user via the test dialog,
    // ping that URL only.
    if (candidateUrl != null && candidateUrl.trim().isNotEmpty) {
      final clean = candidateUrl.trim().replaceFirst(RegExp(r'/+$'), '');
      statusNotifier.value = 'Testing connection…';
      final ok = await _pingUrl(clean, timeoutMs: 15000);
      statusNotifier.value = null;
      if (ok) {
        _activeFallbackUrl = clean;
        await AppConfig.setCustomApiUrl(clean);
      }
      return ok;
    }

    final current = baseUrl;
    statusNotifier.value = 'Connecting to server…';

    // 1. Initial health ping (12 seconds)
    if (await _pingUrl(current, timeoutMs: 12000)) {
      statusNotifier.value = null;
      return true;
    }

    // 2. Render container spin-up (cold-start window up to 45 seconds)
    if (current.contains('onrender.com') || AppConfig.isProduction) {
      statusNotifier.value = 'Server is waking up, please wait…';
      final ok = await _pingUrl(AppConfig.productionApiUrl, timeoutMs: 45000);
      statusNotifier.value = null;
      return ok;
    }

    statusNotifier.value = null;
    return false;
  }

  /// Low-level ping helper. Returns true iff /health responds with HTTP 200.
  static Future<bool> _pingUrl(String url, {required int timeoutMs}) async {
    try {
      final headers = <String, String>{};
      if (url.contains('loca.lt')) {
        headers['bypass-tunnel-reminder'] = '1';
      }
      final res = await http
          .get(Uri.parse('$url/health'), headers: headers)
          .timeout(Duration(milliseconds: timeoutMs));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Headers ───────────────────────────────────────────────────────────────

  static Map<String, String> _buildHeaders({
    bool isJson = true,
    String? targetUrl,
  }) {
    final url = targetUrl ?? baseUrl;
    final headers = <String, String>{};
    if (url.contains('loca.lt')) {
      headers['bypass-tunnel-reminder'] = '1';
    }
    if (isJson) {
      headers['Content-Type'] = 'application/json';
    }
    final token = _cachedToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  // ── Internal request runner with smart retry ──────────────────────────────

  /// Sends a request with smart cold-start retrying on production.
  static Future<http.Response> _runWithFallback(
    Future<http.Response> Function(String base) sendRequest,
  ) async {
    final targetUrl = baseUrl;
    final isProductionTarget = !AppConfig.isDevelopmentUrl(targetUrl);

    // ── First attempt ────────────────────────────────────────────────────────
    try {
      final res = await sendRequest(targetUrl);
      if (_isBadGateway(res, targetUrl)) {
        throw http.ClientException('Server returned gateway status ${res.statusCode}');
      }
      statusNotifier.value = null;
      return res;
    } catch (e) {
      if (!_isNetworkError(e)) {
        statusNotifier.value = null;
        rethrow;
      }

      debugPrint('[ApiService] Request to $targetUrl failed: $e');

      // ── Cold-start retry for production Render backend (up to 2 attempts) ──
      if (isProductionTarget || targetUrl.contains('onrender.com')) {
        statusNotifier.value = 'Server is waking up, please wait…';
        try {
          await Future.delayed(const Duration(seconds: 4));
          for (int attempt = 1; attempt <= 2; attempt++) {
            try {
              final retry = await sendRequest(targetUrl);
              if (!_isBadGateway(retry, targetUrl)) return retry;
            } catch (retryErr) {
              debugPrint('[ApiService] Cold-start retry $attempt: $retryErr');
              if (attempt < 2) {
                await Future.delayed(const Duration(seconds: 6));
              }
            }
          }
        } finally {
          statusNotifier.value = null;
        }

        throw ApiException(
          503,
          'The transport server is starting up or temporarily unreachable. Please tap Retry in a moment.',
        );
      }

      throw ApiException(
        503,
        'Unable to reach server at $targetUrl. Please check your network connection.',
      );
    }
  }

  static bool _isBadGateway(http.Response res, String url) =>
      res.statusCode == 502 ||
      res.statusCode == 503 ||
      (url.contains('loca.lt') && res.statusCode == 403);

  static bool _isNetworkError(Object e) =>
      e is SocketException ||
      e is http.ClientException ||
      e is TimeoutException;

  // ── Login (unauthenticated) ───────────────────────────────────────────────

  static Future<Map<String, dynamic>> postLogin({
    required String email,
    required String password,
  }) async {
    final bodyStr = jsonEncode({'email': email, 'password': password});
    final response = await _runWithFallback((base) async {
      return http
          .post(_uriFor('/auth/login', base),
              headers: _buildHeaders(targetUrl: base), body: bodyStr)
          .timeout(const Duration(seconds: 45));
    });
    return _handleResponse(response);
  }

  // ── Byte download (e.g. Excel template) ──────────────────────────────────

  static Future<List<int>> getBytes(String endpoint) async {
    final response = await _runWithFallback((base) async {
      return http
          .get(_uriFor(endpoint, base),
              headers: _buildHeaders(targetUrl: base, isJson: false))
          .timeout(const Duration(seconds: 45));
    });
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.bodyBytes;
    }
    throw ApiException(response.statusCode,
        'Download failed with status ${response.statusCode}');
  }

  // ── Standard authenticated CRUD methods ───────────────────────────────────

  static Future<Map<String, dynamic>> get(String endpoint) async {
    final response = await _runWithFallback((base) async {
      return http
          .get(_uriFor(endpoint, base), headers: _buildHeaders(targetUrl: base))
          .timeout(const Duration(seconds: 45));
    });
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> post(
      String endpoint, Map<String, dynamic> body) async {
    final bodyStr = jsonEncode(body);
    final response = await _runWithFallback((base) async {
      return http
          .post(_uriFor(endpoint, base),
              headers: _buildHeaders(targetUrl: base), body: bodyStr)
          .timeout(const Duration(seconds: 45));
    });
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> put(
      String endpoint, Map<String, dynamic> body) async {
    final bodyStr = jsonEncode(body);
    final response = await _runWithFallback((base) async {
      return http
          .put(_uriFor(endpoint, base),
              headers: _buildHeaders(targetUrl: base), body: bodyStr)
          .timeout(const Duration(seconds: 45));
    });
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> delete(String endpoint) async {
    final response = await _runWithFallback((base) async {
      return http
          .delete(_uriFor(endpoint, base),
              headers: _buildHeaders(targetUrl: base))
          .timeout(const Duration(seconds: 45));
    });
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> postMultipart({
    required String endpoint,
    required Map<String, String> fields,
    required String fileParamName,
    required String filePath,
    List<int>? fileBytes,
    String? fileName,
  }) async {
    final uri = _uriFor(endpoint);
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_buildHeaders(isJson: false));
    request.fields.addAll(fields);

    if (fileBytes != null && fileName != null) {
      request.files.add(http.MultipartFile.fromBytes(
        fileParamName,
        fileBytes,
        filename: fileName,
      ));
    } else if (filePath.isNotEmpty) {
      request.files.add(await http.MultipartFile.fromPath(
        fileParamName,
        filePath,
      ));
    }

    final streamed = await request.send().timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        throw ApiException(408, 'Upload timed out. Check your connection.');
      },
    );
    final response = await http.Response.fromStream(streamed);
    return _handleResponse(response);
  }

  // ── Response handler ──────────────────────────────────────────────────────

  static Map<String, dynamic> _handleResponse(http.Response response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = {'message': response.body};
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decoded is Map<String, dynamic>) return decoded;
      return {'data': decoded};
    }

    final msg = decoded is Map && decoded['error'] != null
        ? decoded['error'].toString()
        : (decoded is Map && decoded['message'] != null
            ? decoded['message'].toString()
            : 'Server error (${response.statusCode})');
    throw ApiException(response.statusCode, msg);
  }
}
