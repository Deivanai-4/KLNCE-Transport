import 'package:flutter/foundation.dart';
import '../models/bus_route.dart';
import 'api_service.dart';

class BusService extends ChangeNotifier {
  List<BusRoute> _searchResults = [];
  List<BusRoute> _routes = [];
  List<Map<String, dynamic>> _allStops = [];
  bool _isLoading = false;
  String? _errorMessage;
  String _lastQuery = '';
  int _searchRevision = 0;
  String? _activeTrip;
  String? get activeTrip => _activeTrip;

  List<BusRoute> get searchResults => _searchResults;
  List<BusRoute> get routes => _routes;
  List<Map<String, dynamic>> get allStops => _allStops;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get lastQuery => _lastQuery;

  Future<void> fetchAllRoutes() async {
    try {
      final res = await ApiService.get('/buses');
      final raw = res['buses'] as List<dynamic>? ??
          res['routes'] as List<dynamic>? ??
          [];
      _routes =
          raw.map((b) => BusRoute.fromJson(b as Map<String, dynamic>)).toList();
      notifyListeners();
    } catch (_) {}
  }

  /// Alias for fetchAllRoutes
  Future<void> fetchAllBusRoutes() => fetchAllRoutes();

  Future<void> searchByStop(String stopName, {String? trip}) async {
    final requestRevision = ++_searchRevision;
    if (stopName.trim().isEmpty) {
      _searchResults = [];
      _lastQuery = '';
      _isLoading = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    _lastQuery = stopName;
    notifyListeners();

    try {
      final encodedStop = Uri.encodeComponent(stopName.trim());
      final tripParam = trip == null ? '' : '&trip=$trip';
      final res = await ApiService.get(
        '/buses/search?stop=$encodedStop$tripParam',
      );
      if (requestRevision != _searchRevision) return;
      _activeTrip = res['active_trip'] as String?;
      final raw = res['buses'] as List<dynamic>? ?? [];
      _searchResults =
          raw.map((b) => BusRoute.fromJson(b as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (requestRevision != _searchRevision) return;
      _errorMessage = e.message;
      _searchResults = [];
    } catch (e) {
      if (requestRevision != _searchRevision) return;
      _errorMessage = 'Network error. Check backend connection.';
      _searchResults = [];
    } finally {
      if (requestRevision == _searchRevision) {
        _isLoading = false;
        notifyListeners();
      }
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
    _searchRevision++;
    _searchResults = [];
    _lastQuery = '';
    _errorMessage = null;
    _isLoading = false;
    notifyListeners();
  }
}