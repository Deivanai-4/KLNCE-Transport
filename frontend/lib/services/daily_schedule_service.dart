import 'package:flutter/foundation.dart';
import '../models/daily_schedule.dart';
import 'api_service.dart';

class DailyScheduleService extends ChangeNotifier {
  List<DailySchedule> _schedules = [];
  bool _isLoading = false;
  String? _errorMessage;
  Map<String, dynamic>? _lastChangeSummary;

  List<DailySchedule> get schedules => _schedules;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  Map<String, dynamic>? get lastChangeSummary => _lastChangeSummary;
  void clearLastChangeSummary() => _lastChangeSummary = null;

  /// Fetch daily schedules. If [date], [session], [status], or [busNumber] are provided, appends query params.
  Future<List<DailySchedule>> fetchDailySchedules({
    String? date,
    String? session,
    String? status,
    String? busNumber,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final queryParams = <String>[];
      if (date != null && date.trim().isNotEmpty) {
        queryParams.add('date=${Uri.encodeComponent(date.trim())}');
      }
      if (session != null && session.trim().isNotEmpty) {
        queryParams.add('session=${Uri.encodeComponent(session.trim())}');
      }
      if (status != null && status.trim().isNotEmpty) {
        queryParams.add('status=${Uri.encodeComponent(status.trim())}');
      }
      if (busNumber != null && busNumber.trim().isNotEmpty) {
        queryParams.add('bus_number=${Uri.encodeComponent(busNumber.trim().toUpperCase())}');
      }

      final qs = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
      final res = await ApiService.get('/daily-schedules$qs');

      final rawList = res['daily_schedules'] as List<dynamic>? ?? [];
      _schedules = rawList
          .map((item) => DailySchedule.fromJson(item as Map<String, dynamic>))
          .toList();
      _errorMessage = null;
      return _schedules;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      return [];
    } catch (_) {
      _errorMessage = 'Could not load daily schedules. Please check connection.';
      return [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Create a new daily schedule (draft or published).
  Future<DailySchedule> createDailySchedule({
    required String date,
    required String session,
    required String status,
    required List<DailyBus> buses,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final payload = {
        'date': date,
        'session': session,
        'status': status,
        'buses': buses.map((b) => b.toJson()).toList(),
      };

      final res = await ApiService.post('/daily-schedules', payload);
      final created = DailySchedule.fromJson(
          res['daily_schedule'] as Map<String, dynamic>);

      // Refresh local list or prepend
      _schedules.removeWhere(
          (s) => s.date == created.date && s.session == created.session);
      _schedules.insert(0, created);
      return created;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Update an existing daily schedule.
  Future<DailySchedule> updateDailySchedule(
    int id, {
    String? date,
    String? session,
    String? status,
    List<DailyBus>? buses,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final payload = <String, dynamic>{};
      if (date != null) payload['date'] = date;
      if (session != null) payload['session'] = session;
      if (status != null) payload['status'] = status;
      if (buses != null) {
        payload['buses'] = buses.map((b) => b.toJson()).toList();
      }

      _lastChangeSummary = null;
      final res = await ApiService.put('/daily-schedules/$id', payload);
      final updated = DailySchedule.fromJson(
          res['daily_schedule'] as Map<String, dynamic>);
      if (res['schedule_change_detected'] == true) {
        _lastChangeSummary =
            Map<String, dynamic>.from(res['change_summary'] as Map);
      }

      final idx = _schedules.indexWhere((s) => s.id == id);
      if (idx >= 0) {
        _schedules[idx] = updated;
      }
      return updated;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Publish a draft or revised schedule.
  Future<DailySchedule> publishDailySchedule(int id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await ApiService.post('/daily-schedules/$id/publish', {});
      final published = DailySchedule.fromJson(
          res['daily_schedule'] as Map<String, dynamic>);

      final idx = _schedules.indexWhere((s) => s.id == id);
      if (idx >= 0) {
        _schedules[idx] = published;
      }
      return published;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Delete a daily schedule.
  Future<void> deleteDailySchedule(int id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await ApiService.delete('/daily-schedules/$id');
      _schedules.removeWhere((s) => s.id == id);
    } on ApiException catch (e) {
      _errorMessage = e.message;
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Alias for deleteDailySchedule.
  Future<void> deleteSchedule(int id) => deleteDailySchedule(id);

  /// Fetch dashboard statistics from the backend.
  /// Requires admin JWT to be present in ApiService.
  Future<Map<String, dynamic>> fetchStats() async {
    try {
      final res = await ApiService.get('/daily-schedules/stats');
      return Map<String, dynamic>.from(res as Map);
    } on ApiException catch (e) {
      throw Exception(e.message);
    } catch (_) {
      throw Exception('Could not load schedule statistics.');
    }
  }
}
