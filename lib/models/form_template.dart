import 'package:cloud_firestore/cloud_firestore.dart';
import 'form_field_definition.dart';

class FormTemplate {
  final String id;
  final String workspaceId;
  final String? projectId;
  final String name;
  final String? description;
  final List<FormFieldDefinition> fields;
  final bool isPublic;
  final String? publicSlug;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  FormTemplate({
    required this.id,
    required this.workspaceId,
    this.projectId,
    required this.name,
    this.description,
    required this.fields,
    this.isPublic = false,
    this.publicSlug,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FormTemplate.fromJson(Map<String, dynamic> json, String id) {
    final fieldsList = (json['fields'] as List?)
            ?.map((item) =>
                FormFieldDefinition.fromJson(item as Map<String, dynamic>))
            .toList() ??
        [];

    return FormTemplate(
      id: id,
      workspaceId: json['workspaceId'] as String,
      projectId: json['projectId'] as String?,
      name: json['name'] as String,
      description: json['description'] as String?,
      fields: fieldsList,
      isPublic: json['isPublic'] as bool? ?? false,
      publicSlug: json['publicSlug'] as String?,
      createdBy: json['createdBy'] as String,
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
    );
  }

  /// Parses a datetime value that may be a Firestore [Timestamp], a [DateTime],
  /// an ISO-8601 [String], or a duck-typed object with a [toDate()] method.
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
      'workspaceId': workspaceId,
      'projectId': projectId,
      'name': name,
      'description': description,
      'fields': fields.map((f) => f.toJson()).toList(),
      'isPublic': isPublic,
      'publicSlug': publicSlug,
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  int get fieldCount => fields.length;
  int get requiredFieldCount => fields.where((f) => f.isRequired).length;

  String get publicUrl {
    if (publicSlug == null) return '';
    return '/f/$publicSlug';
  }

  FormTemplate copyWith({
    String? id,
    String? workspaceId,
    String? projectId,
    String? name,
    String? description,
    List<FormFieldDefinition>? fields,
    bool? isPublic,
    String? publicSlug,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FormTemplate(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      projectId: projectId ?? this.projectId,
      name: name ?? this.name,
      description: description ?? this.description,
      fields: fields ?? this.fields,
      isPublic: isPublic ?? this.isPublic,
      publicSlug: publicSlug ?? this.publicSlug,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
