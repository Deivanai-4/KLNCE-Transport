class DailyStop {
  final int stopOrder;
  final String stopName;
  final String arrivalTime;

  DailyStop({
    required this.stopOrder,
    required this.stopName,
    required this.arrivalTime,
  });

  factory DailyStop.fromJson(Map<String, dynamic> json) {
    return DailyStop(
      stopOrder: json['stop_order'] as int? ?? 1,
      stopName: json['stop_name'] as String? ?? '',
      arrivalTime: json['arrival_time'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'stop_order': stopOrder,
        'stop_name': stopName,
        'arrival_time': arrivalTime,
      };

  DailyStop copyWith({
    int? stopOrder,
    String? stopName,
    String? arrivalTime,
  }) {
    return DailyStop(
      stopOrder: stopOrder ?? this.stopOrder,
      stopName: stopName ?? this.stopName,
      arrivalTime: arrivalTime ?? this.arrivalTime,
    );
  }
}

class DailyBus {
  final String busNumber;
  final int? routeId;
  final String routeName;
  final String departureTime;
  final List<DailyStop> stops;

  DailyBus({
    required this.busNumber,
    this.routeId,
    required this.routeName,
    required this.departureTime,
    required this.stops,
  });

  factory DailyBus.fromJson(Map<String, dynamic> json) {
    final rawStops = json['stops'] as List<dynamic>? ?? [];
    return DailyBus(
      busNumber: json['bus_number'] as String? ?? '',
      routeId: json['route_id'] as int?,
      routeName: json['route_name'] as String? ?? '',
      departureTime: json['departure_time'] as String? ?? '',
      stops: rawStops
          .map((s) => DailyStop.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'bus_number': busNumber,
        if (routeId != null) 'route_id': routeId,
        'route_name': routeName,
        'departure_time': departureTime,
        'stops': stops.map((s) => s.toJson()).toList(),
      };

  DailyBus copyWith({
    String? busNumber,
    int? routeId,
    String? routeName,
    String? departureTime,
    List<DailyStop>? stops,
  }) {
    return DailyBus(
      busNumber: busNumber ?? this.busNumber,
      routeId: routeId ?? this.routeId,
      routeName: routeName ?? this.routeName,
      departureTime: departureTime ?? this.departureTime,
      stops: stops ?? this.stops,
    );
  }
}

class DailySchedule {
  final int id;
  final String date;
  final String session; // 'morning' | 'afternoon'
  final String status; // 'draft' | 'published'
  final bool isUpdated;
  final int version;
  final int createdBy;
  final List<DailyBus> buses;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? publishedAt;

  DailySchedule({
    required this.id,
    required this.date,
    required this.session,
    this.status = 'draft',
    this.isUpdated = false,
    this.version = 1,
    this.createdBy = 1,
    required this.buses,
    this.createdAt,
    this.updatedAt,
    this.publishedAt,
  });

  bool get isPublished => status == 'published';
  bool get isMorning => session.toLowerCase() == 'morning';
  bool get isAfternoon => session.toLowerCase() == 'afternoon';

  factory DailySchedule.fromJson(Map<String, dynamic> json) {
    final rawBuses = json['buses'] as List<dynamic>? ?? [];
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      try {
        return DateTime.parse(v as String);
      } catch (_) {
        return null;
      }
    }

    return DailySchedule(
      id: json['id'] as int? ?? 0,
      date: json['date'] as String? ?? '',
      session: json['session'] as String? ?? 'morning',
      status: json['status'] as String? ?? 'draft',
      isUpdated: json['is_updated'] as bool? ?? false,
      version: json['version'] as int? ?? 1,
      createdBy: json['created_by'] as int? ?? 1,
      buses: rawBuses
          .map((b) => DailyBus.fromJson(b as Map<String, dynamic>))
          .toList(),
      createdAt: parseDate(json['created_at']),
      updatedAt: parseDate(json['updated_at']),
      publishedAt: parseDate(json['published_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'session': session,
        'status': status,
        'is_updated': isUpdated,
        'version': version,
        'created_by': createdBy,
        'buses': buses.map((b) => b.toJson()).toList(),
      };
}
