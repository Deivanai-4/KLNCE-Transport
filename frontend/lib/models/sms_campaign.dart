import 'package:flutter/material.dart';

/// Information about a detected physical SIM card or eSIM on the administrator's phone.
class SimCardInfo {
  final int subscriptionId;
  final int simSlotIndex;
  final String carrierName;
  final String displayName;
  final String countryIso;

  SimCardInfo({
    required this.subscriptionId,
    required this.simSlotIndex,
    required this.carrierName,
    required this.displayName,
    this.countryIso = '',
  });

  factory SimCardInfo.fromMap(Map<dynamic, dynamic> map) {
    return SimCardInfo(
      subscriptionId: (map['subscriptionId'] as num?)?.toInt() ?? -1,
      simSlotIndex: (map['simSlotIndex'] as num?)?.toInt() ?? 0,
      carrierName: map['carrierName']?.toString() ?? 'Unknown Carrier',
      displayName: map['displayName']?.toString() ?? 'SIM 1',
      countryIso: map['countryIso']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'subscriptionId': subscriptionId,
      'simSlotIndex': simSlotIndex,
      'carrierName': carrierName,
      'displayName': displayName,
      'countryIso': countryIso,
    };
  }

  String get slotLabel => 'SIM ${simSlotIndex + 1} ($carrierName)';
}

/// Telephony hardware and SIM status on the administrator's device.
class DeviceTelephonyStatus {
  final bool hasTelephony;
  final String simState;
  final bool isSimReady;
  final bool sendSmsGranted;
  final bool readPhoneStateGranted;
  final bool isReady;
  final List<SimCardInfo> simCards;
  final int defaultSubId;
  final String deviceModel;
  final String androidVersion;
  final int sdkInt;

  DeviceTelephonyStatus({
    required this.hasTelephony,
    required this.simState,
    required this.isSimReady,
    required this.sendSmsGranted,
    required this.readPhoneStateGranted,
    required this.isReady,
    required this.simCards,
    required this.defaultSubId,
    required this.deviceModel,
    required this.androidVersion,
    required this.sdkInt,
  });

  factory DeviceTelephonyStatus.fromMap(Map<dynamic, dynamic> map) {
    final rawCards = map['simCards'] as List<dynamic>? ?? [];
    final cards = rawCards
        .map((c) => SimCardInfo.fromMap(c as Map<dynamic, dynamic>))
        .toList();

    return DeviceTelephonyStatus(
      hasTelephony: map['hasTelephony'] as bool? ?? false,
      simState: map['simState']?.toString() ?? 'UNKNOWN',
      isSimReady: map['isSimReady'] as bool? ?? false,
      sendSmsGranted: map['sendSmsGranted'] as bool? ?? false,
      readPhoneStateGranted: map['readPhoneStateGranted'] as bool? ?? false,
      isReady: map['isReady'] as bool? ?? false,
      simCards: cards,
      defaultSubId: (map['defaultSubId'] as num?)?.toInt() ?? -1,
      deviceModel: map['deviceModel']?.toString() ?? 'Android Device',
      androidVersion: map['androidVersion']?.toString() ?? '',
      sdkInt: (map['sdkInt'] as num?)?.toInt() ?? 0,
    );
  }

  factory DeviceTelephonyStatus.initial() {
    return DeviceTelephonyStatus(
      hasTelephony: false,
      simState: 'CHECKING',
      isSimReady: false,
      sendSmsGranted: false,
      readPhoneStateGranted: false,
      isReady: false,
      simCards: [],
      defaultSubId: -1,
      deviceModel: 'Detecting...',
      androidVersion: '',
      sdkInt: 0,
    );
  }
}

/// Individual recipient within an SMS dispatch session with Stage 7 tracking.
class SmsRecipientItem {
  final int studentId;
  final String registerNumber;
  final String name;
  final String mobileNumber;
  final String maskedMobile;
  final String messageRef;
  String status; // 'pending', 'sending', 'submitted_to_sms_service', 'delivery_confirmed', 'failed', 'cancelled'
  int attemptCount;
  String? errorReason;
  String? createdAt;
  String? sentAt;
  String? deliveredAt;

