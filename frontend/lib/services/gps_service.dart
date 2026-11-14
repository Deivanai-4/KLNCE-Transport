import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/gps_location.dart';
import 'api_service.dart';

class GpsService extends ChangeNotifier {
  GpsLocation? _selectedBusLocation;
  List<GpsLocation> _allActiveBuses = [];
  Timer? _pollingTimer;
  bool _isLoading = false;
  String? _errorMessage;

  GpsLocation? get selectedBusLocation => _selectedBusLocation;
  List<GpsLocation> get allActiveBuses => _allActiveBuses;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void startTrackingBus(String busCode) {
    stopTracking();
    fetchBusLocation(busCode);
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      fetchBusLocation(busCode);
    });
  }

  void stopTracking() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _selectedBusLocation = null;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> fetchBusLocation(String busCode) async {
    try {
      final res = await ApiService.get('/gps/live/$busCode');
      if (res['location'] != null) {
        _selectedBusLocation =
            GpsLocation.fromJson(res['location'] as Map<String, dynamic>);
        _errorMessage = null;
        notifyListeners();
      } else {
        _selectedBusLocation = null;
        _errorMessage = 'No recent GPS update is available for this bus.';
        notifyListeners();
      }
    } on ApiException catch (error) {
      _errorMessage = error.message;
      notifyListeners();
    } catch (_) {
      _errorMessage = 'Unable to retrieve this bus location.';
      notifyListeners();
    }
  }

  Future<void> fetchAllActiveBuses() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final res = await ApiService.get('/gps/active');
      if (res['active_buses'] != null) {
        final raw = res['active_buses'] as List<dynamic>;
        _allActiveBuses = raw
            .map((g) => GpsLocation.fromJson(g as Map<String, dynamic>))
            .toList();
      } else {
        _allActiveBuses = [];
      }
    } on ApiException catch (error) {
      _errorMessage = error.message;
      _allActiveBuses = [];
    } catch (_) {
      _errorMessage = 'Unable to retrieve active bus locations.';
      _allActiveBuses = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }
}

