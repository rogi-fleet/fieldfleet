import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/project.dart';
import '../../../providers/workspace_provider.dart';
import '../../../theme/theme.dart';
import '../../../utils/project_terminology.dart';
import '../../../widgets/weather_widget.dart';

/// Shows weather conditions at today's job sites.
class JobSiteWeatherWidget extends StatelessWidget {
  final String workspaceId;
  final String userId;
  final List<Project>? allProjects;

  const JobSiteWeatherWidget({
    super.key,
    required this.workspaceId,
    required this.userId,
    this.allProjects,
  });

  @override
  Widget build(BuildContext context) {
    final pluralTerminology =
        context.watch<WorkspaceProvider>().projectTerminology;
    final singularTerminology = singularProjectTerminology(
      pluralTerminology,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(singularTerminology),
            const SizedBox(height: AppSpacing.base),
            _buildContent(singularTerminology, pluralTerminology),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String singularTerminology) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFE8973A).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: const Icon(
            Icons.wb_sunny,
            color: Color(0xFFE8973A),
            size: 20,
          ),
        ),
        const SizedBox(width: AppSpacing.iconGap),
        Expanded(
          child: Text(
            '$singularTerminology Site Weather',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(
    String singularTerminology,
    String pluralTerminology,
  ) {
    // Get active projects with addresses that the user is a team member of.
    final projects = (allProjects ?? <Project>[]).where((p) {
      if (p.status != ProjectStatus.active) return false;
      if (!p.teamMemberIds.contains(userId)) return false;
      if (p.address.isEmpty) return false;
      return true;
    }).toList();

    if (projects.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sectionGap),
        child: Center(
          child: Column(
            children: [
              const Icon(Icons.cloud_off, size: 48, color: AppColors.cardBorder),
              const SizedBox(height: AppSpacing.iconGap),
              Text(
                'No ${singularTerminology.toLowerCase()} sites with addresses',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Add addresses to your ${pluralTerminology.toLowerCase()} to see weather',
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

    // Show weather for up to 3 job sites.
    final displayProjects = projects.take(3).toList();

    return Column(
      children: displayProjects.map((project) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                project.name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              WeatherWidget(
                locationQuery: project.address,
                compact: true,
                height: 80,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
