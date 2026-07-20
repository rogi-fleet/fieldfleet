import '../models/user_role.dart';

/// Module group used to section the permission matrix.
enum ModuleGroup { core, financial, contactsDocs, system }

const Map<ModuleGroup, String> moduleGroupLabels = {
  ModuleGroup.core: 'Core Operations',
  ModuleGroup.financial: 'Financial',
  ModuleGroup.contactsDocs: 'Contacts & Docs',
  ModuleGroup.system: 'System',
};

/// Ordered list of modules — authoritative for UI rendering.
const List<String> orderedModuleKeys = [
  // Core
  'projects',
  'properties',
  'tasks',
  'time_tracking',
  // Financial
  'estimating',
  'customer_invoices',
  'vendor_bills',
  'change_orders',
  'budget',
  // Contacts & Docs
  'customers',
  'vendors',
  'documents',
  'bid_requests',
  // System
  'team',
  'reports',
  'settings',
];

const Map<String, ModuleGroup> moduleGroups = {
  'projects': ModuleGroup.core,
  'properties': ModuleGroup.core,
  'tasks': ModuleGroup.core,
  'time_tracking': ModuleGroup.core,
  'estimating': ModuleGroup.financial,
  'customer_invoices': ModuleGroup.financial,
  'vendor_bills': ModuleGroup.financial,
  'change_orders': ModuleGroup.financial,
  'budget': ModuleGroup.financial,
  'customers': ModuleGroup.contactsDocs,
  'vendors': ModuleGroup.contactsDocs,
  'documents': ModuleGroup.contactsDocs,
  'bid_requests': ModuleGroup.contactsDocs,
  'team': ModuleGroup.system,
  'reports': ModuleGroup.system,
  'settings': ModuleGroup.system,
};

const Map<String, String> modulePermissionLabels = {
  'projects': 'Jobs',
  'properties': 'Properties',
  'tasks': 'Tasks',
  'time_tracking': 'Time Tracking',
  'estimating': 'Estimating',
  'customer_invoices': 'Customer Invoices',
  'vendor_bills': 'Vendor Bills',
  'change_orders': 'Change Orders',
  'budget': 'Budget',
  'customers': 'Customers',
  'vendors': 'Vendors',
  'documents': 'Documents & Forms',
  'bid_requests': 'Bid Requests',
  'team': 'Team',
  'reports': 'Reports',
  'settings': 'Settings',
};

const Map<String, String> modulePermissionDescriptions = {
  'projects':
      'Create and manage jobs, including status, scope, and assignments.',
  'properties':
      'Manage property records: units and areas.',
  'tasks':
      'Create and manage task assignments, task status, and task comments.',
  'time_tracking':
      'View and edit time entries, clock-in/out records, and timesheets.',
  'estimating': 'Prepare and send estimates, proposals, and line-item quotes.',
  'customer_invoices': 'Create, send, and reconcile customer invoices.',
  'vendor_bills': 'Enter, review, and pay vendor bills and purchase orders.',
  'change_orders':
      'Raise and approve change orders that alter job scope or price.',
  'budget':
      'View and edit project budgets, cost items, and financial reports.',
  'customers':
      'Create and manage customer contacts, accounts, and portal invites.',
  'vendors':
      'Create and manage vendor contacts, subcontractor accounts, and portal invites.',
  'documents': 'Upload, share, and manage files, forms, and project documents.',
  'bid_requests':
      'Send bid requests to vendors and review their responses.',
  'team':
      'View team members and their assignments. Editing allows inviting or removing members.',
  'reports': 'Build, save, and export reports across modules.',
  'settings':
      'Configure workspace preferences, integrations, branding, and users.',
};

const List<String> modulePermissionLevels = ['none', 'read', 'write'];

const Map<String, String> modulePermissionLevelLabels = {
  'none': 'No Access',
  'read': 'View',
  'write': 'Edit',
};

/// CRUD flags that a given level implies, for matrix display.
/// write → {C,R,E,D}; read → {R}; none → {}.
const Map<String, Set<String>> modulePermissionLevelCrud = {
  'none': <String>{},
  'read': {'R'},
  'write': {'C', 'R', 'E', 'D'},
};

const List<String> crudOrder = ['C', 'R', 'E', 'D'];

/// Modules a given role can access by default (read or write).
/// Modules not listed are granted 'none'.
/// Uses the keys from [orderedModuleKeys].
Map<String, String> defaultPermissionsForRole(UserRole role) {
  Map<String, String> withDefault(
    Map<String, String> overrides, {
    String fallback = 'none',
  }) {
    return {
      for (final key in orderedModuleKeys) key: overrides[key] ?? fallback,
    };
  }

  switch (role) {
    case UserRole.masterAdmin:
      return withDefault(const {}, fallback: 'write');
    case UserRole.admin:
      return withDefault(const {'settings': 'read'}, fallback: 'write');
    case UserRole.projectManager:
      return withDefault(const {
        'projects': 'write',
        'properties': 'write',
        'tasks': 'write',
        'time_tracking': 'write',
        'estimating': 'read',
        'customer_invoices': 'read',
        'vendor_bills': 'read',
        'change_orders': 'write',
        'budget': 'read',
        'customers': 'read',
        'vendors': 'read',
        'documents': 'write',
        'bid_requests': 'write',
        'team': 'read',
        'reports': 'read',
        'settings': 'none',
      });
    case UserRole.fieldTechnician:
      return withDefault(const {
        'projects': 'read',
        'properties': 'read',
        'tasks': 'write',
        'time_tracking': 'write',
        'documents': 'read',
        'team': 'read',
      });
    case UserRole.client:
      return withDefault(const {
        'projects': 'read',
        'properties': 'read',
        'customer_invoices': 'read',
        'change_orders': 'read',
        'customers': 'read',
        'documents': 'read',
      });
    case UserRole.vendor:
      return withDefault(const {
        'vendor_bills': 'read',
        'vendors': 'read',
        'documents': 'read',
        'bid_requests': 'write',
      });
  }
}

Map<String, String> normalizeModulePermissions(
  Map<String, String> permissions,
) {
  final normalized = <String, String>{};
  for (final module in orderedModuleKeys) {
    final value = permissions[module] ?? 'none';
    normalized[module] = modulePermissionLevels.contains(value)
        ? value
        : 'read';
  }
  return normalized;
}
