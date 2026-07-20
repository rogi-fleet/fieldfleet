import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../services/service_locator.dart';
import '../../services/notification_navigation_service.dart';
import '../../services/supabase/workspace_notification_prefs_service.dart';
import '../../models/app_notification.dart';
import '../../theme/theme.dart';
import '../../widgets/common/module_header.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final appUser = authProvider.appUser;
    final workspaceId = appUser?.currentWorkspaceId;

    if (workspaceId == null || appUser == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final notificationService = ServiceLocator.notificationService;

    return Scaffold(
      // Content surface — without this the notification titles (which use the
      // default text color) render dark-on-dark over the chrome background.
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          ModuleHeader(
            icon: Icons.notifications_outlined,
            title: 'Notifications',
            description:
                'Recent alerts and activity across your workspace.',
            trailing: [
              _MuteMenuButton(userId: appUser.id, workspaceId: workspaceId),
              TextButton(
                onPressed: () => notificationService.markAllAsRead(
                  userId: appUser.id,
                  workspaceId: workspaceId,
                ),
                child: const Text('Mark all as read'),
              ),
            ],
          ),
          Expanded(
            child: StreamBuilder<List<AppNotification>>(
        stream: notificationService.getNotifications(
          userId: appUser.id,
          workspaceId: workspaceId,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final notifications = snapshot.data ?? [];

          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 64,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'No notifications yet',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: notifications.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final notification = notifications[index];
              return _NotificationTile(
                notification: notification,
                onTap: () {
                  // Mark as read
                  if (!notification.isRead) {
                    notificationService.markAsRead(notification.id);
                  }

                  context.go(
                    NotificationNavigationService.routeForNotification(
                      notification,
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    ),
  ],
  ),
);
  }
}

class _MuteMenuButton extends StatefulWidget {
  final String userId;
  final String workspaceId;

  const _MuteMenuButton({required this.userId, required this.workspaceId});

  @override
  State<_MuteMenuButton> createState() => _MuteMenuButtonState();
}

class _MuteMenuButtonState extends State<_MuteMenuButton> {
  final _service = WorkspaceNotificationPrefsService();

  Future<void> _setMute(Duration? duration) async {
    final until = duration == null ? null : DateTime.now().add(duration);
    try {
      await _service.setMutedUntil(
        userId: widget.userId,
        workspaceId: widget.workspaceId,
        until: until,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update workspace mute')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DateTime?>(
      stream: _service.watchMutedUntil(
        userId: widget.userId,
        workspaceId: widget.workspaceId,
      ),
      builder: (context, snapshot) {
        final mutedUntil = snapshot.data;
        final isMuted = mutedUntil != null;
        return PopupMenuButton<String>(
          tooltip: isMuted ? 'Workspace muted' : 'Mute workspace notifications',
          icon: Icon(
            isMuted ? Icons.notifications_off : Icons.notifications_active,
            size: 20,
          ),
          onSelected: (value) {
            switch (value) {
              case '1h':
                _setMute(const Duration(hours: 1));
                break;
              case '8h':
                _setMute(const Duration(hours: 8));
                break;
              case '24h':
                _setMute(const Duration(hours: 24));
                break;
              case 'forever':
                _setMute(const Duration(days: 365 * 10));
                break;
              case 'unmute':
                _setMute(null);
                break;
            }
          },
          itemBuilder: (context) => [
            if (isMuted)
              const PopupMenuItem(
                value: 'unmute',
                child: Text('Unmute this workspace'),
              )
            else ...[
              const PopupMenuItem(value: '1h', child: Text('Mute for 1 hour')),
              const PopupMenuItem(value: '8h', child: Text('Mute for 8 hours')),
              const PopupMenuItem(value: '24h', child: Text('Mute for 24 hours')),
              const PopupMenuItem(
                value: 'forever',
                child: Text('Mute until I unmute'),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const _NotificationTile({required this.notification, required this.onTap});

  IconData _iconForType(String type) {
    switch (type) {
      case 'mention':
        return Icons.alternate_email;
      case 'task_assignment':
        return Icons.person_add_outlined;
      case 'task_completion':
        return Icons.check_circle_outline;
      case 'workspace_member_joined':
        return Icons.group_add_outlined;
      case 'time_entry_submitted':
        return Icons.pending_actions_outlined;
      case 'time_entry_approved':
        return Icons.approval_outlined;
      case 'time_entry_rejected':
        return Icons.cancel_outlined;
      case 'document_signed':
        return Icons.draw_outlined;
      case 'agreement_signed':
        return Icons.assignment_turned_in_outlined;
      case 'project_update':
        return Icons.edit_calendar_outlined;
      case 'capacity_alert':
        return Icons.groups_2_outlined;
      case 'priority_alert':
        return Icons.priority_high;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _iconColorForType(String type) {
    switch (type) {
      case 'mention':
        return AppColors.info;
      case 'task_assignment':
        return AppColors.primary;
      case 'task_completion':
        return AppColors.success;
      case 'workspace_member_joined':
        return AppColors.primary;
      case 'time_entry_submitted':
        return AppColors.warning;
      case 'time_entry_approved':
        return AppColors.success;
      case 'time_entry_rejected':
        return AppColors.error;
      case 'document_signed':
        return AppColors.success;
      case 'agreement_signed':
        return AppColors.success;
      case 'project_update':
        return AppColors.info;
      case 'capacity_alert':
        return AppColors.warning;
      case 'priority_alert':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  String _timeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dateTime.month}/${dateTime.day}/${dateTime.year}';
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _iconColorForType(
          notification.type,
        ).withValues(alpha: 0.1),
        child: Icon(
          _iconForType(notification.type),
          color: _iconColorForType(notification.type),
          size: 20,
        ),
      ),
      title: Text(
        notification.title,
        style: TextStyle(
          fontWeight: notification.isRead ? FontWeight.normal : FontWeight.w600,
          fontSize: 14,
        ),
      ),
      subtitle: notification.body != null && notification.body!.isNotEmpty
          ? Text(
              notification.body!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            )
          : null,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _timeAgo(notification.createdAt),
            style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
          ),
          if (!notification.isRead)
            Container(
              margin: const EdgeInsets.only(top: 4),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
      tileColor: notification.isRead
          ? null
          : AppColors.primary.withValues(alpha: 0.04),
      onTap: onTap,
    );
  }
}
