import 'user_role.dart';

enum InvitationStatus {
  pending,
  accepted,
  expired,
  revoked;

  static InvitationStatus fromString(String status) {
    return InvitationStatus.values.firstWhere(
      (e) => e.name == status,
      orElse: () => InvitationStatus.pending,
    );
  }
}

class WorkspaceInvitation {
  final String id;
  final String workspaceId;
  final String email; // Always lowercase
  final UserRole role;
  final String? roleTemplateId;
  final String? roleName;
  final String interfaceMode; // 'manager' | 'field'
  final String invitedBy; // User ID who sent invitation
  final String token; // Secure random token
  final InvitationStatus status;
  final DateTime expiresAt;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final String? acceptedBy; // User ID who accepted
  final String? workspaceName; // Resolved for token-based invitation display
  final String? inviterName; // Optional display name of inviter

  WorkspaceInvitation({
    required this.id,
    required this.workspaceId,
    required this.email,
    required this.role,
    this.roleTemplateId,
    this.roleName,
    this.interfaceMode = 'manager',
    required this.invitedBy,
    required this.token,
    required this.status,
    required this.expiresAt,
    required this.createdAt,
    this.acceptedAt,
    this.acceptedBy,
    this.workspaceName,
    this.inviterName,
  });

  // Validation
  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isPending => status == InvitationStatus.pending && !isExpired;
  bool get canAccept => isPending;
  String get displayRoleName {
    final trimmed = roleName?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    return role.displayName;
  }

  factory WorkspaceInvitation.fromJson(Map<String, dynamic> json, String id) {
    return WorkspaceInvitation(
      id: id,
      workspaceId: (json['workspaceId'] ?? json['workspace_id']) as String,
      email: (json['email'] as String).toLowerCase(),
      role: UserRole.fromString(json['role'] as String),
      roleTemplateId:
          (json['roleTemplateId'] ?? json['role_template_id']) as String?,
      interfaceMode:
          (json['interfaceMode'] ?? json['interface_mode'] as String?) ??
          'manager',
      invitedBy: (json['invitedBy'] ?? json['invited_by']) as String,
      token: json['token'] as String,
      status: InvitationStatus.fromString(json['status'] as String),
      expiresAt: _parseTimestamp(json['expiresAt'] ?? json['expires_at']),
      createdAt: _parseTimestamp(json['createdAt'] ?? json['created_at']),
      acceptedAt: (json['acceptedAt'] ?? json['accepted_at']) != null
          ? _parseTimestamp(json['acceptedAt'] ?? json['accepted_at'])
          : null,
      acceptedBy: (json['acceptedBy'] ?? json['accepted_by']) as String?,
      workspaceName:
          (json['workspaceName'] ?? json['workspace_name']) as String?,
      inviterName: (json['inviterName'] ?? json['inviter_name']) as String?,
    );
  }

  /// Parse timestamp from various formats (Firebase Timestamp, DateTime, or object with toDate())
  static DateTime _parseTimestamp(dynamic value) {
    if (value == null) {
      return DateTime.now();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.parse(value);
    }
    // Handle Firebase Timestamp or any object with toDate() method
    try {
      return (value as dynamic).toDate() as DateTime;
    } catch (e) {
      return DateTime.now();
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'workspaceId': workspaceId,
      'email': email.toLowerCase(),
      'role': role.toString(),
      'roleTemplateId': roleTemplateId,
      'roleName': roleName,
      'interfaceMode': interfaceMode,
      'invitedBy': invitedBy,
      'token': token,
      'status': status.name,
      'expiresAt': expiresAt.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'acceptedAt': acceptedAt?.toIso8601String(),
      'acceptedBy': acceptedBy,
      'workspaceName': workspaceName,
      'inviterName': inviterName,
    };
  }

  WorkspaceInvitation copyWith({
    String? id,
    String? workspaceId,
    String? email,
    UserRole? role,
    String? roleTemplateId,
    bool clearRoleTemplateId = false,
    String? roleName,
    String? interfaceMode,
    String? invitedBy,
    String? token,
    InvitationStatus? status,
    DateTime? expiresAt,
    DateTime? createdAt,
    DateTime? acceptedAt,
    String? acceptedBy,
    String? workspaceName,
    String? inviterName,
  }) {
    return WorkspaceInvitation(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      email: email ?? this.email,
      role: role ?? this.role,
      roleTemplateId: clearRoleTemplateId
          ? null
          : (roleTemplateId ?? this.roleTemplateId),
      roleName: roleName ?? this.roleName,
      interfaceMode: interfaceMode ?? this.interfaceMode,
      invitedBy: invitedBy ?? this.invitedBy,
      token: token ?? this.token,
      status: status ?? this.status,
      expiresAt: expiresAt ?? this.expiresAt,
      createdAt: createdAt ?? this.createdAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      acceptedBy: acceptedBy ?? this.acceptedBy,
      workspaceName: workspaceName ?? this.workspaceName,
      inviterName: inviterName ?? this.inviterName,
    );
  }

  // Validation method
  String? validate() {
    // Email validation - more permissive to allow + and other valid characters
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    if (!emailRegex.hasMatch(email)) {
      return 'Invalid email format';
    }

    // Token should be at least 32 characters
    if (token.length < 32) {
      return 'Invalid token length';
    }

    return null;
  }
}
