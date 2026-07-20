import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/project.dart';
import '../../models/task.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/project_terminology.dart';

class MyTasksWidget extends StatelessWidget {
  final String workspaceId;
  final String userId;
  final Map<String, String> projectNamesById;
  final List<Task>? allTasks;
  final List<Project>? allProjects;

  const MyTasksWidget({
    super.key,
    required this.workspaceId,
    required this.userId,
    this.projectNamesById = const <String, String>{},
    this.allTasks,
    this.allProjects,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.taskAccentLight,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: const Icon(
                    Icons.check_circle_outline,
                    color: AppColors.taskAccent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.iconGap),
                const Expanded(
                  child: Text(
                    'My Tasks',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => context.go('/tasks'),
                  child: const Text('View All'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.base),

            // Tasks list — use provided data or fall back to own stream.
            if (allTasks != null)
              _buildTaskList(context, allTasks!)
            else
              StreamBuilder<List<Task>>(
                stream: ServiceLocator.taskService.getAllWorkspaceTasks(
                  workspaceId,
                ),
                builder: (context, snapshot) {
                  if (snapshot.hasError) return _buildErrorState();
                  if (!snapshot.hasData) return _buildLoadingState();
                  return _buildTaskList(context, snapshot.data!);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskList(BuildContext context, List<Task> tasks) {
    final singularTerminology = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    );
    final myTasks = tasks.where((task) {
      return task.assignedToIds.contains(userId) && !task.isComplete;
    }).toList();

    myTasks.sort((a, b) {
      final aDue = a.dueDate;
      final bDue = b.dueDate;
      if (aDue == null && bDue == null) return 0;
      if (aDue == null) return 1;
      if (bDue == null) return -1;
      return aDue.compareTo(bDue);
    });

    final displayTasks = myTasks.take(5).toList();

    if (displayTasks.isEmpty) return _buildEmptyState(context);

    final now = DateTime.now();
    final overdueCount = myTasks.where((task) {
      return task.dueDate != null && task.dueDate!.isBefore(now);
    }).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (overdueCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.iconGap),
            child: InkWell(
              onTap: () => context.go('/tasks?overdue=true'),
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.errorLight,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.errorDark,
                      size: 18,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        '$overdueCount overdue ${overdueCount == 1 ? 'task' : 'tasks'}',
                        style: const TextStyle(
                          color: AppColors.errorDark,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: AppColors.errorDark,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ...displayTasks.map((task) {
          final project = _projectFor(task.projectId);
          return _TaskMiniCard(
            task: task,
            projectName:
                projectNamesById[task.projectId] ??
                'Unknown $singularTerminology',
            customerName: project?.customerName,
            address: project?.address,
          );
        }),
      ],
    );
  }

  Project? _projectFor(String projectId) {
    if (allProjects == null) return null;
    try {
      return allProjects!.firstWhere((p) => p.id == projectId);
    } catch (_) {
      return null;
    }
  }

  Widget _buildLoadingState() {
    return const SizedBox(
      height: 100,
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }

  Widget _buildErrorState() {
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.base),
      child: Text(
        'Unable to load tasks',
        style: TextStyle(color: AppColors.textTertiary),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sectionGap),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.task_alt, size: 48, color: AppColors.cardBorder),
            const SizedBox(height: AppSpacing.iconGap),
            const Text(
              'No tasks assigned to you',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 4),
            const Text(
              'You\'re all caught up!',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskMiniCard extends StatelessWidget {
  final Task task;
  final String projectName;
  final String? customerName;
  final String? address;

  const _TaskMiniCard({
    required this.task,
    required this.projectName,
    this.customerName,
    this.address,
  });

  @override
  Widget build(BuildContext context) {
    final isOverdue =
        task.dueDate != null && task.dueDate!.isBefore(DateTime.now());

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => context.go(
          '/projects/${task.projectId}?tab=tasks&taskId=${task.id}',
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.iconGap),
          decoration: BoxDecoration(
            color: isOverdue ? AppColors.errorLight : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: isOverdue
                  ? AppColors.error.withValues(alpha: 0.3)
                  : AppColors.cardBorder,
            ),
          ),
          child: Row(
            children: [
              // Status indicator
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _getStatusColor(),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.iconGap),

              // Task info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: isOverdue
                            ? AppColors.errorDark
                            : AppColors.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      projectName,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (customerName != null && customerName!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(
                            Icons.person_outline,
                            size: 12,
                            color: AppColors.textTertiary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              customerName!,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textTertiary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (address != null && address!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 12,
                            color: AppColors.textTertiary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              address!,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textTertiary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (task.dueDate != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          decoration: BoxDecoration(
                            color: isOverdue
                                ? AppColors.error.withValues(alpha: 0.15)
                                : AppColors.cardBorder.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Text(
                            _formatDueDate(task.dueDate!),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isOverdue
                                  ? AppColors.errorDark
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: AppSpacing.sm),
              const Icon(
                Icons.chevron_right,
                color: AppColors.textTertiary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor() {
    switch (task.status.toLowerCase()) {
      case 'done':
      case 'completed':
        return AppColors.success;
      case 'working on it':
      case 'in progress':
        return AppColors.info;
      case 'stuck':
        return AppColors.error;
      default:
        return AppColors.textTertiary;
    }
  }

  String _formatDueDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);

    if (dateOnly.isBefore(today)) {
      final days = today.difference(dateOnly).inDays;
      return days == 1 ? 'Yesterday' : '$days days ago';
    } else if (dateOnly == today) {
      return 'Today';
    } else if (dateOnly == tomorrow) {
      return 'Tomorrow';
    } else {
      return DateFormat('MMM d').format(date);
    }
  }
}
