class WorkflowTemplate {
  final String id;
  final String workspaceId;
  final String name;
  final String slug;
  final String? description;
  final String workflowMarkdown;
  final Map<String, dynamic> workflowSchema;
  final bool isSystem;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const WorkflowTemplate({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.slug,
    this.description,
    required this.workflowMarkdown,
    this.workflowSchema = const {},
    this.isSystem = false,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WorkflowTemplate.fromSupabase(Map<String, dynamic> row) {
    DateTime parseDate(dynamic value) {
      if (value is String && value.isNotEmpty) {
        return DateTime.tryParse(value) ?? DateTime.now();
      }
      return DateTime.now();
    }

    final schema = row['workflow_schema'];
    return WorkflowTemplate(
      id: row['id'] as String? ?? '',
      workspaceId: row['workspace_id'] as String? ?? '',
      name: row['name'] as String? ?? '',
      slug: row['slug'] as String? ?? '',
      description: row['description'] as String?,
      workflowMarkdown: row['workflow_markdown'] as String? ?? '',
      workflowSchema: schema is Map<String, dynamic>
          ? schema
          : schema is Map
          ? Map<String, dynamic>.from(schema)
          : const {},
      isSystem: row['is_system'] as bool? ?? false,
      createdBy: row['created_by'] as String? ?? '',
      createdAt: parseDate(row['created_at']),
      updatedAt: parseDate(row['updated_at']),
    );
  }

  Map<String, dynamic> toSupabaseInsert() {
    return {
      'workspace_id': workspaceId,
      'name': name,
      'slug': slug,
      'description': description,
      'workflow_markdown': workflowMarkdown,
      'workflow_schema': workflowSchema,
      'is_system': isSystem,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  WorkflowTemplate copyWith({
    String? id,
    String? workspaceId,
    String? name,
    String? slug,
    String? description,
    String? workflowMarkdown,
    Map<String, dynamic>? workflowSchema,
    bool? isSystem,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WorkflowTemplate(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      description: description ?? this.description,
      workflowMarkdown: workflowMarkdown ?? this.workflowMarkdown,
      workflowSchema: workflowSchema ?? this.workflowSchema,
      isSystem: isSystem ?? this.isSystem,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
