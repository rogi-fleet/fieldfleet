import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/project.dart';
import '../../../models/task.dart';
import '../../../providers/workspace_provider.dart';
import '../../../services/service_locator.dart';
import '../../../services/project_health_service.dart';
import '../../../theme/theme.dart';
import '../../../utils/project_terminology.dart';

/// Progress Bar widget showing overall project completion
class ProjectProgressWidget extends StatelessWidget {
  final Project project;

  const ProjectProgressWidget({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
    final projectTerminology = context.watch<WorkspaceProvider>().projectTerminology;
    final singular = singularProjectTerminology(projectTerminology);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$singular Progress',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Icon(
                  Icons.timeline,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
            const SizedBox(height: 16),
            StreamBuilder<List<Task>>(
              stream: ServiceLocator.taskService.getTasks(
                project.id,
                workspaceId: project.workspaceId,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.base),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                final tasks = snapshot.data ?? [];
                final totalTasks = tasks.length;
                final completedTasks = tasks.where((task) => task.isComplete).length;
                final progress = totalTasks > 0 ? completedTasks / totalTasks : 0.0;
                final progressPercent = (progress * 100).toInt();

                // Calculate timeline progress
                double timelineProgress = 0.0;
                if (project.startDate != null && project.targetCompletionDate != null) {
                  final now = DateTime.now();
                  final totalDuration = project.targetCompletionDate!.difference(project.startDate!).inDays;
                  final elapsed = now.difference(project.startDate!).inDays;
                  timelineProgress = totalDuration > 0 ? (elapsed / totalDuration).clamp(0.0, 1.0) : 0.0;
                }

                return Column(
                  children: [
                    // Task Progress
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Tasks Completed',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          '$completedTasks / $totalTasks tasks',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Stack(
                      children: [
                        Container(
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.cardBorder,
                            borderRadius: BorderRadius.circular(AppRadius.xl),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: progress,
                          child: Container(
                            height: 32,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(context).colorScheme.primary,
                                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(AppRadius.xl),
                            ),
                          ),
                        ),
                        Container(
                          height: 32,
                          alignment: Alignment.center,
                          child: Text(
                            '$progressPercent%',
                            style: TextStyle(
                              color: progress > 0.5 ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (project.startDate != null && project.targetCompletionDate != null) ...[
                      const SizedBox(height: 20),
                      // Timeline Progress
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Timeline Progress',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          Text(
                            '${(timelineProgress * 100).toInt()}% elapsed',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: timelineProgress,
                        backgroundColor: AppColors.cardBorder,
                        color: timelineProgress > progress
                            ? AppColors.secondary  // Behind schedule
                            : AppColors.success,  // On or ahead of schedule
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                        minHeight: 8,
                      ),
                      const SizedBox(height: 8),
                      if (timelineProgress > progress)
                        Row(
                          children: [
                            Icon(Icons.warning_amber, size: 16, color: AppColors.secondary),
                            const SizedBox(width: 4),
                            Text(
                              'Behind schedule',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.secondaryDark,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        )
                      else if (progress > timelineProgress && progress > 0)
                        Row(
                          children: [
                            Icon(Icons.check_circle, size: 16, color: AppColors.success),
                            const SizedBox(width: 4),
                            Text(
                              'Ahead of schedule',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.successDark,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                    ],
                    // Health Score Breakdown
                    const SizedBox(height: 20),
                    _buildHealthScoreBreakdown(tasks),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthScoreBreakdown(List<Task> tasks) {
    const healthService = ProjectHealthService();
    final score = healthService.computeScore(
      project: project,
      tasks: tasks,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: score.color.withValues(alpha: 0.12),
                border: Border.all(color: score.color, width: 2.5),
              ),
              child: Center(
                child: Text(
                  '${score.overallScore}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: score.color,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Health Score: ${score.label}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: score.color,
                  ),
                ),
                const Text(
                  'Based on schedule, budget, velocity & overdue tasks',
                  style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildScoreRow('Schedule', score.scheduleScore, '30%'),
        const SizedBox(height: 8),
        _buildScoreRow('Budget', score.budgetScore, '25%'),
        const SizedBox(height: 8),
        _buildScoreRow('Task Velocity', score.taskVelocityScore, '25%'),
        const SizedBox(height: 8),
        _buildScoreRow('Overdue Tasks', score.overdueTasksScore, '20%'),
      ],
    );
  }

  Widget _buildScoreRow(String label, int value, String weight) {
    final color = value >= 70
        ? AppColors.success
        : value >= 40
            ? AppColors.secondary
            : AppColors.error;

    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: value / 100,
              minHeight: 6,
              backgroundColor: AppColors.cardBorder,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 28,
          child: Text(
            '$value',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 28,
          child: Text(
            weight,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}
