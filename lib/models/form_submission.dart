import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class FormSubmission {
  final String id;
  final String formTemplateId;
  final String workspaceId;
  final Map<String, dynamic> data;
  final DateTime submittedAt;
  final String? submittedByEmail;
  final String? submittedByName;
  final String? ipAddress;

  FormSubmission({
    required this.id,
    required this.formTemplateId,
    required this.workspaceId,
    required this.data,
    required this.submittedAt,
    this.submittedByEmail,
    this.submittedByName,
    this.ipAddress,
  });

  factory FormSubmission.fromJson(Map<String, dynamic> json, String id) {
    return FormSubmission(
      id: id,
      formTemplateId: json['formTemplateId'] as String,
      workspaceId: json['workspaceId'] as String,
      data: Map<String, dynamic>.from(json['data'] as Map? ?? {}),
      submittedAt: _parseDateTime(json['submittedAt']),
      submittedByEmail: json['submittedByEmail'] as String?,
      submittedByName: json['submittedByName'] as String?,
      ipAddress: json['ipAddress'] as String?,
    );
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.parse(value);
    try {
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {
      return DateTime.now();
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'formTemplateId': formTemplateId,
      'workspaceId': workspaceId,
      'data': data,
      'submittedAt': Timestamp.fromDate(submittedAt),
      'submittedByEmail': submittedByEmail,
      'submittedByName': submittedByName,
      'ipAddress': ipAddress,
    };
  }

  String get formattedSubmittedAt {
    return DateFormat('MM/dd/yyyy hh:mm a').format(submittedAt);
  }

  String getFieldValue(String fieldId) {
    final value = data[fieldId];
    if (value == null) return '';
    if (value is Map) {
      final fileName = value['fileName'];
      final fileUrl = value['fileUrl'];
      if (fileName is String && fileName.isNotEmpty) {
        return fileUrl is String && fileUrl.isNotEmpty
            ? '$fileName ($fileUrl)'
            : fileName;
      }
      return value.toString();
    }
    if (value is List) return value.join(', ');
    return value.toString();
  }

  FormSubmission copyWith({
    String? id,
    String? formTemplateId,
    String? workspaceId,
    Map<String, dynamic>? data,
    DateTime? submittedAt,
    String? submittedByEmail,
    String? submittedByName,
    String? ipAddress,
  }) {
    return FormSubmission(
      id: id ?? this.id,
      formTemplateId: formTemplateId ?? this.formTemplateId,
      workspaceId: workspaceId ?? this.workspaceId,
      data: data ?? this.data,
      submittedAt: submittedAt ?? this.submittedAt,
      submittedByEmail: submittedByEmail ?? this.submittedByEmail,
      submittedByName: submittedByName ?? this.submittedByName,
      ipAddress: ipAddress ?? this.ipAddress,
    );
  }
}
