import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import 'api_service.dart';

class AuthService extends ChangeNotifier {
  User? _currentUser;
  String? _token;
  bool _isLoading = false;
  String? _errorMessage;

  User? get currentUser => _currentUser;
  String? get token => _token;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isLoggedIn => _token != null && _currentUser != null;
  bool get isAdmin => _currentUser?.isAdmin ?? false;
  bool get isDriver => _currentUser?.isDriver ?? false;

  Future<bool> tryAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final storedToken = prefs.getString('auth_token');
    if (storedToken == null || storedToken.isEmpty) {
      return false;
    }

    _token = storedToken;
    try {
      final res = await ApiService.get('/auth/me');
      if (res['user'] != null) {
        _currentUser = User.fromJson(res['user'] as Map<String, dynamic>);
        notifyListeners();
        return true;
      }
    } catch (_) {
      await logout();
    }
    return false;
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await ApiService.post('/auth/login', {
        'email': email.trim(),
        'password': password,
      });

      _token = res['token'] as String?;
      if (res['user'] != null) {
        _currentUser = User.fromJson(res['user'] as Map<String, dynamic>);
      }

      final prefs = await SharedPreferences.getInstance();
      if (_token != null) {
        await prefs.setString('auth_token', _token!);
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Network error. Please verify backend connection.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _token = null;
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    notifyListeners();
  }
}

