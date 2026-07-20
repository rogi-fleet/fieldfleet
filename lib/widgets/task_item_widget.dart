import 'package:flutter/material.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:go_router/go_router.dart';
import '../models/task.dart';
import '../models/user.dart';
import '../services/service_locator.dart';
import '../theme/theme.dart';
import 'user_avatar.dart';

class TaskItemWidget extends StatelessWidget {
  final Task task;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const TaskItemWidget({
    super.key,
    required this.task,
    required this.onTap,
    required this.onDelete,
  });

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isOverdue = task.isOverdue();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      child: ListTile(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: task.isComplete,
              onChanged: (bool? value) async {
                try {
                  await ServiceLocator.taskService.toggleTaskCompletion(
                    task.id,
                    task.isComplete,
                  );
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          UserFacingError.uiMessage(e, action: 'updating task'),
                        ),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                }
              },
            ),
            // Show assigned user avatars (using new assignedToIds list)
            if (task.assignedToIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...task.assignedToIds
                        .take(3)
                        .map(
                          (userId) => Padding(
                            padding: const EdgeInsets.only(right: 2.0),
                            child: FutureBuilder<AppUser?>(
                              future: ServiceLocator.userService.getUserById(
                                userId,
                              ),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return CircleAvatar(
                                    radius: 12,
                                    backgroundColor: AppColors.cardBorder,
                                    child: const Icon(
                                      Icons.person,
                                      size: 14,
                                      color: AppColors.textTertiary,
                                    ),
                                  );
                                }
                                return Tooltip(
                                  message:
                                      snapshot.data?.displayName ??
                                      snapshot.data?.email ??
                                      'Unknown',
                                  child: UserAvatar(
                                    user: snapshot.data,
                                    size: AvatarSize.small,
                                    onTap: () {
                                      context.push('/profile/$userId');
                                    },
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                    if (task.assignedToIds.length > 3)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.cardBorder,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Text(
                          '+${task.assignedToIds.length - 3}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
        title: Text(
          task.title,
          style: TextStyle(
            decoration: task.isComplete ? TextDecoration.lineThrough : null,
            color: task.isComplete ? AppColors.textTertiary : null,
          ),
        ),
        subtitle: task.dueDate != null
            ? Text(
                'Due: ${_formatDate(task.dueDate!)}',
                style: TextStyle(
                  color: isOverdue ? AppColors.error : AppColors.textTertiary,
                  fontWeight: isOverdue ? FontWeight.bold : FontWeight.normal,
                ),
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isOverdue)
              const Padding(
                padding: EdgeInsets.only(right: 8.0),
                child: Icon(Icons.warning, color: AppColors.error, size: 20),
              ),
            if (task.requiredAssetIds.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(right: 8.0),
                child: Icon(
                  Icons.inventory_2,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
              ),
            IconButton(
              icon: const Icon(Icons.delete, color: AppColors.error),
              onPressed: onDelete,
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
