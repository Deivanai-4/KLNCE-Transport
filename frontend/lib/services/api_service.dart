import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode;
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
  static String get baseUrl => AppConfig.apiBaseUrl;

  static Uri _uriFor(String endpoint) {
    if (baseUrl.isEmpty) {
      throw ApiException(
        503,
        'Backend URL is not configured. Build with '
        '--dart-define=API_BASE_URL=https://your-backend.example/api.',
      );
    }
    final uri = Uri.tryParse('$baseUrl$endpoint');
    if (uri == null || !uri.hasAuthority) {
      throw ApiException(503, 'The configured backend URL is invalid.');
    }
    if (!kDebugMode && uri.scheme != 'https') {
      throw ApiException(
        503,
        'The production backend URL must use HTTPS.',
      );
    }
    return uri;
  }

  static Future<Map<String, String>> _getHeaders({bool isJson = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    final headers = <String, String>{};
    if (isJson) {
      headers['Content-Type'] = 'application/json';
    }
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  static Future<Map<String, dynamic>> get(String endpoint) async {
    final uri = _uriFor(endpoint);
    final headers = await _getHeaders();

    final response = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 35), onTimeout: () {
      throw ApiException(
          408, 'Request timed out. Please check backend connection.');
    });
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> post(
      String endpoint, Map<String, dynamic> body) async {
    final uri = _uriFor(endpoint);
    final headers = await _getHeaders();

    final response = await http
        .post(uri, headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 45), onTimeout: () {
      throw ApiException(
          408, 'Request timed out. Server took too long to respond.');
    });
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> put(
      String endpoint, Map<String, dynamic> body) async {
    final uri = _uriFor(endpoint);
    final headers = await _getHeaders();

    final response = await http
        .put(uri, headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 35), onTimeout: () {
      throw ApiException(
          408, 'Request timed out. Server took too long to respond.');
    });
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> delete(String endpoint) async {
    final uri = _uriFor(endpoint);
    final headers = await _getHeaders();

    final response = await http
        .delete(uri, headers: headers)
        .timeout(const Duration(seconds: 35), onTimeout: () {
      throw ApiException(
          408, 'Request timed out. Server took too long to respond.');
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

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

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

  static Map<String, dynamic> _handleResponse(http.Response response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = {'message': response.body};
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
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
