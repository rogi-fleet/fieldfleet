import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum FieldFormStatus {
  draft,
  submitted,
  approved,
  rejected;

  String get displayName {
    switch (this) {
      case FieldFormStatus.draft:
        return 'Draft';
      case FieldFormStatus.submitted:
        return 'Submitted';
      case FieldFormStatus.approved:
        return 'Approved';
      case FieldFormStatus.rejected:
        return 'Rejected';
    }
  }

  Color get color {
    switch (this) {
      case FieldFormStatus.draft:
        return Colors.grey;
      case FieldFormStatus.submitted:
        return Colors.blue;
      case FieldFormStatus.approved:
        return Colors.green;
      case FieldFormStatus.rejected:
        return Colors.red;
    }
  }

  bool get isTerminal =>
      this == FieldFormStatus.approved || this == FieldFormStatus.rejected;

  static FieldFormStatus fromString(String value) {
    return FieldFormStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => FieldFormStatus.draft,
    );
  }
}

/// Holds the data for a single signature slot (technician, supervisor, or customer).
class FormSignatureSlot {
  final String? signatureUrl;
  final String? signedByName;
  final String? signedByEmail;
  final DateTime? signedAt;
  final String? signatureIp;

  const FormSignatureSlot({
    this.signatureUrl,
    this.signedByName,
    this.signedByEmail,
    this.signedAt,
    this.signatureIp,
  });

  bool get isSigned => signatureUrl != null && signedAt != null;

  String get formattedSignedAt {
    if (signedAt == null) return '';
    return DateFormat('MM/dd/yyyy hh:mm a').format(signedAt!);
  }

  static FormSignatureSlot fromRow(Map<String, dynamic> row, String prefix) {
    final url = row['${prefix}_signature_url'] as String?;
    final signedAtRaw = row['${prefix}_signed_at'];
    return FormSignatureSlot(
      signatureUrl: url,
      signedByName: row['${prefix}_signed_by_name'] as String?,
      signedByEmail: row['${prefix}_signed_by_email'] as String?,
      signedAt: signedAtRaw != null
          ? DateTime.parse(signedAtRaw as String)
          : null,
      signatureIp: row['${prefix}_signature_ip'] as String?,
    );
  }

  Map<String, dynamic> toUpdateMap(String prefix) {
    return {
      '${prefix}_signature_url': signatureUrl,
      '${prefix}_signed_by_name': signedByName,
      '${prefix}_signed_by_email': signedByEmail,
      '${prefix}_signed_at': signedAt?.toIso8601String(),
      '${prefix}_signature_ip': signatureIp,
    };
  }
}

class FieldFormSubmission {
  final String id;
  final String workspaceId;
  final String templateId;
  final String templateName;
  final String? projectId;
  final String? taskId;
  final String? title;
  final FieldFormStatus status;
  final Map<String, dynamic> data;
  final String? filledById;
  final String? filledByName;
  final DateTime? filledAt;
  final DateTime? submittedAt;
  final String? notes;
  final List<String> attachedPhotoIds;

  /// User IDs to notify when this submission is submitted. Captured at fill
  /// time, dispatched once on the transition to `submitted` status.
  final List<String> notifiedUserIds;

  final FormSignatureSlot techSignature;
  final FormSignatureSlot supervisorSignature;
  final FormSignatureSlot customerSignature;

  final DateTime createdAt;
  final DateTime updatedAt;

