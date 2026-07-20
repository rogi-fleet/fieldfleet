enum UserRole {
  masterAdmin,
  admin,
  projectManager,
  fieldTechnician,
  client,
  vendor;

  String get displayName {
    switch (this) {
      case UserRole.masterAdmin:
        return 'Master Admin';
      case UserRole.admin:
        return 'Admin';
      case UserRole.projectManager:
        return 'Project Manager';
      case UserRole.fieldTechnician:
        return 'Field Technician';
      case UserRole.client:
        return 'Customer';
      case UserRole.vendor:
        return 'Vendor';
    }
  }

  static UserRole fromString(String role) {
    final normalized = role.trim().toLowerCase();

    switch (normalized) {
      case 'masteradmin':
      case 'master_admin':
      case 'owner':
        return UserRole.masterAdmin;
      case 'admin':
        return UserRole.admin;
      case 'projectmanager':
      case 'project_manager':
      case 'manager':
        return UserRole.projectManager;
      case 'fieldtechnician':
      case 'field_technician':
      case 'technician':
        return UserRole.fieldTechnician;
      case 'client':
      case 'customer':
        return UserRole.client;
      case 'vendor':
      case 'subcontractor':
      case 'sub':
        return UserRole.vendor;
      default:
        return UserRole.projectManager;
    }
  }

  @override
  String toString() {
    return name;
  }

  /// Admin-tier roles that can manage team membership. Keeps Admin in the
  /// tier for backward compatibility — existing workspaces don't have any
  /// Master Admin members yet, and the app doesn't otherwise distinguish
  /// the two tiers for user management.
  bool get canManageUsers {
    return this == UserRole.masterAdmin || this == UserRole.admin;
  }

  /// Billing-specific permission. Reserved for the future Master Admin
  /// distinction if/when we gate payment settings.
  bool get canManageBilling {
    return this == UserRole.masterAdmin;
  }

  bool get canCreateProjects {
    return this == UserRole.masterAdmin ||
        this == UserRole.admin ||
        this == UserRole.projectManager;
  }

  bool get canEditProjects {
    return this == UserRole.masterAdmin ||
        this == UserRole.admin ||
        this == UserRole.projectManager;
  }

  bool get canDeleteProjects {
    return this == UserRole.masterAdmin ||
        this == UserRole.admin ||
        this == UserRole.projectManager;
  }

  bool get canCreateTasks {
    return this == UserRole.masterAdmin ||
        this == UserRole.admin ||
        this == UserRole.projectManager;
  }

  bool get canEditTasks {
    return this == UserRole.masterAdmin ||
        this == UserRole.admin ||
        this == UserRole.projectManager ||
        this == UserRole.fieldTechnician;
  }

  bool get canDeleteTasks {
    return this == UserRole.masterAdmin ||
        this == UserRole.admin ||
        this == UserRole.projectManager;
  }

  bool get canUploadFiles {
    return this != UserRole.client && this != UserRole.vendor;
  }

  bool get canDeleteFiles {
    return this == UserRole.masterAdmin ||
        this == UserRole.admin ||
        this == UserRole.projectManager;
  }

  bool get isReadOnly {
    return this == UserRole.client || this == UserRole.vendor;
  }

  bool get isExternalPortal {
    return this == UserRole.client || this == UserRole.vendor;
  }

  bool get canAccessSettings {
    return this == UserRole.masterAdmin || this == UserRole.admin;
  }

  /// Check if this role can view a specific navigation item.
  /// External portal roles have a restricted navigation.
  bool canViewNavItem(String navItem) {
    if (!isExternalPortal) return true;

    if (this == UserRole.client) {
      const clientVisibleItems = {
        'dashboard',
        'inbox',
        'projects',
        'documents',
        'schedule',
        'profile',
        'logout',
      };
      return clientVisibleItems.contains(navItem.toLowerCase());
    }

    // Vendor portal
    const vendorVisibleItems = {
      'dashboard',
      'inbox',
      'documents',
      'profile',
      'logout',
    };
    return vendorVisibleItems.contains(navItem.toLowerCase());
  }

  List<int>? get visibleNavIndices {
    if (!isExternalPortal) return null;
    if (this == UserRole.client) {
      return [0, 1, 2, 6, 14, 15];
    }
    // Vendor: dashboard, inbox, documents, profile, logout
    return [0, 1, 14, 15];
  }
}
