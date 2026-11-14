import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/schedule.dart';
import '../models/bus_route.dart';

class OfflineService {
  static const String _scheduleKey = 'klnce_offline_schedule';
  static const String _lastSyncKey = 'klnce_last_sync_time';

  static Future<void> cacheSchedule(Schedule schedule) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(schedule.toJson());
    await prefs.setString(_scheduleKeyFor(schedule.tripDirection), jsonStr);
    await prefs.setString(
      _lastSyncKeyFor(schedule.tripDirection),
      DateTime.now().toIso8601String(),
    );
  }

  static Future<Schedule?> getCachedSchedule({String? trip}) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = trip == null
        ? prefs.getString(_scheduleKey) ??
            prefs.getString(_scheduleKeyFor('incoming')) ??
            prefs.getString(_scheduleKeyFor('outgoing'))
        : prefs.getString(_scheduleKeyFor(trip)) ??
            prefs.getString(_scheduleKey);
    if (jsonStr == null || jsonStr.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      final schedule = Schedule.fromJson(decoded);
      return trip == null || schedule.tripDirection == trip ? schedule : null;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getLastSyncTime({String? trip}) async {
    final prefs = await SharedPreferences.getInstance();
    return trip == null
        ? prefs.getString(_lastSyncKey) ??
            prefs.getString(_lastSyncKeyFor('incoming')) ??
            prefs.getString(_lastSyncKeyFor('outgoing'))
        : prefs.getString(_lastSyncKeyFor(trip)) ??
            prefs.getString(_lastSyncKey);
  }

  static String _scheduleKeyFor(String trip) => '${_scheduleKey}_$trip';

  static String _lastSyncKeyFor(String trip) => '${_lastSyncKey}_$trip';

  static Future<List<BusRoute>> searchOfflineStops(String query) async {
    final schedule = await getCachedSchedule();
    if (schedule == null) return [];

    final q = query.toLowerCase().trim();
    List<BusRoute> matches = [];

    for (final bus in schedule.busRoutes) {
      bool found = false;
      for (final stop in bus.stops) {
        if (stop.stopNameEn.toLowerCase().contains(q) ||
            (stop.stopNameTa != null && stop.stopNameTa!.toLowerCase().contains(q))) {
          found = true;
          break;
        }
      }
      if (found) {
        matches.add(bus);
      }
    }
    return matches;
  }
}

