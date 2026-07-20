import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/task.dart';
import '../models/user.dart';
import '../theme/theme.dart';

/// A rich hover tooltip for tasks that displays comprehensive task information
/// including title, description, dates, progress, and checklist summary.
class TaskHoverTooltip extends StatelessWidget {
  final Task task;
  final Widget child;
  final Map<String, AppUser>? usersMap;
  final Duration waitDuration;
  final bool preferBelow;

  const TaskHoverTooltip({
    super.key,
    required this.task,
    required this.child,
    this.usersMap,
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
      decoration: BoxDecoration(
        color: Colors.transparent,
      ),
      child: child,
    );
  }

  Widget _buildTooltipContent(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _getStatusColor();

    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.3),
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
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppRadius.lg),
              ),
              border: Border(
                bottom: BorderSide(
                  color: statusColor.withOpacity(0.2),
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
                    task.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      decoration: task.isComplete ? TextDecoration.lineThrough : null,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (task.priority != 'medium')
                  _buildPriorityBadge(),
              ],
            ),
          ),

          // Body content
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Description
                if (task.description != null && task.description!.isNotEmpty) ...[
                  Text(
                    task.description!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                ],

                // Info row: dates, progress
                _buildInfoRow(context),

                // Checklist summary
                if (task.hasChecklist) ...[
                  const SizedBox(height: 12),
                  _buildChecklistSummary(context),
                ],

                // Assignees
                if (task.assignedToIds.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildAssigneesRow(context),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriorityBadge() {
    Color bgColor;
    Color textColor;

    switch (task.priority.toLowerCase()) {
      case 'high':
        bgColor = AppColors.errorLight;
        textColor = AppColors.errorDark;
        break;
      case 'low':
        bgColor = AppColors.infoLight;
        textColor = AppColors.infoDark;
        break;
      default:
        bgColor = AppColors.surfaceAlt;
        textColor = AppColors.textPrimary;
    }

    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        task.priority,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context) {
    final theme = Theme.of(context);
    final items = <Widget>[];

    // Status
    items.add(
      _buildInfoChip(
        icon: Icons.circle,
        iconColor: _getStatusColor(),
        iconSize: 8,
        label: _statusDisplayName(),
      ),
    );

    // Due date
    if (task.dueDate != null) {
      final isOverdue = task.isOverdue();
      items.add(
        _buildInfoChip(
          icon: Icons.calendar_today,
          iconColor: isOverdue ? AppColors.error : theme.colorScheme.primary,
          label: DateFormat('MMM d, yyyy').format(task.dueDate!),
          labelColor: isOverdue ? AppColors.error : null,
        ),
      );
    }

    // Progress
    if (task.progress > 0) {
      items.add(
        _buildInfoChip(
          icon: Icons.trending_up,
          iconColor: _getProgressColor(task.progress),
          label: '${task.progress}%',
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: items,
    );
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

  Widget _buildChecklistSummary(BuildContext context) {
    final theme = Theme.of(context);
    final completed = task.completedChecklistCount;
    final total = task.totalChecklistCount;
    final progress = task.checklistProgress;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.checklist,
                size: 14,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'Checklist ($completed/$total)',
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
          // Progress bar
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
          // Show first few checklist items as preview
          if (task.checklistItems.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...task.checklistItems.take(3).map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  Icon(
                    item.isComplete 
                        ? Icons.check_box 
                        : Icons.check_box_outline_blank,
                    size: 12,
                    color: item.isComplete ? AppColors.success : AppColors.textTertiary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textPrimary,
                        decoration: item.isComplete 
                            ? TextDecoration.lineThrough 
                            : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            )),
            if (task.checklistItems.length > 3)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '+${task.checklistItems.length - 3} more items',
                  style: TextStyle(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildAssigneesRow(BuildContext context) {
    final theme = Theme.of(context);
    
    return Row(
      children: [
        Icon(
          Icons.people_outline,
          size: 14,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 6),
        Text(
          '${task.assignedToIds.length} assignee${task.assignedToIds.length > 1 ? 's' : ''}',
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
        // Show names if usersMap is provided
        if (usersMap != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              task.assignedToIds
                  .take(3)
                  .map((id) => usersMap![id]?.displayName ?? 'Unknown')
                  .join(', ') +
                  (task.assignedToIds.length > 3 
                      ? ' +${task.assignedToIds.length - 3}' 
                      : ''),
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textTertiary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }

  String _statusDisplayName() {
    switch (task.status.toLowerCase()) {
      case 'done':
      case 'complete':
      case 'completed':
        return 'Done';
      case 'working_on_it':
      case 'working on it':
      case 'in_progress':
      case 'in progress':
        return 'Working on it';
      case 'stuck':
      case 'blocked':
        return 'Stuck';
      case 'not_started':
      case 'not started':
      default:
        return 'Not started';
    }
  }

  Color _getStatusColor() {
    if (task.isComplete) return AppColors.success;
    if (task.isOverdue()) return AppColors.error;

    switch (task.status.toLowerCase()) {
      case 'done':
      case 'complete':
      case 'completed':
        return AppColors.success;
      case 'working_on_it':
      case 'working on it':
      case 'in_progress':
      case 'in progress':
        return AppColors.info;
      case 'stuck':
      case 'blocked':
        return AppColors.error;
      case 'not_started':
      case 'not started':
      default:
        return AppColors.textTertiary;
    }
  }

  Color _getProgressColor(int progress) {
    if (progress >= 100) return AppColors.success;
    if (progress >= 50) return AppColors.info;
    if (progress > 0) return AppColors.secondary;
    return AppColors.textTertiary;
  }
}
