/// Constants for the [FileFolder.virtualType] field.
class VirtualFolderType {
  static const String tasks = 'tasks';
  static const String messages = 'messages';
  static const String forms = 'forms';
  static const String documents = 'documents';
  // Project module sections that used to be top-level project tabs
  // (Daily Logs, Inspections, Punch List, Warranties, Plans,
  // Specifications). Re-homed under Files so the project header stays
  // focused.
  static const String dailyLogs = 'daily-logs';
  static const String inspections = 'inspections';
  static const String specifications = 'specifications';
  static const String punchList = 'punch-list';
  static const String warranties = 'warranties';
  static const String plans = 'plans';

  /// Virtual folder types backed by a project module (rendered by a
  /// dedicated module widget rather than a file list).
  static const Set<String> moduleTypes = {
    dailyLogs,
    inspections,
    specifications,
    punchList,
    warranties,
    plans,
  };

  VirtualFolderType._();
}

/// Represents a folder in the project file structure.
class FileFolder {
  final String id;
  final String workspaceId;
  final String projectId;
  final String name;
  final String? parentFolderId; // null for root folders
  final bool isVirtual; // true for Tasks/Messages folders (read-only)
  final String? virtualType; // 'tasks' or 'messages' for virtual folders
  final String createdBy;
  final DateTime createdAt;

  FileFolder({
    required this.id,
    required this.workspaceId,
    required this.projectId,
    required this.name,
    this.parentFolderId,
    this.isVirtual = false,
    this.virtualType,
    required this.createdBy,
    required this.createdAt,
  });

  /// Factory for Supabase (snake_case keys)
  factory FileFolder.fromSupabase(Map<String, dynamic> json) {
    return FileFolder(
      id: json['id'] as String,
      workspaceId: json['workspace_id'] as String,
      projectId: json['project_id'] as String,
      name: json['name'] as String,
      parentFolderId: json['parent_folder_id'] as String?,
      isVirtual: json['is_virtual'] as bool? ?? false,
      virtualType: json['virtual_type'] as String?,
      createdBy: json['created_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Factory for Firebase (camelCase keys with Timestamp)
  factory FileFolder.fromJson(Map<String, dynamic> json, String id) {
    final createdAtValue = json['createdAt'];
    DateTime createdAt;
    if (createdAtValue is DateTime) {
      createdAt = createdAtValue;
    } else if (createdAtValue is String) {
      createdAt = DateTime.parse(createdAtValue);
    } else {
      // Handle Firebase Timestamp
      createdAt = (createdAtValue as dynamic).toDate();
    }

    return FileFolder(
      id: id,
      workspaceId: json['workspaceId'] as String,
      projectId: json['projectId'] as String,
      name: json['name'] as String,
      parentFolderId: json['parentFolderId'] as String?,
      isVirtual: json['isVirtual'] as bool? ?? false,
      virtualType: json['virtualType'] as String?,
      createdBy: json['createdBy'] as String,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'workspaceId': workspaceId,
      'projectId': projectId,
      'name': name,
      'parentFolderId': parentFolderId,
      'isVirtual': isVirtual,
      'virtualType': virtualType,
      'createdBy': createdBy,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toSupabase() {
    return {
      'workspace_id': workspaceId,
      'project_id': projectId,
      'name': name,
      'parent_folder_id': parentFolderId,
      'is_virtual': isVirtual,
      'virtual_type': virtualType,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Returns true if this is a root-level folder (no parent)
  bool get isRoot => parentFolderId == null;

  /// Display name shown in the UI. Overrides the stored [name] for virtual
  /// folders and legacy default folders so that existing projects immediately
  /// show updated labels without a migration.
  String get displayName {
    if (!isVirtual && name == 'Mitigation') {
      return 'General';
    }

    switch (virtualType) {
      case VirtualFolderType.tasks:
        return 'Task Files';
      case VirtualFolderType.messages:
        return 'Message Files';
      case VirtualFolderType.forms:
        return 'Forms';
      case VirtualFolderType.documents:
        return 'Financials';
      case VirtualFolderType.plans:
        return 'Plans';
      case VirtualFolderType.specifications:
        return 'Specifications';
      default:
        return name;
    }
  }

  /// Returns the icon appropriate for this folder type
  String get iconName {
    if (virtualType == VirtualFolderType.tasks) return 'task';
    if (virtualType == VirtualFolderType.messages) return 'message';
    return 'folder';
  }

  FileFolder copyWith({
    String? id,
    String? workspaceId,
    String? projectId,
    String? name,
    String? Function()? parentFolderId,
    bool? isVirtual,
    String? Function()? virtualType,
    String? createdBy,
    DateTime? createdAt,
  }) {
    return FileFolder(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      projectId: projectId ?? this.projectId,
      name: name ?? this.name,
      parentFolderId: parentFolderId != null ? parentFolderId() : this.parentFolderId,
      isVirtual: isVirtual ?? this.isVirtual,
      virtualType: virtualType != null ? virtualType() : this.virtualType,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
