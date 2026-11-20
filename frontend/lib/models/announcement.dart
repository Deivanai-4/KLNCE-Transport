// lib/models/announcement.dart
// Stage 9 — Broadcast Announcements & Schedule Change Alerts Model

import 'package:flutter/material.dart';

class Announcement {
  final int id;
  final String title;
  final String message;
  final String category;
  final String priority; // 'low', 'normal', 'high', 'emergency'
  final String status; // 'draft', 'published', 'archived'
  final String targetType; // 'all_active', 'route', 'bus', 'selected'
  final String? targetRoute;
  final String? targetBus;
  final List<int> targetStudentIds;
  final List<String> channels; // ['in_app', 'sms']
  final int createdBy;
  final String createdByName;
  final DateTime? createdAt;
  final DateTime? publishedAt;
  final DateTime? updatedAt;
  final int recipientCount;
  final int inAppCount;
  final int? smsCampaignId;
  final String? smsStatus;
  final bool isRead;
  final int readCount;
  final bool isEmergency;
  final Map<String, dynamic> scheduleChangeMetadata;

  const Announcement({
    required this.id,
    required this.title,
    required this.message,
    this.category = 'General Transport Notice',
    this.priority = 'normal',
    this.status = 'draft',
    this.targetType = 'all_active',
    this.targetRoute,
    this.targetBus,
    this.targetStudentIds = const [],
    this.channels = const ['in_app'],
    this.createdBy = 0,
    this.createdByName = 'Admin',
    this.createdAt,
    this.publishedAt,
    this.updatedAt,
    this.recipientCount = 0,
    this.inAppCount = 0,
    this.smsCampaignId,
    this.smsStatus,
    this.isRead = false,
    this.readCount = 0,
    this.isEmergency = false,
    this.scheduleChangeMetadata = const {},
  });

  factory Announcement.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic d) {
      if (d == null) return null;
      try {
        return DateTime.parse(d.toString());
      } catch (_) {
        return null;
      }
    }

    final rawId = json['id'] ?? json['_id'];
    final idInt = (rawId is num)
        ? rawId.toInt()
        : (int.tryParse(rawId?.toString() ?? '') ?? 0);

    final priorityStr = json['priority']?.toString().toLowerCase() ?? 'normal';
    final categoryStr = json['category']?.toString() ?? 'General Transport Notice';
    final isEmerg = json['is_emergency'] as bool? ??
        (priorityStr == 'emergency' || categoryStr == 'Emergency Notice');

    final rawStudentIds = json['target_student_ids'] as List? ?? [];
    final studentIds = rawStudentIds
        .map((e) => (e is num) ? e.toInt() : (int.tryParse(e.toString()) ?? 0))
        .where((id) => id > 0)
        .toList();

    final rawChannels = json['channels'] as List? ?? ['in_app'];
    final channels = rawChannels.map((e) => e.toString()).toList();

    return Announcement(
      id: idInt,
      title: json['title']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      category: categoryStr,
      priority: priorityStr,
      status: json['status']?.toString() ?? 'draft',
      targetType: json['target_type']?.toString() ?? 'all_active',
      targetRoute: json['target_route']?.toString(),
      targetBus: json['target_bus']?.toString(),
      targetStudentIds: studentIds,
      channels: channels,
      createdBy: (json['created_by'] as num?)?.toInt() ?? 0,
      createdByName: json['created_by_name']?.toString() ?? 'Admin',
      createdAt: parseDate(json['created_at']),
      publishedAt: parseDate(json['published_at']),
      updatedAt: parseDate(json['updated_at']),
      recipientCount: (json['recipient_count'] as num?)?.toInt() ?? 0,
      inAppCount: (json['in_app_count'] as num?)?.toInt() ?? 0,
      smsCampaignId: (json['sms_campaign_id'] as num?)?.toInt(),
      smsStatus: json['sms_status']?.toString(),
      isRead: json['is_read'] as bool? ?? false,
      readCount: (json['read_count'] as num?)?.toInt() ?? 0,
      isEmergency: isEmerg,
      scheduleChangeMetadata: json['schedule_change_metadata'] is Map
          ? Map<String, dynamic>.from(json['schedule_change_metadata'] as Map)
          : const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'message': message,
        'category': category,
        'priority': priority,
        'status': status,
        'target_type': targetType,
        'target_route': targetRoute,
        'target_bus': targetBus,
        'target_student_ids': targetStudentIds,
        'channels': channels,
        'send_sms': channels.contains('sms'),
        'schedule_change_metadata': scheduleChangeMetadata,
      };

  bool get isDraft => status == 'draft';
  bool get isPublished => status == 'published';
  bool get hasSms => channels.contains('sms');

  Color get priorityColor {
    switch (priority) {
      case 'emergency':
        return const Color(0xFFDC2626);
      case 'high':
        return const Color(0xFFEA580C);
      case 'low':
        return const Color(0xFF64748B);
      case 'normal':
      default:
        return const Color(0xFF0F766E);
    }
  }

  IconData get categoryIcon {
    switch (category) {
      case 'Bus Delay':
        return Icons.access_time_filled_rounded;
      case 'Bus Cancellation':
        return Icons.cancel_rounded;
      case 'Route Change':
        return Icons.alt_route_rounded;
      case 'Bus Replacement':
        return Icons.published_with_changes_rounded;
      case 'Schedule Change':
        return Icons.schedule_rounded;
      case 'Emergency Notice':
        return Icons.warning_rounded;
      case 'Holiday Transport Notice':
        return Icons.celebration_rounded;
      case 'General Transport Notice':
      default:
        return Icons.campaign_rounded;
    }
  }

  Color get categoryColor {
    switch (category) {
      case 'Emergency Notice':
        return const Color(0xFFDC2626);
      case 'Bus Delay':
        return const Color(0xFFD97706);
      case 'Bus Cancellation':
        return const Color(0xFFB91C1C);
      case 'Route Change':
        return const Color(0xFF7C3AED);
      case 'Bus Replacement':
        return const Color(0xFF2563EB);
      case 'Schedule Change':
        return const Color(0xFF0D9488);
      case 'Holiday Transport Notice':
        return const Color(0xFF059669);
      case 'General Transport Notice':
      default:
        return const Color(0xFF475569);
    }
  }

  String get targetLabel {
    switch (targetType) {
      case 'route':
        return 'Route: ${targetRoute ?? "Unspecified"}';
      case 'bus':
        return 'Bus: ${targetBus ?? "Unspecified"}';
      case 'selected':
        return '${targetStudentIds.length} Selected Students';
      case 'all_active':
      default:
        return 'All Active Students ($recipientCount)';
    }
  }
}
