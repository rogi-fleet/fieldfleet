import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../models/project.dart';
import '../../models/project_status_theme.dart';
import '../../services/service_locator.dart';
import '../../providers/workspace_provider.dart';
import '../../theme/theme.dart';
import '../../utils/address_formatter.dart';
import '../../utils/project_terminology.dart';

class ActiveProjectsWidget extends StatefulWidget {
  final String workspaceId;
  final String userId;
  final List<Project>? allProjects;

  const ActiveProjectsWidget({
    super.key,
    required this.workspaceId,
    required this.userId,
    this.allProjects,
  });

  @override
  State<ActiveProjectsWidget> createState() => _ActiveProjectsWidgetState();
}

class _ActiveProjectsWidgetState extends State<ActiveProjectsWidget> {
  Set<String> _favoriteIds = {};

  String get workspaceId => widget.workspaceId;
  String get userId => widget.userId;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final ids = await ServiceLocator.userPreferencesService
        .getFavoriteProjectIds();
    if (mounted) setState(() => _favoriteIds = ids.toSet());
  }

  @override
  Widget build(BuildContext context) {
    final projectTerminology = context
        .watch<WorkspaceProvider>()
        .projectTerminology;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.projectAccentLight,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: const Icon(
                    Icons.folder_open,
                    color: AppColors.projectAccent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.iconGap),
                Expanded(
                  child: Text(
                    'My $projectTerminology',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => context.go('/projects'),
                  child: const Text('View All'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.base),

            // Projects list
            Builder(
              builder: (context) {
                final allProjects = widget.allProjects;
                if (allProjects == null) {
                  return const SizedBox(
                    height: 100,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }

                final myProjects = allProjects.where((project) {
                  return project.teamMemberIds.contains(userId) ||
                      project.projectManagerId == userId;
                }).toList();

                final activeList = myProjects.where((project) {
                  return !project.status.isClosed;
                }).toList();

                if (_favoriteIds.isNotEmpty) {
                  activeList.sort((a, b) {
                    final aFav = _favoriteIds.contains(a.id) ? 0 : 1;
                    final bFav = _favoriteIds.contains(b.id) ? 0 : 1;
                    return aFav.compareTo(bFav);
                  });
                }

                final activeProjects = activeList.take(4).toList();

                if (activeProjects.isEmpty) {
                  return _buildEmptyState(context, projectTerminology);
                }

                return Column(
                  children: activeProjects
                      .map((project) => _ProjectMiniCard(project: project))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, String projectTerminology) {
    final singularTerminology =
        singularProjectTerminology(projectTerminology);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sectionGap),
      child: Center(
        child: Column(
          children: [
            const Icon(
              Icons.folder_off_outlined,
              size: 48,
              color: AppColors.cardBorder,
            ),
            const SizedBox(height: AppSpacing.iconGap),
            Text(
              'No active ${projectTerminology.toLowerCase()}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => context.go('/projects/new'),
              child: Text(
                'Create $singularTerminology',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectMiniCard extends StatelessWidget {
  final Project project;

  const _ProjectMiniCard({required this.project});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.iconGap),
      child: InkWell(
        onTap: () => context.go('/projects/${project.id}'),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.iconGap),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            children: [
              // Project photo/placeholder
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  color: AppColors.projectAccent.withValues(alpha: 0.15),
                ),
                clipBehavior: Clip.antiAlias,
                child: project.photoUrl != null
                    ? CachedNetworkImage(
                        imageUrl: project.photoUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) =>
                            _buildPlaceholder(),
                      )
                    : _buildPlaceholder(),
              ),
              const SizedBox(width: AppSpacing.iconGap),

              // Project info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 12,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            project.address.isNotEmpty
                                ? AddressFormatter.condense(project.address)
                                : 'No location',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Status badge
              _buildStatusBadge(project.status),

              const SizedBox(width: AppSpacing.sm),
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

  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.projectAccent.withValues(alpha: 0.2),
      child: Center(
        child: Text(
          project.name.isNotEmpty ? project.name[0].toUpperCase() : 'P',
          style: const TextStyle(
            color: AppColors.projectAccent,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(ProjectStatus status) {
    Color backgroundColor;
    Color textColor;
    String label;

    backgroundColor = ProjectStatusTheme.colorLight(status);
    textColor = ProjectStatusTheme.colorDark(status);
    label = status.displayName;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}