  SmsRecipientItem({
    required this.studentId,
    required this.registerNumber,
    required this.name,
    required this.mobileNumber,
    required this.maskedMobile,
    this.messageRef = '',
    this.status = 'pending',
    this.attemptCount = 0,
    this.errorReason,
    this.createdAt,
    this.sentAt,
    this.deliveredAt,
  });

  factory SmsRecipientItem.fromJson(Map<String, dynamic> json) {
    return SmsRecipientItem(
      studentId: (json['student_id'] as num?)?.toInt() ?? 0,
      registerNumber: json['register_number']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      mobileNumber: (json['mobile_number'] ?? json['student_mobile'])?.toString() ?? '',
      maskedMobile: json['masked_mobile']?.toString() ?? '***',
      messageRef: json['message_ref']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      attemptCount: (json['attempt_count'] as num?)?.toInt() ?? 0,
      errorReason: (json['error_reason'] ?? json['error_message'])?.toString(),
      createdAt: json['created_at']?.toString(),
      sentAt: (json['sent_at'] ?? json['dispatched_at'])?.toString(),
      deliveredAt: json['delivered_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'student_id': studentId,
      'register_number': registerNumber,
      'name': name,
      'mobile_number': mobileNumber,
      'masked_mobile': maskedMobile,
      'message_ref': messageRef,
      'status': status,
      'attempt_count': attemptCount,
      'error_reason': errorReason,
      'error_message': errorReason,
      'created_at': createdAt,
      'sent_at': sentAt,
      'dispatched_at': sentAt,
      'delivered_at': deliveredAt,
    };
  }

  bool get isSubmitted =>
      status == 'submitted_to_sms_service' || status == 'sent_to_sms_service';
  bool get isDelivered => status == 'delivery_confirmed';
  bool get isFailed => status == 'failed';
  bool get isCancelled => status == 'cancelled';
  bool get isPending => status == 'pending';
  bool get isSending => status == 'sending';

  Color get statusColor {
    switch (status) {
      case 'delivery_confirmed':
        return const Color(0xFF1B5E20); // Deep green
      case 'submitted_to_sms_service':
      case 'sent_to_sms_service':
        return const Color(0xFF2E7D32); // Emerald green
      case 'failed':
        return const Color(0xFFC62828); // Red
      case 'cancelled':
        return const Color(0xFF757575); // Grey
      case 'sending':
        return const Color(0xFF0288D1); // Blue
      case 'pending':
      default:
        return const Color(0xFFE65100); // Orange / Pending
    }
  }

  String get statusDisplay {
    switch (status) {
      case 'delivery_confirmed':
        return 'Delivery Confirmed';
      case 'submitted_to_sms_service':
      case 'sent_to_sms_service':
        return 'Submitted to SMS Service';
      case 'failed':
        return 'Failed';
      case 'cancelled':
        return 'Cancelled';
      case 'sending':
        return 'Sending...';
      case 'pending':
      default:
        return 'Pending';
    }
  }
}

/// An SMS campaign session stored in MongoDB with full Stage 7/8 metadata.
class SmsCampaign {
  final int id;
  final String title;
  final String message;
  final String targetType;
  final String? routeName;
  final String? busNumber;
  final Map<String, dynamic> senderDevice;
  final String deliveryMethod;
  final String status;
  final int totalRecipients;
  final int submittedCount;
  final int deliveryConfirmedCount;
  final int failedCount;
  final int cancelledCount;
  final int pendingCount;
  final bool allowDuplicates;
  final int duplicatesPreventedCount;
  final int segmentsPerMessage;
  final int totalSmsCount;
  final int validCount;
  final int invalidCount;
  final int duplicateCount;
  final List<SmsRecipientItem> recipients;
  final DateTime? createdAt;
  final DateTime? completedAt;
  // Stage 8 — auto-schedule fields
  final String? session; // 'morning' | 'afternoon'
  final String? scheduleDate; // 'YYYY-MM-DD'
  final int? busCount;
  final int? routeCount;
  final String? autoCampaignKey;

