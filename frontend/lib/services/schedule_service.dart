import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/schedule.dart';
import 'api_service.dart';

class ScheduleService extends ChangeNotifier {
  Schedule? _publishedSchedule;
  List<Schedule> _allSchedules = [];
  bool _isLoading = false;
  String? _errorMessage;
  int _publishedRequestRevision = 0;
  bool _lastPublishedFetchSucceeded = false;
  String? _activeTrip;
  DateTime? _serverTimeIst;
  DateTime? _nextTransitionIst;

  Schedule? get publishedSchedule => _publishedSchedule;
  List<Schedule> get allSchedules => _allSchedules;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get lastPublishedFetchSucceeded => _lastPublishedFetchSucceeded;
  String? get activeTrip => _activeTrip;
  DateTime? get serverTimeIst => _serverTimeIst;
  DateTime? get nextTransitionIst => _nextTransitionIst;

  Future<void> fetchPublishedSchedule({String? trip, String? college}) async {
    final requestRevision = ++_publishedRequestRevision;
    _isLoading = true;
    _errorMessage = null;
    _lastPublishedFetchSucceeded = false;
    notifyListeners();

    try {
      String endpoint = '/schedules/published';
      List<String> queryParams = [];
      if (trip != null) queryParams.add('trip=$trip');
      if (college != null) queryParams.add('college=$college');
      if (queryParams.isNotEmpty) {
        endpoint += '?${queryParams.join('&')}';
      }

      final res = await ApiService.get(endpoint);
      if (requestRevision != _publishedRequestRevision) return;
      _activeTrip = res['active_trip'] as String?;
      _serverTimeIst = DateTime.tryParse(
        res['server_time_ist']?.toString() ?? '',
      );
      _nextTransitionIst = DateTime.tryParse(
        res['next_transition_ist']?.toString() ?? '',
      );
      final rawSchedule = res['schedule'];
      _publishedSchedule = rawSchedule is Map<String, dynamic>
          ? Schedule.fromJson(rawSchedule)
          : null;
      _lastPublishedFetchSucceeded = true;
    } on ApiException catch (e) {
      if (requestRevision != _publishedRequestRevision) return;
      _publishedSchedule = null;
      _errorMessage = e.message;
      _clearPublishedAvailability();
    } catch (e) {
      if (requestRevision != _publishedRequestRevision) return;
      _publishedSchedule = null;
      _errorMessage = 'Could not load timetable.';
      _clearPublishedAvailability();
    } finally {
      if (requestRevision == _publishedRequestRevision) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  void _clearPublishedAvailability() {
    _activeTrip = null;
    _serverTimeIst = null;
    _nextTransitionIst = null;
  }

  Future<void> fetchAllSchedules() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await ApiService.get('/schedules');
      if (res['schedules'] != null) {
        final raw = res['schedules'] as List<dynamic>;
        _allSchedules = raw
            .map((s) => Schedule.fromJson(s as Map<String, dynamic>))
            .toList();
      }
    } on ApiException catch (e) {
      _errorMessage = e.message;
    } catch (_) {
      _errorMessage = 'Failed to load schedule list.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Schedule?> createManualSchedule({
    required String title,
    required String tripDirection,
    required String college,
    required String effectiveDate,
    required List<Map<String, dynamic>> routes,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await ApiService.post('/schedules/manual', {
        'title': title,
        'trip_direction': tripDirection,
        'college': college,
        'effective_date': effectiveDate,
        'routes': routes,
      });
      final rawSchedule = res['schedule'];
      if (rawSchedule is! Map<String, dynamic>) {
        throw ApiException(502, 'The server returned an invalid schedule.');
      }
      return Schedule.fromJson(rawSchedule);
    } on ApiException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'Could not create the schedule. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return null;
  }

  Future<Schedule?> uploadAndExtractSchedule({
    required String title,
    required String tripDirection,
    required String college,
    required String effectiveDate,
    required String filePath,
    List<int>? fileBytes,
    String? fileName,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final Map<String, dynamic> res;

      // On Web (or when fileBytes are available), send JSON with base64
      // This avoids http.MultipartRequest stream lockups on Flutter Web.
      if (fileBytes != null && fileBytes.isNotEmpty) {
        final b64 = base64Encode(fileBytes);
        res = await ApiService.post('/schedules/upload', {
          'title': title,
          'trip_direction': tripDirection,
          'college': college,
          'effective_date': effectiveDate,
          'file_base64': b64,
          'filename': fileName ?? 'schedule.png',
        });
      } else {
        // Fallback for native mobile with local file path
        res = await ApiService.postMultipart(
          endpoint: '/schedules/upload',
          fields: {
            'title': title,
            'trip_direction': tripDirection,
            'college': college,
            'effective_date': effectiveDate,
          },
          fileParamName: 'file',
          filePath: filePath,
          fileBytes: fileBytes,
          fileName: fileName ?? 'schedule_upload.png',
        );
      }

      if (res['schedule'] != null) {
        final draft =
            Schedule.fromJson(res['schedule'] as Map<String, dynamic>);
        _isLoading = false;
        notifyListeners();
        return draft;
      }
    } on ApiException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage =
          'Schedule upload & OCR processing failed: ${e.toString()}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return null;
  }

  Future<bool> updateDraftRoutes(
      int scheduleId, List<Map<String, dynamic>> routes) async {
    _isLoading = true;
    notifyListeners();

    try {
      await ApiService.put('/schedules/$scheduleId/routes', {
        'routes': routes,
      });
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to update draft table: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> publishSchedule(int scheduleId) async {
    _isLoading = true;
    notifyListeners();

    try {
      await ApiService.post('/schedules/$scheduleId/publish', {});
      await fetchAllSchedules();
      await fetchPublishedSchedule();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to publish schedule: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
}
