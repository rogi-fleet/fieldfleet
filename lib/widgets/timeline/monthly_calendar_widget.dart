import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/task.dart';
import '../../models/project.dart';
import '../../models/user.dart';
import '../../theme/theme.dart';
import 'base_calendar_grid.dart';
export 'base_calendar_grid.dart' show CalendarRange;
import 'task_calendar_card.dart';
import 'task_calendar_color_resolver.dart';

/// Calendar view for displaying tasks on a calendar grid.
///
/// Uses [BaseCalendarGrid] for shared calendar infrastructure (header,
/// navigation, day/week/month grid) and supplies task-specific rendering.
class MonthlyCalendarWidget extends StatefulWidget {
  final Project? project;
  final List<Task> tasks;
  final Map<String, AppUser> usersMap;
  final String? projectAddress;
  final void Function(Task task)? onTaskTap;
  final void Function(DateTime date)? onDateTap;
  final void Function(DateTime date)? onAddTaskForDate;
  final void Function(DateTime date, List<Task> tasks)? onShowMoreTasks;
  final void Function(Task task, DateTime newDate)? onTaskDateChanged;

  const MonthlyCalendarWidget({
    super.key,
    this.project,
    required this.tasks,
    this.usersMap = const {},
    this.projectAddress,
    this.onTaskTap,
    this.onDateTap,
    this.onAddTaskForDate,
    this.onShowMoreTasks,
    this.onTaskDateChanged,
  });

  @override
  State<MonthlyCalendarWidget> createState() => _MonthlyCalendarWidgetState();
}