  SmsCampaign({
    required this.id,
    required this.title,
    required this.message,
    required this.targetType,
    this.routeName,
    this.busNumber,
    this.senderDevice = const {},
    this.deliveryMethod = 'direct_sim',
    required this.status,
    required this.totalRecipients,
    required this.submittedCount,
    this.deliveryConfirmedCount = 0,
    required this.failedCount,
    this.cancelledCount = 0,
    required this.pendingCount,
    this.allowDuplicates = false,
    this.duplicatesPreventedCount = 0,
    this.segmentsPerMessage = 1,
    this.totalSmsCount = 0,
    this.validCount = 0,
    this.invalidCount = 0,
    this.duplicateCount = 0,
    this.recipients = const [],
    this.createdAt,
    this.completedAt,
    this.session,
    this.scheduleDate,
    this.busCount,
    this.routeCount,
    this.autoCampaignKey,
  });

  factory SmsCampaign.fromJson(Map<String, dynamic> json) {
    final rawRecipients = json['recipients'] as List<dynamic>? ?? [];
    final recipientsList = rawRecipients
        .map((r) => SmsRecipientItem.fromJson(r as Map<String, dynamic>))
        .toList();

    DateTime? parseDate(dynamic d) {
      if (d == null) return null;
      try {
        return DateTime.parse(d.toString());
      } catch (_) {
        return null;
      }
    }

    final int total = (json['total_recipients'] as num?)?.toInt() ?? recipientsList.length;
    final int submitted = ((json['submitted_count'] ?? json['sent_count']) as num?)?.toInt() ?? 0;
    final int delivered = (json['delivery_confirmed_count'] as num?)?.toInt() ?? 0;
    final int failed = (json['failed_count'] as num?)?.toInt() ?? 0;
    final int cancelled = (json['cancelled_count'] as num?)?.toInt() ?? 0;
    final int pending = (json['pending_count'] as num?)?.toInt() ??
        (total - submitted - failed - cancelled);

    // Support both numeric and string IDs
    final rawId = json['id'] ?? json['_id'];
    final idInt = (rawId is num)
        ? rawId.toInt()
        : (int.tryParse(rawId?.toString() ?? '') ?? 0);

    return SmsCampaign(
      id: idInt,
      title: json['title']?.toString() ?? 'SMS Broadcast',
      message: json['message']?.toString() ?? '',
      targetType: json['target_type']?.toString() ?? 'all_active',
      routeName: json['route_name']?.toString(),
      busNumber: json['bus_number']?.toString(),
      senderDevice: json['sender_device'] is Map<String, dynamic>
          ? json['sender_device'] as Map<String, dynamic>
          : {},
      deliveryMethod: json['delivery_method']?.toString() ?? 'direct_sim',
      status: json['status']?.toString() ?? 'draft',
      totalRecipients: total,
      submittedCount: submitted,
      deliveryConfirmedCount: delivered,
      failedCount: failed,
      cancelledCount: cancelled,
      pendingCount: pending < 0 ? 0 : pending,
      allowDuplicates: json['allow_duplicates'] as bool? ?? false,
      duplicatesPreventedCount: (json['duplicates_prevented_count'] as num?)?.toInt() ?? 0,
      segmentsPerMessage: (json['segments_per_message'] as num?)?.toInt() ?? 1,
      totalSmsCount: (json['total_sms_count'] as num?)?.toInt() ?? total,
      validCount: (json['valid_count'] as num?)?.toInt() ?? total,
      invalidCount: (json['invalid_count'] as num?)?.toInt() ?? 0,
      duplicateCount: (json['duplicate_count'] as num?)?.toInt() ?? 0,
      recipients: recipientsList,
      createdAt: parseDate(json['created_at']),
      completedAt: parseDate(json['completed_at']),
      // Stage 8 fields
      session: json['session']?.toString(),
      scheduleDate: json['schedule_date']?.toString(),
      busCount: (json['bus_count'] as num?)?.toInt(),
      routeCount: (json['route_count'] as num?)?.toInt(),
      autoCampaignKey: json['auto_campaign_key']?.toString(),
    );
  }

  String get sessionLabel {
    if (session == 'morning') return 'Morning Schedule';
    if (session == 'afternoon') return 'Afternoon Schedule';
    return title.isNotEmpty ? title : 'Scheduled Broadcast';
  }

