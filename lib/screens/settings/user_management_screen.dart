import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../models/user.dart';
import '../../models/workspace_member.dart';
import '../../models/workspace_role_template.dart';
import '../../providers/auth_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/user_facing_error.dart';
import '../../widgets/workspace_member_tile.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  List<WorkspaceRoleTemplate> _roleTemplates = [];

  String? _lastFetchedIdsKey;
  Future<Map<String, AppUser>>? _usersFuture;

  final _searchController = TextEditingController();
  String _searchQuery = '';
  // null = no role filter; `_adminFilterId` = any admin-access role;
  // otherwise the id of a specific role template.
  static const _adminFilterId = '__admin__';
  String? _filterTemplateId;

  bool _selectionMode = false;
  final Set<String> _selectedUserIds = {};
  bool _bulkBusy = false;

  @override
  void initState() {
    super.initState();
    _loadRoleTemplates();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<WorkspaceMember> _applyFilters(
    List<WorkspaceMember> members,
    Map<String, AppUser> usersById,
  ) {
    final query = _searchQuery.trim().toLowerCase();
    return members.where((m) {
      if (_filterTemplateId == _adminFilterId) {
        if (!m.isAdminRole) return false;
      } else if (_filterTemplateId != null &&
          m.roleTemplateId != _filterTemplateId) {
        return false;
      }
      if (query.isEmpty) return true;
      final user = usersById[m.userId];
      final name = user?.displayName?.toLowerCase() ?? '';
      final email = user?.email.toLowerCase() ?? '';
      return name.contains(query) || email.contains(query);
    }).toList();
  }

  Future<void> _loadRoleTemplates() async {
    final workspaceId =
        context.read<AuthProvider>().appUser?.currentWorkspaceId ?? '';
    if (workspaceId.isEmpty) return;

    try {
      final templates = await ServiceLocator.roleTemplateService.getTemplates(
        workspaceId: workspaceId,
      );
      if (mounted) {
        setState(() {
          _roleTemplates = List<WorkspaceRoleTemplate>.from(templates);
        });
      }
    } catch (_) {}
  }

  Future<Map<String, AppUser>> _fetchUsers(List<String> ids) async {
    final users =
        await ServiceLocator.userService.getUsersByIds(ids) as List<AppUser>;
    return {for (final u in users) u.id: u};
  }

  Future<Map<String, AppUser>> _usersForMembers(List<WorkspaceMember> members) {
    final ids = members.map((m) => m.userId).toSet().toList()..sort();
    final key = ids.join(',');
    if (key != _lastFetchedIdsKey) {
      _lastFetchedIdsKey = key;
      _usersFuture = _fetchUsers(ids);
    }
    return _usersFuture ?? Future.value(const {});
  }

  AppBar _buildSelectionAppBar(String currentUserId) {
    final count = _selectedUserIds.length;
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Exit selection',
        onPressed: _bulkBusy
            ? null
            : () => setState(() {
                  _selectionMode = false;
                  _selectedUserIds.clear();
                }),
      ),
      title: Text(count == 0
          ? 'Select members'
          : '$count selected'),
    );
  }

  Widget _buildSelectionToolbar({
    required List<WorkspaceMember> visibleMembers,
    required String currentUserId,
  }) {
    final selectableIds = visibleMembers
        .where((m) => m.userId != currentUserId)
        .map((m) => m.userId)
        .toSet();
    final allSelected = selectableIds.isNotEmpty &&
        selectableIds.every(_selectedUserIds.contains);
    final hasSelection = _selectedUserIds.isNotEmpty;

    return Material(
      color: AppColors.primarySurface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
        child: Row(
          children: [
            TextButton.icon(
              onPressed: _bulkBusy || selectableIds.isEmpty
                  ? null
                  : () => setState(() {
                        if (allSelected) {
                          _selectedUserIds.removeAll(selectableIds);
                        } else {
                          _selectedUserIds.addAll(selectableIds);
                        }
                      }),
              icon: Icon(
                allSelected
                    ? Icons.deselect
                    : Icons.select_all,
                size: 18,
              ),
              label: Text(allSelected ? 'Deselect all' : 'Select all visible'),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed:
                  _bulkBusy || !hasSelection || _roleTemplates.isEmpty
                      ? null
                      : _bulkAssignRole,
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: const Text('Change role'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: _bulkBusy || !hasSelection ? null : _bulkRemove,
              icon: _bulkBusy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.person_remove, size: 18),
              label: const Text('Remove'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _bulkAssignRole() async {
    if (_roleTemplates.isEmpty || _selectedUserIds.isEmpty) return;

    final workspaceId =
        context.read<AuthProvider>().appUser?.currentWorkspaceId ?? '';
    String selectedId = _roleTemplates.first.id;
    final confirmed = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            'Change role for ${_selectedUserIds.length} member'
            '${_selectedUserIds.length == 1 ? '' : 's'}',
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select the role to assign to the selected members.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: _roleTemplates.map((t) {
                    return DropdownMenuItem<String>(
                      value: t.id,
                      child: Row(
                        children: [
                          Icon(
                            t.isAdmin
                                ? Icons.admin_panel_settings
                                : Icons.person_outline,
                            size: 18,
                            color: t.isAdmin
                                ? AppColors.messageAccent
                                : AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              t.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedId = value);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, selectedId),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == null) return;

    setState(() => _bulkBusy = true);
    final failed = <String>[];
    for (final userId in _selectedUserIds.toList()) {
      try {
        await ServiceLocator.workspaceMemberService.updateMemberRoleTemplate(
          workspaceId: workspaceId,
          userId: userId,
          roleTemplateId: confirmed,
        );
      } catch (e) {
        failed.add(UserFacingError.uiMessage(e, action: 'update the role'));
      }
    }
    if (!mounted) return;
    setState(() {
      _bulkBusy = false;
      _selectedUserIds.clear();
      _selectionMode = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed.isEmpty
              ? 'Role updated for all selected members.'
              : '${failed.length} update${failed.length == 1 ? '' : 's'} failed. '
                  'First error: ${failed.first}',
        ),
        backgroundColor:
            failed.isEmpty ? AppColors.success : AppColors.error,
        duration: Duration(seconds: failed.isEmpty ? 4 : 10),
      ),
    );
  }

  Future<void> _bulkRemove() async {
    if (_selectedUserIds.isEmpty) return;

    final workspaceId =
        context.read<AuthProvider>().appUser?.currentWorkspaceId ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Remove ${_selectedUserIds.length} member'
          '${_selectedUserIds.length == 1 ? '' : 's'}?',
        ),
        content: const Text(
          'They will lose access to this workspace immediately. This '
          'cannot be undone from this screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _bulkBusy = true);
    final failed = <String>[];
    for (final userId in _selectedUserIds.toList()) {
      try {
        await ServiceLocator.workspaceMemberService.removeMember(
          workspaceId: workspaceId,
          userId: userId,
        );
      } catch (e) {
        failed.add(UserFacingError.uiMessage(e, action: 'remove the member'));
      }
    }
    if (!mounted) return;
    setState(() {
      _bulkBusy = false;
      _selectedUserIds.clear();
      _selectionMode = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed.isEmpty
              ? 'Members removed.'
              : '${failed.length} removal${failed.length == 1 ? '' : 's'} failed. '
                  'First error: ${failed.first}',
        ),
        backgroundColor:
            failed.isEmpty ? AppColors.success : AppColors.error,
        duration: Duration(seconds: failed.isEmpty ? 4 : 10),
      ),
    );
  }

  Widget _buildFilterBar(int total, int visible) {
    final showCount = _searchQuery.isNotEmpty || _filterTemplateId != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by name or email',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                  ),
                  onChanged: (value) =>
                      setState(() => _searchQuery = value),
                ),
              ),
              const SizedBox(width: 12),
              if (_roleTemplates.isNotEmpty)
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _filterTemplateId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      labelText: 'Role',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All roles'),
                      ),
                      DropdownMenuItem<String?>(
                        value: _adminFilterId,
                        child: Row(
                          children: [
                            Icon(
                              Icons.admin_panel_settings,
                              size: 16,
                              color: AppColors.messageAccent,
                            ),
                            const SizedBox(width: 6),
                            const Text('Admin access'),
                          ],
                        ),
                      ),
                      ..._roleTemplates.map((t) {
                        return DropdownMenuItem<String?>(
                          value: t.id,
                          child: Text(
                            t.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                    ],
                    onChanged: (value) =>
                        setState(() => _filterTemplateId = value),
                  ),
                ),
            ],
          ),
          if (showCount)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: Text(
                'Showing $visible of $total members',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.appUser;

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('User Management')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final canManageUsers = authProvider.canManageUsers;

    return Scaffold(
      appBar: _selectionMode
          ? _buildSelectionAppBar(currentUser.id)
          : AppBar(
              title: const Text('User Management'),
              actions: [
                if (canManageUsers)
                  IconButton(
                    icon: const Icon(Icons.checklist),
                    tooltip: 'Select multiple',
                    onPressed: () {
                      setState(() {
                        _selectionMode = true;
                        _selectedUserIds.clear();
                      });
                    },
                  ),
                if (canManageUsers)
                  IconButton(
                    icon: const Icon(Icons.person_add),
                    onPressed: () {
                      context.push(
                        '/settings/invite?workspaceId=${currentUser.currentWorkspaceId}',
                      );
                    },
                    tooltip: 'Invite User',
                  ),
              ],
            ),
      body: StreamBuilder<List<WorkspaceMember>>(
        stream: ServiceLocator.workspaceMemberService.getWorkspaceMembers(
          currentUser.currentWorkspaceId,
        ),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: SelectableText(
                  UserFacingError.uiMessage(
                    snapshot.error,
                    action: 'load members',
                  ),
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final members = snapshot.data ?? [];

          if (members.isEmpty) {
            return const Center(child: Text('No members found'));
          }

          return FutureBuilder<Map<String, AppUser>>(
            future: _usersForMembers(members),
            builder: (context, usersSnap) {
              if (!usersSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final usersById = usersSnap.data!;
              final visible = _applyFilters(members, usersById);

              return Column(
                children: [
                  if (_selectionMode)
                    _buildSelectionToolbar(
                      visibleMembers: visible,
                      currentUserId: currentUser.id,
                    )
                  else
                    _buildFilterBar(members.length, visible.length),
                  Expanded(
                    child: visible.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.xl),
                              child: Text(
                                'No members match your filters.',
                                style: TextStyle(
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: visible.length,
                            itemBuilder: (context, index) {
                              final member = visible[index];
                              final isCurrentUser =
                                  member.userId == currentUser.id;

                              final canSelect = !isCurrentUser;
                              return WorkspaceMemberTile(
                                member: member,
                                user: usersById[member.userId],
                                isCurrentUser: isCurrentUser,
                                canManageUsers: canManageUsers,
                                roleTemplates: _roleTemplates,
                                selectionMode: _selectionMode,
                                isSelected:
                                    _selectedUserIds.contains(member.userId),
                                onSelectionToggle: _selectionMode && canSelect
                                    ? () => setState(() {
                                          if (_selectedUserIds
                                              .contains(member.userId)) {
                                            _selectedUserIds.remove(member.userId);
                                          } else {
                                            _selectedUserIds.add(member.userId);
                                          }
                                        })
                                    : null,
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
