class GpsLocation {
  final String busCode;
  final double latitude;
  final double longitude;
  final double? speedKmh;
  final bool isActiveTrip;
  final String recordedAt;

  GpsLocation({
    required this.busCode,
    required this.latitude,
    required this.longitude,
    this.speedKmh,
    this.isActiveTrip = true,
    required this.recordedAt,
  });

  factory GpsLocation.fromJson(Map<String, dynamic> json) {
    return GpsLocation(
      busCode: json['bus_code'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      speedKmh: (json['speed_kmh'] as num?)?.toDouble(),
      isActiveTrip: json['is_active_trip'] as bool? ?? true,
      recordedAt: json['recorded_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bus_code': busCode,
      'latitude': latitude,
      'longitude': longitude,
      'speed_kmh': speedKmh,
      'is_active_trip': isActiveTrip,
      'recorded_at': recordedAt,
    };
  }
}

