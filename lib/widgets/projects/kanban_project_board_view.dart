import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/project.dart';
import '../../models/project_status_theme.dart';
import '../../models/project_task_metrics.dart';
import '../../providers/workspace_provider.dart';
import '../../theme/theme.dart';
import 'kanban_project_card.dart';

/// Kanban board view with columns for each project status.
class KanbanProjectBoardView extends StatelessWidget {
  final List<Project> projects;
  final Map<String, ProjectTaskMetrics> taskMetricsByProject;
  final void Function(Project project, ProjectStatus newStatus)?
      onProjectStatusChanged;

  const KanbanProjectBoardView({
    super.key,
    required this.projects,
    this.taskMetricsByProject = const {},
    this.onProjectStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = ProjectStatus.values;
        final columnWidth = constraints.maxWidth >= 1000
            ? (constraints.maxWidth / columns.length)
                .clamp(250.0, 400.0)
            : isMobile
                ? 200.0
                : 280.0;

        final content = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final status in columns)
              SizedBox(
                width: columnWidth,
                child: _KanbanProjectColumn(
                  compact: isMobile,
                  status: status,
                  projects: projects
                      .where((p) => p.status == status)
                      .toList(),
                  taskMetricsByProject: taskMetricsByProject,
                  onProjectDropped: onProjectStatusChanged != null
                      ? (project) =>
                          onProjectStatusChanged!(project, status)
                      : null,
                ),
              ),
          ],
        );

        if (constraints.maxWidth >= columnWidth * columns.length) {
          return content;
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: content,
        );
      },
    );
  }
}

class _KanbanProjectColumn extends StatefulWidget {
  final bool compact;
  final ProjectStatus status;
  final List<Project> projects;
  final Map<String, ProjectTaskMetrics> taskMetricsByProject;
  final void Function(Project project)? onProjectDropped;

  const _KanbanProjectColumn({
    this.compact = false,
    required this.status,
    required this.projects,
    required this.taskMetricsByProject,
    this.onProjectDropped,
  });

  @override
  State<_KanbanProjectColumn> createState() => _KanbanProjectColumnState();
}

class _KanbanProjectColumnState extends State<_KanbanProjectColumn> {
  bool _isDragOver = false;

  @override
  Widget build(BuildContext context) {
    final color = ProjectStatusTheme.color(widget.status);

    return DragTarget<Project>(
      onWillAcceptWithDetails: (details) =>
          details.data.status != widget.status,
      onAcceptWithDetails: (details) {
        setState(() => _isDragOver = false);
        widget.onProjectDropped?.call(details.data);
      },
      onMove: (_) {
        if (!_isDragOver) setState(() => _isDragOver = true);
      },
      onLeave: (_) {
        if (_isDragOver) setState(() => _isDragOver = false);
      },
      builder: (context, candidateData, rejectedData) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: _isDragOver
                ? color.withValues(alpha: 0.08)
                : ChromeColors.of(context).isDark
                    ? const Color(0xFF253347)
                    : Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(AppRadius.r12),
            border: Border.all(
              color: _isDragOver
                  ? color.withValues(alpha: 0.5)
                  : ChromeColors.of(context).isDark
                      ? const Color(0xFF334155)
                      : AppColors.cardBorder.withValues(alpha: 0.5),
              width: _isDragOver ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              // Column header
              Padding(
                padding: widget.compact
                    ? const EdgeInsets.fromLTRB(8, 8, 8, 6)
                    : const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Row(
                  children: [
                    Container(
                      width: widget.compact ? 8 : 10,
                      height: widget.compact ? 8 : 10,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: widget.compact ? 4 : 8),
                    Expanded(
                      child: Text(
                        widget.status.displayName,
                        style: TextStyle(
                          fontSize: widget.compact ? 11 : 13,
                          fontWeight: FontWeight.w600,
                          color: ChromeColors.of(context).isDark
                              ? Colors.white
                              : AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Text(
                        '${widget.projects.length}',
                        style: TextStyle(
                          fontSize: widget.compact ? 10 : 11,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Project cards
              Expanded(
                child: widget.projects.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Text(
                            'No ${context.watch<WorkspaceProvider>().projectTerminology}',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                        itemCount: widget.projects.length,
                        itemBuilder: (context, index) {
                          final project = widget.projects[index];
                          return _buildProjectItem(project);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProjectItem(Project project) {
    final isMobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);

    final surfaceColor = Theme.of(context).colorScheme.surface;

    final feedback = Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        width: 260,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.info, width: 2),
        ),
        child: Row(
          children: [
            Icon(Icons.drag_indicator, size: 16, color: AppColors.info),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                project.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );

    final card = KanbanProjectCard(
      project: project,
      taskMetrics: widget.taskMetricsByProject[project.id],
      compact: widget.compact,
    );

    if (isMobile) {
      // On mobile, only a dedicated drag handle initiates a drag. This
      // prevents accidental drags when the user is swiping horizontally
      // between columns or vertically through the list.
      return Stack(
        children: [
          card,
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: LongPressDraggable<Project>(
              data: project,
              feedback: feedback,
              hapticFeedbackOnStart: true,
              child: Container(
                width: 32,
                alignment: Alignment.center,
                color: Colors.transparent,
                child: Icon(
                  Icons.drag_indicator,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Draggable<Project>(
      data: project,
      feedback: feedback,
      childWhenDragging: Opacity(opacity: 0.3, child: card),
      child: card,
    );
  }
}
