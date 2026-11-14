import 'route_stop.dart';

class BusRoute {
  final int id;
  final int scheduleId;
  final String busCode;
  final String? routeDisplayName;
  final String departureTime;
  final String college;
  final int displayOrder;
  final List<RouteStop> stops;

  BusRoute({
    required this.id,
    required this.scheduleId,
    required this.busCode,
    this.routeDisplayName,
    required this.departureTime,
    this.college = 'engineering',
    this.displayOrder = 0,
    this.stops = const [],
  });

  factory BusRoute.fromJson(Map<String, dynamic> json) {
    var rawStops = json['stops'] as List<dynamic>? ?? [];
    List<RouteStop> parsedStops = rawStops.map((s) {
      if (s is String) {
        return RouteStop(
          id: 0,
          busRouteId: json['id'] as int? ?? 0,
          stopOrder: 1,
          stopNameEn: s,
          stopNameTa: s,
        );
      }
      return RouteStop.fromJson(s as Map<String, dynamic>);
    }).toList();

    return BusRoute(
      id: json['id'] as int? ?? 0,
      scheduleId: json['schedule_id'] as int? ?? 0,
      busCode: json['bus_code'] as String? ?? '',
      routeDisplayName: json['route_display_name'] as String?,
      departureTime: json['departure_time'] as String? ?? '08:00',
      college: json['college'] as String? ?? 'engineering',
      displayOrder: json['display_order'] as int? ?? 0,
      stops: parsedStops,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'schedule_id': scheduleId,
      'bus_code': busCode,
      'route_display_name': routeDisplayName,
      'departure_time': departureTime,
      'college': college,
      'display_order': displayOrder,
      'stops': stops.map((s) => s.toJson()).toList(),
    };
  }
}

