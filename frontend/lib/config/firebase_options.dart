import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _messagingSenderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const _storageBucket =
      String.fromEnvironment('FIREBASE_STORAGE_BUCKET');

  static FirebaseOptions get currentPlatform {
    final missingValues = <String>[
      if (_apiKey.isEmpty) 'FIREBASE_API_KEY',
      if (_appId.isEmpty) 'FIREBASE_APP_ID',
      if (_messagingSenderId.isEmpty) 'FIREBASE_MESSAGING_SENDER_ID',
      if (_projectId.isEmpty) 'FIREBASE_PROJECT_ID',
      if (kIsWeb && _authDomain.isEmpty) 'FIREBASE_AUTH_DOMAIN',
    ];
    if (missingValues.isNotEmpty) {
      throw StateError(
        'Missing Firebase configuration: ${missingValues.join(', ')}',
      );
    }

    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError(
        'Firebase is configured only for Android and web.',
      );
    }

    return FirebaseOptions(
      apiKey: _apiKey,
      appId: _appId,
      messagingSenderId: _messagingSenderId,
      projectId: _projectId,
      authDomain: kIsWeb ? _authDomain : null,
      storageBucket: _storageBucket.isEmpty ? null : _storageBucket,
    );
  }
}