class _MonthlyCalendarWidgetState extends State<MonthlyCalendarWidget>
    with BaseCalendarGrid {
  DateTime?
      _dragTargetDate; // Track which date cell is being hovered during drag

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

  TaskCalendarColorResolver get _colorResolver => TaskCalendarColorResolver(
        tasks: widget.tasks,
        preferPhaseColors: widget.project != null,
      );

  // ── BaseCalendarGrid overrides ────────────────────────────────────────

  @override
  int itemCountForDate(DateTime date) => _getTasksForDate(date).length;

  @override
  void onCalendarDateTap(DateTime date) =>
      widget.onDateTap?.call(date);

  @override
  void onCalendarDateDoubleTap(DateTime date) =>
      widget.onAddTaskForDate?.call(date);

  @override
  Widget build(BuildContext context) => buildCalendar();

  bool _isDragTarget(DateTime date) =>
      _dragTargetDate != null &&
      _dragTargetDate!.year == date.year &&
      _dragTargetDate!.month == date.month &&
      _dragTargetDate!.day == date.day;

  @override
  Color? monthCellBackgroundColor(DateTime date) {
    if (_isDragTarget(date)) {
      return Theme.of(context).colorScheme.primary.withValues(alpha: 0.15);
    }
    return null;
  }

  @override
  BorderSide? monthCellRightBorder(DateTime date) {
    if (_isDragTarget(date)) {
      return BorderSide(
        color: Theme.of(context).colorScheme.primary,
        width: 2,
      );
    }
    return null;
  }

  @override
  Widget wrapMonthDayCell(DateTime date, Widget child) {
    if (widget.onTaskDateChanged == null) return child;

    return DragTarget<Task>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) {
        final normalizedDate = DateTime(date.year, date.month, date.day);
        widget.onTaskDateChanged?.call(details.data, normalizedDate);
        setState(() => _dragTargetDate = null);
      },
      onMove: (_) {
        if (_dragTargetDate?.day != date.day ||
            _dragTargetDate?.month != date.month ||
            _dragTargetDate?.year != date.year) {
          setState(() => _dragTargetDate = date);
        }
      },
      onLeave: (_) {
        if (_dragTargetDate != null) {
          setState(() => _dragTargetDate = null);
        }
      },
      builder: (context, candidateData, rejectedData) => child,
    );
  }

  // ── Day view ──────────────────────────────────────────────────────────

  @override
  Widget buildDayViewBody(DateTime date) {
    final tasksForDay = _getTasksForDate(date);

    return Stack(
      children: [
        SingleChildScrollView(
          controller: calendarScrollController,
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (tasksForDay.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xxxl),
                    child: Column(
                      children: [
                        Icon(
                          Icons.task_outlined,
                          size: 48,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No tasks for this day',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...tasksForDay.map(
                  (task) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildExpandedTaskCard(task),
                  ),
                ),
            ],
          ),
        ),
        if (widget.onAddTaskForDate != null)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.small(
              onPressed: () => widget.onAddTaskForDate?.call(date),
              tooltip: 'Add task',
              child: const Icon(Icons.add),
            ),
          ),
      ],
    );
  }

  Widget _buildExpandedTaskCard(Task task) {
    final colorResolver = _colorResolver;
    final accentColor = colorResolver.accentColorFor(task);
    final statusColor = colorResolver.statusColorForTask(task);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => widget.onTaskTap?.call(task),
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
                      task.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                        decoration: task.isComplete
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _statusLabel(task.status),
                        style: TextStyle(fontSize: 11, color: statusColor),
                      ),
                    ),
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
    if (widget.onAddTaskForDate == null) return null;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => widget.onAddTaskForDate?.call(date),
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
    final tasksForDay = _getTasksForDate(date);
    return Column(
      children: tasksForDay
          .map(
            (task) => TaskCalendarCard(
              task: task,
              usersMap: widget.usersMap,
              location: widget.projectAddress,
              accentColor: _colorResolver.accentColorFor(task),
              statusIndicatorColor:
                  _colorResolver.shouldShowStatusIndicator(task)
                      ? _colorResolver.statusColorForTask(task)
                      : null,
              onTap: () => widget.onTaskTap?.call(task),
            ),
          )
          .toList(),
    );
  }

  // ── Month cell ────────────────────────────────────────────────────────

  /// The month view needs drag-and-drop support, so we override the base
  /// class's cell building by overriding [build] to delegate to
  /// [buildCalendar] and keeping custom drag logic in a separate layer.
  ///
  /// We achieve this by NOT using the base class month cell for tasks —
  /// instead we override buildMonthCellBody to render draggable cards.

  @override
  Widget buildMonthCellBody(DateTime date, bool isCurrentMonth) {
    final tasksForDay = _getTasksForDate(date);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: tasksForDay.take(5).map((task) {
        final isMobile = !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.iOS ||
                defaultTargetPlatform == TargetPlatform.android);
        final feedbackWidget = Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 150,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
            child: Text(
              task.title,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
        final whenDragging = Opacity(
          opacity: 0.3,
          child: TaskCalendarCard(
            task: task,
            usersMap: widget.usersMap,
            location: widget.projectAddress,
            accentColor: _colorResolver.accentColorFor(task),
            statusIndicatorColor:
                _colorResolver.shouldShowStatusIndicator(task)
                    ? _colorResolver.statusColorForTask(task)
                    : null,
            onTap: () => widget.onTaskTap?.call(task),
          ),
        );
        final cardChild = TaskCalendarCard(
          task: task,
          usersMap: widget.usersMap,
          location: widget.projectAddress,
          accentColor: _colorResolver.accentColorFor(task),
          statusIndicatorColor:
              _colorResolver.shouldShowStatusIndicator(task)
                  ? _colorResolver.statusColorForTask(task)
                  : null,
          onTap: () => widget.onTaskTap?.call(task),
        );
        if (isMobile) {
          return LongPressDraggable<Task>(
            data: task,
            feedback: feedbackWidget,
            childWhenDragging: whenDragging,
            hapticFeedbackOnStart: true,
            child: cardChild,
          );
        }
        return Draggable<Task>(
          data: task,
          feedback: feedbackWidget,
          childWhenDragging: whenDragging,
          child: cardChild,
        );
      }).toList(),
    );
  }

  @override
  Widget buildMonthCellFooter(DateTime date) {
    final tasksForDay = _getTasksForDate(date);
    return Padding(
      padding: const EdgeInsets.only(left: 6, right: 4, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (tasksForDay.length > 5)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => widget.onShowMoreTasks?.call(date, tasksForDay),
                child: Text(
                  '+${tasksForDay.length - 5} more',
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
          if (widget.onAddTaskForDate != null)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => widget.onAddTaskForDate?.call(date),
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

  // ── Task date matching ────────────────────────────────────────────────

  List<Task> _getTasksForDate(DateTime date) {
    return widget.tasks.where((task) {
      if (task.startDate != null) {
        final startDate = task.startDate!;
        if (startDate.year == date.year &&
            startDate.month == date.month &&
            startDate.day == date.day) {
          return true;
        }
      }

      if (task.dueDate != null) {
        final dueDate = task.dueDate!;
        if (dueDate.year == date.year &&
            dueDate.month == date.month &&
            dueDate.day == date.day) {
          return true;
        }
      }

      if (task.startDate != null && task.dueDate != null) {
        final normalizedDate = DateTime(date.year, date.month, date.day);
        final normalizedStart = DateTime(
          task.startDate!.year,
          task.startDate!.month,
          task.startDate!.day,
        );
        final normalizedEnd = DateTime(
          task.dueDate!.year,
          task.dueDate!.month,
          task.dueDate!.day,
        );

        if (normalizedDate.isAfter(normalizedStart) &&
            normalizedDate.isBefore(normalizedEnd)) {
          return true;
        }
      }

      return false;
    }).toList();
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'working_on_it':
      case 'working on it':
      case 'in_progress':
      case 'in progress':
        return 'Working on it';
      case 'not_started':
      case 'not started':
        return 'Not started';
      case 'done':
      case 'complete':
      case 'completed':
        return 'Done';
      case 'stuck':
      case 'blocked':
        return 'Stuck';
      default:
        return status.replaceAll('_', ' ');
    }
  }
}
