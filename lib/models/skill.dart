import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme/theme.dart';

/// A skill that can be assigned to team members and required by tasks.
/// Skills are defined at the workspace level.
class Skill {
  final String id;
  final String workspaceId;
  final String name;
  final String? description;
  final Color color;
  final DateTime createdAt;
  final DateTime updatedAt;

  Skill({
    required this.id,
    required this.workspaceId,
    required this.name,
    this.description,
    required this.color,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Skill.fromJson(Map<String, dynamic> json, String id) {
    return Skill(
      id: id,
      workspaceId: json['workspaceId'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      color: Color(json['color'] as int? ?? AppColors.info.toARGB32()),
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      updatedAt: (json['updatedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'workspaceId': workspaceId,
      'name': name,
      'description': description,
      'color': color.toARGB32(),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  Skill copyWith({
    String? id,
    String? workspaceId,
    String? name,
    String? description,
    Color? color,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Skill(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      name: name ?? this.name,
      description: description ?? this.description,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static Color fallbackColorForName(String? name) {
    switch ((name ?? '').trim().toLowerCase()) {
      case 'electrical':
        return AppColors.warning;
      case 'plumbing':
        return AppColors.info;
      case 'hvac':
        return AppColors.financialAccent;
      case 'carpentry':
      case 'concrete':
        return AppColors.textSecondary;
      case 'drywall':
        return AppColors.textTertiary;
      case 'painting':
        return AppColors.messageAccent;
      case 'roofing':
        return AppColors.secondary;
      default:
        return AppColors.info;
    }
  }

  /// Default skills to seed when a workspace is created
  static List<Map<String, dynamic>> get defaultSkills => [
    {'name': 'Electrical', 'color': AppColors.warning.toARGB32()},
    {'name': 'Plumbing', 'color': AppColors.info.toARGB32()},
    {'name': 'HVAC', 'color': AppColors.financialAccent.toARGB32()},
    {'name': 'Carpentry', 'color': AppColors.textSecondary.toARGB32()},
    {'name': 'Drywall', 'color': AppColors.textTertiary.toARGB32()},
    {'name': 'Painting', 'color': AppColors.messageAccent.toARGB32()},
    {'name': 'Roofing', 'color': AppColors.secondary.toARGB32()},
    {'name': 'Concrete', 'color': AppColors.textSecondary.toARGB32()},
  ];
}
