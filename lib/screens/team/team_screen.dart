import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/workspace_member.dart';
import '../../models/role_permissions.dart';
import '../../models/vehicle.dart';
import '../../models/workspace_role_template.dart';
import '../../models/user.dart';
import '../../models/user_role.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../services/supabase/vehicle_service.dart';
import '../../utils/app_logger.dart';
import '../../utils/module_permissions.dart';
import '../../utils/table_column_visibility.dart';
import '../../utils/user_facing_error.dart';
import '../../theme/theme.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/common/app_search_bar.dart';
import '../../widgets/common/module_header.dart';
import '../../widgets/table/table_column_picker_button.dart';
import 'team_capacity_tab.dart';
import '../settings/skills_management_screen.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';
import '../../widgets/common/zero_items_action_empty_state.dart';
import '../../widgets/adaptive_navigation.dart';

class TeamScreen extends StatefulWidget {
  final String? initialTab;
  final String? initialProjectId;
  final String? initialMemberId;

  const TeamScreen({
    super.key,
    this.initialTab,
    this.initialProjectId,
    this.initialMemberId,
  });

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  final dynamic _memberService = ServiceLocator.workspaceMemberService;
  final dynamic _roleTemplateService = ServiceLocator.roleTemplateService;
  final dynamic _userService = ServiceLocator.userService;
  String _searchQuery = '';
  bool _searchExpanded = false;
  List<WorkspaceRoleTemplate> _roleTemplates = const [];
  String? _roleTemplatesWorkspaceId;

  // Column visibility for the members table.
  // Persisted per-device under [_columnPrefsKey] so each user's chosen
  // layout survives reloads. The Vehicles column is hidden by default —
  // it's behind one extra query and only matters for fleet-using teams,
  // so opt-in keeps the toolbar quiet for everyone else.
  static const _allColumns = <String>[
    'email',
    'role',
    'hourly',
    'weekly',
    'joined',
    'vehicles',
  ];
  static const _defaultVisibleColumns = <String>[
    'email',
    'role',
    'hourly',
    'weekly',
    'joined',
  ];
  static const _columnNames = <String, String>{
    'email': 'Email',
    'role': 'Role',
    'hourly': 'Hourly Wage',
    'weekly': 'Weekly Wage',
    'joined': 'Joined',
    'vehicles': 'Vehicles',
  };
  static const _columnPrefsKey = 'team_visible_columns';

  TableColumnVisibility _colVis = TableColumnVisibility(
    _defaultVisibleColumns,
  );
  bool _columnPrefsLoaded = false;

  // Vehicles bucketed by user id (primary OR current driver). Loaded once
  // per workspace and cached so toggling the column doesn't re-fetch.
  Future<Map<String, List<Vehicle>>>? _vehiclesByUserFuture;
  String? _vehiclesLoadedForWorkspace;

  @override
  void initState() {
    super.initState();
    _loadColumnPreferences();
  }

  bool _isColumnVisible(String columnId) => _colVis.isVisible(columnId);

  Future<void> _loadColumnPreferences() async {
    if (_columnPrefsLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_columnPrefsKey);
    if (!mounted) return;
    setState(() {
      _columnPrefsLoaded = true;
      if (saved != null) {
        _colVis = TableColumnVisibility(saved);
      }
    });
  }

