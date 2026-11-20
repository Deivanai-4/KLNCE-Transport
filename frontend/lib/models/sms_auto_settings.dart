// lib/models/sms_auto_settings.dart
// Model for automatic SMS schedule settings (Stage 8)

class SmsAutoSettings {
  final bool isEnabled;
  final String morningTime;
  final String afternoonTime;
  final String confirmationPolicy; // 'confirmation' | 'automatic'
  final List<String> enabledSessions; // ['morning','afternoon']
  final String recipientGroup; // 'all_active' | 'by_route' | 'by_bus'
  final String testPhone;
  final String messageTemplateMorning;
  final String messageTemplateAfternoon;
  final bool emergencyDisabled;
  final String? lastRunMorning;
  final String? lastRunAfternoon;

  // Computed by backend
  final String? nextScheduledMorning;
  final String? nextScheduledAfternoon;
  final int pendingConfirmationsCount;
  final bool isReadyForMorning;
  final bool isReadyForAfternoon;
  final String? todayDate;
  final String? currentTimeIst;
  final String? scheduleStatus;

  const SmsAutoSettings({
    this.isEnabled = false,
    this.morningTime = '06:30',
    this.afternoonTime = '14:00',
    this.confirmationPolicy = 'confirmation',
    this.enabledSessions = const ['morning', 'afternoon'],
    this.recipientGroup = 'all_active',
    this.testPhone = '',
    this.messageTemplateMorning =
        'KLNCE Transport: Morning bus {bus_number} on {route_name} departs at {departure_time}. Check app for stop sequence.',
    this.messageTemplateAfternoon =
        'KLNCE Transport: Afternoon bus {bus_number} on {route_name} departs at {departure_time}. Check app for stop sequence.',
    this.emergencyDisabled = false,
    this.lastRunMorning,
    this.lastRunAfternoon,
    this.nextScheduledMorning,
    this.nextScheduledAfternoon,
    this.pendingConfirmationsCount = 0,
    this.isReadyForMorning = false,
    this.isReadyForAfternoon = false,
    this.todayDate,
    this.currentTimeIst,
    this.scheduleStatus,
  });

  factory SmsAutoSettings.fromJson(Map<String, dynamic> json) {
    final settings = json['settings'] as Map<String, dynamic>? ?? json;
    final schedule = json['schedule'] as Map<String, dynamic>? ?? {};
    return SmsAutoSettings(
      isEnabled: settings['is_enabled'] as bool? ?? false,
      morningTime: settings['morning_time'] as String? ?? '06:30',
      afternoonTime: settings['afternoon_time'] as String? ?? '14:00',
      confirmationPolicy:
          settings['confirmation_policy'] as String? ?? 'confirmation',
      enabledSessions: List<String>.from(
          settings['enabled_sessions'] as List? ?? ['morning', 'afternoon']),
      recipientGroup: settings['recipient_group'] as String? ?? 'all_active',
      testPhone: settings['test_phone'] as String? ?? '',
      messageTemplateMorning: settings['message_template_morning'] as String? ??
          'KLNCE Transport: Morning bus {bus_number} on {route_name} departs at {departure_time}. Check app for stop sequence.',
      messageTemplateAfternoon:
          settings['message_template_afternoon'] as String? ??
              'KLNCE Transport: Afternoon bus {bus_number} on {route_name} departs at {departure_time}. Check app for stop sequence.',
      emergencyDisabled: settings['emergency_disabled'] as bool? ?? false,
      lastRunMorning: settings['last_run_morning'] as String?,
      lastRunAfternoon: settings['last_run_afternoon'] as String?,
      nextScheduledMorning: json['next_scheduled_morning'] as String?,
      nextScheduledAfternoon: json['next_scheduled_afternoon'] as String?,
      pendingConfirmationsCount:
          (json['pending_confirmations_count'] as num?)?.toInt() ?? 0,
      isReadyForMorning: schedule['is_ready_morning'] as bool? ?? false,
      isReadyForAfternoon: schedule['is_ready_afternoon'] as bool? ?? false,
      todayDate: schedule['today_date'] as String?,
      currentTimeIst: schedule['current_time_ist'] as String?,
      scheduleStatus: schedule['schedule_status'] as String?,
    );
  }

  Map<String, dynamic> toUpdatePayload() => {
        'is_enabled': isEnabled,
        'morning_time': morningTime,
        'afternoon_time': afternoonTime,
        'confirmation_policy': confirmationPolicy,
        'enabled_sessions': enabledSessions,
        'recipient_group': recipientGroup,
        'test_phone': testPhone,
        'message_template_morning': messageTemplateMorning,
        'message_template_afternoon': messageTemplateAfternoon,
      };

  SmsAutoSettings copyWith({
    bool? isEnabled,
    String? morningTime,
    String? afternoonTime,
    String? confirmationPolicy,
    List<String>? enabledSessions,
    String? recipientGroup,
    String? testPhone,
    String? messageTemplateMorning,
    String? messageTemplateAfternoon,
    bool? emergencyDisabled,
    String? lastRunMorning,
    String? lastRunAfternoon,
    int? pendingConfirmationsCount,
    String? nextScheduledMorning,
    String? nextScheduledAfternoon,
    bool? isReadyForMorning,
    bool? isReadyForAfternoon,
    String? todayDate,
    String? currentTimeIst,
    String? scheduleStatus,
  }) =>
      SmsAutoSettings(
        isEnabled: isEnabled ?? this.isEnabled,
        morningTime: morningTime ?? this.morningTime,
        afternoonTime: afternoonTime ?? this.afternoonTime,
        confirmationPolicy: confirmationPolicy ?? this.confirmationPolicy,
        enabledSessions: enabledSessions ?? this.enabledSessions,
        recipientGroup: recipientGroup ?? this.recipientGroup,
        testPhone: testPhone ?? this.testPhone,
        messageTemplateMorning:
            messageTemplateMorning ?? this.messageTemplateMorning,
        messageTemplateAfternoon:
            messageTemplateAfternoon ?? this.messageTemplateAfternoon,
        emergencyDisabled: emergencyDisabled ?? this.emergencyDisabled,
        lastRunMorning: lastRunMorning ?? this.lastRunMorning,
        lastRunAfternoon: lastRunAfternoon ?? this.lastRunAfternoon,
        nextScheduledMorning: nextScheduledMorning ?? this.nextScheduledMorning,
        nextScheduledAfternoon:
            nextScheduledAfternoon ?? this.nextScheduledAfternoon,
        pendingConfirmationsCount:
            pendingConfirmationsCount ?? this.pendingConfirmationsCount,
        isReadyForMorning: isReadyForMorning ?? this.isReadyForMorning,
        isReadyForAfternoon: isReadyForAfternoon ?? this.isReadyForAfternoon,
        todayDate: todayDate ?? this.todayDate,
        currentTimeIst: currentTimeIst ?? this.currentTimeIst,
        scheduleStatus: scheduleStatus ?? this.scheduleStatus,
      );

  bool get isAutomaticMode => confirmationPolicy == 'automatic';
  bool get hasPendingConfirmations => pendingConfirmationsCount > 0;
  bool get isMorningEnabled => enabledSessions.contains('morning');
  bool get isAfternoonEnabled => enabledSessions.contains('afternoon');
  bool get isEffectivelyEnabled => isEnabled && !emergencyDisabled;
}
