import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/user.dart';
import 'api_service.dart';
import 'notification_service.dart';

class AuthService extends ChangeNotifier {
  User? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isLoggedIn => _currentUser != null;
  bool get isAdmin => _currentUser?.isAdmin ?? false;
  bool get isDriver => _currentUser?.isDriver ?? false;

  /// Attempt to restore a saved session using the stored JWT token.
  Future<bool> tryAutoLogin() async {
    // If there is no saved token, nothing to restore.
    if (ApiService.savedToken == null) return false;

    try {
      final response = await ApiService.get('/auth/me');
      final userJson = response['user'];
      if (userJson is! Map<String, dynamic>) return false;
      _currentUser = User.fromJson(userJson);
      NotificationService.registerDeviceToken();
      notifyListeners();
      return true;
    } catch (error) {
      debugPrint('Auto-login failed: $error');
      await logout();
      return false;
    }
  }

  /// Log in with email and password against the backend.
  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await ApiService.postLogin(
        email: email.trim(),
        password: password,
      );

      final token = response['token'] as String?;
      final userJson = response['user'];

      if (token == null || token.isEmpty) {
        _errorMessage = 'Server did not return a session token.';
        return false;
      }
      if (userJson is! Map<String, dynamic>) {
        _errorMessage = 'Server returned an invalid user profile.';
        return false;
      }

      await ApiService.saveToken(token);
      _currentUser = User.fromJson(userJson);
      NotificationService.registerDeviceToken();
      return true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
    } on http.ClientException {
      _errorMessage =
          'Unable to connect to the transport server. Please check your internet connection.';
    } catch (error) {
      debugPrint('Unexpected login error: $error');
      _errorMessage =
          'Unable to sign in. Please check your connection and try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }

    return _currentUser != null;
  }

  Future<void> logout() async {
    await NotificationService.clearDeviceToken();
    await ApiService.clearToken();
    _currentUser = null;
    notifyListeners();
  }
}