  Future<void> _saveColumnPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_columnPrefsKey, _colVis.toList());
  }

  void _toggleColumn(String columnId) {
    setState(() => _colVis = _colVis.toggle(columnId));
    _saveColumnPreferences();
  }

  /// Fetch every vehicle in the workspace once and bucket by user id.
  /// Each vehicle appears under its primary driver *and* its current
  /// driver (if different) so a member with handed-off keys still shows
  /// up in the row. One query is cheaper than per-row N queries; for
  /// workspaces with hundreds of vehicles this still fits in one round
  /// trip.
  Future<Map<String, List<Vehicle>>> _loadVehiclesByUser(
    String workspaceId,
  ) async {
    final service = SupabaseVehicleService(workspaceId: workspaceId);
    final vehicles = await service.getVehiclesOnce();
    final byUser = <String, List<Vehicle>>{};
    for (final v in vehicles) {
      final primary = v.assignedToUserId;
      final current = v.currentDriverId;
      if (primary != null && primary.isNotEmpty) {
        byUser.putIfAbsent(primary, () => []).add(v);
      }
      if (current != null && current.isNotEmpty && current != primary) {
        byUser.putIfAbsent(current, () => []).add(v);
      }
    }
    return byUser;
  }

  Future<Map<String, List<Vehicle>>> _ensureVehiclesLoaded(String workspaceId) {
    if (_vehiclesByUserFuture != null &&
        _vehiclesLoadedForWorkspace == workspaceId) {
      return _vehiclesByUserFuture!;
    }
    _vehiclesLoadedForWorkspace = workspaceId;
    _vehiclesByUserFuture = _loadVehiclesByUser(workspaceId);
    return _vehiclesByUserFuture!;
  }

  Future<void> _loadRoleTemplatesForWorkspace(String workspaceId) async {
    try {
      final templates = await _roleTemplateService.getTemplates(
        workspaceId: workspaceId,
      );
      if (!mounted) return;
      setState(() {
        _roleTemplates = List<WorkspaceRoleTemplate>.from(templates);
      });
    } catch (e) {
      AppLogger.warning(
        'Failed to load team role templates',
        metadata: {'workspaceId': workspaceId, 'error': e.toString()},
      );
    }
  }

  Future<void> _updateMemberRoleTemplate(
    BuildContext context,
    WorkspaceMember member,
    WorkspaceRoleTemplate newTemplate,
    bool isCurrentUserAdmin,
  ) async {
    if (!isCurrentUserAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only admins can change member roles'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (_templateForMember(member)?.id == newTemplate.id) {
      return;
    }

    final currentTemplate = _templateForMember(member);
    final isSelfDemotion =
        member.userId == context.read<AuthProvider>().appUser?.id &&
        (currentTemplate?.isAdmin == true || currentTemplate?.role == UserRole.masterAdmin) &&
        newTemplate.isAdmin == false &&
        newTemplate.role != UserRole.masterAdmin;
    if (isSelfDemotion) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Change your own role?'),
          content: Text(
            'You are about to change your own role from '
            '"${currentTemplate?.name ?? 'current'}" to "${newTemplate.name}". '
            'You will immediately lose admin-only access. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Change role'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      await _memberService.updateMemberRoleTemplate(
        workspaceId: member.workspaceId,
        userId: member.userId,
        roleTemplateId: newTemplate.id,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Role updated to ${newTemplate.name}')),
        );
      }
    } catch (e) {
      AppLogger.error('Failed to update member role', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update role: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _removeMember(
    BuildContext context,
    WorkspaceMember member,
    String memberName,
    bool isCurrentUserAdmin,
  ) async {
    if (!isCurrentUserAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only admins can remove members'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Member?'),
        content: Text(
          'Are you sure you want to remove $memberName from this workspace? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _memberService.removeMember(
        workspaceId: member.workspaceId,
        userId: member.userId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$memberName removed from workspace')),
        );
      }
    } catch (e) {
      AppLogger.error('Failed to remove member', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove member: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _updateMemberSettings(
    BuildContext context,
    WorkspaceMember member, {
    double? hourlyRate,
    double? weeklyWage,
    Map<String, String>? modulePermissions,
    String? interfaceMode,
  }) async {
    try {
      await _memberService.updateMemberSettings(
        workspaceId: member.workspaceId,
        userId: member.userId,
        hourlyRate: hourlyRate,
        weeklyWage: weeklyWage,
        modulePermissions: modulePermissions,
        interfaceMode: interfaceMode,
      );

      // If we just changed the current user's own wage, refresh the cached
      // workspace memberships so screens reading WorkspaceProvider (e.g. the
      // clock-in wage gate, R012) pick it up without a full reload.
      if (mounted && (hourlyRate != null || weeklyWage != null)) {
        final auth = context.read<AuthProvider>();
        if (auth.appUser?.id == member.userId) {
          await context
              .read<WorkspaceProvider>()
              .loadWorkspaces(member.userId);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member settings updated')),
        );
      }
    } catch (e) {
      AppLogger.error('Failed to update member settings', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // Role palette keyed to the 7-role schematic. Customer/Vendor need colors
  // outside the stock AppColors set so they stand out as external portals.
  static const Color _customerTeal = Color(0xFF0D9488);
  static const Color _vendorPink = Color(0xFFDB2777);

  Color _roleColorForUserRole(UserRole role) {
    switch (role) {
      case UserRole.masterAdmin:
        return AppColors.secondary; // orange
      case UserRole.admin:
        return AppColors.info; // blue
      case UserRole.projectManager:
        return AppColors.success; // green
      case UserRole.fieldTechnician:
        return AppColors.warning; // amber
      case UserRole.client:
        return _customerTeal;
      case UserRole.vendor:
        return _vendorPink;
    }
  }

  Color _getRoleColor({
    UserRole? role,
    required bool isAdmin,
    required Map<String, String> permissions,
  }) {
    if (role != null) return _roleColorForUserRole(role);
    // Custom role (no enum). Purple keeps the schematic mapping.
    if (isAdmin) return AppColors.messageAccent;

    final rolePermissions = RolePermissions(
      roleName: '',
      isAdmin: false,
      modulePermissions: normalizeModulePermissions(permissions),
    );
    if (rolePermissions.isClientMode) return _customerTeal;
    return AppColors.messageAccent;
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 30) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '$months month${months > 1 ? 's' : ''} ago';
    } else {
      final years = (difference.inDays / 365).floor();
      return '$years year${years > 1 ? 's' : ''} ago';
    }
  }

  WorkspaceRoleTemplate? _templateForMember(WorkspaceMember member) {
    for (final template in _roleTemplates) {
      if (template.id == member.roleTemplateId) return template;
    }
    for (final template in _roleTemplates) {
      if (member.roleTemplateName != null &&
          template.name == member.roleTemplateName) {
        return template;
      }
    }
    for (final template in _roleTemplates) {
      if (template.isSystem && template.role == member.role) return template;
    }
    return null;
  }

  String _displayRoleNameForMember(WorkspaceMember member) {
    return _templateForMember(member)?.name ??
        member.roleTemplateName ??
        member.role.displayName;
  }

  bool _isAdminMember(WorkspaceMember member) {
    return _templateForMember(member)?.isAdmin == true || member.isAdminRole;
  }

  Color _getRoleColorForTemplate(WorkspaceRoleTemplate template) {
    return _getRoleColor(
      role: template.role,
      isAdmin: template.isAdmin,
      permissions: template.modulePermissions,
    );
  }

  Color _getRoleColorForMember(WorkspaceMember member) {
    final template = _templateForMember(member);
    if (template != null) {
      return _getRoleColorForTemplate(template);
    }

    return _getRoleColor(
      role: member.role,
      isAdmin: member.isAdminRole,
      permissions: member.modulePermissions.isNotEmpty
          ? member.modulePermissions
          : defaultPermissionsForRole(member.role),
    );
  }

  Map<String, String> _effectivePermissionsForMember(WorkspaceMember member) {
    final template = _templateForMember(member);
    if (template?.isAdmin == true || member.isAdminRole) {
      return {for (final key in modulePermissionLabels.keys) key: 'write'};
    }

    if (template != null) {
      return normalizeModulePermissions(template.modulePermissions);
    }

    if (member.modulePermissions.isNotEmpty) {
      return normalizeModulePermissions(member.modulePermissions);
    }

    return defaultPermissionsForRole(member.role);
  }

  String _permissionSummary(Map<String, String> permissions) {
    var write = 0;
    var read = 0;
    var none = 0;

    for (final value in permissions.values) {
      switch (value) {
        case 'write':
          write++;
          break;
        case 'none':
          none++;
          break;
        default:
          read++;
      }
    }

    if (none == 0 && read == 0) return 'Full access';
    if (write == 0 && read == 0) return 'No access';
    if (write == 0) return 'Read-only access';
    return '$write write · $read read · $none blocked';
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final workspaceProvider = context.watch<WorkspaceProvider>();
    final currentUser = authProvider.appUser;
    final workspaceId = currentUser?.currentWorkspaceId;
    final defaultHourlyRate =
        workspaceProvider.activeWorkspace?.defaultHourlyRate;
    final defaultWeeklyWage =
        workspaceProvider.activeWorkspace?.defaultWeeklyWage;

    if (currentUser == null || workspaceId == null) {
      return const Scaffold(body: Center(child: Text('No workspace selected')));
    }

    if (_roleTemplatesWorkspaceId != workspaceId) {
      _roleTemplatesWorkspaceId = workspaceId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadRoleTemplatesForWorkspace(workspaceId);
      });
    }

    final initialIndex = switch (widget.initialTab) {
      'capacity' => 1,
      'skills' => 2,
      _ => 0,
    };

    return DefaultTabController(
      length: 3,
      initialIndex: initialIndex,
      child: TabSwitchNotifier(
        child: Column(
          children: [
            const ModuleHeader(
              icon: Icons.groups_outlined,
              title: 'Team',
              description:
                  'Members, roles and permissions across the workspace.',
            ),
            Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 500;
                  return Row(
                    children: [
                      Expanded(
                        child: TabBar(
                          isScrollable: isNarrow,
                          tabAlignment: isNarrow
                              ? TabAlignment.start
                              : TabAlignment.fill,
                          tabs: const [
                            Tab(icon: Icon(Icons.person_outline), text: 'Members'),
                            Tab(icon: Icon(Icons.bar_chart_outlined), text: 'Capacity'),
                            Tab(icon: Icon(Icons.psychology_outlined), text: 'Skills'),
                          ],
                        ),
                      ),
                      // Show invite button only on wider screens
                      if (!isNarrow)
                        Builder(
                          builder: (context) {
                            final isAdmin = context
                                .read<AuthProvider>()
                                .canManageUsers;
                            if (!isAdmin) return const SizedBox.shrink();

                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: FilledButton.icon(
                                onPressed: () {
                                  context.push(
                                    '/settings/invite?workspaceId=$workspaceId',
                                  );
                                },
                                icon: const Icon(Icons.person_add, size: 18),
                                label: const Text('Invite Team Member'),
                              ),
                            );
                          },
                        ),
                    ],
                  );
                },
              ),
            ),
            Expanded(
              child: TabBarView(
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildMembersTab(
                    workspaceId: workspaceId,
                    currentUserId: currentUser.id,
                    defaultHourlyRate: defaultHourlyRate,
                    defaultWeeklyWage: defaultWeeklyWage,
                  ),
                  TeamCapacityTab(
                    workspaceId: workspaceId,
                    currentUserId: currentUser.id,
                    currentUserDisplayName:
                        currentUser.displayName ?? currentUser.email,
                    currentUserEmail: currentUser.email,
                    initialProjectId: widget.initialProjectId,
                    initialMemberId: widget.initialMemberId,
                  ),
                  const SkillsManagementScreen(embedded: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMembersTab({
    required String workspaceId,
    required String currentUserId,
    required double? defaultHourlyRate,
    required double? defaultWeeklyWage,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
          child: _searchExpanded
              ? Row(
                  children: [
                    Expanded(
                      child: AppSearchBar(
                        hintText: 'Search team members...',
                        height: 36,
                        onChanged: (value) {
                          setState(() => _searchQuery = value.toLowerCase());
                        },
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 20,
                        color: ChromeColors.of(context).text,
                      ),
                      onPressed: () => setState(() {
                        _searchExpanded = false;
                        _searchQuery = '';
                      }),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.search,
                        size: 22,
                        color: ChromeColors.of(context).text,
                      ),
                      tooltip: 'Search team members',
                      onPressed: () => setState(() => _searchExpanded = true),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    TableDefaultColumnPickerButton(
                      columnIds: _allColumns,
                      isColumnVisible: _isColumnVisible,
                      onToggleColumn: _toggleColumn,
                      columnNames: _columnNames,
                    ),
                  ],
                ),
        ),

        // Team members list
        Expanded(
          child: StreamBuilder<List<WorkspaceMember>>(
            stream: _memberService.getWorkspaceMembers(workspaceId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.base),
                    child: Text(
                      UserFacingError.uiMessage(
                        snapshot.error,
                        action: 'load team members',
                      ),
                      style: const TextStyle(color: AppColors.errorDark),
                    ),
                  ),
                );
              }

              final members = snapshot.data ?? [];

              if (members.isEmpty) {
                return ZeroItemsActionEmptyState(
                  icon: Icons.group_outlined,
                  title: 'No team members yet',
                  subtitle:
                      'Invite your team to start collaborating on ${context.read<WorkspaceProvider>().projectTerminology.toLowerCase()}',
                  ctaLabel: 'Invite Team Member',
                  onTap: () =>
                      context.push('/settings/invite?workspaceId=$workspaceId'),
                );
              }

              return Builder(
                builder: (context) {
                  final isCurrentUserAdmin = context
                      .read<AuthProvider>()
                      .canManageUsers;

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      // Use table view on wide screens, cards on narrow
                      if (constraints.maxWidth > 800) {
                        return _buildTableView(
                          context,
                          members,
                          currentUserId,
                          isCurrentUserAdmin,
                          defaultHourlyRate,
                          defaultWeeklyWage,
                          workspaceId,
                        );
                      } else {
                        return _buildCardView(
                          context,
                          members,
                          currentUserId,
                          isCurrentUserAdmin,
                          defaultHourlyRate,
                          defaultWeeklyWage,
                        );
                      }
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTableView(
    BuildContext context,
    List<WorkspaceMember> members,
    String currentUserId,
    bool isCurrentUserAdmin,
    double? defaultHourlyRate,
    double? defaultWeeklyWage,
    String workspaceId,
  ) {
    // Filter members based on search query
    final filteredMembers = members.where((member) {
      if (_searchQuery.isEmpty) return true;
      // We'll filter once we have user details
      return true;
    }).toList();

    // Only fetch vehicles when the column is on — avoids a query for
    // workspaces that don't use the fleet feature.
    final vehiclesFuture = _isColumnVisible('vehicles')
        ? _ensureVehiclesLoaded(workspaceId)
        : Future.value(<String, List<Vehicle>>{});

    return FutureBuilder<Map<String, List<Vehicle>>>(
      future: vehiclesFuture,
      builder: (context, snapshot) {
        final vehiclesByUser = snapshot.data ?? const <String, List<Vehicle>>{};

        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Card(
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 56), // Avatar space
                      const Expanded(
                        flex: 3,
                        child: Text(
                          'Name',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (_isColumnVisible('email'))
                        const Expanded(
                          flex: 3,
                          child: Text(
                            'Email',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      if (_isColumnVisible('role'))
                        const Expanded(
                          flex: 2,
                          child: Text(
                            'Role',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      if (_isColumnVisible('hourly'))
                        const Expanded(
                          flex: 2,
                          child: Text(
                            'Hourly Wage',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      if (_isColumnVisible('weekly'))
                        const Expanded(
                          flex: 2,
                          child: Text(
                            'Weekly Wage',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      if (_isColumnVisible('joined'))
                        const Expanded(
                          flex: 2,
                          child: Text(
                            'Joined',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      if (_isColumnVisible('vehicles'))
                        const Expanded(
                          flex: 3,
                          child: Text(
                            'Vehicles',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      const SizedBox(width: 80), // Actions space
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Members
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredMembers.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final member = filteredMembers[index];
                    return _buildTableRow(
                      context,
                      member,
                      currentUserId,
                      isCurrentUserAdmin,
                      defaultHourlyRate,
                      defaultWeeklyWage,
                      vehiclesByUser[member.userId] ?? const <Vehicle>[],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTableRow(
    BuildContext context,
    WorkspaceMember member,
    String currentUserId,
    bool isCurrentUserAdmin,
    double? defaultHourlyRate,
    double? defaultWeeklyWage,
    List<Vehicle> memberVehicles,
  ) {
    return FutureBuilder<AppUser?>(
      future: _userService.getUserById(member.userId),
      builder: (context, userSnapshot) {
        final user = userSnapshot.data;
        final isCurrentUser = member.userId == currentUserId;
        final displayName = user?.displayName ?? user?.email ?? 'Loading...';
        final email = user?.email ?? 'Loading...';
        final selectedTemplate = _templateForMember(member);
        final displayRoleName = _displayRoleNameForMember(member);
        final isAdminMember = _isAdminMember(member);
        final hourlyDisplay = _formatWage(
          member.hourlyRate,
          defaultHourlyRate,
          fallbackLabel: 'Set wage',
        );
        final weeklyDisplay = _formatWage(
          member.weeklyWage,
          defaultWeeklyWage,
          fallbackLabel: 'Set wage',
        );
        final hourlyIsDefault =
            member.hourlyRate == null && defaultHourlyRate != null;
        final weeklyIsDefault =
            member.weeklyWage == null && defaultWeeklyWage != null;

        // Filter based on search query
        if (_searchQuery.isNotEmpty &&
            !displayName.toLowerCase().contains(_searchQuery) &&
            !email.toLowerCase().contains(_searchQuery)) {
          return const SizedBox.shrink();
        }

        return InkWell(
          onTap: () {
            // Navigate to user profile
            context.push('/profile/${member.userId}');
          },
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Row(
              children: [
                // Avatar
                UserAvatar(
                  user: user,
                  userId: member.userId,
                  size: AvatarSize.medium,
                  onTap: null, // Disable tap since row is tappable
                ),
                const SizedBox(width: 16),

                // Name
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isCurrentUser) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.info.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(AppRadius.xs),
                              ),
                              child: const Text(
                                'You',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.info,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // Email
                if (_isColumnVisible('email'))
                  Expanded(
                    flex: 3,
                    child: Text(
                      email,
                      style: const TextStyle(color: AppColors.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                // Role
                if (_isColumnVisible('role'))
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        isCurrentUserAdmin && !isCurrentUser
                          ? DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                borderRadius: AppRadius.cardRadius,
                                value: selectedTemplate?.id,
                                isDense: true,
                                items: _roleTemplates.map((template) {
                                  return DropdownMenuItem(
                                    value: template.id,
                                    child: Row(
                                      children: [
                                        Icon(
                                          template.isAdmin
                                              ? Icons.admin_panel_settings
                                              : Icons.circle,
                                          size: template.isAdmin ? 14 : 8,
                                          color: _getRoleColorForTemplate(
                                            template,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            template.name,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: (templateId) async {
                                  if (templateId == null) return;
                                  final template = _roleTemplates.firstWhere(
                                    (item) => item.id == templateId,
                                  );
                                  await _updateMemberRoleTemplate(
                                    context,
                                    member,
                                    template,
                                    isCurrentUserAdmin,
                                  );
                                },
                              ),
                            )
                          : Row(
                              children: [
                                Icon(
                                  isAdminMember
                                      ? Icons.admin_panel_settings
                                      : Icons.circle,
                                  size: isAdminMember ? 14 : 8,
                                  color: _getRoleColorForMember(member),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    displayRoleName,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                      const SizedBox(height: 2),
                      Text(
                        _permissionSummary(
                          _effectivePermissionsForMember(member),
                        ),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),

                // Hourly Wage
                if (_isColumnVisible('hourly'))
                  Expanded(
                    flex: 2,
                    child: isCurrentUserAdmin
                        ? InkWell(
                            onTap: () =>
                                _showCompensationDialog(context, member),
                            child: Text(
                              hourlyDisplay,
                              style: TextStyle(
                                color: member.hourlyRate != null
                                    ? null
                                    : (hourlyIsDefault
                                          ? AppColors.textPrimary
                                          : AppColors.info),
                                decoration: member.hourlyRate != null ||
                                        hourlyIsDefault
                                    ? null
                                    : TextDecoration.underline,
                              ),
                            ),
                          )
                        : Text(hourlyDisplay),
                  ),

                // Weekly Wage
                if (_isColumnVisible('weekly'))
                  Expanded(
                    flex: 2,
                    child: isCurrentUserAdmin
                        ? InkWell(
                            onTap: () =>
                                _showCompensationDialog(context, member),
                            child: Text(
                              weeklyDisplay,
                              style: TextStyle(
                                color: member.weeklyWage != null
                                    ? null
                                    : (weeklyIsDefault
                                          ? AppColors.textPrimary
                                          : AppColors.info),
                                decoration: member.weeklyWage != null ||
                                        weeklyIsDefault
                                    ? null
                                    : TextDecoration.underline,
                              ),
                            ),
                          )
                        : Text(weeklyDisplay),
                  ),

                // Joined date
                if (_isColumnVisible('joined'))
                  Expanded(
                    flex: 2,
                    child: Text(
                      _formatDate(member.joinedAt),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),

                // Vehicles
                if (_isColumnVisible('vehicles'))
                  Expanded(
                    flex: 3,
                    child: _VehiclesCell(vehicles: memberVehicles),
                  ),

                // Actions
                SizedBox(
                  width: 80,
                  child: isCurrentUserAdmin && !isCurrentUser
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.security_outlined,
                                size: 20,
                              ),
                              tooltip: 'Module Permissions',
                              onPressed: () =>
                                  _showPermissionsDialog(context, member),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              tooltip: 'Remove member',
                              onPressed: () => _removeMember(
                                context,
                                member,
                                displayName,
                                isCurrentUserAdmin,
                              ),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCardView(
    BuildContext context,
    List<WorkspaceMember> members,
    String currentUserId,
    bool isCurrentUserAdmin,
    double? defaultHourlyRate,
    double? defaultWeeklyWage,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.base),
      itemCount: members.length,
      itemBuilder: (context, index) {
        final member = members[index];
        return _buildMemberCard(
          context,
          member,
          currentUserId,
          isCurrentUserAdmin,
          defaultHourlyRate,
          defaultWeeklyWage,
        );
      },
    );
  }

  Widget _buildMemberCard(
    BuildContext context,
    WorkspaceMember member,
    String currentUserId,
    bool isCurrentUserAdmin,
    double? defaultHourlyRate,
    double? defaultWeeklyWage,
  ) {
    return FutureBuilder<AppUser?>(
      future: _userService.getUserById(member.userId),
      builder: (context, userSnapshot) {
        final user = userSnapshot.data;
        final isCurrentUser = member.userId == currentUserId;
        final displayName = user?.displayName ?? user?.email ?? 'Loading...';
        final email = user?.email ?? 'Loading...';

        // Filter based on search query
        if (_searchQuery.isNotEmpty &&
            !displayName.toLowerCase().contains(_searchQuery) &&
            !email.toLowerCase().contains(_searchQuery)) {
          return const SizedBox.shrink();
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            onTap: () {
              context.push('/profile/${member.userId}');
            },
            borderRadius: BorderRadius.circular(AppRadius.r12),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Column(
                children: [
                  Row(
                    children: [
                      UserAvatar(
                        user: user,
                        userId: member.userId,
                        size: AvatarSize.medium,
                        onTap: null, // Disable tap since card is tappable
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    displayName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isCurrentUser) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.info.withValues(
                                        alpha: 0.2,
                                      ),
                                      borderRadius: BorderRadius.circular(AppRadius.xs),
                                    ),
                                    child: const Text(
                                      'You',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.info,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              email,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (isCurrentUserAdmin && !isCurrentUser)
                        IconButton(
                          icon: const Icon(Icons.more_vert),
                          onPressed: () {
                            showModalBottomSheet(
                              context: context,
                              builder: (context) => _buildMemberActions(
                                context,
                                member,
                                displayName,
                                isCurrentUserAdmin,
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildInfoChip(
                          context,
                          icon: Icons.attach_money,
                          label: _formatWage(
                            member.hourlyRate,
                            defaultHourlyRate,
                            fallbackLabel: 'No hourly wage',
                            includeLabel: true,
                            labelPrefix: 'Hourly',
                          ),
                          color: AppColors.info,
                          onTap: isCurrentUserAdmin
                              ? () => _showCompensationDialog(context, member)
                              : null,
                        ),
                        _buildInfoChip(
                          context,
                          icon: Icons.payments_outlined,
                          label: _formatWage(
                            member.weeklyWage,
                            defaultWeeklyWage,
                            fallbackLabel: 'No weekly wage',
                            includeLabel: true,
                            labelPrefix: 'Weekly',
                          ),
                          color: AppColors.financialAccent,
                          onTap: isCurrentUserAdmin
                              ? () => _showCompensationDialog(context, member)
                              : null,
                        ),
                        _buildInfoChip(
                          context,
                          icon: Icons.shield_outlined,
                          label: _permissionSummary(_effectivePermissionsForMember(member)),
                          color: AppColors.messageAccent,
                          onTap: isCurrentUserAdmin && !isCurrentUser
                              ? () => _showPermissionsDialog(context, member)
                              : null,
                        ),
                        _buildInfoChip(
                          context,
                          icon: Icons.calendar_today,
                          label: _formatDate(member.joinedAt),
                          color: AppColors.textTertiary,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatWage(
    double? memberValue,
    double? defaultValue, {
    required String fallbackLabel,
    bool includeLabel = false,
    String labelPrefix = '',
  }) {
    final format = (double value) => '\$${value.toStringAsFixed(2)}';
    String value;
    if (memberValue != null) {
      value = format(memberValue);
    } else if (defaultValue != null) {
      value = 'Default ${format(defaultValue)}';
    } else {
      value = fallbackLabel;
    }
    if (!includeLabel || labelPrefix.isEmpty) {
      return value;
    }
    return '$labelPrefix: $value';
  }

  Widget _buildMemberActions(
    BuildContext context,
    WorkspaceMember member,
    String memberName,
    bool isCurrentUserAdmin,
  ) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.admin_panel_settings),
            title: const Text('Change Role'),
            onTap: () {
              Navigator.pop(context);
              _showRoleChangeDialog(context, member, isCurrentUserAdmin);
            },
          ),
          ListTile(
            leading: const Icon(Icons.security),
            title: const Text('Module Permissions'),
            onTap: () {
              Navigator.pop(context);
              _showPermissionsDialog(context, member);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: AppColors.error),
            title: const Text(
              'Remove from Workspace',
              style: TextStyle(color: AppColors.error),
            ),
            onTap: () {
              Navigator.pop(context);
              _removeMember(context, member, memberName, isCurrentUserAdmin);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showRoleChangeDialog(
    BuildContext context,
    WorkspaceMember member,
    bool isCurrentUserAdmin,
  ) async {
    if (_roleTemplates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Role templates are still loading'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final selectedTemplate = await showDialog<WorkspaceRoleTemplate>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Role'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _roleTemplates
                  .where(
                    (t) =>
                        t.role != UserRole.client && t.role != UserRole.vendor,
                  )
                  .map((template) {
                return RadioListTile<String>(
                  title: Row(
                    children: [
                      Icon(
                        template.isAdmin
                            ? Icons.admin_panel_settings
                            : Icons.circle,
                        size: template.isAdmin ? 16 : 12,
                        color: _getRoleColorForTemplate(template),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(template.name)),
                    ],
                  ),
                  subtitle: template.description?.trim().isNotEmpty == true
                      ? Text(template.description!)
                      : const Text(
                          'Custom role — no description provided.',
                          style: TextStyle(fontStyle: FontStyle.italic),
                        ),
                  value: template.id,
                  groupValue: _templateForMember(member)?.id,
                  onChanged: (value) {
                    if (value == null) return;
                    Navigator.of(context).pop(template);
                  },
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selectedTemplate != null && mounted) {
      await _updateMemberRoleTemplate(
        context,
        member,
        selectedTemplate,
        isCurrentUserAdmin,
      );
    }
  }

  Future<void> _showCompensationDialog(
    BuildContext context,
    WorkspaceMember member,
  ) async {
    final hourlyController = TextEditingController(
      text: member.hourlyRate?.toString() ?? '',
    );
    final weeklyController = TextEditingController(
      text: member.weeklyWage?.toString() ?? '',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update Wages'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StackedField(
              label: 'Hourly Wage (\$)',
              child: TextField(
                controller: hourlyController,
                decoration: const InputDecoration(
                  prefixText: '\$ ',
                  hintText: '0.00',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                autofocus: true,
              ),
            ),
            const SizedBox(height: 12),
            StackedField(
              label: 'Weekly Wage (\$)',
              child: TextField(
                controller: weeklyController,
                decoration: const InputDecoration(
                  prefixText: '\$ ',
                  hintText: '0.00',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final rate = hourlyController.text.trim().isEmpty
          ? null
          : double.tryParse(hourlyController.text.trim());
      final weeklyWage = weeklyController.text.trim().isEmpty
          ? null
          : double.tryParse(weeklyController.text.trim());
      if (rate != null || weeklyWage != null) {
        _updateMemberSettings(
          context,
          member,
          hourlyRate: rate,
          weeklyWage: weeklyWage,
        );
      }
    }
  }

  Future<void> _applyPermissionsToRoleTemplate(
    BuildContext context, {
    required WorkspaceMember sourceMember,
    required Map<String, String> modulePermissions,
  }) async {
    try {
      final sourceTemplate = _templateForMember(sourceMember);
      final sourceLabel =
          sourceTemplate?.name ?? _displayRoleNameForMember(sourceMember);
      final membersStream =
          _memberService.getWorkspaceMembers(sourceMember.workspaceId)
              as Stream<List<WorkspaceMember>>;
      final members = await membersStream.first;
      final targets = members.where((m) {
        if (m.userId == sourceMember.userId) return false;
        final candidateTemplate = _templateForMember(m);
        if (sourceTemplate != null) {
          return candidateTemplate?.id == sourceTemplate.id;
        }
        return candidateTemplate == null && m.role == sourceMember.role;
      }).toList();

      if (!mounted) return;

      if (targets.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No other $sourceLabel members to update.',
            ),
          ),
        );
        return;
      }

      final confirmed = await _confirmBulkApply(
        context,
        sourceLabel: sourceLabel,
        targets: targets,
      );
      if (!confirmed) return;

      for (final target in targets) {
        await _memberService.updateMemberSettings(
          workspaceId: target.workspaceId,
          userId: target.userId,
          modulePermissions: modulePermissions,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Applied permissions to ${targets.length} $sourceLabel member(s)',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed bulk apply: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<bool> _confirmBulkApply(
    BuildContext context, {
    required String sourceLabel,
    required List<WorkspaceMember> targets,
  }) async {
    final count = targets.length;
    final plural = count == 1 ? 'member' : 'members';
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Apply to $count other $sourceLabel $plural?'),
        content: Text(
          'This overwrites the module permissions for every $sourceLabel '
          '$plural in this workspace (except yourself). Continue?',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Apply to $count'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _showPermissionsDialog(
    BuildContext context,
    WorkspaceMember member,
  ) async {
    List<WorkspaceRoleTemplate> roleTemplates = const [];
    try {
      final templates = await _roleTemplateService.getTemplates(
        workspaceId: member.workspaceId,
      );
      roleTemplates = List<WorkspaceRoleTemplate>.from(templates);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load role templates: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    if (roleTemplates.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No role templates available for this workspace'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }
    if (!mounted) return;

    final permissions = _effectivePermissionsForMember(member);
    WorkspaceRoleTemplate selectedTemplate =
        _templateForMember(member) ?? roleTemplates.first;
    bool applyToRole = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Permissions Matrix'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StackedField(
                  label: 'Role Template',
                  child: DropdownButtonFormField<String>(
                    borderRadius: AppRadius.cardRadius,
                    initialValue: selectedTemplate.id,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: roleTemplates.map((template) {
                      final suffix = template.role != null
                          ? ' (${template.role!.displayName})'
                          : '';
                      return DropdownMenuItem<String>(
                        value: template.id,
                        child: Text('${template.name}$suffix'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      final template = roleTemplates.firstWhere(
                        (item) => item.id == value,
                      );
                      setDialogState(() {
                        selectedTemplate = template;
                        permissions
                          ..clear()
                          ..addAll(
                            normalizeModulePermissions(
                              template.modulePermissions,
                            ),
                          );
                      });
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        final defaultTemplate =
                            _templateForMember(member) ?? roleTemplates.first;
                        setDialogState(() {
                          selectedTemplate = defaultTemplate;
                          permissions
                            ..clear()
                            ..addAll(
                              normalizeModulePermissions(
                                selectedTemplate.modulePermissions,
                              ),
                            );
                        });
                      },
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: const Text('Reset to Template Defaults'),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        context.push('/settings/role-templates');
                      },
                      icon: const Icon(Icons.settings_outlined, size: 18),
                      label: const Text('Manage Templates'),
                    ),
                  ],
                ),
                const Divider(),
                ...modulePermissionLabels.entries.map((entry) {
                  final moduleKey = entry.key;
                  final moduleName = entry.value;
                  final currentLevel = permissions[moduleKey] ?? 'read';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          moduleName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          children: modulePermissionLevels.map((level) {
                            final selected = currentLevel == level;
                            return ChoiceChip(
                              label: Text(
                                modulePermissionLevelLabels[level] ?? level,
                              ),
                              selected: selected,
                              onSelected: (_) {
                                setDialogState(() {
                                  permissions[moduleKey] = level;
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 8),
                Text(
                  'Effective Access: ${_permissionSummary(permissions)}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                CheckboxListTile(
                  value: applyToRole,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Apply to all ${_displayRoleNameForMember(member)} members',
                  ),
                  subtitle: const Text(
                    'Updates everyone else with the same role in this workspace.',
                  ),
                  onChanged: (value) {
                    setDialogState(() {
                      applyToRole = value ?? false;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final normalized = normalizeModulePermissions(permissions);
                await _updateMemberSettings(
                  context,
                  member,
                  modulePermissions: normalized,
                );
                if (!context.mounted) return;
                Navigator.pop(context);
                if (applyToRole) {
                  await _applyPermissionsToRoleTemplate(
                    context,
                    sourceMember: member,
                    modulePermissions: normalized,
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders a member's vehicles in the team table row. Shows up to two
/// names inline with a "+N" overflow chip; tap any chip to jump to the
/// vehicle detail. The cell stays empty (subtle dash) when the member
/// has no fleet attachment, since most teams will have non-driver members
/// and a row of "—" is noisier than blank.
class _VehiclesCell extends StatelessWidget {
  final List<Vehicle> vehicles;

  const _VehiclesCell({required this.vehicles});

  @override
  Widget build(BuildContext context) {
    if (vehicles.isEmpty) {
      return const Text(
        '—',
        style: TextStyle(color: AppColors.textTertiary),
      );
    }

    const maxInline = 2;
    final shown = vehicles.take(maxInline).toList();
    final overflow = vehicles.length - shown.length;

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final v in shown)
          _VehicleChip(
            label: v.name.isNotEmpty
                ? v.name
                : (v.licensePlate.isNotEmpty ? v.licensePlate : 'Vehicle'),
            onTap: () => context.push('/vehicles/${v.id}'),
          ),
        if (overflow > 0)
          _VehicleChip(label: '+$overflow', onTap: null, dense: true),
      ],
    );
  }
}

class _VehicleChip extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool dense;

  const _VehicleChip({required this.label, this.onTap, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 8,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!dense) ...[
            const Icon(
              Icons.directions_car,
              size: 13,
              color: AppColors.textTertiary,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: content,
    );
  }
}
