import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../config/firebase_options.dart';
import 'api_service.dart';

/// Top-level background message handler for Firebase Cloud Messaging.
///
/// Must be annotated with `@pragma('vm:entry-point')` so Flutter's AOT
/// compiler does not strip it when the engine is spawned in background.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('[FCM Background] Firebase initialize warning: $e');
  }

  debugPrint('======================================================');
  debugPrint('[FCM Background Handler] Received message in background/terminated:');
  debugPrint('  Message ID: ${message.messageId}');
  debugPrint('  Title: ${message.notification?.title ?? message.data['title']}');
  debugPrint('  Body: ${message.notification?.body ?? message.data['body']}');
  debugPrint('  Data: ${message.data}');
  debugPrint('======================================================');
}

/// Firebase Cloud Messaging (FCM) Service for KLNCE Transport.
///
/// Handles device token generation, token refresh, notification permissions (Android 13+),
/// foreground in-app notifications, and background/terminated tap handling.
class NotificationService {
  static const _broadcastTopic = 'klnce_transport';
  static bool _initialized = false;
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// Global key for displaying in-app foreground notification alerts
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static String? _cachedFcmToken;

  /// Returns the current cached FCM device token
  static String? get deviceToken => _cachedFcmToken;

  /// Direct accessor for the FirebaseMessaging instance
  static FirebaseMessaging get messaging => _messaging;

