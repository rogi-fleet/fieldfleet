import 'package:flutter/material.dart';
import '../../models/project.dart';
import '../../models/project_status_theme.dart';
import '../../models/project_task_metrics.dart';
import '../../theme/theme.dart';
import 'gantt_toolbar.dart';
import 'project_gantt_bar.dart';
import 'timeline_calculator.dart';
import 'undated_projects_banner.dart';

/// Gantt chart view for the project list.
///
/// Displays each project as a horizontal bar on a scrollable timeline,
/// colored by [ProjectStatus]. Reuses [TimelineCalculator] and
/// [GanttToolbar] from the task Gantt infrastructure.
class ProjectGanttView extends StatefulWidget {
  final List<Project> projects;
  final Map<String, ProjectTaskMetrics> taskMetricsByProject;
  final void Function(Project project)? onProjectTap;

  const ProjectGanttView({
    super.key,
    required this.projects,
    this.taskMetricsByProject = const {},
    this.onProjectTap,
  });

  @override
  State<ProjectGanttView> createState() => _ProjectGanttViewState();
}

class _ProjectGanttViewState extends State<ProjectGanttView> {
  // Scroll controllers — bidirectional sync between left pane and timeline
  final ScrollController _verticalLeftController = ScrollController();
  final ScrollController _verticalRightController = ScrollController();
  final ScrollController _horizontalBodyController = ScrollController();
  final ScrollController _horizontalHeaderController = ScrollController();

  late TimelineCalculator _calculator;
  late DateTime _rangeStart;
  late DateTime _rangeEnd;
  String _currentView = 'Month';
  bool _isSidebarCollapsed = false;

  static const double _rowHeight = 56.0;
  static const double _leftPaneWidth = 320.0;
  static const double _leftPaneWidthMobile = 200.0;

  // Cached on project list change (initState / didUpdateWidget)
  late List<Project> _datedProjects;
  late int _undatedCount;

  bool get _isMobile => MediaQuery.of(context).size.width < AppBreakpoints.mobile;

  double get _effectiveLeftWidth => _isMobile ? _leftPaneWidthMobile : _leftPaneWidth;

