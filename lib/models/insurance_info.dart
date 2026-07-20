import 'package:cloud_firestore/cloud_firestore.dart';

class InsuranceInfo {
  final String? provider;
  final String? policyNumber;
  final double? liabilityCoverage;
  final DateTime? expirationDate;
  final String? certificateUrl;
  final bool isValid;

  InsuranceInfo({
    this.provider,
    this.policyNumber,
    this.liabilityCoverage,
    this.expirationDate,
    this.certificateUrl,
    this.isValid = true,
  });

  factory InsuranceInfo.fromJson(Map<String, dynamic> json) {
    return InsuranceInfo(
      provider: json['provider'] as String?,
      policyNumber: json['policyNumber'] as String?,
      liabilityCoverage: json['liabilityCoverage'] != null
          ? (json['liabilityCoverage'] as num).toDouble()
          : null,
      expirationDate: json['expirationDate'] != null
          ? (json['expirationDate'] as Timestamp).toDate()
          : null,
      certificateUrl: json['certificateUrl'] as String?,
      isValid: json['isValid'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'provider': provider,
      'policyNumber': policyNumber,
      'liabilityCoverage': liabilityCoverage,
      'expirationDate':
          expirationDate != null ? Timestamp.fromDate(expirationDate!) : null,
      'certificateUrl': certificateUrl,
      'isValid': isValid,
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
    return daysUntilExpiration >= 0 && daysUntilExpiration <= 30;
  }

  InsuranceInfo copyWith({
    String? provider,
    String? policyNumber,
    double? liabilityCoverage,
    DateTime? expirationDate,
    String? certificateUrl,
    bool? isValid,
  }) {
    return InsuranceInfo(
      provider: provider ?? this.provider,
      policyNumber: policyNumber ?? this.policyNumber,
      liabilityCoverage: liabilityCoverage ?? this.liabilityCoverage,
      expirationDate: expirationDate ?? this.expirationDate,
      certificateUrl: certificateUrl ?? this.certificateUrl,
      isValid: isValid ?? this.isValid,
    );
  }
}
