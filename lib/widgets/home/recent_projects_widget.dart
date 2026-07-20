import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/project.dart';
import '../../models/project_status_theme.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';

class RecentProjectsWidget extends StatefulWidget {
  final String workspaceId;
  final List<Project>? allProjects;

  const RecentProjectsWidget({
    super.key,
    required this.workspaceId,
    this.allProjects,
  });

  @override
  State<RecentProjectsWidget> createState() => _RecentProjectsWidgetState();
}

class _RecentProjectsWidgetState extends State<RecentProjectsWidget> {
  List<Project> _recentProjects = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RecentProjectsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaceId != widget.workspaceId ||
        oldWidget.allProjects != widget.allProjects) {
      _loading = true;
      _recentProjects = [];
      _load();
    }
  }

  Future<void> _load() async {
    if (widget.allProjects == null) {
      return;
    }

    try {
      final recents = await ServiceLocator.userPreferencesService
          .getRecentProjectViews();
      if (recents.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final projectIds = recents.map((e) => e['project_id'] as String).toList();

      final allProjects = widget.allProjects ?? const <Project>[];

      final projectMap = {for (final p in allProjects) p.id: p};
      final ordered = <Project>[];
      for (final id in projectIds) {
        final p = projectMap[id];
        if (p != null) ordered.add(p);
      }

      if (mounted) {
        setState(() {
          _recentProjects = ordered;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (_recentProjects.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.history,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Recently Viewed',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.base),
            Row(
              children: [
                for (var i = 0;
                    i < _recentProjects.length && i < 3;
                    i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(
                    child: _RecentProjectMiniCard(
                      project: _recentProjects[i],
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

class _RecentProjectMiniCard extends StatelessWidget {
  final Project project;

  const _RecentProjectMiniCard({required this.project});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go('/projects/${project.id}'),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo or initial
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                color: _projectColor.withValues(alpha: 0.15),
              ),
              child: Center(
                child: Text(
                  project.name.isNotEmpty ? project.name[0].toUpperCase() : 'P',
                  style: TextStyle(
                    color: _projectColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              project.name,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              _statusLabel,
              style: TextStyle(
                fontSize: 11,
                color: _statusColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color get _projectColor {
    final colors = [
      AppColors.info,
      const Color(0xFF388E3C),
      const Color(0xFFD32F2F),
      const Color(0xFF7B1FA2),
      const Color(0xFF0097A7),
      const Color(0xFFF57C00),
    ];
    return colors[project.name.hashCode.abs() % colors.length];
  }

  String get _statusLabel => project.status.displayName;

  Color get _statusColor => ProjectStatusTheme.colorDark(project.status);
}
