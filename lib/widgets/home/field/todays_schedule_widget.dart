import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/project.dart';
import '../../../models/task.dart';
import '../../../providers/workspace_provider.dart';
import '../../../theme/theme.dart';
import '../../../utils/project_terminology.dart';
import 'field_task_utils.dart';

/// Shows today's assigned tasks as a timeline with project names and addresses.
class TodaysScheduleWidget extends StatelessWidget {
  final String workspaceId;
  final String userId;
  final List<Project>? allProjects;
  final Map<String, String> projectNamesById;
  final List<Task>? allTasks;

  const TodaysScheduleWidget({
    super.key,
    required this.workspaceId,
    required this.userId,
    this.allProjects,
    this.projectNamesById = const <String, String>{},
    this.allTasks,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: AppSpacing.base),
            _buildContent(context),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (allTasks == null) return _buildLoadingState();
    final singularTerminology = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    );

    final todaysTasks = filterTodaysTasks(allTasks!, userId);

    if (todaysTasks.isEmpty) return _buildEmptyState(singularTerminology);

    return Column(
      children: todaysTasks.map((task) {
        return _ScheduleRow(
          task: task,
          projectName:
              projectNamesById[task.projectId] ??
              'Unknown $singularTerminology',
          address: _addressForProject(task.projectId),
        );
      }).toList(),
    );
  }

  String? _addressForProject(String projectId) {
    if (allProjects == null) return null;
    try {
      final project = allProjects!.firstWhere((p) => p.id == projectId);
      return project.address;
    } catch (_) {
      return null;
    }
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF2563EB).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: const Icon(
            Icons.calendar_today,
            color: Color(0xFF2563EB),
            size: 20,
          ),
        ),
        const SizedBox(width: AppSpacing.iconGap),
        const Expanded(
          child: Text(
            "Today's Schedule",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        TextButton(
          // The standalone /schedule route was removed and merged into Tasks
          // (see router.dart). Land on the calendar view so "Full Schedule"
          // actually shows a schedule, not the default grouped list.
          onPressed: () => context.go('/tasks?view=month'),
          child: const Text('Full Schedule'),
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return const SizedBox(
      height: 100,
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }

  Widget _buildEmptyState(String singularTerminology) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sectionGap),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.event_available, size: 48, color: AppColors.cardBorder),
            const SizedBox(height: AppSpacing.iconGap),
            Text(
              'No ${singularTerminology.toLowerCase()}s scheduled for today',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Check the full schedule for upcoming work',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  final Task task;
  final String projectName;
  final String? address;

  const _ScheduleRow({
    required this.task,
    required this.projectName,
    this.address,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isOverdue = task.dueDate != null && task.dueDate!.isBefore(today);
    final time = task.startDate ?? task.dueDate;

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
              // Time column
              SizedBox(
                width: 56,
                child: Column(
                  children: [
                    if (time != null)
                      Text(
                        DateFormat.jm().format(time),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isOverdue
                              ? AppColors.errorDark
                              : AppColors.textPrimary,
                        ),
                      )
                    else
                      const Text(
                        'TBD',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    if (isOverdue)
                      const Text(
                        'OVERDUE',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppColors.errorDark,
                        ),
                      ),
                  ],
                ),
              ),
              // Divider line
              Container(
                width: 3,
                height: 40,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: isOverdue
                      ? AppColors.error
                      : AppColors.info,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      projectName,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (address != null && address!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(
                            Icons.place,
                            size: 12,
                            color: AppColors.textTertiary,
                          ),
                          const SizedBox(width: 2),
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
                  ],
                ),
              ),
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
}
