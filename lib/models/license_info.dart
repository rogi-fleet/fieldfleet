import 'package:cloud_firestore/cloud_firestore.dart';

class LicenseInfo {
  final String licenseType;
  final String licenseNumber;
  final String? issuingState;
  final DateTime? expirationDate;
  final bool isActive;

  LicenseInfo({
    required this.licenseType,
    required this.licenseNumber,
    this.issuingState,
    this.expirationDate,
    this.isActive = true,
  });

  factory LicenseInfo.fromJson(Map<String, dynamic> json) {
    return LicenseInfo(
      licenseType: json['licenseType'] as String,
      licenseNumber: json['licenseNumber'] as String,
      issuingState: json['issuingState'] as String?,
      expirationDate: json['expirationDate'] != null
          ? (json['expirationDate'] as Timestamp).toDate()
          : null,
      isActive: json['isActive'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'licenseType': licenseType,
      'licenseNumber': licenseNumber,
      'issuingState': issuingState,
      'expirationDate':
          expirationDate != null ? Timestamp.fromDate(expirationDate!) : null,
      'isActive': isActive,
    };
  }

  bool get isExpired {
    if (expirationDate == null) return false;
    return DateTime.now().isAfter(expirationDate!);
  }

  bool get isExpiringSoon {
    if (expirationDate == null) return false;
    final now = DateTime.now();
    final daysUntilExpiration = expirationDate!.difference(now).inDays;
    return daysUntilExpiration >= 0 && daysUntilExpiration <= 60;
  }

  LicenseInfo copyWith({
    String? licenseType,
    String? licenseNumber,
    String? issuingState,
    DateTime? expirationDate,
    bool? isActive,
  }) {
    return LicenseInfo(
      licenseType: licenseType ?? this.licenseType,
      licenseNumber: licenseNumber ?? this.licenseNumber,
      issuingState: issuingState ?? this.issuingState,
      expirationDate: expirationDate ?? this.expirationDate,
      isActive: isActive ?? this.isActive,
    );
  }
}
