import 'package:flutter/material.dart';
import '../../models/task.dart';
import '../../models/user.dart';
import '../../theme/theme.dart';
import '../common/hover_card.dart';
import '../task_assignee_avatars.dart';

/// Compact card widget for displaying a task on the Kanban board.
class KanbanTaskCard extends StatelessWidget {
  final Task task;
  final Map<String, AppUser> usersMap;
  final List<AppUser> allWorkspaceUsers;
  final bool compact;
  final VoidCallback? onTap;

  const KanbanTaskCard({
    super.key,
    required this.task,
    required this.usersMap,
    this.allWorkspaceUsers = const [],
    this.compact = false,
    this.onTap,
  });

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'high':
        return AppColors.error;
      case 'low':
        return AppColors.info;
      default:
        return AppColors.textSecondary;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = date.difference(DateTime(now.year, now.month, now.day)).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff == -1) return 'Yesterday';
    return '${date.month}/${date.day}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isOverdue = task.isOverdue();
    final isComplete = task.isComplete;

    return HoverCard(
      onTap: onTap,
      margin: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 8,
        vertical: compact ? 2 : 4,
      ),
      borderRadius: BorderRadius.circular(compact ? 6 : 8),
      child: Padding(
          padding: EdgeInsets.all(compact ? 8 : 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title row with priority dot
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Priority dot
                  Padding(
                    padding: EdgeInsets.only(
                      top: compact ? 3 : 4,
                      right: compact ? 4 : 8,
                    ),
                    child: Container(
                      width: compact ? 6 : 8,
                      height: compact ? 6 : 8,
                      decoration: BoxDecoration(
                        color: _priorityColor(task.priority),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  // Recurring icon
                  if (task.isRecurring)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: 4),
                      child: Icon(
                        Icons.repeat,
                        size: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  // Title
                  Expanded(
                    child: Text(
                      task.displayTitle,
                      style: TextStyle(
                        fontSize: compact ? 11 : 13,
                        fontWeight: FontWeight.w500,
                        color: isComplete
                            ? AppColors.textTertiary
                            : AppColors.textPrimary,
                        decoration: isComplete
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 4 : 8),
              // Bottom row: assignees, due date, progress/checklist
              Row(
                children: [
                  // Assignee avatars
                  TaskAssigneeAvatars(
                    task: task,
                    usersMap: usersMap,
                    allWorkspaceUsers: allWorkspaceUsers,
                    maxVisible: compact ? 1 : 2,
                    avatarSize: compact ? 16 : 20,
                    readOnly: true,
                  ),
                  const Spacer(),
                  // Checklist count
                  if (task.checklistItems.isNotEmpty) ...[
                    Icon(
                      Icons.checklist,
                      size: 14,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${task.checklistItems.where((i) => i.isComplete).length}/${task.checklistItems.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Progress bar
                  if (task.progress > 0 && !task.isComplete) ...[
                    SizedBox(
                      width: 24,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: task.progress / 100,
                          backgroundColor: AppColors.cardBorder,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            task.progress >= 100
                                ? AppColors.success
                                : AppColors.info,
                          ),
                          minHeight: 4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '${task.progress}%',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Due date
                  if (task.dueDate != null) ...[
                    Icon(
                      Icons.schedule,
                      size: 12,
                      color: isOverdue
                          ? AppColors.error
                          : AppColors.textTertiary,
                    ),
                    const SizedBox(width: 2),
                    Flexible(
                      child: Text(
                        _formatDate(task.dueDate!),
                        style: TextStyle(
                          fontSize: 11,
                          color: isOverdue
                              ? AppColors.error
                              : AppColors.textSecondary,
                          fontWeight: isOverdue
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
      ),
    );
  }
}
