import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../models/app_notification.dart';
import '../providers/auth_provider.dart';
import '../services/service_locator.dart';
import '../services/notification_navigation_service.dart';
import '../theme/theme.dart';

/// Shows the notification panel as a bottom sheet on mobile, dialog on desktop
void showNotificationPanel(BuildContext context) {
  final isMobile = MediaQuery.of(context).size.width < AppBreakpoints.mobile;

  if (isMobile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _NotificationBottomSheet(),
    );
  } else {
    showDialog(
      context: context,
      builder: (context) => const _NotificationDialog(),
    );
  }
}

class _NotificationBottomSheet extends StatelessWidget {
  const _NotificationBottomSheet();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Expanded(
                child: _NotificationContent(scrollController: scrollController),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NotificationDialog extends StatelessWidget {
  const _NotificationDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: const _NotificationContent(),
      ),
    );
  }
}

class _NotificationContent extends StatelessWidget {
  final ScrollController? scrollController;

  const _NotificationContent({this.scrollController});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.appUser;

    if (currentUser == null) {
      return const Center(child: Text('Not signed in'));
    }

    final notificationService = ServiceLocator.notificationService;

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          child: Row(
            children: [
              const Text(
                'Notifications',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  notificationService.markAllAsRead(
                    userId: currentUser.id,
                    workspaceId: currentUser.currentWorkspaceId,
                  );
                },
                child: const Text('Mark all read'),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Notification list
        Expanded(
          child: StreamBuilder<List<AppNotification>>(
            stream: notificationService.getNotifications(
              userId: currentUser.id,
              workspaceId: currentUser.currentWorkspaceId,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                );
              }

              final notifications = snapshot.data ?? [];

              if (notifications.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.notifications_none,
                        size: 56,
                        color: AppColors.cardBorder,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No notifications yet',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                itemCount: notifications.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 60),
                itemBuilder: (context, index) {
                  return _NotificationTile(notification: notifications[index]);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;

  const _NotificationTile({required this.notification});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _onTap(context),
      child: Container(
        color: notification.isRead
            ? null
            : AppColors.infoLight.withValues(alpha: 0.3),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(_icon, size: 18, color: _iconColor),
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: notification.isRead
                          ? FontWeight.w400
                          : FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (notification.body != null &&
                      notification.body!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      notification.body!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    _timeAgo(notification.createdAt),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            // Unread indicator
            if (!notification.isRead)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6, left: 8),
                decoration: const BoxDecoration(
                  color: AppColors.info,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData get _icon {
    switch (notification.type) {
      case 'mention':
        return Icons.alternate_email;
      case 'task_assignment':
        return Icons.assignment_ind;
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
      case 'project_update':
        return Icons.edit_calendar_outlined;
      case 'capacity_alert':
        return Icons.groups_2_outlined;
      case 'priority_alert':
        return Icons.priority_high;
      case 'ai_plan_ready':
        return Icons.auto_awesome;
      case 'ai_plan_failed':
        return Icons.error_outline;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color get _iconColor {
    switch (notification.type) {
      case 'mention':
        return AppColors.info;
      case 'task_assignment':
        return AppColors.secondary;
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
      case 'project_update':
        return AppColors.info;
      case 'capacity_alert':
        return AppColors.warning;
      case 'priority_alert':
        return AppColors.error;
      case 'ai_plan_ready':
        return AppColors.secondaryDark;
      case 'ai_plan_failed':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  void _onTap(BuildContext context) {
    // Mark as read
    ServiceLocator.notificationService.markAsRead(notification.id);

    Navigator.pop(context);
    context.go(
      NotificationNavigationService.routeForNotification(notification),
    );
  }

  String _timeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  }
}
