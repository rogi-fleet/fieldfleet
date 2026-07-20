import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/project.dart';
import '../../models/project_task_metrics.dart';
import '../../theme/theme.dart';
import '../common/hover_card.dart';

/// Compact card widget for displaying a project on the Kanban board.
class KanbanProjectCard extends StatelessWidget {
  final Project project;
  final ProjectTaskMetrics? taskMetrics;
  final bool compact;
  final VoidCallback? onTap;

  const KanbanProjectCard({
    super.key,
    required this.project,
    this.taskMetrics,
    this.compact = false,
    this.onTap,
  });

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
    final isOverdue = project.isOverdue();

    return HoverCard(
      onTap: onTap ?? () => context.go('/projects/${project.id}'),
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
            // Project name
            Text(
              project.name,
              style: TextStyle(
                fontSize: compact ? 12 : 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (project.customerName != null &&
                project.customerName!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                project.customerName!,
                style: TextStyle(
                  fontSize: compact ? 10 : 11,
                  color: AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (project.address.isNotEmpty) ...[
              const SizedBox(height: 1),
              Text(
                project.address,
                style: TextStyle(
                  fontSize: compact ? 10 : 11,
                  color: AppColors.textTertiary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            SizedBox(height: compact ? 4 : 8),
            // Bottom row: task progress + due date
            Row(
              children: [
                if (taskMetrics != null) ...[
                  Icon(
                    Icons.check_circle_outline,
                    size: 12,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '${taskMetrics!.completedCount}/${taskMetrics!.totalCount}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                const Spacer(),
                if (project.targetCompletionDate != null) ...[
                  Icon(
                    Icons.schedule,
                    size: 12,
                    color: isOverdue ? AppColors.error : AppColors.textTertiary,
                  ),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(
                      _formatDate(project.targetCompletionDate!),
                      style: TextStyle(
                        fontSize: 11,
                        color: isOverdue
                            ? AppColors.error
                            : AppColors.textSecondary,
                        fontWeight:
                            isOverdue ? FontWeight.w600 : FontWeight.normal,
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
