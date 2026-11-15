import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/user.dart';
import 'api_service.dart';

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

  Future<bool> tryAutoLogin() async {
    if (firebase_auth.FirebaseAuth.instance.currentUser == null) {
      return false;
    }

    try {
      final response = await ApiService.get('/auth/me');
      final userJson = response['user'];
      if (userJson is! Map<String, dynamic>) {
        throw ApiException(502, 'The server returned an invalid user profile.');
      }
      _currentUser = User.fromJson(userJson);
      notifyListeners();
      return true;
    } catch (error) {
      debugPrint('Unable to restore Firebase session: $error');
      await logout();
      return false;
    }
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    var signedInToFirebase = false;

    try {
      final credential =
          await firebase_auth.FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      if (credential.user == null) {
        throw StateError('Firebase sign-in returned no user.');
      }
      signedInToFirebase = true;

      final response = await ApiService.get('/auth/me');
      final userJson = response['user'];
      if (userJson is! Map<String, dynamic>) {
        throw ApiException(502, 'The server returned an invalid user profile.');
      }
      _currentUser = User.fromJson(userJson);
      return true;
    } on firebase_auth.FirebaseAuthException catch (error) {
      _errorMessage = _firebaseErrorMessage(error);
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
      if (signedInToFirebase && _currentUser == null) {
        await firebase_auth.FirebaseAuth.instance.signOut();
      }
      _isLoading = false;
      notifyListeners();
    }

    return _currentUser != null;
  }

  String _firebaseErrorMessage(firebase_auth.FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-credential':
      case 'user-not-found':
      case 'wrong-password':
        return 'Email or password is incorrect.';
      case 'user-disabled':
        return 'This Firebase account is disabled. Contact the transport office.';
      case 'too-many-requests':
        return 'Too many sign-in attempts. Please try again later.';
      case 'network-request-failed':
        return 'Unable to connect to Firebase. Check your internet connection.';
      default:
        return error.message ?? 'Unable to sign in with Firebase.';
    }
  }

  Future<void> logout() async {
    await firebase_auth.FirebaseAuth.instance.signOut();
    _currentUser = null;
    notifyListeners();
  }
}
