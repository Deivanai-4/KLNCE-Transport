import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/sms_campaign.dart';
import 'api_service.dart';

/// Service managing Android SIM-based SMS sending, dual-SIM selection,
/// telephony capabilities, batch queue management, and dispatch synchronization with MongoDB Atlas.
class SmsService extends ChangeNotifier {
  static const MethodChannel _channel = MethodChannel('com.klnce.transport/sms');

  DeviceTelephonyStatus _deviceStatus = DeviceTelephonyStatus.initial();
  DeviceTelephonyStatus get deviceStatus => _deviceStatus;

  int _selectedSimIndex = 0;
  int get selectedSimIndex => _selectedSimIndex;

  List<SmsCampaign> _campaigns = [];
  List<SmsCampaign> get campaigns => _campaigns;

  bool _isCheckingStatus = false;
  bool get isCheckingStatus => _isCheckingStatus;

  bool _isSending = false;
  bool get isSending => _isSending;

  bool _isPaused = false;
  bool get isPaused => _isPaused;

  bool _isCancelled = false;
  bool get isCancelled => _isCancelled;

  String? _lastError;
  String? get lastError => _lastError;

  SimCardInfo? get selectedSim {
    if (_deviceStatus.simCards.isEmpty) return null;
    if (_selectedSimIndex >= 0 && _selectedSimIndex < _deviceStatus.simCards.length) {
      return _deviceStatus.simCards[_selectedSimIndex];
    }
    return _deviceStatus.simCards.first;
  }

  void selectSimIndex(int index) {
    if (index >= 0 && index < _deviceStatus.simCards.length) {
      _selectedSimIndex = index;
      notifyListeners();
    }
  }

  // â”€â”€ 1. Telephony and SIM Detection â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Inspect Android device hardware, SIM readiness, permissions, and carrier list.
  Future<DeviceTelephonyStatus> checkDeviceStatus() async {
    _isCheckingStatus = true;
    _lastError = null;
    notifyListeners();

    try {
      if (kIsWeb) {
        _deviceStatus = DeviceTelephonyStatus(
          hasTelephony: false,
          simState: 'WEB_PLATFORM',
          isSimReady: false,
          sendSmsGranted: false,
          readPhoneStateGranted: false,
          isReady: false,
          simCards: [],
          defaultSubId: -1,
          deviceModel: 'Web Browser (Simulated)',
          androidVersion: 'N/A',
          sdkInt: 0,
        );
      } else {
        final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('checkSmsCapability');
        if (result != null) {
          _deviceStatus = DeviceTelephonyStatus.fromMap(result);
          if (_selectedSimIndex >= _deviceStatus.simCards.length) {
            _selectedSimIndex = 0;
          }
        }
      }
    } catch (e) {
      _lastError = 'Could not inspect SIM status: $e';
      debugPrint('[SmsService] checkDeviceStatus error: $e');
    } finally {
      _isCheckingStatus = false;
      notifyListeners();
    }
    return _deviceStatus;
  }

  /// Request SEND_SMS and READ_PHONE_STATE permissions from the administrator.
  Future<bool> requestPermissions() async {
    try {
      if (kIsWeb) return false;
      final bool? granted = await _channel.invokeMethod<bool>('requestSmsPermissions');
      await checkDeviceStatus();
      return granted ?? false;
    } catch (e) {
      _lastError = 'Failed to request SMS permission: $e';
      notifyListeners();
      return false;
    }
  }

