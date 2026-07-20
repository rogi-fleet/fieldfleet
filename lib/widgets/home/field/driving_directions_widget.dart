import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/project.dart';
import '../../../models/task.dart';
import '../../../providers/workspace_provider.dart';
import '../../../theme/theme.dart';
import '../../../utils/project_terminology.dart';
import 'field_task_utils.dart';

/// Shows the next job site with address and one-tap navigation to maps.
class DrivingDirectionsWidget extends StatelessWidget {
  final String workspaceId;
  final String userId;
  final List<Project>? allProjects;
  final List<Task>? allTasks;

  const DrivingDirectionsWidget({
    super.key,
    required this.workspaceId,
    required this.userId,
    this.allProjects,
    this.allTasks,
  });

  @override
  Widget build(BuildContext context) {
    final singularTerminology = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: AppSpacing.base),
            _buildContent(singularTerminology),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(String singularTerminology) {
    if (allTasks == null) return _buildLoadingState();

    final todaysTasks = filterTodaysTasks(allTasks!, userId);

    // Find next task with a project that has an address.
    Project? nextProject;
    Task? nextTask;

    for (final task in todaysTasks) {
      if (allProjects == null) break;
      try {
        final project = allProjects!.firstWhere(
          (p) => p.id == task.projectId,
        );
        if (project.address.isNotEmpty) {
          nextProject = project;
          nextTask = task;
          break;
        }
      } catch (_) {
        continue;
      }
    }

    if (nextProject == null || nextTask == null) {
      return _buildEmptyState(singularTerminology);
    }

    return _buildDirectionsCard(nextTask, nextProject, singularTerminology);
  }

  Widget _buildDirectionsCard(
    Task task,
    Project project,
    String singularTerminology,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Project name and task
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: const Color(0xFF0891B2).withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: const Color(0xFF0891B2).withValues(alpha: 0.2),
            ),
          ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Next $singularTerminology',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                project.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                task.title,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.place,
                    size: 14,
                    color: Color(0xFF0891B2),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      project.address,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.iconGap),

        // Navigate button
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _openMaps(project.address),
            icon: const Icon(Icons.navigation, size: 18),
            label: const Text('Open in Maps'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0891B2),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openMaps(String address) async {
    final encoded = Uri.encodeComponent(address);
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encoded');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF0891B2).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: const Icon(
            Icons.directions_car,
            color: Color(0xFF0891B2),
            size: 20,
          ),
        ),
        const SizedBox(width: AppSpacing.iconGap),
        const Expanded(
          child: Text(
            'Driving Directions',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
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
            const Icon(Icons.near_me_disabled, size: 48, color: AppColors.cardBorder),
            const SizedBox(height: AppSpacing.iconGap),
            Text(
              'No upcoming ${singularTerminology.toLowerCase()} sites',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Your next ${singularTerminology.toLowerCase()} will appear here',
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
