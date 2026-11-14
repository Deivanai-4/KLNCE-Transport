import 'api_service.dart';

class NotificationService {
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
