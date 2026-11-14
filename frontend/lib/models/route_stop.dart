class RouteStop {
  final int id;
  final int busRouteId;
  final int stopOrder;
  final String stopNameEn;
  final String? stopNameTa;
  final String? estimatedArrivalTime;
  final int? masterStopId;

  RouteStop({
    required this.id,
    required this.busRouteId,
    required this.stopOrder,
    required this.stopNameEn,
    this.stopNameTa,
    this.estimatedArrivalTime,
    this.masterStopId,
  });

  String get displayName => (stopNameTa != null && stopNameTa!.isNotEmpty)
      ? '$stopNameEn ($stopNameTa)'
      : stopNameEn;

  String? get arrivalTime => estimatedArrivalTime;

  String get stopNameTaOrEn =>
      (stopNameTa != null && stopNameTa!.isNotEmpty) ? stopNameTa! : stopNameEn;

  factory RouteStop.fromJson(Map<String, dynamic> json) {
    return RouteStop(
      id: json['id'] as int? ?? 0,
      busRouteId: json['bus_route_id'] as int? ?? 0,
      stopOrder: json['stop_order'] as int? ?? 0,
      stopNameEn: json['stop_name_en'] as String? ?? '',
      stopNameTa: json['stop_name_ta'] as String?,
      estimatedArrivalTime: json['estimated_arrival_time'] as String?,
      masterStopId: json['master_stop_id'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'bus_route_id': busRouteId,
      'stop_order': stopOrder,
      'stop_name_en': stopNameEn,
      'stop_name_ta': stopNameTa,
      'estimated_arrival_time': estimatedArrivalTime,
      'master_stop_id': masterStopId,
    };
  }
}