  String get targetDisplay {
    switch (targetType) {
      case 'route':
        return 'Route: ${routeName ?? 'Unspecified'}';
      case 'bus':
        return 'Bus: ${busNumber ?? 'Unspecified'}';
      case 'selected':
        return 'Individual Students ($totalRecipients)';
      case 'test':
        return 'Test SMS to Admin';
      case 'all_active':
      default:
        return 'All Active Students ($totalRecipients)';
    }
  }

  String get statusDisplay {
    switch (status) {
      case 'completed':
        return 'Completed';
      case 'sending':
        return 'Sending in Batches...';
      case 'paused':
        return 'Paused';
      case 'partially_failed':
        return 'Partially Failed';
      case 'cancelled':
        return 'Cancelled';
      case 'draft':
      default:
        return 'Draft / Pending';
    }
  }

  Color get statusColor {
    switch (status) {
      case 'completed':
        return const Color(0xFF2E7D32);
      case 'partially_failed':
        return const Color(0xFFE65100);
      case 'failed':
        return const Color(0xFFC62828);
      case 'sending':
        return const Color(0xFF0288D1);
      case 'paused':
        return const Color(0xFFF57C00);
      case 'cancelled':
      default:
        return const Color(0xFF757575);
    }
  }
}

/// Item representing a student recipient in a pre-flight preview inspection.
class SmsRecipientPreviewItem {
  final int studentId;
  final String registerNumber;
  final String name;
  final String mobileNumber;
  final String maskedMobile;
  final String? parentMobile;
  final String routeName;
  final String busNumber;
  final String? boardingStop;
  final bool isDuplicate;
  final String? error;

  SmsRecipientPreviewItem({
    required this.studentId,
    required this.registerNumber,
    required this.name,
    required this.mobileNumber,
    required this.maskedMobile,
    this.parentMobile,
    this.routeName = '',
    this.busNumber = '',
    this.boardingStop,
    this.isDuplicate = false,
    this.error,
  });

  factory SmsRecipientPreviewItem.fromJson(Map<String, dynamic> json) {
    return SmsRecipientPreviewItem(
      studentId: (json['student_id'] as num?)?.toInt() ?? 0,
      registerNumber: json['register_number']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      mobileNumber: (json['mobile_number'] ?? json['student_mobile'])?.toString() ?? '',
      maskedMobile: json['masked_mobile']?.toString() ?? '***',
      parentMobile: json['parent_mobile']?.toString(),
      routeName: json['route_name']?.toString() ?? '',
      busNumber: json['bus_number']?.toString() ?? '',
      boardingStop: (json['boarding_stop'] ?? json['stop_name'])?.toString(),
      isDuplicate: json['is_duplicate'] as bool? ?? false,
      error: json['error']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'student_id': studentId,
      'register_number': registerNumber,
      'name': name,
      'mobile_number': mobileNumber,
      'masked_mobile': maskedMobile,
      'parent_mobile': parentMobile,
      'route_name': routeName,
      'bus_number': busNumber,
      'boarding_stop': boardingStop,
      'is_duplicate': isDuplicate,
      'error': error,
    };
  }
}

/// Comprehensive pre-flight recipient analysis summary.
class RecipientPreviewSummary {
  final String target;
  final String recipientCategory;
  final String? routeName;
  final String? busNumber;
  final int totalSelectedStudents;
  final int validCount;
  final int invalidCount;
  final int duplicateCount;
  final int uniqueValidCount;
  final int effectiveRecipientCount;
  final bool allowDuplicates;
  final int duplicatesPrevented;
  final List<SmsRecipientPreviewItem> validRecipients;
  final List<Map<String, dynamic>> invalidRecipients;
  final List<Map<String, dynamic>> duplicateGroups;
  final List<SmsRecipientPreviewItem> recipients;

  RecipientPreviewSummary({
    required this.target,
    required this.recipientCategory,
    this.routeName,
    this.busNumber,
    required this.totalSelectedStudents,
    required this.validCount,
    required this.invalidCount,
    required this.duplicateCount,
    required this.uniqueValidCount,
    required this.effectiveRecipientCount,
    required this.allowDuplicates,
    required this.duplicatesPrevented,
    this.validRecipients = const [],
    this.invalidRecipients = const [],
    this.duplicateGroups = const [],
    this.recipients = const [],
  });

