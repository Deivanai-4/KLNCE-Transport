// lib/services/announcement_service.dart
// Stage 9 — Service for Broadcast Announcements & Schedule Change Alerts

import 'package:flutter/foundation.dart';
import '../models/announcement.dart';
import 'api_service.dart';

class AnnouncementService extends ChangeNotifier {
  List<Announcement> _adminAnnouncements = [];
  List<Announcement> _studentAnnouncements = [];
  List<Map<String, dynamic>> _history = [];
  int _studentUnreadCount = 0;
  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;

  List<Announcement> get adminAnnouncements => _adminAnnouncements;
  List<Announcement> get studentAnnouncements => _studentAnnouncements;
  List<Map<String, dynamic>> get history => _history;
  int get studentUnreadCount => _studentUnreadCount;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get error => _error;

  /// Fetch announcements for the admin dashboard.
  Future<void> fetchAdminAnnouncements({
    String status = 'all',
    String? category,
    String? priority,
    String? search,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final params = <String, String>{'status': status};
      if (category != null && category.isNotEmpty) params['category'] = category;
      if (priority != null && priority.isNotEmpty) params['priority'] = priority;
      if (search != null && search.isNotEmpty) params['search'] = search;

      final qs = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
      final path = '/announcements${qs.isNotEmpty ? "?$qs" : ""}';

      final res = await ApiService.get(path) as Map<String, dynamic>;
      final rawList = res['announcements'] as List? ?? [];
      _adminAnnouncements = rawList
          .map((e) => Announcement.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _error = e.toString();
      _adminAnnouncements = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fetch announcements for the current student.
  Future<void> fetchStudentAnnouncements() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await ApiService.get('/announcements/student') as Map<String, dynamic>;
      final rawList = res['announcements'] as List? ?? [];
      _studentAnnouncements = rawList
          .map((e) => Announcement.fromJson(e as Map<String, dynamic>))
          .toList();
      _studentUnreadCount = (res['unread_count'] as num?)?.toInt() ?? 0;
    } catch (e) {
      _error = e.toString();
      _studentAnnouncements = [];
      _studentUnreadCount = 0;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Create an announcement (draft or published).
  Future<Map<String, dynamic>?> createAnnouncement(Map<String, dynamic> payload) async {
    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      final res = await ApiService.post('/announcements', payload) as Map<String, dynamic>;
      await fetchAdminAnnouncements();
      return res;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  /// Update an existing announcement.
  Future<bool> updateAnnouncement(int id, Map<String, dynamic> payload) async {
    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      await ApiService.put('/announcements/$id', payload);
      await fetchAdminAnnouncements();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  /// Publish a draft announcement.
  Future<Map<String, dynamic>?> publishAnnouncement(int id, {bool sendSms = false}) async {
    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      final res = await ApiService.post(
        '/announcements/$id/publish',
        {'send_sms': sendSms},
      ) as Map<String, dynamic>;
      await fetchAdminAnnouncements();
      return res;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  /// Delete an announcement.
  Future<bool> deleteAnnouncement(int id) async {
    try {
      await ApiService.delete('/announcements/$id');
      _adminAnnouncements.removeWhere((a) => a.id == id);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Student marks an announcement as read.
  Future<void> markAsRead(int id) async {
    try {
      await ApiService.post('/announcements/$id/read', {});
      // Optimistic local update
      final idx = _studentAnnouncements.indexWhere((a) => a.id == id);
      if (idx != -1 && !_studentAnnouncements[idx].isRead) {
        final current = _studentAnnouncements[idx];
        _studentAnnouncements[idx] = Announcement(
          id: current.id,
          title: current.title,
          message: current.message,
          category: current.category,
          priority: current.priority,
          status: current.status,
          targetType: current.targetType,
          targetRoute: current.targetRoute,
          targetBus: current.targetBus,
          targetStudentIds: current.targetStudentIds,
          channels: current.channels,
          createdBy: current.createdBy,
          createdByName: current.createdByName,
          createdAt: current.createdAt,
          publishedAt: current.publishedAt,
          updatedAt: current.updatedAt,
          recipientCount: current.recipientCount,
          inAppCount: current.inAppCount,
          smsCampaignId: current.smsCampaignId,
          smsStatus: current.smsStatus,
          isRead: true,
          readCount: current.readCount + 1,
          isEmergency: current.isEmergency,
          scheduleChangeMetadata: current.scheduleChangeMetadata,
        );
        if (_studentUnreadCount > 0) _studentUnreadCount--;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Preview recipients before saving/publishing.
  Future<Map<String, dynamic>?> previewRecipients({
    required String targetType,
    String? targetRoute,
    String? targetBus,
    List<int>? targetStudentIds,
  }) async {
    try {
      final payload = <String, dynamic>{
        'target_type': targetType,
      };
      if (targetRoute != null && targetRoute.isNotEmpty) payload['target_route'] = targetRoute;
      if (targetBus != null && targetBus.isNotEmpty) payload['target_bus'] = targetBus;
      if (targetStudentIds != null && targetStudentIds.isNotEmpty) {
        payload['target_student_ids'] = targetStudentIds;
      }
      final res = await ApiService.post('/announcements/recipient-preview', payload)
          as Map<String, dynamic>;
      return res;
    } catch (e) {
      return null;
    }
  }

  /// Detect changes between current published schedule and proposed updates.
  Future<Map<String, dynamic>?> detectScheduleChanges(
    int scheduleId,
    Map<String, dynamic> newData,
  ) async {
    try {
      final res = await ApiService.post('/announcements/detect-schedule-changes', {
        'schedule_id': scheduleId,
        'new_data': newData,
      }) as Map<String, dynamic>;
      return res;
    } catch (_) {
      return null;
    }
  }

  /// Fetch full delivery and notification audit history.
  Future<void> fetchHistory() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await ApiService.get('/announcements/history') as Map<String, dynamic>;
      final rawList = res['history'] as List? ?? [];
      _history = rawList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      _error = e.toString();
      _history = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
