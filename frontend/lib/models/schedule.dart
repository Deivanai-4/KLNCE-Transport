import 'bus_route.dart';

class Schedule {
  final int id;
  final String title;
  final String fileUrl;
  final String fileType;
  final String tripDirection; // 'incoming' or 'outgoing'
  final String college;
  final String effectiveDate;
  final String status; // 'draft', 'verified', 'published', 'archived'
  final DateTime? createdAt;
  final String? publishedAt;
  final int routesCount;
  final List<BusRoute> busRoutes;

  Schedule({
    required this.id,
    required this.title,
    required this.fileUrl,
    required this.fileType,
    required this.tripDirection,
    required this.college,
    required this.effectiveDate,
    required this.status,
    this.createdAt,
    this.publishedAt,
    this.routesCount = 0,
    this.busRoutes = const [],
  });

  bool get isPublished => status == 'published';
  bool get isDraft => status == 'draft' || status == 'verified';

  bool isActivityVisibleAt(DateTime now) {
    final cutoff = now.toUtc().subtract(const Duration(days: 7));
    final createdAt = this.createdAt;
    return createdAt == null || !createdAt.isBefore(cutoff);
  }

  factory Schedule.fromJson(Map<String, dynamic> json) {
    var rawRoutes = json['bus_routes'] as List<dynamic>? ?? [];
    List<BusRoute> routes = rawRoutes
        .map((r) => BusRoute.fromJson(r as Map<String, dynamic>))
        .toList();

    return Schedule(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? 'KLNCE Bus Schedule',
      fileUrl: json['file_url'] as String? ?? '',
      fileType: json['file_type'] as String? ?? 'image',
      tripDirection: json['trip_direction'] as String? ?? 'incoming',
      college: json['college'] as String? ?? 'both',
      effectiveDate: json['effective_date'] as String? ?? '',
      status: json['status'] as String? ?? 'draft',
      createdAt: _parseUtcDateTime(json['created_at']),
      publishedAt: json['published_at'] as String?,
      routesCount: json['routes_count'] as int? ?? routes.length,
      busRoutes: routes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'file_url': fileUrl,
      'file_type': fileType,
      'trip_direction': tripDirection,
      'college': college,
      'effective_date': effectiveDate,
      'status': status,
      'created_at': createdAt?.toIso8601String(),
      'published_at': publishedAt,
      'routes_count': routesCount,
      'bus_routes': busRoutes.map((r) => r.toJson()).toList(),
    };
  }
}

DateTime? _parseUtcDateTime(dynamic value) {
  if (value is! String || value.trim().isEmpty) return null;
  final timestamp = value.trim();
  final hasTimezone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(timestamp);
  return DateTime.tryParse(hasTimezone ? timestamp : '${timestamp}Z')?.toUtc();
}
