import 'package:cloud_firestore/cloud_firestore.dart';

class CustomerTag {
  final String id;
  final String workspaceId;
  final String name;
  final String color; // Hex color code (e.g., '#FF5733')
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CustomerTag({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.color,
    this.description,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CustomerTag.fromJson(Map<String, dynamic> json, String id) {
    return CustomerTag(
      id: id,
      workspaceId: json['workspaceId'] as String,
      name: json['name'] as String,
      color: json['color'] as String,
      description: json['description'] as String?,
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      updatedAt: (json['updatedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'workspaceId': workspaceId,
      'name': name,
      'color': color,
      'description': description,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  CustomerTag copyWith({
    String? id,
    String? workspaceId,
    String? name,
    String? color,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CustomerTag(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      name: name ?? this.name,
      color: color ?? this.color,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Validation
  bool validate() {
    if (name.trim().isEmpty) return false;
    if (color.isEmpty || !_isValidHexColor(color)) return false;
    return true;
  }

  bool _isValidHexColor(String color) {
    // Accept formats: #RGB, #RRGGBB, #AARRGGBB
    final hexPattern = RegExp(r'^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$');
    return hexPattern.hasMatch(color);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CustomerTag && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
