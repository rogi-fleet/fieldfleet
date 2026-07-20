import 'package:flutter/material.dart';
import '../../../models/project.dart';
import '../../theme/theme.dart';
import '../../../models/task.dart';
import '../../../services/service_locator.dart';

/// Compact progress bar for display in project header
class CompactProgressBar extends StatelessWidget {
  final Project project;

  const CompactProgressBar({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeColors.of(context);

    return StreamBuilder<List<Task>>(
      stream: ServiceLocator.taskService.getTasks(
        project.id,
        workspaceId: project.workspaceId,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final tasks = snapshot.data!;
        if (tasks.isEmpty) {
          return const SizedBox.shrink();
        }

        final totalTasks = tasks.length;
        final completedTasks = tasks.where((task) => task.isComplete).length;
        final progress = completedTasks / totalTasks;
        final progressPercent = (progress * 100).toInt();

        return LayoutBuilder(
          builder: (context, constraints) {
            final resolvedWidth = constraints.hasBoundedWidth
                ? constraints.maxWidth
                : 200.0;
            return SizedBox(
              width: resolvedWidth,
              height: 20,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: chrome.hover,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            chrome.isDark ? AppColors.primaryLight : AppColors.primarySurface,
                            chrome.isDark ? AppColors.info : AppColors.infoLight,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                  ),
                  Center(
                    child: Text(
                      '$completedTasks/$totalTasks tasks ($progressPercent%)',
                      style: TextStyle(
                        color: chrome.textActive,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
