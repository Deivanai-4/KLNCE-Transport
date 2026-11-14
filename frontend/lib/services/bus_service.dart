import 'package:flutter/foundation.dart';
import '../models/bus_route.dart';
import 'api_service.dart';

class BusService extends ChangeNotifier {
  List<BusRoute> _searchResults = [];
  List<Map<String, dynamic>> _allStops = [];
  bool _isLoading = false;
  String? _errorMessage;
  String _lastQuery = '';

  List<BusRoute> get searchResults => _searchResults;
  List<Map<String, dynamic>> get allStops => _allStops;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get lastQuery => _lastQuery;

  Future<void> searchByStop(String stopName, {String trip = 'incoming'}) async {
    if (stopName.trim().isEmpty) {
      _searchResults = [];
      _lastQuery = '';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    _lastQuery = stopName;
    notifyListeners();

    try {
      final encodedStop = Uri.encodeComponent(stopName.trim());
      final res = await ApiService.get('/buses/search?stop=$encodedStop&trip=$trip');
      final raw = res['buses'] as List<dynamic>? ?? [];
      _searchResults = raw
          .map((b) => BusRoute.fromJson(b as Map<String, dynamic>))
          .toList();
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _searchResults = [];
    } catch (e) {
      _errorMessage = 'Network error. Check backend connection.';
      _searchResults = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchAllStops({String? query}) async {
    try {
      final endpoint = query != null && query.isNotEmpty
          ? '/buses/all-stops?q=${Uri.encodeComponent(query)}'
          : '/buses/all-stops';
      final res = await ApiService.get(endpoint);
      _allStops = List<Map<String, dynamic>>.from(res['stops'] ?? []);
      notifyListeners();
    } catch (_) {}
  }

  void clearResults() {
    _searchResults = [];
    _lastQuery = '';
    _errorMessage = null;
    notifyListeners();
  }
}