  factory RecipientPreviewSummary.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> castList(dynamic list) {
      if (list is! List) return [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }

    final rawValids = json['valid_recipients'] as List<dynamic>? ?? [];
    final validItems = rawValids
        .map((e) => SmsRecipientPreviewItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    final rawRecips = json['recipients'] as List<dynamic>? ?? [];
    final recipItems = rawRecips
        .map((e) => SmsRecipientPreviewItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    return RecipientPreviewSummary(
      target: json['target']?.toString() ?? 'all_active',
      recipientCategory: json['recipient_category']?.toString() ?? 'All Active',
      routeName: json['route_name']?.toString(),
      busNumber: json['bus_number']?.toString(),
      totalSelectedStudents: (json['total_selected_students'] as num?)?.toInt() ?? 0,
      validCount: (json['valid_count'] as num?)?.toInt() ?? 0,
      invalidCount: (json['invalid_count'] as num?)?.toInt() ?? 0,
      duplicateCount: (json['duplicate_count'] as num?)?.toInt() ?? 0,
      uniqueValidCount: (json['unique_valid_count'] as num?)?.toInt() ?? 0,
      effectiveRecipientCount: (json['effective_recipient_count'] as num?)?.toInt() ?? 0,
      allowDuplicates: json['allow_duplicates'] as bool? ?? false,
      duplicatesPrevented: (json['duplicates_prevented'] as num?)?.toInt() ?? 0,
      validRecipients: validItems,
      invalidRecipients: castList(json['invalid_recipients']),
      duplicateGroups: castList(json['duplicate_groups']),
      recipients: recipItems,
    );
  }

  factory RecipientPreviewSummary.empty() {
    return RecipientPreviewSummary(
      target: 'all_active',
      recipientCategory: 'All Active Students',
      totalSelectedStudents: 0,
      validCount: 0,
      invalidCount: 0,
      duplicateCount: 0,
      uniqueValidCount: 0,
      effectiveRecipientCount: 0,
      allowDuplicates: false,
      duplicatesPrevented: 0,
    );
  }
}

/// Compatibility alias
typedef SmsRecipientPreview = RecipientPreviewSummary;

/// Live calculation of SMS segment and encoding metrics.
class SmsSegmentCalculation {
  final String encoding;
  final bool isUnicode;
  final int charCount;
  final int segmentsPerMessage;
  final int remainingInSegment;

  SmsSegmentCalculation({
    required this.encoding,
    required this.isUnicode,
    required this.charCount,
    required this.segmentsPerMessage,
    required this.remainingInSegment,
  });

  factory SmsSegmentCalculation.fromText(String text) {
    if (text.isEmpty) {
      return SmsSegmentCalculation(
        encoding: 'GSM-7',
        isUnicode: false,
        charCount: 0,
        segmentsPerMessage: 1,
        remainingInSegment: 160,
      );
    }

    const gsmBasic = "@£\$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞ\x1bÆæßÉ"
        " !\"#¤%&'()*+,-./0123456789:;<=>?"
        "¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§"
        "¿abcdefghijklmnopqrstuvwxyzäöñüà"
        "^{}\\[~]|€";

    final bool isUnicode = text.split('').any((c) => !gsmBasic.contains(c));
    final length = text.length;
    int segments;
    int remaining;

    if (isUnicode) {
      if (length <= 70) {
        segments = 1;
        remaining = 70 - length;
      } else {
        segments = ((length + 66) ~/ 67);
        remaining = (segments * 67) - length;
      }
    } else {
      if (length <= 160) {
        segments = 1;
        remaining = 160 - length;
      } else {
        segments = ((length + 152) ~/ 153);
        remaining = (segments * 153) - length;
      }
    }

    return SmsSegmentCalculation(
      encoding: isUnicode ? 'Unicode (UCS-2)' : 'GSM-7',
      isUnicode: isUnicode,
      charCount: length,
      segmentsPerMessage: segments,
      remainingInSegment: remaining,
    );
  }
}
