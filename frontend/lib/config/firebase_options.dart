import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Generated from google-services.json for KLNCE Transport.
class DefaultFirebaseOptions {
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCYgYuofFZApiwktW5VorDBdQx7jY10-J0',
    appId: '1:825226484631:android:a3f498a59392ca851a02d2',
    messagingSenderId: '825226484631',
    projectId: 'klnce-transport',
    storageBucket: 'klnce-transport.firebasestorage.app',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCYgYuofFZApiwktW5VorDBdQx7jY10-J0',
    appId: '1:825226484631:web:a3f498a59392ca851a02d2',
    messagingSenderId: '825226484631',
    projectId: 'klnce-transport',
    storageBucket: 'klnce-transport.firebasestorage.app',
    authDomain: 'klnce-transport.firebaseapp.com',
  );

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        return android;
    }
  }
}
