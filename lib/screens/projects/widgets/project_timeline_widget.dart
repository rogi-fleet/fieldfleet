import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/project.dart';
import '../../../models/task.dart';
import '../../../services/service_locator.dart';
import '../../../theme/theme.dart';

class ProjectTimelineWidget extends StatelessWidget {
  final Project project;

  const ProjectTimelineWidget({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
    // If the project already carries both an explicit start and target, the
    // task dates can't add anything — skip the stream entirely.
    if (project.startDate != null && project.targetCompletionDate != null) {
      return _buildCard(context, tasks: const []);
    }
    // Otherwise fall back to deriving the span from task dates so a project
    // that's been scheduled task-by-task still shows a timeline instead of an
    // empty "No dates set" state.
    return StreamBuilder<List<Task>>(
      stream: ServiceLocator.taskService.getTasks(
        project.id,
        workspaceId: project.workspaceId,
      ),
      builder: (context, snapshot) =>
          _buildCard(context, tasks: snapshot.data ?? const []),
    );
  }

  /// Min/max of every non-null date carried by the project's tasks.
  ({DateTime? start, DateTime? end}) _taskSpan(List<Task> tasks) {
    DateTime? min, max;
    for (final t in tasks) {
      for (final d in [t.startDate, t.dueDate, t.endDate]) {
        if (d == null) continue;
        if (min == null || d.isBefore(min)) min = d;
        if (max == null || d.isAfter(max)) max = d;
      }
    }
    return (start: min, end: max);
  }

  Widget _buildCard(BuildContext context, {required List<Task> tasks}) {
    final dateFormat = DateFormat('MMM d, yyyy');
    final now = DateTime.now();

    final span = _taskSpan(tasks);
    final start = project.startDate ?? span.start;
    final target = project.targetCompletionDate ?? span.end;
    final received = project.dateRequestReceived;

    // True when at least one shown date came from tasks rather than the
    // project record — used to caption the card so the dates aren't mistaken
    // for committed milestones.
    final derived = (project.startDate == null && span.start != null) ||
        (project.targetCompletionDate == null && span.end != null);

    final totalDays = (start != null && target != null)
        ? target.difference(start).inDays
        : null;
    final elapsedDays = start != null
        ? now.difference(start).inDays.clamp(0, totalDays ?? 1 << 30)
        : null;
    final remainingDays = target?.difference(now).inDays;

    // Overdue stays tied to the project's committed target only — a derived
    // span shouldn't raise a false "OVERDUE" alarm.
    final overdue = project.isOverdue();
    final progress = (totalDays != null && totalDays > 0 && elapsedDays != null)
        ? (elapsedDays / totalDays).clamp(0.0, 1.0)
        : null;

    final hasAnyDate = start != null || target != null || received != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.event,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Timeline',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (overdue)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.r12),
                      border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      'OVERDUE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.error,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (!hasAnyDate)
              _buildEmpty()
            else ...[
              if (derived) ...[
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_outlined,
                      size: 13,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'Estimated from task dates',
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              if (progress != null) ...[
                _buildProgressBar(progress, overdue),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${(progress * 100).round()}% elapsed',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      remainingDays != null
                          ? (remainingDays >= 0
                              ? '$remainingDays days left'
                              : '${-remainingDays} days overdue')
                          : '',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: overdue
                            ? AppColors.error
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              if (received != null)
                _buildDateRow(
                  icon: Icons.inbox_outlined,
                  label: 'Request Received',
                  value: dateFormat.format(received),
                  color: AppColors.textSecondary,
                ),
              if (start != null)
                _buildDateRow(
                  icon: Icons.play_circle_outline,
                  label: 'Start Date',
                  value: dateFormat.format(start),
                  color: AppColors.info,
                ),
              if (target != null)
                _buildDateRow(
                  icon: Icons.flag_outlined,
                  label: 'Target Completion',
                  value: dateFormat.format(target),
                  color: overdue ? AppColors.error : AppColors.success,
                ),
              if (totalDays != null && totalDays > 0) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    'Duration: $totalDays days',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
      child: Row(
        children: [
          Icon(
            Icons.event_busy,
            size: 18,
            color: AppColors.textTertiary,
          ),
          const SizedBox(width: 8),
          const Text(
            'No dates set for this project',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(double progress, bool overdue) {
    final color = overdue
        ? AppColors.error
        : (progress > 0.85 ? AppColors.warning : AppColors.info);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: LinearProgressIndicator(
        value: progress,
        minHeight: 6,
        backgroundColor: color.withValues(alpha: 0.12),
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }

  Widget _buildDateRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