  // â”€â”€ 2. Query Eligible Recipients & Analytics Preview â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Fetch recipient validation preview including valid, invalid, duplicate counts,
  /// duplicate groups, and masked phone numbers.
  Future<RecipientPreviewSummary> fetchRecipientPreview({
    String target = 'all_active',
    String? routeName,
    String? busNumber,
    List<int>? studentIds,
    bool allowDuplicates = false,
  }) async {
    final queryParams = <String, String>{
      'target': target,
      'allow_duplicates': allowDuplicates ? 'true' : 'false',
    };
    if (routeName != null && routeName.isNotEmpty) {
      queryParams['route_name'] = routeName;
    }
    if (busNumber != null && busNumber.isNotEmpty) {
      queryParams['bus_number'] = busNumber;
    }
    if (studentIds != null && studentIds.isNotEmpty) {
      queryParams['student_ids'] = studentIds.join(',');
    }

    final query = queryParams.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

    final res = await ApiService.get('/sms/recipients?$query');
    return RecipientPreviewSummary.fromJson(res);
  }

  /// Backward-compatible query for recipients list.
  Future<List<Map<String, dynamic>>> fetchEligibleRecipients({
    String target = 'all_active',
    String? routeName,
    String? busNumber,
    List<int>? studentIds,
    bool allowDuplicates = false,
  }) async {
    final preview = await fetchRecipientPreview(
      target: target,
      routeName: routeName,
      busNumber: busNumber,
      studentIds: studentIds,
      allowDuplicates: allowDuplicates,
    );
    return preview.recipients.map((r) => r.toJson()).toList();
  }

  // â”€â”€ 3. Campaign Creation & Storage in MongoDB â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Create a new SMS campaign session in MongoDB.
  Future<SmsCampaign> createCampaign({
    required String title,
    required String message,
    required String targetType,
    String? routeName,
    String? busNumber,
    List<int>? selectedStudentIds,
    String? testPhone,
    bool allowDuplicates = false,
    String deliveryMethod = 'direct_sim',
  }) async {
    final sim = selectedSim;
    final senderDevice = {
      'device_model': _deviceStatus.deviceModel,
      'android_version': _deviceStatus.androidVersion,
      'sim_slot': sim?.simSlotIndex ?? 0,
      'carrier': sim?.carrierName ?? 'Unknown',
      'display_name': sim?.displayName ?? 'SIM',
      'subscription_id': sim?.subscriptionId ?? -1,
    };

    final payload = {
      'title': title,
      'message': message,
      'target_type': targetType,
      'route_name': routeName,
      'bus_number': busNumber,
      'selected_student_ids': selectedStudentIds,
      'test_phone': testPhone,
      'allow_duplicates': allowDuplicates,
      'delivery_method': deliveryMethod,
      'sender_device': senderDevice,
    };

    final res = await ApiService.post('/sms/campaigns', payload);
    final campaignData = res['campaign'] as Map<String, dynamic>;
    final createdCampaign = SmsCampaign.fromJson(campaignData);
    _campaigns.insert(0, createdCampaign);
    notifyListeners();
    return createdCampaign;
  }