  // ── Lifecycle ────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initializeTimeline();
    _syncScrollControllers();
    WidgetsBinding.instance.addPostFrameCallback((_) => scrollToToday());
  }

  @override
  void didUpdateWidget(ProjectGanttView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projects != widget.projects) {
      _initializeTimeline();
    }
  }

  @override
  void dispose() {
    _verticalLeftController.dispose();
    _verticalRightController.dispose();
    _horizontalBodyController.dispose();
    _horizontalHeaderController.dispose();
    super.dispose();
  }

  void _initializeTimeline() {
    _datedProjects = widget.projects
        .where((p) => p.startDate != null || p.targetCompletionDate != null)
        .toList();
    _undatedCount = widget.projects.length - _datedProjects.length;

    DateTime? earliest;
    DateTime? latest;
    for (final p in _datedProjects) {
      final s = p.startDate;
      final e = p.targetCompletionDate;
      if (s != null && (earliest == null || s.isBefore(earliest))) earliest = s;
      if (e != null && (latest == null || e.isAfter(latest))) latest = e;
    }

    final now = DateTime.now();
    final rawStart = earliest?.subtract(const Duration(days: 45)) ?? now.subtract(const Duration(days: 60));
    final rawEnd = latest?.add(const Duration(days: 60)) ?? now.add(const Duration(days: 90));

    // Snap to month boundaries for clean header alignment
    _rangeStart = DateTime(rawStart.year, rawStart.month, 1);
    _rangeEnd = DateTime(rawEnd.year, rawEnd.month + 1, 1);

    // Ensure at least 90 days of visible range
    if (_rangeEnd.difference(_rangeStart).inDays < 90) {
      _rangeEnd = _rangeStart.add(const Duration(days: 90));
    }

    _calculator = _createCalculator(TimelineView.fromLabel(_currentView));
  }

  void _syncScrollControllers() {
    // Horizontal: header follows body
    _horizontalBodyController.addListener(() {
      if (_horizontalHeaderController.hasClients) {
        _horizontalHeaderController.jumpTo(_horizontalBodyController.offset);
      }
    });

    // Vertical: bidirectional sync between left pane and timeline
    bool isSyncing = false;
    _verticalLeftController.addListener(() {
      if (isSyncing) return;
      if (_verticalRightController.hasClients) {
        isSyncing = true;
        _verticalRightController.jumpTo(_verticalLeftController.offset);
        isSyncing = false;
      }
    });
    _verticalRightController.addListener(() {
      if (isSyncing) return;
      if (_verticalLeftController.hasClients) {
        isSyncing = true;
        _verticalLeftController.jumpTo(_verticalRightController.offset);
        isSyncing = false;
      }
    });
  }

  void scrollToToday() {
    if (!_horizontalBodyController.hasClients) return;
    final today = DateTime.now();
    final daysDiff = today.difference(_rangeStart).inDays;
    final targetOffset = daysDiff * _calculator.pixelsPerDay;
    final viewportWidth = _horizontalBodyController.position.viewportDimension;
    final centeredOffset = targetOffset - (viewportWidth / 2);
    final maxOffset = _horizontalBodyController.position.maxScrollExtent;
    _horizontalBodyController.animateTo(
      centeredOffset.clamp(0.0, maxOffset),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  TimelineCalculator _createCalculator(TimelineView viewMode) {
    return TimelineCalculator(
      viewMode: viewMode,
      anchorDate: DateTime.now(),
    );
  }


  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final datedProjects = _datedProjects;
    final undated = _undatedCount;
    final totalDays = _rangeEnd.difference(_rangeStart).inDays;
    final timelineWidth = _calculator.pixelsPerDay * totalDays;
    final chrome = ChromeColors.of(context);

    return Container(
      margin: chrome.isDark
          ? const EdgeInsets.symmetric(horizontal: AppSpacing.xs)
          : EdgeInsets.zero,
      clipBehavior: chrome.isDark ? Clip.antiAlias : Clip.none,
      decoration: chrome.isDark
          ? BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x30000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            )
          : const BoxDecoration(),
      child: Column(
      children: [
        GanttToolbar(
          currentView: _currentView,
          onScrollToToday: scrollToToday,
          onViewChanged: (view) {
            setState(() {
              _currentView = view;
              _calculator = _createCalculator(TimelineView.fromLabel(view));
            });
            WidgetsBinding.instance.addPostFrameCallback((_) => scrollToToday());
          },
          onZoomIn: () {
            bool changed = true;
            setState(() {
              switch (_currentView) {
                case 'Year':
                  _currentView = 'Quarter';
                  break;
                case 'Quarter':
                  _currentView = 'Month';
                  break;
                case 'Month':
                  _currentView = 'Week';
                  break;
                case 'Week':
                  _currentView = 'Day';
                  break;
                case 'Day':
                  changed = false;
                  return;
              }
              _calculator = _createCalculator(TimelineView.fromLabel(_currentView));
            });
            if (changed) {
              WidgetsBinding.instance.addPostFrameCallback((_) => scrollToToday());
            }
          },
          onZoomOut: () {
            bool changed = true;
            setState(() {
              switch (_currentView) {
                case 'Day':
                  _currentView = 'Week';
                  break;
                case 'Week':
                  _currentView = 'Month';
                  break;
                case 'Month':
                  _currentView = 'Quarter';
                  break;
                case 'Quarter':
                  _currentView = 'Year';
                  break;
                case 'Year':
                  changed = false;
                  return;
              }
              _calculator = _createCalculator(TimelineView.fromLabel(_currentView));
            });
            if (changed) {
              WidgetsBinding.instance.addPostFrameCallback((_) => scrollToToday());
            }
          },
        ),

        if (undated > 0) UndatedProjectsBanner(count: undated),

        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // LEFT: Fixed columns
              if (!_isSidebarCollapsed)
                SizedBox(
                  width: _effectiveLeftWidth,
                  child: Column(
                    children: [
                      _buildLeftHeader(),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _verticalLeftController,
                          physics: const ClampingScrollPhysics(),
                          child: Column(
                            children: [
                              for (final project in datedProjects)
                                _buildLeftRow(project),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Divider with collapse toggle
              _buildDivider(),

              // RIGHT: Timeline
              Expanded(
                child: Column(
                  children: [
                    // Timeline header
                    SizedBox(
                      height: _rowHeight,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        controller: _horizontalHeaderController,
                        physics: const NeverScrollableScrollPhysics(),
                        child: SizedBox(
                          width: timelineWidth,
                          child: _buildTimelineHeader(),
                        ),
                      ),
                    ),

                    // Timeline body
                    Expanded(
                      child: ScrollbarTheme(
                        data: ScrollbarThemeData(
                          thumbVisibility: WidgetStateProperty.all(true),
                          trackVisibility: WidgetStateProperty.all(true),
                          thickness: WidgetStateProperty.all(12),
                          radius: const Radius.circular(6),
                          thumbColor: WidgetStateProperty.all(AppColors.textSecondary),
                          trackColor: WidgetStateProperty.all(AppColors.cardBorder),
                        ),
                        child: Scrollbar(
                          controller: _horizontalBodyController,
                          thumbVisibility: true,
                          trackVisibility: true,
                          thickness: 12,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            controller: _horizontalBodyController,
                            child: SizedBox(
                              width: timelineWidth,
                              child: SingleChildScrollView(
                                controller: _verticalRightController,
                                physics: const ClampingScrollPhysics(),
                                child: Stack(
                                  children: [
                                    Column(
                                      children: [
                                        for (final project in datedProjects)
                                          SizedBox(
                                            height: _rowHeight,
                                            child: Stack(
                                              children: [
                                                Container(
                                                  decoration: BoxDecoration(
                                                    border: Border(
                                                      bottom: BorderSide(
                                                        color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                ProjectGanttBar(
                                                  project: project,
                                                  calculator: _calculator,
                                                  rangeStart: _rangeStart,
                                                  rowHeight: _rowHeight,
                                                  taskMetrics: widget.taskMetricsByProject[project.id],
                                                  onTap: widget.onProjectTap != null
                                                      ? () => widget.onProjectTap!(project)
                                                      : null,
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),

                                    // Today indicator
                                    Builder(
                                      builder: (context) {
                                        final todayX = _calculator.dateToPixel(DateTime.now(), _rangeStart);
                                        return Positioned(
                                          left: todayX - 12,
                                          top: 0,
                                          bottom: 0,
                                          child: Column(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppColors.error,
                                                  borderRadius: BorderRadius.circular(AppRadius.sm),
                                                ),
                                                child: const Text(
                                                  'Today',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Expanded(
                                                child: Container(
                                                  width: 2,
                                                  color: AppColors.error.withValues(alpha: 0.6),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
      ),
    );
  }

  // ── Left pane widgets ────────────────────────────────────────────────

  Widget _buildLeftHeader() {
    final chrome = ChromeColors.of(context);
    final effectiveChrome = chrome.isDark ? ChromeColors.light : chrome;
    return Container(
      height: _rowHeight,
      decoration: BoxDecoration(
        color: effectiveChrome.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 2),
          right: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              'Project',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: effectiveChrome.text,
              ),
            ),
          ),
          SizedBox(
            width: _isMobile ? 70 : 90,
            child: Text(
              'Status',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: effectiveChrome.text,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildLeftRow(Project project) {
    final chrome = ChromeColors.of(context);
    final effectiveChrome = chrome.isDark ? ChromeColors.light : chrome;
    final statusColor = ProjectStatusTheme.color(project.status);

    return Semantics(
      label: '${project.name}, ${project.status.displayName}',
      button: widget.onProjectTap != null,
      child: GestureDetector(
        onTap: widget.onProjectTap != null
            ? () => widget.onProjectTap!(project)
            : null,
        child: Container(
        height: _rowHeight,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
            ),
            right: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
            ),
          ),
        ),
        child: Row(
          children: [
            // Status color indicator dot
            const SizedBox(width: 12),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            // Project name
            Expanded(
              flex: 3,
              child: Text(
                project.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: effectiveChrome.textActive,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Status badge
            SizedBox(
              width: _isMobile ? 70 : 90,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text(
                  project.status.displayName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
      ),
    );
  }

  // ── Divider ──────────────────────────────────────────────────────────

  Widget _buildDivider() {
    final chrome = ChromeColors.of(context);
    final effectiveChrome = chrome.isDark ? ChromeColors.light : chrome;
    return GestureDetector(
      onTap: () => setState(() => _isSidebarCollapsed = !_isSidebarCollapsed),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 8,
          color: Colors.transparent,
          child: Center(
            child: Container(
              width: 1,
              color: Theme.of(context).dividerColor,
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Container(
                    width: 12,
                    height: 18,
                    decoration: BoxDecoration(
                      color: effectiveChrome.surface,
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    child: Icon(
                      _isSidebarCollapsed ? Icons.chevron_right : Icons.chevron_left,
                      size: 12,
                      color: effectiveChrome.text,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Timeline header ──────────────────────────────────────────────────

  static const _kMonthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                                'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  Widget _buildTimelineHeader() {
    final pixelsPerDay = _calculator.pixelsPerDay;
    final borderSide = BorderSide(
      color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
    );
    final textColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7);
    const textStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.w500);

    List<Widget> columns;

    switch (_calculator.viewMode) {
      case TimelineView.year:
      case TimelineView.quarter:
        // Monthly columns with exact day-count widths
        columns = [];
        var current = DateTime(_rangeStart.year, _rangeStart.month, 1);
        while (current.isBefore(_rangeEnd)) {
          final next = DateTime(current.year, current.month + 1, 1);
          final days = next.difference(current).inDays;
          columns.add(Container(
            width: pixelsPerDay * days,
            decoration: BoxDecoration(
              border: Border(right: borderSide),
            ),
            child: Center(
              child: Text(
                _kMonthNames[current.month - 1],
                style: textStyle.copyWith(color: textColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ));
          current = next;
        }

      case TimelineView.month:
        // Weekly columns — show "MMM d" for the week's start date
        columns = [];
        var current = _rangeStart;
        while (current.isBefore(_rangeEnd)) {
          columns.add(Container(
            width: pixelsPerDay * 7,
            decoration: BoxDecoration(
              border: Border(right: borderSide),
            ),
            child: Center(
              child: Text(
                '${_kMonthNames[current.month - 1]} ${current.day}',
                style: textStyle.copyWith(color: textColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ));
          current = current.add(const Duration(days: 7));
        }

      case TimelineView.week:
        // Daily columns
        columns = [];
        var current = _rangeStart;
        const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        while (current.isBefore(_rangeEnd)) {
          final isWeekend = current.weekday >= 6;
          columns.add(Container(
            width: pixelsPerDay,
            decoration: BoxDecoration(
              color: isWeekend
                  ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
                  : null,
              border: Border(right: borderSide),
            ),
            child: Center(
              child: Text(
                '${dayNames[current.weekday - 1]} ${current.month}/${current.day}',
                style: textStyle.copyWith(
                  color: isWeekend ? textColor.withValues(alpha: 0.57) : textColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ));
          current = current.add(const Duration(days: 1));
        }

      case TimelineView.day:
        // Daily columns — pixelsPerDay (120px) is enough for a short date label
        columns = [];
        var current = _rangeStart;
        const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        while (current.isBefore(_rangeEnd)) {
          final isWeekend = current.weekday >= 6;
          columns.add(Container(
            width: pixelsPerDay,
            decoration: BoxDecoration(
              color: isWeekend
                  ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
                  : null,
              border: Border(right: borderSide),
            ),
            child: Center(
              child: Text(
                '${dayNames[current.weekday - 1]} ${current.month}/${current.day}',
                style: textStyle.copyWith(
                  color: isWeekend ? textColor.withValues(alpha: 0.57) : textColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ));
          current = current.add(const Duration(days: 1));
        }
    }

    return Container(
      height: _rowHeight,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 2),
        ),
      ),
      child: Row(children: columns),
    );
  }

}
