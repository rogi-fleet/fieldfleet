import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_role.dart';
import '../utils/module_permissions.dart';

class WorkspaceMember {
  final String id;
  final String workspaceId;
  final String userId;
  final UserRole role;
  final String? roleTemplateId;
  final String? roleTemplateName;
  final bool? roleTemplateIsAdmin;
  final List<String> skillIds; // Skills this member has
  final double? hourlyRate; // Workspace-specific hourly rate
  final double? weeklyWage; // Workspace-specific weekly wage
  final Map<String, String>
  modulePermissions; // { "projects": "write", "budget": "read" }
  final String interfaceMode; // 'manager' | 'field'
  final DateTime joinedAt;
  final String? invitedBy; // null if workspace creator
  final DateTime createdAt;
  final DateTime updatedAt;

  WorkspaceMember({
    required this.id,
    required this.workspaceId,
    required this.userId,
    required this.role,
    this.roleTemplateId,
    this.roleTemplateName,
    this.roleTemplateIsAdmin,
    this.skillIds = const [],
    this.hourlyRate,
    this.weeklyWage,
    this.modulePermissions = const {},
    this.interfaceMode = 'manager',
    required this.joinedAt,
    this.invitedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WorkspaceMember.fromJson(Map<String, dynamic> json, String id) {
    // Support nested role template data from joins
    final templateData =
        json['workspace_role_templates'] as Map<String, dynamic>?;

    return WorkspaceMember(
      id: id,
      workspaceId: json['workspaceId'] as String,
      userId: json['userId'] as String,
      role: UserRole.fromString(json['role'] as String),
      roleTemplateId:
          (json['roleTemplateId'] ?? json['role_template_id']) as String?,
      roleTemplateName:
          (json['roleTemplateName'] ??
                  json['role_template_name'] ??
                  templateData?['name'])
              as String?,
      roleTemplateIsAdmin:
          (json['roleTemplateIsAdmin'] ??
                  json['role_template_is_admin'] ??
                  templateData?['is_admin'])
              as bool?,
      skillIds: json['skillIds'] != null
          ? List<String>.from(json['skillIds'] as List)
          : [],
      hourlyRate: (json['hourlyRate'] ?? json['hourly_rate'] as num?)
          ?.toDouble(),
      weeklyWage: (json['weeklyWage'] ?? json['weekly_wage'] as num?)
          ?.toDouble(),
      modulePermissions: normalizeModulePermissions(
        json['modulePermissions'] != null
            ? Map<String, String>.from(json['modulePermissions'] as Map)
            : json['module_permissions'] != null
            ? Map<String, String>.from(json['module_permissions'] as Map)
            : const {},
      ),
      interfaceMode:
          (json['interfaceMode'] ?? json['interface_mode'] as String?) ??
          'manager',
      joinedAt: _parseTimestamp(json['joinedAt'] ?? json['joined_at']),
      invitedBy: (json['invitedBy'] ?? json['invited_by']) as String?,
      createdAt: _parseTimestamp(json['createdAt'] ?? json['created_at']),
      updatedAt: _parseTimestamp(json['updatedAt'] ?? json['updated_at']),
    );
  }

  static DateTime _parseTimestamp(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.parse(value);
    return DateTime.now();
  }

  Map<String, dynamic> toJson() {
    return {
      'workspaceId': workspaceId,
      'userId': userId,
      'role': role.toString(),
      'skillIds': skillIds,
      'hourlyRate': hourlyRate,
      'weeklyWage': weeklyWage,
      'modulePermissions': modulePermissions,
      'interfaceMode': interfaceMode,
      'joinedAt': Timestamp.fromDate(joinedAt),
      'invitedBy': invitedBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  WorkspaceMember copyWith({
    String? id,
    String? workspaceId,
    String? userId,
    UserRole? role,
    String? roleTemplateId,
    bool clearRoleTemplateId = false,
    String? roleTemplateName,
    bool? roleTemplateIsAdmin,
    List<String>? skillIds,
    double? hourlyRate,
    double? weeklyWage,
    Map<String, String>? modulePermissions,
    String? interfaceMode,
    DateTime? joinedAt,
    String? invitedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WorkspaceMember(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      userId: userId ?? this.userId,
      role: role ?? this.role,
      roleTemplateId: clearRoleTemplateId
          ? null
          : (roleTemplateId ?? this.roleTemplateId),
      roleTemplateName: roleTemplateName ?? this.roleTemplateName,
      roleTemplateIsAdmin: roleTemplateIsAdmin ?? this.roleTemplateIsAdmin,
      skillIds: skillIds ?? this.skillIds,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      weeklyWage: weeklyWage ?? this.weeklyWage,
      modulePermissions: modulePermissions ?? this.modulePermissions,
      interfaceMode: interfaceMode ?? this.interfaceMode,
      joinedAt: joinedAt ?? this.joinedAt,
      invitedBy: invitedBy ?? this.invitedBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  String get displayRoleName {
    final templateName = roleTemplateName?.trim();
    if (templateName != null && templateName.isNotEmpty) {
      return templateName;
    }
    return role.displayName;
  }

  bool get isAdminRole =>
      roleTemplateIsAdmin == true ||
      role == UserRole.admin ||
      role == UserRole.masterAdmin;

  Map<String, String> get effectiveModulePermissions {
    if (modulePermissions.isNotEmpty) {
      return normalizeModulePermissions(modulePermissions);
    }
    return defaultPermissionsForRole(role);
  }

  /// Check if this member has access to a specific module at a certain level
  /// Level can be 'none', 'read', 'write'
  bool hasModuleAccess(String module, String requiredLevel) {
    // Admins have full access to everything
    if (isAdminRole) return true;

    final actualLevel =
        effectiveModulePermissions[module.toLowerCase()] ?? 'none';

    if (requiredLevel == 'write') {
      return actualLevel == 'write';
    } else if (requiredLevel == 'read') {
      return actualLevel == 'read' || actualLevel == 'write';
    }

    return true; // none always allowed
  }

  // Helper to generate composite ID
  static String generateId(String workspaceId, String userId) {
    return '${workspaceId}_$userId';
  }
}
