import 'package:flutter/material.dart';
import '../../models/property.dart';
import '../../models/task.dart';
import '../../theme/theme.dart';

/// Dashboard widget showing properties with incomplete tasks.
/// Displays progress bars by property and allows navigation to property details.
class PropertyTasksWidget extends StatelessWidget {
  final List<Property> properties;
  final List<Task> tasks;
  final Function(String propertyId)? onPropertyTap;

  const PropertyTasksWidget({
    super.key,
    required this.properties,
    required this.tasks,
    this.onPropertyTap,
  });

  @override
  Widget build(BuildContext context) {
    // Group tasks by property
    final propertyTaskCounts = <String, _PropertyTaskInfo>{};

    for (final task in tasks) {
      for (final propertyId in task.propertyIds) {
        if (propertyId.isNotEmpty) {
          final info = propertyTaskCounts.putIfAbsent(
            propertyId,
            () => _PropertyTaskInfo(),
          );
          info.totalTasks++;
          if (task.isComplete) {
            info.completedTasks++;
          }
        }
      }
    }

    // Filter to only properties with tasks
    final propertiesWithTasks = properties
        .where((p) => propertyTaskCounts.containsKey(p.id))
        .toList();

    // Sort by incomplete tasks (most incomplete first)
    propertiesWithTasks.sort((a, b) {
      final infoA = propertyTaskCounts[a.id]!;
      final infoB = propertyTaskCounts[b.id]!;
      final incompleteA = infoA.totalTasks - infoA.completedTasks;
      final incompleteB = infoB.totalTasks - infoB.completedTasks;
      return incompleteB.compareTo(incompleteA);
    });

    // Take only top 5 properties
    final displayProperties = propertiesWithTasks.take(5).toList();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r12)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.home_work_outlined, color: AppColors.financialAccent, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Property Tasks',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (displayProperties.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  child: Column(
                    children: [
                      Icon(Icons.check_circle, size: 48, color: AppColors.success),
                      const SizedBox(height: 8),
                      Text(
                        'No tasks linked to properties',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...displayProperties.map((property) {
                final info = propertyTaskCounts[property.id]!;
                return _buildPropertyRow(context, property, info);
              }),
            if (propertiesWithTasks.length > 5) ...[
              const SizedBox(height: 8),
              Center(
                child: Text(
                  '+ ${propertiesWithTasks.length - 5} more properties',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPropertyRow(
    BuildContext context,
    Property property,
    _PropertyTaskInfo info,
  ) {
    final progress = info.totalTasks > 0
        ? info.completedTasks / info.totalTasks
        : 0.0;
    final incompleteTasks = info.totalTasks - info.completedTasks;
    final isComplete = incompleteTasks == 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onPropertyTap != null ? () => onPropertyTap!(property.id) : null,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: isComplete ? AppColors.successLight : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: isComplete ? AppColors.success : AppColors.cardBorder,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      property.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: isComplete ? AppColors.success : AppColors.warning,
                      borderRadius: BorderRadius.circular(AppRadius.r12),
                    ),
                    child: Text(
                      isComplete
                          ? 'Complete'
                          : '$incompleteTasks left',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: AppColors.cardBorder,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isComplete ? AppColors.success : AppColors.financialAccent,
                        ),
                        minHeight: 6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(progress * 100).round()}%',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PropertyTaskInfo {
  int totalTasks = 0;
  int completedTasks = 0;
}
