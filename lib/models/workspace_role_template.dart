import 'package:cloud_firestore/cloud_firestore.dart';

import 'role_permissions.dart';
import 'user_role.dart';
import '../utils/module_permissions.dart';

class WorkspaceRoleTemplate {
  final String id;
  final String workspaceId;
  final String name;
  final UserRole? role;
  final Map<String, String> modulePermissions;
  final bool isSystem;
  final bool isAdmin;
  final String defaultInterfaceMode;
  final String? description;
  final String? color;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  WorkspaceRoleTemplate({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.role,
    required this.modulePermissions,
    required this.isSystem,
    this.isAdmin = false,
    this.defaultInterfaceMode = 'manager',
    this.description,
    this.color,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WorkspaceRoleTemplate.fromJson(Map<String, dynamic> json) {
    return WorkspaceRoleTemplate(
      id: json['id'] as String,
      workspaceId: json['workspace_id'] as String,
      name: (json['name'] as String? ?? '').trim(),
      role: _stringToRole(json['role'] as String?),
      modulePermissions: normalizeModulePermissions(
        json['module_permissions'] != null
            ? Map<String, String>.from(json['module_permissions'] as Map)
            : const {},
      ),
      isSystem: json['is_system'] as bool? ?? false,
      isAdmin: json['is_admin'] as bool? ?? false,
      defaultInterfaceMode:
          (json['default_interface_mode'] as String?) ?? 'manager',
      description: json['description'] as String?,
      color: json['color'] as String?,
      createdBy: json['created_by'] as String?,
      createdAt: _parseTimestamp(json['created_at']),
      updatedAt: _parseTimestamp(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'workspace_id': workspaceId,
      'name': name,
      'role': _roleToString(role),
      'module_permissions': modulePermissions,
      'is_system': isSystem,
      'is_admin': isAdmin,
      'default_interface_mode': defaultInterfaceMode,
      'description': description,
      'color': color,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  WorkspaceRoleTemplate copyWith({
    String? id,
    String? workspaceId,
    String? name,
    UserRole? role,
    bool clearRole = false,
    Map<String, String>? modulePermissions,
    bool? isSystem,
    bool? isAdmin,
    String? defaultInterfaceMode,
    String? description,
    bool clearDescription = false,
    String? color,
    bool clearColor = false,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WorkspaceRoleTemplate(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      name: name ?? this.name,
      role: clearRole ? null : (role ?? this.role),
      modulePermissions: modulePermissions ?? this.modulePermissions,
      isSystem: isSystem ?? this.isSystem,
      isAdmin: isAdmin ?? this.isAdmin,
      defaultInterfaceMode: defaultInterfaceMode ?? this.defaultInterfaceMode,
      description: clearDescription ? null : (description ?? this.description),
      color: clearColor ? null : (color ?? this.color),
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Returns the [role] if set, otherwise derives a legacy role
  /// from the template's permission shape via [RolePermissions].
  UserRole get legacyRole {
    if (role != null) return role!;
    return RolePermissions(
      roleName: name,
      isAdmin: isAdmin,
      modulePermissions: modulePermissions,
    ).legacyRole;
  }

  static DateTime _parseTimestamp(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.parse(value);
    return DateTime.now();
  }

  static String? _roleToString(UserRole? role) {
    if (role == null) return null;
    switch (role) {
      case UserRole.masterAdmin:
        return 'master_admin';
      case UserRole.admin:
        return 'admin';
      case UserRole.projectManager:
        return 'project_manager';
      case UserRole.fieldTechnician:
        return 'field_technician';
      case UserRole.client:
        return 'client';
      case UserRole.vendor:
        return 'vendor';
    }
  }

  static UserRole? _stringToRole(String? value) {
    switch (value) {
      case 'master_admin':
        return UserRole.masterAdmin;
      case 'admin':
        return UserRole.admin;
      case 'project_manager':
        return UserRole.projectManager;
      case 'field_technician':
        return UserRole.fieldTechnician;
      case 'client':
        return UserRole.client;
      case 'vendor':
        return UserRole.vendor;
      default:
        return null;
    }
  }
}
