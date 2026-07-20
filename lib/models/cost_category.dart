import 'package:cloud_firestore/cloud_firestore.dart';

class CostCategory {
  final String id;
  final String workspaceId;
  final String name;
  final String color; // Hex color for UI
  final bool isDefault; // True for system categories
  final DateTime createdAt;
  final DateTime updatedAt;

  CostCategory({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.color,
    required this.isDefault,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CostCategory.fromJson(Map<String, dynamic> json, String id) {
    return CostCategory(
      id: id,
      workspaceId: json['workspaceId'] as String,
      name: json['name'] as String,
      color: json['color'] as String,
      isDefault: json['isDefault'] as bool? ?? false,
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      updatedAt: (json['updatedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'workspaceId': workspaceId,
      'name': name,
      'color': color,
      'isDefault': isDefault,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  CostCategory copyWith({
    String? id,
    String? workspaceId,
    String? name,
    String? color,
    bool? isDefault,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CostCategory(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      name: name ?? this.name,
      color: color ?? this.color,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Default categories for construction projects
  static List<Map<String, String>> get defaultCategories => [
        {'name': 'General', 'color': '#9E9E9E'},
        {'name': 'Site Work', 'color': '#795548'},
        {'name': 'Framing', 'color': '#FF9800'},
        {'name': 'Electrical', 'color': '#FFC107'},
        {'name': 'Plumbing', 'color': '#2196F3'},
        {'name': 'HVAC', 'color': '#00BCD4'},
        {'name': 'Drywall', 'color': '#CDDC39'},
        {'name': 'Painting', 'color': '#E91E63'},
        {'name': 'Flooring', 'color': '#8BC34A'},
        {'name': 'Fixtures', 'color': '#9C27B0'},
        {'name': 'Cleanup', 'color': '#607D8B'},
      ];
}
