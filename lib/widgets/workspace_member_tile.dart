import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/role_permissions.dart';
import '../models/user.dart';
import '../models/workspace_role_template.dart';
import '../theme/theme.dart';
import '../models/workspace_member.dart';

import '../services/service_locator.dart';
import '../utils/module_permissions.dart';
import '../utils/user_facing_error.dart';
import '../widgets/user_avatar.dart';

class WorkspaceMemberTile extends StatelessWidget {
  final WorkspaceMember member;
  final bool isCurrentUser;
  final bool canManageUsers;
  final List<WorkspaceRoleTemplate> roleTemplates;

  /// When provided, skips the per-tile user fetch. Callers that render a list
  /// of tiles should batch-fetch user docs and pass them in to avoid N+1.
  final AppUser? user;

  /// When true, renders a selection checkbox in place of the actions menu
  /// and calls [onSelectionToggle] on any tap instead of navigating to the
  /// member's profile.
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback? onSelectionToggle;

  const WorkspaceMemberTile({
    super.key,
    required this.member,
    required this.isCurrentUser,
    required this.canManageUsers,
    this.roleTemplates = const [],
    this.user,
    this.selectionMode = false,
    this.isSelected = false,
    this.onSelectionToggle,
  });

  Future<void> _updateMemberRoleTemplate(
    BuildContext context,
    WorkspaceRoleTemplate template,
  ) async {
    if (_currentTemplate?.id == template.id) return;
    if (!await _confirmRoleDowngrade(context, template)) return;
    try {
      await ServiceLocator.workspaceMemberService.updateMemberRoleTemplate(
        workspaceId: member.workspaceId,
        userId: member.userId,
        roleTemplateId: template.id,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Updated role to ${template.name}'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: SelectableText(
              UserFacingError.uiMessage(e, action: 'update the role'),
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 10),
          ),
        );
      }
    }
  }

  Future<void> _removeMember(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Member'),
        content: const Text(
          'Are you sure you want to remove this user from the workspace?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      try {
        await ServiceLocator.workspaceMemberService.removeMember(
          workspaceId: member.workspaceId,
          userId: member.userId,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Member removed successfully'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: SelectableText(
                UserFacingError.uiMessage(e, action: 'remove the member'),
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: AppColors.error,
              duration: const Duration(seconds: 10),
            ),
          );
        }
      }
    }
  }

  String get _displayRoleName =>
      _currentTemplate?.name ??
      member.roleTemplateName ??
      member.role.displayName;

  bool get _isAdminRole => member.isAdminRole;

  WorkspaceRoleTemplate? get _currentTemplate {
    for (final t in roleTemplates) {
      if (t.id == member.roleTemplateId) return t;
    }
    for (final t in roleTemplates) {
      if (member.roleTemplateName != null &&
          t.name == member.roleTemplateName) {
        return t;
      }
    }
    for (final t in roleTemplates) {
      if (t.isSystem && t.role == member.role) return t;
    }
    return null;
  }

  Map<String, String> get _effectivePermissions {
    final template = _currentTemplate;
    if (template != null) {
      if (template.isAdmin) {
        return {for (final key in modulePermissionLabels.keys) key: 'write'};
      }
      return normalizeModulePermissions(template.modulePermissions);
    }
    if (_isAdminRole) {
      return {for (final key in modulePermissionLabels.keys) key: 'write'};
    }
    if (member.modulePermissions.isNotEmpty) {
      return normalizeModulePermissions(member.modulePermissions);
    }
    return normalizeModulePermissions(defaultPermissionsForRole(member.role));
  }

  Color _colorForPermissions({
    required bool isAdmin,
    required Map<String, String> permissions,
  }) {
    if (isAdmin) return AppColors.messageAccent;

    final rolePermissions = RolePermissions(
      roleName: _displayRoleName,
      isAdmin: false,
      modulePermissions: normalizeModulePermissions(permissions),
    );

    if (rolePermissions.isClientMode) return AppColors.success;
    if (rolePermissions.hasModuleAccess('projects', 'write') ||
        rolePermissions.hasModuleAccess('budget', 'write') ||
        rolePermissions.hasModuleAccess('team', 'write') ||
        rolePermissions.hasModuleAccess('settings', 'read')) {
      return AppColors.info;
    }

    return AppColors.warning;
  }

  Future<void> _showRoleScorecard(BuildContext context) async {
    final template = _currentTemplate;
    final permissions = _effectivePermissions;
    final description = template?.description;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              _isAdminRole ? Icons.admin_panel_settings : Icons.shield_outlined,
              color: _getRoleChipColor(),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(_displayRoleName)),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (description != null && description.isNotEmpty) ...[
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (_isAdminRole)
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.messageAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.verified_user,
                        size: 18,
                        color: AppColors.messageAccent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Full admin access — every module is editable.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.messageAccent,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                Text(
                  'MODULE ACCESS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textTertiary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                ...modulePermissionLabels.entries.map((entry) {
                  final level = permissions[entry.key] ?? 'none';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Row(
                      children: [
                        Expanded(child: Text(entry.value)),
                        _buildScorecardBadge(level),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildScorecardBadge(String level) {
    final label = modulePermissionLevelLabels[level] ?? level;
    Color color;
    IconData icon;
    switch (level) {
      case 'write':
        color = AppColors.success;
        icon = Icons.edit_outlined;
        break;
      case 'read':
        color = AppColors.info;
        icon = Icons.visibility_outlined;
        break;
      default:
        color = AppColors.textTertiary;
        icon = Icons.block_outlined;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Returns false if the user cancels a destructive role change.
  /// Returns true if no confirmation is needed or the user proceeds.
  Future<bool> _confirmRoleDowngrade(
    BuildContext context,
    WorkspaceRoleTemplate next,
  ) async {
    final losses = _describeDowngrades(next);
    if (losses.isEmpty) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Change role to "${next.name}"?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This user will lose the following access:'),
            const SizedBox(height: 12),
            ...losses.map(
              (l) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(child: Text(l)),
                  ],
                ),
              ),
            ),
          ],
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
    return result ?? false;
  }

  /// Produces human-readable bullets describing what access the member
  /// will lose going from the current effective permissions to [next].
  /// Empty list means the change is neutral or an upgrade.
  List<String> _describeDowngrades(WorkspaceRoleTemplate next) {
    // If the new role is admin, they gain everything — never a downgrade.
    if (next.isAdmin) return const [];

    // Moving off an admin template (or legacy admin role) is always a
    // material downgrade regardless of the module comparison.
    final wasAdmin = _isAdminRole;
    if (wasAdmin) {
      return const ['Full admin access — including all modules'];
    }

    const rank = {'none': 0, 'read': 1, 'write': 2};
    final currentPermissions = _effectivePermissions;
    final nextPermissions = normalizeModulePermissions(next.modulePermissions);
    final losses = <String>[];
    for (final entry in modulePermissionLabels.entries) {
      final moduleKey = entry.key;
      final oldLevel = currentPermissions[moduleKey] ?? 'none';
      final newLevel = nextPermissions[moduleKey] ?? 'none';
      final oldRank = rank[oldLevel] ?? 0;
      final newRank = rank[newLevel] ?? 0;
      if (newRank < oldRank) {
        final oldLabel = modulePermissionLevelLabels[oldLevel] ?? oldLevel;
        final newLabel = modulePermissionLevelLabels[newLevel] ?? newLevel;
        losses.add('${entry.value}: $oldLabel → $newLabel');
      }
    }
    return losses;
  }

  @override
  Widget build(BuildContext context) {
    if (user != null) return _buildTile(context, user!);

    return FutureBuilder<AppUser?>(
      future: ServiceLocator.authService.getUserDocument(member.userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            margin: EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
            child: ListTile(
              leading: CircleAvatar(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              title: Text('Loading...'),
            ),
          );
        }

        final resolved = snapshot.data;
        if (resolved == null) {
          return const SizedBox.shrink();
        }
        return _buildTile(context, resolved);
      },
    );
  }

  Widget _buildTile(BuildContext context, AppUser user) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      color: selectionMode && isSelected ? AppColors.primarySurface : null,
      child: ListTile(
        leading: UserAvatar(
          user: user,
          size: AvatarSize.medium,
          onTap: selectionMode
              ? onSelectionToggle
              : () {
                  context.push('/profile/${user.id}');
                },
        ),
        title: Text(
          user.displayName ?? user.email,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user.email),
            if (user.jobTitle != null || user.companyName != null) ...[
              const SizedBox(height: 2),
              Text(
                [
                  user.jobTitle,
                  user.companyName,
                ].where((e) => e != null && e.isNotEmpty).join(' at '),
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
              ),
            ],
            const SizedBox(height: 4),
            InkWell(
              onTap: () => _showRoleScorecard(context),
              borderRadius: BorderRadius.circular(AppRadius.r16),
              child: Chip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _displayRoleName,
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: _getRoleChipColor(),
                    ),
                  ],
                ),
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: _getRoleChipColor().withValues(alpha: 0.2),
                labelStyle: TextStyle(
                  color: _getRoleChipColor(),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        trailing: selectionMode
            ? Checkbox(
                value: isSelected,
                onChanged: onSelectionToggle == null
                    ? null
                    : (_) => onSelectionToggle!(),
              )
            : isCurrentUser
            ? const Chip(
                label: Text('You'),
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              )
            : canManageUsers
            ? _buildPopupMenu(context)
            : null,
        onTap: selectionMode
            ? onSelectionToggle
            : () {
                context.push('/profile/${user.id}');
              },
      ),
    );
  }

  Widget _buildPopupMenu(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        if (value == 'remove') {
          _removeMember(context);
        } else if (value.startsWith('template_')) {
          final templateId = value.substring('template_'.length);
          final template = roleTemplates.firstWhere((t) => t.id == templateId);
          _updateMemberRoleTemplate(context, template);
        }
      },
      itemBuilder: (context) {
        final systemTemplates = roleTemplates.where((t) => t.isSystem).toList();
        final customTemplates = roleTemplates
            .where((t) => !t.isSystem)
            .toList();

        final items = <PopupMenuEntry<String>>[];

        if (systemTemplates.isNotEmpty) {
          items.add(_buildSectionHeader('System roles'));
          items.addAll(systemTemplates.map(_buildTemplateMenuItem));
        }

        if (customTemplates.isNotEmpty) {
          if (systemTemplates.isNotEmpty) {
            items.add(const PopupMenuDivider());
          }
          items.add(_buildSectionHeader('Custom roles'));
          items.addAll(customTemplates.map(_buildTemplateMenuItem));
        }

        if (items.isNotEmpty) {
          items.add(const PopupMenuDivider());
        }
        items.add(
          PopupMenuItem<String>(
            value: 'remove',
            child: Row(
              children: [
                Icon(Icons.person_remove, color: AppColors.error),
                const SizedBox(width: 12),
                Text('Remove Member', style: TextStyle(color: AppColors.error)),
              ],
            ),
          ),
        );
        return items;
      },
    );
  }

  PopupMenuEntry<String> _buildSectionHeader(String label) {
    return PopupMenuItem<String>(
      enabled: false,
      height: 32,
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textTertiary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  PopupMenuEntry<String> _buildTemplateMenuItem(
    WorkspaceRoleTemplate template,
  ) {
    final isSelected = _currentTemplate?.id == template.id;
    return PopupMenuItem<String>(
      value: 'template_${template.id}',
      child: Row(
        children: [
          Icon(
            isSelected ? Icons.check_circle : Icons.circle_outlined,
            size: 20,
            color: _colorForPermissions(
              isAdmin: template.isAdmin,
              permissions: template.modulePermissions,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(template.name)),
          if (template.isAdmin) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.admin_panel_settings,
              size: 16,
              color: AppColors.messageAccent,
            ),
          ],
        ],
      ),
    );
  }

  Color _getRoleChipColor() {
    return _colorForPermissions(
      isAdmin: _isAdminRole,
      permissions: _effectivePermissions,
    );
  }
}
