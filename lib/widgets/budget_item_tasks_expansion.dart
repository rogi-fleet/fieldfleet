import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/task.dart';
import '../services/service_locator.dart';
import '../theme/theme.dart';
import 'user_avatar.dart';

/// Expandable panel showing tasks linked to a budget item
class BudgetItemTasksExpansion extends StatefulWidget {
  final String budgetItemId;
  final String projectId;
  final String workspaceId;

  const BudgetItemTasksExpansion({
    super.key,
    required this.budgetItemId,
    required this.projectId,
    required this.workspaceId,
  });

  @override
  State<BudgetItemTasksExpansion> createState() =>
      _BudgetItemTasksExpansionState();
}

class _BudgetItemTasksExpansionState extends State<BudgetItemTasksExpansion> {
  List<Task> _tasks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    try {
      final taskIds = await ServiceLocator.budgetTaskLinkService
          .getTaskIdsForBudgetItem(widget.budgetItemId);

      if (taskIds.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Load task details
      final tasks = <Task>[];
      for (final taskId in taskIds) {
        try {
          final task = await ServiceLocator.taskService.getTask(taskId);
          if (task != null) {
            tasks.add(task);
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _tasks = tasks;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'done':
        return AppColors.success;
      case 'working_on_it':
        return AppColors.info;
      case 'stuck':
        return AppColors.error;
      default:
        return AppColors.textTertiary;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'done':
        return 'Done';
      case 'working_on_it':
        return 'In Progress';
      case 'stuck':
        return 'Stuck';
      case 'not_started':
        return 'Not Started';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_tasks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(
          'No linked tasks',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textTertiary,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(left: 40, right: 8, bottom: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: _tasks.map((task) => _buildTaskRow(task)).toList(),
      ),
    );
  }

  Widget _buildTaskRow(Task task) {
    final statusColor = _statusColor(task.status);

    return InkWell(
      onTap: () {
        context.push('/projects/${widget.projectId}/tasks/${task.id}');
      },
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          children: [
            // Status chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Text(
                _statusLabel(task.status),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Task title
            Expanded(
              child: Text(
                task.title,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                  decoration: task.isComplete
                      ? TextDecoration.lineThrough
                      : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Progress bar
            if (task.progress > 0) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 60,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: task.progress / 100,
                    minHeight: 4,
                    backgroundColor: AppColors.cardBorder,
                    valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '${task.progress}%',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
            // Estimated hours
            if (task.estimatedDuration != null) ...[
              const SizedBox(width: 12),
              Text(
                '${task.estimatedDuration!.toStringAsFixed(1)}h est',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
            // Assignees
            if (task.assignedToIds.isNotEmpty) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 24 + (task.assignedToIds.length - 1) * 12.0,
                height: 24,
                child: Stack(
                  children: task.assignedToIds
                      .take(3)
                      .toList()
                      .asMap()
                      .entries
                      .map((entry) => Positioned(
                            left: entry.key * 12.0,
                            child: UserAvatar(
                              userId: entry.value,
                              size: AvatarSize.small,
                            ),
                          ))
                      .toList(),
                ),
              ),
            ],
            // Navigate arrow
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 16,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
