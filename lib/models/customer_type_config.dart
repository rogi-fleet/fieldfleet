/// A workspace-configurable customer type.
///
/// Unlike the old hardcoded enum, these are stored per-workspace in the
/// `customer_types` table and can be added/edited/removed by users.
class CustomerTypeConfig {
  final String id;
  final String workspaceId;
  final String name;
  final String color; // Hex color code (e.g., '#4CAF50')
  final String? description;
  final int sortOrder;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CustomerTypeConfig({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.color,
    this.description,
    this.sortOrder = 0,
    this.isDefault = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CustomerTypeConfig.fromJson(Map<String, dynamic> json) {
    return CustomerTypeConfig(
      id: json['id'] as String,
      workspaceId: json['workspace_id'] as String,
      name: json['name'] as String,
      color: json['color'] as String? ?? '#4CAF50',
      description: json['description'] as String?,
      sortOrder: json['sort_order'] as int? ?? 0,
      isDefault: json['is_default'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'workspace_id': workspaceId,
      'name': name,
      'color': color,
      'description': description,
      'sort_order': sortOrder,
      'is_default': isDefault,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  CustomerTypeConfig copyWith({
    String? id,
    String? workspaceId,
    String? name,
    String? color,
    String? description,
    int? sortOrder,
    bool? isDefault,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CustomerTypeConfig(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      name: name ?? this.name,
      color: color ?? this.color,
      description: description ?? this.description,
      sortOrder: sortOrder ?? this.sortOrder,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CustomerTypeConfig && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
