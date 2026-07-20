import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/project.dart';
import '../models/project_status_theme.dart';
import '../models/project_task_metrics.dart';
import '../theme/theme.dart';

/// A rich hover tooltip for projects that displays project name, status,
/// dates, customer, and task progress.
class ProjectHoverTooltip extends StatelessWidget {
  final Project project;
  final Widget child;
  final ProjectTaskMetrics? taskMetrics;
  final Duration waitDuration;
  final bool preferBelow;

  const ProjectHoverTooltip({
    super.key,
    required this.project,
    required this.child,
    this.taskMetrics,
    this.waitDuration = const Duration(milliseconds: 500),
    this.preferBelow = true,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      richMessage: WidgetSpan(
        child: _buildTooltipContent(context),
      ),
      waitDuration: waitDuration,
      preferBelow: preferBelow,
      padding: EdgeInsets.zero,
      decoration: const BoxDecoration(color: Colors.transparent),
      child: child,
    );
  }

  Widget _buildTooltipContent(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = ProjectStatusTheme.color(project.status);

    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: theme.dividerColor.withValues(alpha:0.3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with status color
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha:0.1),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              border: Border(
                bottom: BorderSide(
                  color: statusColor.withValues(alpha:0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    project.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha:0.15),
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                  child: Text(
                    project.status.displayName,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Body content
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info chips
                _buildInfoRow(context),

                // Task progress
                if (taskMetrics != null && taskMetrics!.totalCount > 0) ...[
                  const SizedBox(height: 12),
                  _buildTaskProgress(context),
                ],

                // Customer
                if (project.customerName != null &&
                    project.customerName!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.business_outlined,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          project.customerName!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
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
        ],
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context) {
    final theme = Theme.of(context);
    final items = <Widget>[];

    // Start date
    if (project.startDate != null) {
      items.add(
        _buildInfoChip(
          icon: Icons.play_arrow,
          iconColor: theme.colorScheme.primary,
          label: DateFormat('MMM d, yyyy').format(project.startDate!),
        ),
      );
    }

    // Target date
    if (project.targetCompletionDate != null) {
      final isOverdue = project.isOverdue();
      items.add(
        _buildInfoChip(
          icon: Icons.flag,
          iconColor: isOverdue ? AppColors.error : theme.colorScheme.primary,
          label: DateFormat('MMM d, yyyy')
              .format(project.targetCompletionDate!),
          labelColor: isOverdue ? AppColors.error : null,
        ),
      );
    }

    // Duration
    final totalDays = project.totalDays;
    if (totalDays > 0) {
      items.add(
        _buildInfoChip(
          icon: Icons.schedule,
          iconColor: AppColors.textSecondary,
          label: '$totalDays days',
        ),
      );
    }

    if (items.isEmpty) {
      items.add(
        _buildInfoChip(
          icon: Icons.calendar_today,
          iconColor: AppColors.textTertiary,
          label: 'No dates set',
        ),
      );
    }

    return Wrap(spacing: 8, runSpacing: 6, children: items);
  }

  Widget _buildInfoChip({
    required IconData icon,
    required Color iconColor,
    required String label,
    Color? labelColor,
    double iconSize = 12,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: iconSize, color: iconColor),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: labelColor ?? AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildTaskProgress(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = taskMetrics!;
    final progress = metrics.progressPercent;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha:0.05),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha:0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.task_outlined,
                size: 14,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'Tasks (${metrics.completedCount}/${metrics.totalCount})',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
              const Spacer(),
              Text(
                '${progress.toInt()}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _getProgressColor(progress.toInt()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress / 100,
              backgroundColor: AppColors.cardBorder,
              valueColor: AlwaysStoppedAnimation<Color>(
                _getProgressColor(progress.toInt()),
              ),
            ),
          ),
          if (metrics.overdueCount > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.warning_amber, size: 12, color: AppColors.error),
                const SizedBox(width: 4),
                Text(
                  '${metrics.overdueCount} overdue',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.error,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Color _getProgressColor(int progress) {
    if (progress >= 100) return AppColors.success;
    if (progress >= 50) return AppColors.info;
    if (progress > 0) return AppColors.secondary;
    return AppColors.textTertiary;
  }
}