  /// Initialize Firebase Cloud Messaging listeners, handlers, and permissions.
  /// Must be invoked during app initialization before runApp().
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // 1. Register top-level background message handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 2. Set foreground presentation options (for heads-up alert on supported platforms)
    try {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (error) {
      debugPrint('[FCM] Set foreground presentation options warning: $error');
    }

    // 3. Foreground notification listener
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('======================================================');
      debugPrint('[FCM Foreground] Received message while app is open:');
      debugPrint('  Message ID: ${message.messageId}');
      debugPrint('  Title: ${message.notification?.title ?? message.data['title']}');
      debugPrint('  Body: ${message.notification?.body ?? message.data['body']}');
      debugPrint('  Data: ${message.data}');
      debugPrint('======================================================');
      _showForegroundNotification(message);
    });

    // 4. Background notification tap listener (app minimized in background)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('======================================================');
      debugPrint('[FCM Tap] App opened from BACKGROUND notification:');
      debugPrint('  Message ID: ${message.messageId}');
      debugPrint('  Title: ${message.notification?.title ?? message.data['title']}');
      debugPrint('  Data: ${message.data}');
      debugPrint('======================================================');
      _handleNotificationTap(message);
    });

    // 5. Terminated notification tap handler (app was completely terminated/closed)
    try {
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('======================================================');
        debugPrint('[FCM Tap] App launched from TERMINATED state via notification:');
        debugPrint('  Message ID: ${initialMessage.messageId}');
        debugPrint('  Title: ${initialMessage.notification?.title ?? initialMessage.data['title']}');
        debugPrint('  Data: ${initialMessage.data}');
        debugPrint('======================================================');
        _handleNotificationTap(initialMessage);
      }
    } catch (error) {
      debugPrint('[FCM] Initial message check warning: $error');
    }

    // 6. Listen for FCM token refresh
    // ignore: deprecated_member_use
    _messaging.onTokenRefresh.listen((newToken) {
      debugPrint('[FCM] Device token refreshed by Firebase:');
      debugPrint(newToken);
      _cachedFcmToken = newToken;
      registerDeviceToken(token: newToken);
    });

    // 7. Request notification permissions (supports Android 13+ POST_NOTIFICATIONS)
    await requestPermission();

    // 8. Generate and log the FCM device token
    await getDeviceToken();

    // 9. Subscribe to college-wide transport announcements topic
    try {
      await _messaging.subscribeToTopic(_broadcastTopic);
      debugPrint('[FCM] Subscribed to topic: "$_broadcastTopic"');
    } catch (error) {
      debugPrint('[FCM] Topic subscription warning: $error');
    }
  }

  /// Request notification permission (supports Android 13+ runtime permission prompt)
  static Future<bool> requestPermission() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      switch (settings.authorizationStatus) {
        case AuthorizationStatus.authorized:
          debugPrint('[FCM Permission] GRANTED: User accepted full notifications.');
          return true;
        case AuthorizationStatus.provisional:
          debugPrint('[FCM Permission] PROVISIONAL: Notifications allowed quietly.');
          return true;
        case AuthorizationStatus.denied:
          debugPrint('[FCM Permission] DENIED: User declined notifications.');
          return false;
        case AuthorizationStatus.notDetermined:
          debugPrint('[FCM Permission] NOT DETERMINED: User has not decided yet.');
          return false;
        default:
          debugPrint('[FCM Permission] Status: ${settings.authorizationStatus.name}');
          return false;
      }
    } catch (error) {
      debugPrint('[FCM Permission] Error requesting permission: $error');
      return false;
    }
  }

  /// Retrieve the device's FCM token, print to debug logs, and store in cache
  static Future<String?> getDeviceToken() async {
    try {
      // ignore: deprecated_member_use
      final token = await _messaging.getToken();
      _cachedFcmToken = token;
      if (token != null && token.isNotEmpty) {
        debugPrint('======================================================');
        debugPrint('[FCM DEVICE TOKEN] Successfully generated:');
        debugPrint(token);
        debugPrint('======================================================');
        // Register token with backend if user is already authenticated
        await registerDeviceToken(token: token);
      } else {
        debugPrint('[FCM] getToken() returned null or empty.');
      }
      return token;
    } catch (error) {
      debugPrint('[FCM] Error generating FCM device token: $error');
      return null;
    }
  }

  /// Display an in-app banner for notifications received while the app is in foreground
  static void _showForegroundNotification(RemoteMessage message) {
    final title = message.notification?.title ??
        message.data['title'] ??
        'KLNCE Transport Alert';
    final body = message.notification?.body ??
        message.data['body'] ??
        'New schedule announcement received.';

    final messenger = scaffoldMessengerKey.currentState;
    if (messenger == null) return;

    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        backgroundColor: const Color(0xFF18324B),
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        duration: const Duration(seconds: 6),
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Color(0xFF147D75),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_active,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      body,
                      style: const TextStyle(
                        color: Color(0xFFF4F6F8),
                        fontSize: 13,
                        height: 1.3,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Handles notification tap when user taps notification from background/terminated
  static void _handleNotificationTap(RemoteMessage message) {
    debugPrint('[FCM Action] Notification tapped by user:');
    debugPrint('  Message ID: ${message.messageId}');
    debugPrint('  Data: ${message.data}');
  }

  /// Registers device FCM token on the backend server
  static Future<void> registerDeviceToken({String? token}) async {
    // Only register if the user is logged in (has a JWT token)
    if (ApiService.savedToken == null) return;

    try {
      final deviceToken = token ?? await getDeviceToken();
      if (deviceToken == null || deviceToken.isEmpty) return;
      await ApiService.put('/auth/fcm-token', {'fcm_token': deviceToken});
      debugPrint('[FCM] Successfully registered device token on transport backend.');
    } catch (error) {
      debugPrint('[FCM] Unable to register FCM device token with backend: $error');
    }
  }

  /// Clears device token on backend when user logs out
  static Future<void> clearDeviceToken() async {
    if (ApiService.savedToken == null) return;

    try {
      await ApiService.put('/auth/fcm-token', {'fcm_token': ''});
      debugPrint('[FCM] Cleared FCM device token from transport backend.');
    } catch (error) {
      debugPrint('[FCM] Unable to clear FCM device token from backend: $error');
    }
  }

  // ── Existing Broadcast Management APIs ────────────────────────────────────

  static Future<bool> sendBroadcast({
    required String title,
    required String body,
    String type = 'general',
    bool sendSms = false,
  }) async {
    try {
      final res = await ApiService.post('/notifications/send', {
        'title': title,
        'body': body,
        'type': type,
        'send_sms': sendSms,
      });
      return res['notification'] != null;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getHistory() async {
    final res = await ApiService.get('/notifications/history');
    final notifications = res['notifications'];
    if (notifications is! List) {
      throw const FormatException('Invalid notification history response.');
    }
    return notifications
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Future<Map<String, dynamic>> updateBroadcast({
    required int id,
    required String title,
    required String body,
  }) {
    return ApiService.put('/notifications/$id', {
      'title': title,
      'body': body,
    });
  }

  static Future<void> deleteBroadcast({required int id}) async {
    await ApiService.delete('/notifications/$id');
  }
}
