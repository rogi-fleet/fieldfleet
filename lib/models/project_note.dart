/// A note associated with an entity (project, customer, or vendor).
class ProjectNote {
  final String id;
  final String workspaceId;
  final String projectId;
  final String entityType;
  final String entityId;
  final String content;
  final String? tag;
  final String authorId;
  final String authorName;
  final DateTime createdAt;
  final DateTime? updatedAt;

  ProjectNote({
    required this.id,
    required this.workspaceId,
    required this.projectId,
    required this.entityType,
    required this.entityId,
    required this.content,
    this.tag,
    required this.authorId,
    required this.authorName,
    required this.createdAt,
    this.updatedAt,
  });

  factory ProjectNote.fromRow(Map<String, dynamic> row) {
    return ProjectNote(
      id: row['id'],
      workspaceId: row['workspace_id'],
      projectId: row['project_id'] ?? '',
      entityType: row['entity_type'] ?? 'project',
      entityId: row['entity_id'] ?? row['project_id'] ?? '',
      content: row['content'] as String,
      tag: row['tag'] as String?,
      authorId: row['author_id'],
      authorName: row['author_name'] as String,
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'])
          : DateTime.now(),
      updatedAt: row['updated_at'] != null
          ? DateTime.parse(row['updated_at'])
          : null,
    );
  }

  Map<String, dynamic> toDbRow() {
    return {
      'workspace_id': workspaceId,
      'project_id': projectId.isNotEmpty ? projectId : null,
      'entity_type': entityType,
      'entity_id': entityId,
      'content': content,
      'tag': tag,
      'author_id': authorId,
      'author_name': authorName,
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  ProjectNote copyWith({
    String? id,
    String? workspaceId,
    String? projectId,
    String? entityType,
    String? entityId,
    String? content,
    String? tag,
    String? authorId,
    String? authorName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ProjectNote(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      projectId: projectId ?? this.projectId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      content: content ?? this.content,
      tag: tag ?? this.tag,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isEdited =>
      updatedAt != null && !updatedAt!.isAtSameMomentAs(createdAt);

  /// Available tags for notes
  static const List<String> availableTags = [
    'observation',
    'instruction',
    'update',
    'issue',
    'resolution',
  ];
}
