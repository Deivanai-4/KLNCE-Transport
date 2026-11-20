class Student {
  final int id;
  final String registerNumber;
  final String name;
  final String department;
  final String year;
  final String section;
  final String studentMobile;
  final String parentMobile;
  final String routeName;
  final String busNumber;
  final String boardingStop;
  final bool isTransportActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Student({
    required this.id,
    required this.registerNumber,
    required this.name,
    required this.department,
    required this.year,
    required this.section,
    required this.studentMobile,
    required this.parentMobile,
    required this.routeName,
    required this.busNumber,
    required this.boardingStop,
    required this.isTransportActive,
    this.createdAt,
    this.updatedAt,
  });

  factory Student.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      try {
        return DateTime.parse(v.toString());
      } catch (_) {
        return null;
      }
    }

    return Student(
      id: json['id'] is int ? json['id'] as int : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      registerNumber: json['register_number']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      department: json['department']?.toString() ?? '',
      year: json['year']?.toString() ?? '',
      section: json['section']?.toString() ?? '',
      studentMobile: json['student_mobile']?.toString() ?? '',
      parentMobile: json['parent_mobile']?.toString() ?? '',
      routeName: json['route_name']?.toString() ?? '',
      busNumber: json['bus_number']?.toString() ?? '',
      boardingStop: json['boarding_stop']?.toString() ?? '',
      isTransportActive: json['is_transport_active'] as bool? ?? true,
      createdAt: parseDate(json['created_at']),
      updatedAt: parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'register_number': registerNumber,
      'name': name,
      'department': department,
      'year': year,
      'section': section,
      'student_mobile': studentMobile,
      'parent_mobile': parentMobile,
      'route_name': routeName,
      'bus_number': busNumber,
      'boarding_stop': boardingStop,
      'is_transport_active': isTransportActive,
    };
  }
}

class StudentPreviewRecord {
  final int rowNumber;
  final String registerNumber;
  final String name;
  final String department;
  final String year;
  final String section;
  final String studentMobile;
  final String parentMobile;
  final String routeName;
  final String busNumber;
  final String boardingStop;
  final String status; // 'valid', 'invalid', 'exists', 'sample'
  final bool existsInDb;
  final List<String> errors;

  StudentPreviewRecord({
    required this.rowNumber,
    required this.registerNumber,
    required this.name,
    required this.department,
    required this.year,
    required this.section,
    required this.studentMobile,
    required this.parentMobile,
    required this.routeName,
    required this.busNumber,
    required this.boardingStop,
    required this.status,
    required this.existsInDb,
    required this.errors,
  });

  factory StudentPreviewRecord.fromJson(Map<String, dynamic> json) {
    return StudentPreviewRecord(
      rowNumber: json['row_number'] as int? ?? 0,
      registerNumber: json['register_number']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      department: json['department']?.toString() ?? '',
      year: json['year']?.toString() ?? '',
      section: json['section']?.toString() ?? '',
      studentMobile: json['student_mobile']?.toString() ?? '',
      parentMobile: json['parent_mobile']?.toString() ?? '',
      routeName: json['route_name']?.toString() ?? '',
      busNumber: json['bus_number']?.toString() ?? '',
      boardingStop: json['boarding_stop']?.toString() ?? '',
      status: json['status']?.toString() ?? 'valid',
      existsInDb: json['exists_in_db'] as bool? ?? false,
      errors: (json['errors'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toImportJson() {
    return {
      'row_number': rowNumber,
      'register_number': registerNumber,
      'name': name,
      'department': department,
      'year': year,
      'section': section,
      'student_mobile': studentMobile,
      'parent_mobile': parentMobile,
      'route_name': routeName,
      'bus_number': busNumber,
      'boarding_stop': boardingStop,
    };
  }
}

class ExcelPreviewSummary {
  final int totalRows;
  final int validCount;
  final int invalidCount;
  final int sampleCount;
  final int existingInDbCount;
  final int duplicateInFileCount;
  final int missingFieldsCount;
  final int invalidMobileCount;
  final List<StudentPreviewRecord> records;

  ExcelPreviewSummary({
    required this.totalRows,
    required this.validCount,
    required this.invalidCount,
    required this.sampleCount,
    required this.existingInDbCount,
    required this.duplicateInFileCount,
    required this.missingFieldsCount,
    required this.invalidMobileCount,
    required this.records,
  });

  factory ExcelPreviewSummary.fromJson(Map<String, dynamic> json) {
    final rawList = json['records'] as List<dynamic>? ?? [];
    return ExcelPreviewSummary(
      totalRows: json['total_rows'] as int? ?? 0,
      validCount: json['valid_count'] as int? ?? 0,
      invalidCount: json['invalid_count'] as int? ?? 0,
      sampleCount: json['sample_count'] as int? ?? 0,
      existingInDbCount: json['existing_in_db_count'] as int? ?? 0,
      duplicateInFileCount: json['duplicate_in_file_count'] as int? ?? 0,
      missingFieldsCount: json['missing_fields_count'] as int? ?? 0,
      invalidMobileCount: json['invalid_mobile_count'] as int? ?? 0,
      records: rawList
          .map((r) => StudentPreviewRecord.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }
}