  // â”€â”€ 4. Direct SMS Dispatch Engine â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Send a single SMS via native Android MethodChannel using the phone SIM.
  Future<Map<String, dynamic>> sendSingleDirectSms({
    required String phoneNumber,
    required String message,
    int? subscriptionId,
  }) async {
    if (kIsWeb) {
      await Future.delayed(const Duration(milliseconds: 300));
      return {
        'success': true,
        'status': 'submitted_to_sms_service',
        'message': '[Simulated Web] Submitted to Android SMS service',
      };
    }

    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('sendSmsDirect', {
        'phoneNumber': phoneNumber,
        'message': message,
        'subscriptionId': subscriptionId ?? selectedSim?.subscriptionId,
      });

      if (res != null) {
        return Map<String, dynamic>.from(res);
      }
      return {
        'success': false,
        'status': 'failed',
        'error': 'No response from native SMS manager',
      };
    } catch (e) {
      return {
        'success': false,
        'status': 'failed',
        'error': e.toString(),
      };
    }
  }

  /// Send SMS via default Android SMS app (Google Play compliant fallback).
  Future<bool> sendSmsViaIntent({
    required String phoneNumber,
    required String message,
  }) async {
    if (kIsWeb) return false;
    try {
      final res = await _channel.invokeMethod<bool>('sendSmsViaIntent', {
        'phoneNumber': phoneNumber,
        'message': message,
      });
      return res ?? false;
    } catch (e) {
      debugPrint('[SmsService] sendSmsViaIntent failed: $e');
      return false;
    }
  }

  /// Bulk dispatch campaign recipients in manageable batches via phone SIM with live progress.
  /// Supports >50 recipients, pausing, cancelling, and continuing past recoverable failures.
  Future<void> dispatchCampaign({
    required SmsCampaign campaign,
    required Function(int sent, int failed, int total, String statusMsg) onProgress,
    int batchSize = 10,
    int delayBetweenMessagesMs = 750,
    int coolDownBetweenBatchesMs = 2000,
  }) async {
    if (_isSending) return;

    _isSending = true;
    _isPaused = false;
    _isCancelled = false;
    notifyListeners();

    int submittedCount = campaign.submittedCount;
    int failedCount = campaign.failedCount;
    final total = campaign.recipients.length;
    final recipientUpdates = <Map<String, dynamic>>[];

    try {
      // Notify backend that dispatch is active
      await ApiService.put('/sms/campaigns/${campaign.id}/status', {
        'status': 'sending',
      });

      int processedInCurrentBatch = 0;

      for (int i = 0; i < total; i++) {
        // Check for cancellation
        if (_isCancelled) {
          onProgress(submittedCount, failedCount, total, 'Dispatch cancelled by administrator.');
          await cancelPendingDispatch(campaign);
          break;
        }

        // Check for pause
        if (_isPaused) {
          onProgress(submittedCount, failedCount, total, 'Dispatch paused by administrator.');
          await ApiService.post('/sms/campaigns/${campaign.id}/pause', {});
          break;
        }

        final recipient = campaign.recipients[i];

        // STRICT RULE: Skip already successfully dispatched recipients (prevents accidental duplicate sending)
        if (recipient.isSubmitted || recipient.isDelivered || recipient.isCancelled) {
          continue;
        }

        recipient.status = 'sending';
        onProgress(
          submittedCount,
          failedCount,
          total,
          'Sending to ${recipient.name} (${recipient.maskedMobile})...',
        );

        // Dispatch via physical SIM using full unmasked phone number
        final result = await sendSingleDirectSms(
          phoneNumber: recipient.mobileNumber,
          message: campaign.message,
          subscriptionId: selectedSim?.subscriptionId,
        );

        final bool isSuccess = result['success'] == true;
        if (isSuccess) {
          submittedCount++;
          recipient.status = 'submitted_to_sms_service';
          recipient.errorReason = null;
        } else {
          failedCount++;
          recipient.status = 'failed';
          recipient.errorReason = result['error']?.toString() ?? 'Carrier dispatch failed';
        }

        recipient.sentAt = DateTime.now().toIso8601String();
        recipientUpdates.add({
          'student_id': recipient.studentId,
          'mobile_number': recipient.mobileNumber,
          'status': recipient.status,
          'error_reason': recipient.errorReason,
          'sent_at': recipient.sentAt,
          'dispatched_at': recipient.sentAt,
        });

        processedInCurrentBatch++;

        onProgress(
          submittedCount,
          failedCount,
          total,
          isSuccess
              ? 'Submitted for ${recipient.name} (${recipient.maskedMobile})'
              : 'Failed for ${recipient.name} (${recipient.maskedMobile}): ${recipient.errorReason}',
        );

        // Sync with backend every 5 recipients or on final
        if (recipientUpdates.length >= 5 || i == total - 1) {
          try {
            await ApiService.put('/sms/campaigns/${campaign.id}/status', {
              'recipient_updates': List<Map<String, dynamic>>.from(recipientUpdates),
            });
            recipientUpdates.clear();
          } catch (e) {
            debugPrint('[SmsService] Progress sync warning: $e');
          }
        }

        // Inter-message delay
        if (i < total - 1 && !_isPaused && !_isCancelled) {
          // If batch completed, take a cooldown pause
          if (processedInCurrentBatch >= batchSize) {
            processedInCurrentBatch = 0;
            onProgress(
              submittedCount,
              failedCount,
              total,
              'Batch cooldown ($coolDownBetweenBatchesMs ms) to prevent carrier throttling...',
            );
            await Future.delayed(Duration(milliseconds: coolDownBetweenBatchesMs));
          } else {
            await Future.delayed(Duration(milliseconds: delayBetweenMessagesMs));
          }
        }
      }

      // Mark final campaign state if not paused or cancelled
      if (!_isPaused && !_isCancelled) {
        final finalStatus = failedCount == 0 ? 'completed' : 'partially_failed';
        await ApiService.put('/sms/campaigns/${campaign.id}/status', {
          'status': finalStatus,
          if (recipientUpdates.isNotEmpty) 'recipient_updates': recipientUpdates,
        });

        onProgress(
          submittedCount,
          failedCount,
          total,
          'Finished! $submittedCount submitted to Android SMS service, $failedCount failed.',
        );
      }
    } catch (e) {
      _lastError = 'Dispatch error: $e';
      onProgress(submittedCount, failedCount, total, 'Error: $e');
    } finally {
      _isSending = false;
      notifyListeners();
      await loadCampaignHistory();
    }
  }

  void pauseDispatch() {
    _isPaused = true;
    notifyListeners();
  }

  Future<void> resumeDispatch({
    required SmsCampaign campaign,
    required Function(int sent, int failed, int total, String statusMsg) onProgress,
  }) async {
    _isPaused = false;
    await ApiService.post('/sms/campaigns/${campaign.id}/resume', {});
    await dispatchCampaign(campaign: campaign, onProgress: onProgress);
  }

  Future<void> cancelPendingDispatch(SmsCampaign campaign) async {
    _isCancelled = true;
    _isPaused = false;
    try {
      await ApiService.post('/sms/campaigns/${campaign.id}/cancel-pending', {});
      await loadCampaignHistory();
    } catch (e) {
      debugPrint('[SmsService] cancelPending error: $e');
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  // â”€â”€ 5. Campaign History & Status Tracking â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Load campaign history from MongoDB Atlas.
  Future<void> loadCampaignHistory() async {
    try {
      final res = await ApiService.get('/sms/campaigns?limit=50');
      final rawList = res['campaigns'] as List<dynamic>? ?? [];
      _campaigns = rawList
          .map((c) => SmsCampaign.fromJson(c as Map<String, dynamic>))
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('[SmsService] loadCampaignHistory error: $e');
    }
  }

  /// Get specific campaign with full recipient list, status filter and search.
  Future<SmsCampaign> getCampaignDetails(
    int campaignId, {
    String? status,
    String? search,
  }) async {
    final queryParams = <String>[];
    if (status != null && status.isNotEmpty) {
      queryParams.add('status=${Uri.encodeComponent(status)}');
    }
    if (search != null && search.isNotEmpty) {
      queryParams.add('search=${Uri.encodeComponent(search)}');
    }
    final qs = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
    final res = await ApiService.get('/sms/campaigns/$campaignId$qs');
    return SmsCampaign.fromJson(res);
  }

  /// Retry failed recipients for a campaign.
  Future<SmsCampaign> retryFailedRecipients(
    int campaignId, {
    List<int>? recipientIds,
  }) async {
    final payload = recipientIds != null && recipientIds.isNotEmpty
        ? {'recipient_ids': recipientIds}
        : <String, dynamic>{};
    final res = await ApiService.post('/sms/campaigns/$campaignId/retry-failed', payload);
    final updated = SmsCampaign.fromJson(res['campaign'] as Map<String, dynamic>);
    await loadCampaignHistory();
    return updated;
  }
}

