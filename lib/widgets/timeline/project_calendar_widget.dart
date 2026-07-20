import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/project.dart';
import '../../models/project_status_theme.dart';
import '../../models/project_task_metrics.dart';
import '../../providers/workspace_provider.dart';
import '../../theme/theme.dart';
import '../../utils/project_terminology.dart';
import '../project_hover_tooltip.dart';
import 'base_calendar_grid.dart';
import 'project_calendar_card.dart';
import 'undated_projects_banner.dart';

/// Calendar view for displaying projects on a calendar grid.
///
/// Projects are placed on dates based on their [startDate] and
/// [targetCompletionDate]. A project appears on every day between
/// those two dates (inclusive). Projects that only have one of the two
/// dates show on that single date.
///
/// Uses [BaseCalendarGrid] for shared calendar infrastructure.
class ProjectCalendarWidget extends StatefulWidget {
  final List<Project> projects;
  final Map<String, ProjectTaskMetrics> taskMetricsByProject;
  final void Function(Project project)? onProjectTap;
  final void Function(DateTime date)? onDateTap;
  final void Function(DateTime date)? onAddProjectForDate;

  const ProjectCalendarWidget({
    super.key,
    required this.projects,
    this.taskMetricsByProject = const {},
    this.onProjectTap,
    this.onDateTap,
    this.onAddProjectForDate,
  });

  @override
  State<ProjectCalendarWidget> createState() => _ProjectCalendarWidgetState();
}

class _ProjectCalendarWidgetState extends State<ProjectCalendarWidget>
    with BaseCalendarGrid {
  @override
  void initState() {
    super.initState();
    initCalendar();
  }

  @override
  void dispose() {
    disposeCalendar();
    super.dispose();
  }

  // ── Projects without dates ────────────────────────────────────────────

  int get _undatedProjectCount => widget.projects
      .where((p) => p.startDate == null && p.targetCompletionDate == null)
      .length;

  // ── BaseCalendarGrid overrides ────────────────────────────────────────

  @override
  int itemCountForDate(DateTime date) => _getProjectsForDate(date).length;

  @override
  void onCalendarDateTap(DateTime date) =>
      widget.onDateTap?.call(date);

  @override
  void onCalendarDateDoubleTap(DateTime date) =>
      widget.onAddProjectForDate?.call(date);

  @override
  Widget build(BuildContext context) {
    final undated = _undatedProjectCount;

    if (undated == 0) return buildCalendar();

    // Show a banner above the calendar for projects missing dates
    return Column(
      children: [
        UndatedProjectsBanner(count: undated),
        Expanded(child: buildCalendar()),
      ],
    );
  }


  // ── Day view ──────────────────────────────────────────────────────────

  @override
  Widget buildDayViewBody(DateTime date) {
    final projectsForDay = _getProjectsForDate(date);

    return Stack(
      children: [
        SingleChildScrollView(
          controller: calendarScrollController,
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (projectsForDay.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xxxl),
                    child: Column(
                      children: [
                        Icon(
                          Icons.folder_outlined,
                          size: 48,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No ${context.read<WorkspaceProvider>().projectTerminology} for this day',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...projectsForDay.map(
                  (project) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildExpandedProjectCard(project),
                  ),
                ),
            ],
          ),
        ),
        if (widget.onAddProjectForDate != null)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.small(
              onPressed: () => widget.onAddProjectForDate?.call(date),
              tooltip: 'Add ${singularProjectTerminology(context.read<WorkspaceProvider>().projectTerminology)}',
              child: const Icon(Icons.add),
            ),
          ),
      ],
    );
  }

  Widget _buildExpandedProjectCard(Project project) {
    final accentColor = ProjectStatusTheme.color(project.status);
    final metrics = widget.taskMetricsByProject[project.id];

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => widget.onProjectTap?.call(project),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border(left: BorderSide(color: accentColor, width: 4)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            project.status.displayName,
                            style: TextStyle(fontSize: 11, color: accentColor),
                          ),
                        ),
                        if (metrics != null && metrics.totalCount > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            '${metrics.completedCount}/${metrics.totalCount} tasks',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (project.customerName != null &&
                        project.customerName!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.business_outlined,
                            size: 12,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            project.customerName!,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  // ── Week cell ─────────────────────────────────────────────────────────

  @override
  Widget? buildWeekCellAddButton(DateTime date) {
    if (widget.onAddProjectForDate == null) return null;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => widget.onAddProjectForDate?.call(date),
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .primary
                .withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
          child: Icon(
            Icons.add,
            size: 14,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }

  @override
  Widget buildWeekCellBody(DateTime date) {
    final projectsForDay = _getProjectsForDate(date);
    return Column(
      children: projectsForDay
          .map((project) => _buildProjectCard(project))
          .toList(),
    );
  }

  // ── Month cell ────────────────────────────────────────────────────────

  @override
  Widget buildMonthCellBody(DateTime date, bool isCurrentMonth) {
    final projectsForDay = _getProjectsForDate(date);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: projectsForDay
          .take(5)
          .map((project) => _buildProjectCard(project))
          .toList(),
    );
  }

  @override
  Widget buildMonthCellFooter(DateTime date) {
    final projectsForDay = _getProjectsForDate(date);
    return Padding(
      padding: const EdgeInsets.only(left: 6, right: 4, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (projectsForDay.length > 5)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    currentDate = date;
                    calendarRange = CalendarRange.day;
                  });
                },
                child: Text(
                  '+${projectsForDay.length - 5} more',
                  style: TextStyle(
                    fontSize: 9,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.underline,
                    decorationColor: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            )
          else
            const SizedBox.shrink(),
          if (widget.onAddProjectForDate != null)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => widget.onAddProjectForDate?.call(date),
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                  child: Icon(
                    Icons.add,
                    size: 14,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Shared card builder (wraps with tooltip) ──────────────────────────

  Widget _buildProjectCard(Project project) {
    return ProjectHoverTooltip(
      project: project,
      taskMetrics: widget.taskMetricsByProject[project.id],
      child: ProjectCalendarCard(
        project: project,
        taskMetrics: widget.taskMetricsByProject[project.id],
        customerName: project.customerName,
        accentColor: ProjectStatusTheme.color(project.status),
        onTap: () => widget.onProjectTap?.call(project),
      ),
    );
  }

  // ── Project date matching ─────────────────────────────────────────────

  List<Project> _getProjectsForDate(DateTime date) {
    return widget.projects.where((project) {
      final normalizedDate = DateTime(date.year, date.month, date.day);

      if (project.startDate != null) {
        final start = DateTime(
          project.startDate!.year,
          project.startDate!.month,
          project.startDate!.day,
        );
        if (start == normalizedDate) return true;
      }

      if (project.targetCompletionDate != null) {
        final target = DateTime(
          project.targetCompletionDate!.year,
          project.targetCompletionDate!.month,
          project.targetCompletionDate!.day,
        );
        if (target == normalizedDate) return true;
      }

      if (project.startDate != null && project.targetCompletionDate != null) {
        final normalizedStart = DateTime(
          project.startDate!.year,
          project.startDate!.month,
          project.startDate!.day,
        );
        final normalizedEnd = DateTime(
          project.targetCompletionDate!.year,
          project.targetCompletionDate!.month,
          project.targetCompletionDate!.day,
        );

        if (normalizedDate.isAfter(normalizedStart) &&
            normalizedDate.isBefore(normalizedEnd)) {
          return true;
        }
      }

      return false;
    }).toList();
  }
}
