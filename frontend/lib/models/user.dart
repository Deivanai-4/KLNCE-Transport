class User {
  final int id;
  final String name;
  final String email;
  final String? phone;
  final String role; // 'student', 'staff', 'admin', 'driver'
  final String college;
  final bool isActive;
  final String? fcmToken;

  User({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    required this.role,
    required this.college,
    this.isActive = true,
    this.fcmToken,
  });

  bool get isAdmin => role == 'admin';
  bool get isDriver => role == 'driver';
  bool get isStudent => role == 'student';
  bool get isStaff => role == 'staff';

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String?,
      role: json['role'] as String? ?? 'student',
      college: json['college'] as String? ?? 'engineering',
      isActive: json['is_active'] as bool? ?? true,
      fcmToken: json['fcm_token'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'role': role,
      'college': college,
      'is_active': isActive,
      'fcm_token': fcmToken,
    };
  }
}

