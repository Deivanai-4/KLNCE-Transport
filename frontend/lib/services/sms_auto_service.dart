// lib/services/sms_auto_service.dart
// Service for automatic SMS schedule management (Stage 8)

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/sms_auto_settings.dart';
import '../models/sms_campaign.dart';
import 'api_service.dart';
import 'sms_service.dart';

class SmsAutoService extends ChangeNotifier {
  static const _channel = MethodChannel('com.klnce.transport/sms');

  SmsAutoSettings? _settings;
  List<SmsCampaign> _pendingConfirmations = [];
  bool _isLoading = false;
  String? _error;
  bool _isSaving = false;
  bool _isEmergencyDisabling = false;
  bool _isPreparing = false;
  bool _isApproving = false;

  SmsAutoSettings? get settings => _settings;
  List<SmsCampaign> get pendingConfirmations => _pendingConfirmations;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isSaving => _isSaving;
  bool get isEmergencyDisabling => _isEmergencyDisabling;
  bool get isPreparing => _isPreparing;
  bool get isApproving => _isApproving;

  /// Load current auto SMS settings from backend.
  Future<void> loadSettings() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await ApiService.get('/sms/auto-schedule/settings') as Map<String, dynamic>;
      _settings = SmsAutoSettings.fromJson(data);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Save updated settings to backend, then reschedule Android WorkManager jobs.
  Future<bool> updateSettings(SmsAutoSettings updated) async {
    _isSaving = true;
    _error = null;
    notifyListeners();
    try {
      final payload = updated.toUpdatePayload();
      final data = await ApiService.put('/sms/auto-schedule/settings', payload) as Map<String, dynamic>;
      _settings = SmsAutoSettings.fromJson(data);
      // Reschedule Android jobs with new times
      if (updated.isEffectivelyEnabled) {
        await scheduleAndroidJobs(
          morningTime: updated.morningTime,
          afternoonTime: updated.afternoonTime,
        );
      } else {
        await cancelAndroidJobs();
      }
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  /// Emergency disable — immediately stops all automatic SMS.
  Future<bool> emergencyDisable() async {
    _isEmergencyDisabling = true;
    _error = null;
    notifyListeners();
    try {
      await ApiService.post('/sms/auto-schedule/emergency-disable', {});
      await cancelAndroidJobs();
      await loadSettings();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isEmergencyDisabling = false;
      notifyListeners();
    }
  }

  /// Prepare a scheduled SMS campaign for the given session.
  /// [session]: 'morning' | 'afternoon'
  /// [forceTest]: if true, sends only to [testPhone]
  Future<Map<String, dynamic>?> prepareScheduledCampaign({
    required String session,
    bool forceTest = false,
    String? testPhone,
    String? date,
  }) async {
    _isPreparing = true;
    _error = null;
    notifyListeners();
    try {
      final payload = <String, dynamic>{
        'session': session,
        'force_test': forceTest,
      };
      if (testPhone != null && testPhone.isNotEmpty) payload['test_phone'] = testPhone;
      if (date != null) payload['date'] = date;
      final data = await ApiService.post('/sms/auto-schedule/prepare', payload) as Map<String, dynamic>;
      await loadPendingConfirmations();
      return data;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _isPreparing = false;
      notifyListeners();
    }
  }

  /// Fetch campaigns in pending_confirmation status.
  Future<void> loadPendingConfirmations() async {
    try {
      final data = await ApiService.get('/sms/auto-schedule/pending-confirmations') as Map<String, dynamic>;
      final list = data['campaigns'] as List? ?? [];
      _pendingConfirmations = list
          .map((e) => SmsCampaign.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _pendingConfirmations = [];
    }
    notifyListeners();
  }

  /// Approve a pending confirmation campaign and dispatch it via SIM.
  Future<bool> approveCampaign(
    dynamic campaignId,
    SmsService smsService,
  ) async {
    _isApproving = true;
    _error = null;
    notifyListeners();
    try {
      // Tell backend: approved
      final data = await ApiService.post(
        '/sms/auto-schedule/campaigns/$campaignId/approve',
        {},
      ) as Map<String, dynamic>;
      final campaign = SmsCampaign.fromJson(data['campaign'] as Map<String, dynamic>);
      // Immediately dispatch via SIM
      await smsService.dispatchCampaign(
        campaign: campaign,
        onProgress: (sent, failed, total, logMsg) {},
      );
      await loadPendingConfirmations();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isApproving = false;
      notifyListeners();
    }
  }

  /// Reject a pending confirmation (cancel it without sending).
  Future<bool> rejectCampaign(dynamic campaignId) async {
    try {
      await ApiService.post('/sms/campaigns/$campaignId/cancel-pending', {});
      await loadPendingConfirmations();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  // ── WorkManager Android bridge ─────────────────────────────────────────────

  /// Schedule background morning and afternoon jobs via WorkManager.
  Future<void> scheduleAndroidJobs({
    required String morningTime,
    required String afternoonTime,
  }) async {
    try {
      await _channel.invokeMethod('scheduleAutoSmsJobs', {
        'morningTime': morningTime,
        'afternoonTime': afternoonTime,
      });
    } on PlatformException catch (e) {
      debugPrint('scheduleAutoSmsJobs error: ${e.message}');
    } on MissingPluginException {
      debugPrint('scheduleAutoSmsJobs: not implemented on this platform');
    }
  }

  /// Cancel all scheduled WorkManager jobs.
  Future<void> cancelAndroidJobs() async {
    try {
      await _channel.invokeMethod('cancelAutoSmsJobs');
    } on PlatformException catch (e) {
      debugPrint('cancelAutoSmsJobs error: ${e.message}');
    } on MissingPluginException {
      debugPrint('cancelAutoSmsJobs: not implemented on this platform');
    }
  }

  /// Get WorkManager job status (next scheduled times).
  Future<Map<String, dynamic>> getAndroidScheduleStatus() async {
    try {
      final result = await _channel.invokeMethod('getAutoSmsScheduleStatus');
      return Map<String, dynamic>.from(result as Map);
    } on PlatformException {
      return {};
    } on MissingPluginException {
      return {};
    }
  }
}
