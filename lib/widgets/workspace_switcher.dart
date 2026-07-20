import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../providers/workspace_provider.dart';

import 'workspace_avatar.dart';
import '../theme/theme.dart';

class WorkspaceSwitcher extends StatefulWidget {
  final Color? contentColor;

  const WorkspaceSwitcher({super.key, this.contentColor});

  @override
  State<WorkspaceSwitcher> createState() => _WorkspaceSwitcherState();
}

class _WorkspaceSwitcherState extends State<WorkspaceSwitcher> {
  bool _isSwitching = false;
  String? _lastLoadedUserId;
  String? _lastSyncedWorkspaceId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Load workspaces when user becomes available
    final authProvider = context.watch<AuthProvider>();
    final userId = authProvider.appUser?.id;
    final currentWorkspaceId = authProvider.appUser?.currentWorkspaceId;

    // Keep WorkspaceProvider in sync, but never notify during build.
    if (currentWorkspaceId != null &&
        currentWorkspaceId != _lastSyncedWorkspaceId) {
      _lastSyncedWorkspaceId = currentWorkspaceId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<WorkspaceProvider>().setCurrentWorkspaceId(
          currentWorkspaceId,
        );
      });
    }

    // Only load if we have a user and haven't loaded for this user yet
    if (userId != null && userId != _lastLoadedUserId) {
      print('WorkspaceSwitcher: User changed to $userId, loading workspaces');
      _lastLoadedUserId = userId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<WorkspaceProvider>().loadWorkspaces(userId);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final workspaceProvider = context.watch<WorkspaceProvider>();
    final currentUser = authProvider.appUser;
    final canManageWorkspaceMembers =
        authProvider.canManageUsers || authProvider.canAccessSettings;

    if (currentUser == null) return const SizedBox.shrink();

    // Find current workspace name
    final currentWorkspaceId = currentUser.currentWorkspaceId;
    final currentMembership = workspaceProvider.workspaces
        .where((w) => w.workspaceId == currentWorkspaceId)
        .firstOrNull;

    final currentWorkspaceName =
        currentMembership?.workspaceName ?? 'Current Workspace';

    // If only one workspace, show static display without dropdown
    if (workspaceProvider.workspaces.length <= 1 &&
        !workspaceProvider.isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
        child: Row(
          children: [
            WorkspaceAvatar(
              avatarUrl: currentMembership?.avatarUrl,
              workspaceName: currentWorkspaceName,
              size: WorkspaceAvatarSize.small,
            ),
            const SizedBox(width: 8),
            Expanded(
              // Tooltip so the user can read the full name when it's
              // truncated to fit the sidebar column.
              child: Tooltip(
                message: currentWorkspaceName,
                child: Text(
                  currentWorkspaceName,
                  style: TextStyle(
                    color: widget.contentColor ?? Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return PopupMenuButton<String>(
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      tooltip: 'Switch Workspace',
      itemBuilder: (context) {
        if (workspaceProvider.isLoading) {
          return [
            const PopupMenuItem(
              enabled: false,
              child: Center(child: CircularProgressIndicator()),
            ),
          ];
        }

        if (workspaceProvider.workspaces.isEmpty) {
          return [
            const PopupMenuItem(
              enabled: false,
              child: Text('No other workspaces'),
            ),
          ];
        }

        return [
          const PopupMenuItem(
            enabled: false,
            child: Text(
              'SWITCH WORKSPACE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          ...workspaceProvider.workspaces.map((workspace) {
            final isSelected = workspace.workspaceId == currentWorkspaceId;
            return PopupMenuItem<String>(
              value: workspace.workspaceId,
              child: Row(
                children: [
                  WorkspaceAvatar(
                    avatarUrl: workspace.avatarUrl,
                    workspaceName: workspace.workspaceName,
                    size: WorkspaceAvatarSize.small,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          workspace.workspaceName,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          workspace.displayRoleName,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    Icon(
                      Icons.check,
                      color: Theme.of(context).primaryColor,
                      size: 20,
                    ),
                ],
              ),
            );
          }),
          const PopupMenuDivider(),
          if (canManageWorkspaceMembers)
            PopupMenuItem<String>(
              value: 'invite_members',
              child: Row(
                children: [
                  Icon(
                    Icons.person_add,
                    size: 20,
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Invite Members',
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          if (canManageWorkspaceMembers)
            const PopupMenuItem<String>(
              value: 'workspace_settings',
              child: Row(
                children: [
                  Icon(Icons.settings, size: 20),
                  SizedBox(width: 12),
                  Text('Workspace Settings'),
                ],
              ),
            ),
          const PopupMenuItem<String>(
            value: 'create_new',
            child: Row(
              children: [
                Icon(Icons.add, size: 20),
                SizedBox(width: 12),
                Text('Create New Workspace'),
              ],
            ),
          ),
        ];
      },
      onSelected: (value) async {
        if (value == 'create_new') {
          context.go('/onboarding?newWorkspace=true');
        } else if (value == 'workspace_settings') {
          if (!canManageWorkspaceMembers) return;
          context.go('/workspaces/settings');
        } else if (value == 'invite_members') {
          if (!canManageWorkspaceMembers) return;
          context.push('/settings/invite?workspaceId=$currentWorkspaceId');
        } else if (value != currentWorkspaceId) {
          setState(() => _isSwitching = true);
          try {
            await authProvider.switchWorkspace(value);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Switched workspace successfully'),
                ),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: SelectableText(
                    'Error switching workspace: $e',
                    style: const TextStyle(color: Colors.white),
                  ),
                  backgroundColor: AppColors.error,
                  duration: const Duration(seconds: 10),
                ),
              );
            }
          } finally {
            if (mounted) {
              setState(() => _isSwitching = false);
            }
          }
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
        child: _isSwitching
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                children: [
                  WorkspaceAvatar(
                    avatarUrl: currentMembership?.avatarUrl,
                    workspaceName: currentWorkspaceName,
                    size: WorkspaceAvatarSize.small,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Tooltip(
                      message: currentWorkspaceName,
                      child: Text(
                        currentWorkspaceName,
                        style: TextStyle(
                          color: widget.contentColor ?? Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_drop_down,
                    color: widget.contentColor ?? Colors.black54,
                  ),
                ],
              ),
      ),
    );
  }
}
