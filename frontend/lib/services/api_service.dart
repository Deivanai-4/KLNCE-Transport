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

class ApiService {
  static const _tokenKey = 'klnce_jwt_token';
  static String? _cachedToken;
  static String? _activeFallbackUrl;

  /// Candidate local LAN endpoints to seamlessly fallback to when on the same Wi-Fi
  static const List<String> _lanCandidates = [
    'http://10.37.38.249:5000/api',
    'http://192.168.90.249:5000/api',
    'http://10.83.140.249:5000/api',
    'http://10.0.2.2:5000/api',
    'http://127.0.0.1:5000/api',
  ];

  // ── Token management ──────────────────────────────────────────────────────

  /// The JWT token saved from the last login.
  static String? get savedToken => _cachedToken;

  /// Persist and cache the JWT token after login.
  static Future<void> saveToken(String token) async {
    _cachedToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  /// Load token from disk (called on app start).
  static Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedToken = prefs.getString(_tokenKey);
  }

  /// Clear token on logout.
  static Future<void> clearToken() async {
    _cachedToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  // ── URL Resolution ────────────────────────────────────────────────────────

  static String get baseUrl {
    if (_activeFallbackUrl != null && _activeFallbackUrl!.isNotEmpty) {
      return _activeFallbackUrl!;
    }
    return AppConfig.apiBaseUrl;
  }

  static Uri _uriFor(String endpoint, [String? overrideBaseUrl]) {
    final effectiveBase = overrideBaseUrl ?? baseUrl;
    if (effectiveBase.isEmpty) {
      throw ApiException(503, 'Production server URL is not configured.');
    }
    final uri = Uri.tryParse('$effectiveBase$endpoint');
    if (uri == null || !uri.hasAuthority) {
      throw ApiException(503, 'Invalid production server address.');
    }
    return uri;
  }

  // ── Health Check ──────────────────────────────────────────────────────────

  /// Ping /health to check reachability.
  /// If primary URL fails, automatically probes local LAN candidates so Wi-Fi never drops.
  static Future<bool> testHealth([String? candidateUrl]) async {
    final testUrl = (candidateUrl != null && candidateUrl.trim().isNotEmpty)
        ? candidateUrl.trim().replaceFirst(RegExp(r'/+$'), '')
        : AppConfig.apiBaseUrl;

    try {
      final healthUri = Uri.parse('$testUrl/health');
      final headers = <String, String>{};
      if (testUrl.contains('loca.lt')) {
        headers['bypass-tunnel-reminder'] = '1';
      }
      final res = await http
          .get(healthUri, headers: headers)
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        _activeFallbackUrl = null;
        return true;
      }
    } catch (_) {}

    // If explicit candidateUrl was provided, don't probe fallback LAN endpoints
    if (candidateUrl != null) return false;

    // Automatic Wi-Fi fallback: probe LAN candidates
    for (final lan in _lanCandidates) {
      if (testUrl == lan) continue;
      try {
        final res = await http
            .get(Uri.parse('$lan/health'))
            .timeout(const Duration(milliseconds: 1800));
        if (res.statusCode == 200) {
          debugPrint('[ApiService] Seamlessly switched to local Wi-Fi fallback: $lan');
          _activeFallbackUrl = lan;
          return true;
        }
      } catch (_) {}
    }

    return false;
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

  // ── Internal Request Runner with Auto-Fallback ────────────────────────────

  static Future<http.Response> _runWithFallback(
    Future<http.Response> Function(String effectiveBase) sendRequest,
  ) async {
    try {
      return await sendRequest(baseUrl);
    } catch (e) {
      final isNetworkIssue = e is SocketException ||
          e is http.ClientException ||
          e is TimeoutException;

      if (!isNetworkIssue) rethrow;

      // Primary failed; if we haven't already fallen back, check LAN candidates
      if (_activeFallbackUrl == null) {
        for (final lan in _lanCandidates) {
          try {
            final check = await http
                .get(Uri.parse('$lan/health'))
                .timeout(const Duration(milliseconds: 1500));
            if (check.statusCode == 200) {
              debugPrint('[ApiService] Primary server unreachable. Routed request to: $lan');
              _activeFallbackUrl = lan;
              return await sendRequest(lan);
            }
          } catch (_) {}
        }
      }

      throw ApiException(
        503,
        'Unable to connect to the transport server. Please check your network connection.',
      );
    }
  }

  // ── Login (no token required) ─────────────────────────────────────────────

  /// POST /api/auth/login — authenticates user against database using JWT.
  static Future<Map<String, dynamic>> postLogin({
    required String email,
    required String password,
  }) async {
    final bodyStr = jsonEncode({'email': email, 'password': password});

    final response = await _runWithFallback((effectiveBase) async {
      final uri = _uriFor('/auth/login', effectiveBase);
      final headers = _buildHeaders(targetUrl: effectiveBase);
      return await http
          .post(uri, headers: headers, body: bodyStr)
          .timeout(const Duration(seconds: 30));
    });

    return _handleResponse(response);
  }

  // ── Standard authenticated methods ────────────────────────────────────────

  static Future<Map<String, dynamic>> get(String endpoint) async {
    final response = await _runWithFallback((effectiveBase) async {
      final uri = _uriFor(endpoint, effectiveBase);
      final headers = _buildHeaders(targetUrl: effectiveBase);
      return await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 35));
    });
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> post(
      String endpoint, Map<String, dynamic> body) async {
    final bodyStr = jsonEncode(body);
    final response = await _runWithFallback((effectiveBase) async {
      final uri = _uriFor(endpoint, effectiveBase);
      final headers = _buildHeaders(targetUrl: effectiveBase);
      return await http
          .post(uri, headers: headers, body: bodyStr)
          .timeout(const Duration(seconds: 40));
    });
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> put(
      String endpoint, Map<String, dynamic> body) async {
    final bodyStr = jsonEncode(body);
    final response = await _runWithFallback((effectiveBase) async {
      final uri = _uriFor(endpoint, effectiveBase);
      final headers = _buildHeaders(targetUrl: effectiveBase);
      return await http
          .put(uri, headers: headers, body: bodyStr)
          .timeout(const Duration(seconds: 35));
    });
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> delete(String endpoint) async {
    final response = await _runWithFallback((effectiveBase) async {
      final uri = _uriFor(endpoint, effectiveBase);
      final headers = _buildHeaders(targetUrl: effectiveBase);
      return await http
          .delete(uri, headers: headers)
          .timeout(const Duration(seconds: 35));
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

    final streamedResponse = await request.send().timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        throw ApiException(408, 'Upload timed out. Check backend connection.');
      },
    );
    final response = await http.Response.fromStream(streamedResponse);
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
    } else {
      final msg = decoded is Map && decoded['error'] != null
          ? decoded['error'].toString()
          : (decoded is Map && decoded['message'] != null
              ? decoded['message'].toString()
              : 'Server error (${response.statusCode})');
      throw ApiException(response.statusCode, msg);
    }
  }
}