  const FieldFormSubmission({
    required this.id,
    required this.workspaceId,
    required this.templateId,
    required this.templateName,
    this.projectId,
    this.taskId,
    this.title,
    required this.status,
    required this.data,
    this.filledById,
    this.filledByName,
    this.filledAt,
    this.submittedAt,
    this.notes,
    this.attachedPhotoIds = const [],
    this.notifiedUserIds = const [],
    required this.techSignature,
    required this.supervisorSignature,
    required this.customerSignature,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isFullySigned =>
      techSignature.isSigned &&
      supervisorSignature.isSigned &&
      customerSignature.isSigned;

  String get formattedSubmittedAt {
    if (submittedAt == null) return '';
    return DateFormat('MM/dd/yyyy hh:mm a').format(submittedAt!);
  }

  String get formattedCreatedAt {
    return DateFormat('MM/dd/yyyy').format(createdAt);
  }

  factory FieldFormSubmission.fromRow(Map<String, dynamic> row) {
    return FieldFormSubmission(
      id: row['id'] as String,
      workspaceId: row['workspace_id'] as String,
      templateId: row['template_id'] as String,
      templateName: row['template_name'] as String,
      projectId: row['project_id'] as String?,
      taskId: row['task_id'] as String?,
      title: row['title'] as String?,
      status: FieldFormStatus.fromString(row['status'] as String? ?? 'draft'),
      data: Map<String, dynamic>.from(row['data'] as Map? ?? {}),
      filledById: row['filled_by_id'] as String?,
      filledByName: row['filled_by_name'] as String?,
      filledAt: _parseDateTime(row['filled_at']),
      submittedAt: _parseDateTime(row['submitted_at']),
      notes: row['notes'] as String?,
      attachedPhotoIds:
          (row['attached_photo_ids'] as List?)?.cast<String>() ?? [],
      notifiedUserIds:
          (row['notified_user_ids'] as List?)?.cast<String>() ?? [],
      techSignature: FormSignatureSlot.fromRow(row, 'tech'),
      supervisorSignature: FormSignatureSlot.fromRow(row, 'supervisor'),
      customerSignature: FormSignatureSlot.fromRow(row, 'customer'),
      createdAt: _parseDateTime(row['created_at']) ?? DateTime.now(),
      updatedAt: _parseDateTime(row['updated_at']) ?? DateTime.now(),
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.parse(value);
    return null;
  }

  FieldFormSubmission copyWith({
    String? id,
    String? workspaceId,
    String? templateId,
    String? templateName,
    String? projectId,
    String? taskId,
    String? title,
    FieldFormStatus? status,
    Map<String, dynamic>? data,
    String? filledById,
    String? filledByName,
    DateTime? filledAt,
    DateTime? submittedAt,
    String? notes,
    List<String>? attachedPhotoIds,
    List<String>? notifiedUserIds,
    FormSignatureSlot? techSignature,
    FormSignatureSlot? supervisorSignature,
    FormSignatureSlot? customerSignature,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FieldFormSubmission(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      templateId: templateId ?? this.templateId,
      templateName: templateName ?? this.templateName,
      projectId: projectId ?? this.projectId,
      taskId: taskId ?? this.taskId,
      title: title ?? this.title,
      status: status ?? this.status,
      data: data ?? this.data,
      filledById: filledById ?? this.filledById,
      filledByName: filledByName ?? this.filledByName,
      filledAt: filledAt ?? this.filledAt,
      submittedAt: submittedAt ?? this.submittedAt,
      notes: notes ?? this.notes,
      attachedPhotoIds: attachedPhotoIds ?? this.attachedPhotoIds,
      notifiedUserIds: notifiedUserIds ?? this.notifiedUserIds,
      techSignature: techSignature ?? this.techSignature,
      supervisorSignature: supervisorSignature ?? this.supervisorSignature,
      customerSignature: customerSignature ?? this.customerSignature,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// A row from task_required_forms — links a task to a required form template,
/// and optionally to the submission that fulfils it.
class TaskRequiredForm {
  final String taskId;
  final String templateId;
  final String? submissionId;
  final bool blocksCompletion;
  final DateTime createdAt;

  const TaskRequiredForm({
    required this.taskId,
    required this.templateId,
    this.submissionId,
    this.blocksCompletion = false,
    required this.createdAt,
  });

  bool get isCompleted => submissionId != null;

  factory TaskRequiredForm.fromRow(Map<String, dynamic> row) {
    return TaskRequiredForm(
      taskId: row['task_id'] as String,
      templateId: row['template_id'] as String,
      submissionId: row['submission_id'] as String?,
      blocksCompletion: row['blocks_completion'] as bool? ?? false,
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'] as String)
          : DateTime.now(),
    );
  }
}
