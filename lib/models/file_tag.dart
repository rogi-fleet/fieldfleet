/// Workspace-scoped colored tag attached to [FileAttachment] rows via the
/// `file_attachment_tags` join table.
///
/// Mirrors the shape of [CustomerTag] but is Supabase-native (no Firestore
/// Timestamp dependency).
class FileTag {
  final String id;
  final String workspaceId;
  final String name;
  final String color; // hex e.g. '#64748B'
  final String? description;
  final String? createdBy;

  /// Role tokens allowed to see files exclusively carrying this tag. Empty
  /// list = unrestricted (any workspace member can see). Role tokens match
  /// either the legacy `workspace_member_role` enum string (e.g.
  /// 'project_manager'), a `workspace_role_templates.id`, or the admin
  /// sentinel `'*'`.
  final List<String> visibleToRoles;

  /// When set, the tag is soft-archived — hidden from pickers and the tag
  /// manager's active list, but still rendered on files that already carry it
  /// so history isn't lost.
  final DateTime? archivedAt;

  final DateTime createdAt;
  final DateTime updatedAt;

  const FileTag({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.color,
    this.description,
    this.createdBy,
    this.visibleToRoles = const [],
    this.archivedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isRestricted => visibleToRoles.isNotEmpty;
  bool get isArchived => archivedAt != null;

  factory FileTag.fromSupabase(Map<String, dynamic> json) {
    final roles = (json['visible_to_roles'] as List?)?.cast<String>() ??
        const <String>[];
    final archivedRaw = json['archived_at'] as String?;
    return FileTag(
      id: json['id'] as String,
      workspaceId: json['workspace_id'] as String,
      name: json['name'] as String,
      color: json['color'] as String? ?? '#64748B',
      description: json['description'] as String?,
      createdBy: json['created_by'] as String?,
      visibleToRoles: roles,
      archivedAt: archivedRaw != null ? DateTime.parse(archivedRaw) : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toSupabaseInsert() {
    return {
      'workspace_id': workspaceId,
      'name': name,
      'color': color,
      if (description != null) 'description': description,
      if (createdBy != null) 'created_by': createdBy,
      if (visibleToRoles.isNotEmpty) 'visible_to_roles': visibleToRoles,
    };
  }

  FileTag copyWith({
    String? id,
    String? workspaceId,
    String? name,
    String? color,
    String? Function()? description,
    String? Function()? createdBy,
    List<String>? visibleToRoles,
    DateTime? Function()? archivedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FileTag(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      name: name ?? this.name,
      color: color ?? this.color,
      description: description != null ? description() : this.description,
      createdBy: createdBy != null ? createdBy() : this.createdBy,
      visibleToRoles: visibleToRoles ?? this.visibleToRoles,
      archivedAt: archivedAt != null ? archivedAt() : this.archivedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool validate() {
    if (name.trim().isEmpty) return false;
    if (color.isEmpty || !_isValidHexColor(color)) return false;
    return true;
  }

  static bool _isValidHexColor(String value) {
    final hexPattern = RegExp(r'^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$');
    return hexPattern.hasMatch(value);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FileTag && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
