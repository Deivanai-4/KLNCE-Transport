import 'package:flutter/foundation.dart';
import '../models/student.dart';
import 'api_service.dart';

class StudentService extends ChangeNotifier {
  List<Student> _students = [];
  int _totalCount = 0;
  bool _isLoading = false;
  String? _errorMessage;

  List<Student> get students => _students;
  int get totalCount => _totalCount;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Download student Excel (.xlsx) or CSV template bytes.
  Future<List<int>> downloadTemplate({String format = 'xlsx'}) async {
    try {
      return await ApiService.getBytes('/students/template?format=$format');
    } on ApiException catch (e) {
      throw Exception(e.message);
    } catch (_) {
      throw Exception('Could not download student template.');
    }
  }

  /// Upload file and retrieve validation preview without importing.
  Future<ExcelPreviewSummary> uploadAndPreview({
    required String filePath,
    List<int>? fileBytes,
    required String fileName,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await ApiService.postMultipart(
        endpoint: '/students/upload-preview',
        fields: {},
        fileParamName: 'file',
        filePath: filePath,
        fileBytes: fileBytes,
        fileName: fileName,
      );
      return ExcelPreviewSummary.fromJson(res);
    } on ApiException catch (e) {
      _errorMessage = e.message;
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Confirm and save validated students to MongoDB Atlas.
  Future<Map<String, dynamic>> confirmImport({
    required List<Map<String, dynamic>> records,
    bool updateExisting = false,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await ApiService.post('/students/import', {
        'students': records,
        'update_existing': updateExisting,
      });
      return Map<String, dynamic>.from(res);
    } on ApiException catch (e) {
      _errorMessage = e.message;
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fetch registered students with search and filters.
  Future<List<Student>> fetchStudents({
    int page = 1,
    int perPage = 20,
    String? q,
    String? department,
    String? year,
    String? routeName,
    String? busNumber,
    bool? isTransportActive,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final queryParams = <String>[
        'page=$page',
        'per_page=$perPage',
      ];
      if (q != null && q.trim().isNotEmpty) {
        queryParams.add('q=${Uri.encodeComponent(q.trim())}');
      }
      if (department != null && department.trim().isNotEmpty) {
        queryParams.add('department=${Uri.encodeComponent(department.trim())}');
      }
      if (year != null && year.trim().isNotEmpty) {
        queryParams.add('year=${Uri.encodeComponent(year.trim())}');
      }
      if (routeName != null && routeName.trim().isNotEmpty) {
        queryParams.add('route_name=${Uri.encodeComponent(routeName.trim())}');
      }
      if (busNumber != null && busNumber.trim().isNotEmpty) {
        queryParams.add('bus_number=${Uri.encodeComponent(busNumber.trim())}');
      }
      if (isTransportActive != null) {
        queryParams.add('is_transport_active=$isTransportActive');
      }

      final qs = '?${queryParams.join('&')}';
      final res = await ApiService.get('/students$qs');

      final rawList = res['students'] as List<dynamic>? ?? [];
      _students = rawList
          .map((item) => Student.fromJson(item as Map<String, dynamic>))
          .toList();
      _totalCount = res['total'] as int? ?? _students.length;
      return _students;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      return [];
    } catch (_) {
      _errorMessage = 'Could not load students. Please check connection.';
      return [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Manual Add Student for corrections or individual registrations.
  Future<Student> addStudent(Map<String, dynamic> data) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await ApiService.post('/students', data);
      final created = Student.fromJson(res['student'] as Map<String, dynamic>);
      _students.insert(0, created);
      _totalCount++;
      return created;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Update an existing student's details and route allocation.
  Future<Student> updateStudent(int id, Map<String, dynamic> data) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await ApiService.put('/students/$id', data);
      final updated = Student.fromJson(res['student'] as Map<String, dynamic>);
      final idx = _students.indexWhere((s) => s.id == id);
      if (idx >= 0) {
        _students[idx] = updated;
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

  /// Toggle student transport registration status.
  Future<Student> toggleTransportStatus(int id, {bool? isActive}) async {
    try {
      final payload = <String, dynamic>{};
      if (isActive != null) payload['is_transport_active'] = isActive;
      final res = await ApiService.put('/students/$id/status', payload);
      final updated = Student.fromJson(res['student'] as Map<String, dynamic>);
      final idx = _students.indexWhere((s) => s.id == id);
      if (idx >= 0) {
        _students[idx] = updated;
        notifyListeners();
      }
      return updated;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      rethrow;
    }
  }

  /// Fetch aggregated route allocation summary.
  Future<Map<String, dynamic>> fetchRouteAllocations() async {
    try {
      final res = await ApiService.get('/students/route-allocations');
      return Map<String, dynamic>.from(res);
    } on ApiException catch (e) {
      throw Exception(e.message);
    } catch (_) {
      throw Exception('Could not load route allocations.');
    }
  }

  /// Fetch secure list of student phone numbers for SMS broadcast (Admin only).
  Future<Map<String, dynamic>> fetchSmsRecipients({
    required String target,
    String? routeName,
    String? busNumber,
    List<int>? studentIds,
  }) async {
    try {
      final queryParams = <String>['target=$target'];
      if (routeName != null) {
        queryParams.add('route_name=${Uri.encodeComponent(routeName)}');
      }
      if (busNumber != null) {
        queryParams.add('bus_number=${Uri.encodeComponent(busNumber)}');
      }
      if (studentIds != null && studentIds.isNotEmpty) {
        queryParams.add('student_ids=${studentIds.join(',')}');
      }
      final res = await ApiService.get(
          '/students/sms-recipients?${queryParams.join('&')}');
      return Map<String, dynamic>.from(res);
    } on ApiException catch (e) {
      throw Exception(e.message);
    } catch (_) {
      throw Exception('Could not load SMS recipients.');
    }
  }
}
