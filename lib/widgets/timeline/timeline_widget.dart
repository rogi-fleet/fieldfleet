import 'package:flutter/material.dart';
import '../../models/task.dart';
import '../../models/project.dart';
import '../../theme/theme.dart';
import 'timeline_calculator.dart';
import 'timeline_header.dart';
import 'task_timeline_bar.dart';

class TimelineWidget extends StatefulWidget {
  final Project? project;
  final List<Task> tasks;
  final Function(Task) onTaskTap;
  final Function(Task) onTaskChanged;
  final TimelineView initialView;
  final ScrollController? verticalScrollController;
  final double rowHeight;
  final bool showUnscheduled;

  const TimelineWidget({
    super.key,
    this.project,
    required this.tasks,
    required this.onTaskTap,
    required this.onTaskChanged,
    this.initialView = TimelineView.week,
    this.verticalScrollController,
    this.rowHeight = 50.0,
    this.showUnscheduled = false,
  });

  @override
  State<TimelineWidget> createState() => _TimelineWidgetState();
}

class _TimelineWidgetState extends State<TimelineWidget> {
  late TimelineView _currentView;
  late DateTime _anchorDate;
  late ScrollController _scrollController;
  List<DateLabel>? _cachedLabels;
  TimelineView? _cachedView;

  @override
  void initState() {
    super.initState();
    _currentView = widget.initialView;
    _anchorDate = DateTime.now();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _changeView(TimelineView newView) {
    setState(() {
      _currentView = newView;
      _cachedLabels = null; // Clear cache when view changes
    });
  }

  void _scrollToToday() {
    final calculator = TimelineCalculator(
      viewMode: _currentView,
      anchorDate: _anchorDate,
    );
    final range = calculator.getVisibleRange();
    final position = calculator.dateToPixel(DateTime.now(), range.start);

    _scrollController.animateTo(
      position - 100, // Offset to center
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final calculator = TimelineCalculator(
      viewMode: _currentView,
      anchorDate: _anchorDate,
    );
    final range = calculator.getVisibleRange();

    // Use the provided controller or create a local one if not provided
    // We don't dispose the provided controller
    final verticalController = widget.verticalScrollController ?? ScrollController();

    return Column(
      children: [
        // View mode selector and controls
        _buildControls(context),
        const Divider(height: 1),

        // Timeline content
        Expanded(
          child: Column(
            children: [
              // Timeline header
              TimelineHeader(
                calculator: calculator,
                scrollController: _scrollController,
              ),

              // Timeline body with task bars
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: calculator.dateToPixel(range.end, range.start),
                    child: Stack(
                      children: [
                        // Background grid
                        Positioned.fill(
                          child: _buildBackgroundGrid(context, calculator, range),
                        ),

                        // Today indicator
                        TodayIndicator(
                          calculator: calculator,
                          height: (widget.tasks.length * widget.rowHeight) + 100,
                        ),

                        // Task Rows & Dependencies
                        SizedBox(
                          height: widget.tasks.length * widget.rowHeight,
                          child: CustomPaint(
                            painter: DependencyPainter(
                              tasks: widget.tasks,
                              calculator: calculator,
                              rangeStart: range.start,
                              rowHeight: widget.rowHeight,
                            ),
                            child: ListView.builder(
                              controller: verticalController,
                              itemCount: widget.tasks.length,
                              physics: widget.verticalScrollController != null 
                                  ? const NeverScrollableScrollPhysics() // Scroll controlled by parent if provided
                                  : null, 
                              itemBuilder: (context, index) {
                                final task = widget.tasks[index];
                                return Container(
                                  height: widget.rowHeight,
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: Theme.of(context).dividerColor.withOpacity(0.1),
                                      ),
                                    ),
                                  ),
                                  child: Stack(
                                    children: [
                                      if (task.startDate != null || task.dueDate != null)
                                        TaskTimelineBar(
                                          task: task,
                                          calculator: calculator,
                                          rangeStart: range.start,
                                          onTap: () => widget.onTaskTap(task),
                                          onTaskChanged: widget.onTaskChanged,
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildControls(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          // View mode selector
          SegmentedButton<TimelineView>(
            segments: const [
              ButtonSegment(
                value: TimelineView.day,
                label: Text('Day'),
                icon: Icon(Icons.view_day, size: 16),
              ),
              ButtonSegment(
                value: TimelineView.week,
                label: Text('Week'),
                icon: Icon(Icons.view_week, size: 16),
              ),
              ButtonSegment(
                value: TimelineView.month,
                label: Text('Month'),
                icon: Icon(Icons.calendar_view_month, size: 16),
              ),
              ButtonSegment(
                value: TimelineView.quarter,
                label: Text('Quarter'),
                icon: Icon(Icons.calendar_today, size: 16),
              ),
            ],
            selected: {_currentView},
            onSelectionChanged: (Set<TimelineView> newSelection) {
              _changeView(newSelection.first);
            },
          ),
          const Spacer(),

          // Today button
          OutlinedButton.icon(
            onPressed: _scrollToToday,
            icon: const Icon(Icons.today, size: 16),
            label: const Text('Today'),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundGrid(
    BuildContext context,
    TimelineCalculator calculator,
    DateTimeRange range,
  ) {
    final totalWidth = calculator.dateToPixel(range.end, range.start);

    // Cache labels to avoid regenerating on every build
    if (_cachedLabels == null || _cachedView != calculator.viewMode) {
      _cachedLabels = calculator.generateDateLabels();
      _cachedView = calculator.viewMode;
    }
    final labels = _cachedLabels!;

    // Calculate width once based on view mode
    final double columnWidth;
    switch (calculator.viewMode) {
      case TimelineView.day:
        columnWidth = calculator.pixelsPerDay / 24;
        break;
      case TimelineView.week:
        columnWidth = calculator.pixelsPerDay;
        break;
      case TimelineView.month:
        columnWidth = calculator.pixelsPerDay * 7;
        break;
      case TimelineView.quarter:
        columnWidth = calculator.pixelsPerDay * 30;
        break;
      case TimelineView.year:
        columnWidth = calculator.pixelsPerDay * 91;
        break;
    }

    // Limit the number of grid columns to prevent performance issues
    // On Android, rendering too many widgets can cause freezing
    final maxColumns = calculator.viewMode == TimelineView.day
        ? 24  // Max 1 day worth of hours
        : calculator.viewMode == TimelineView.week
            ? 14  // Max 2 weeks
            : calculator.viewMode == TimelineView.month
                ? 4   // Max ~1 month in weeks
                : calculator.viewMode == TimelineView.year
                    ? 8  // Max 2 years in quarters
                    : 3;  // Max 3 months

    final limitedLabels = labels.length > maxColumns
        ? labels.sublist(0, maxColumns)
        : labels;

    return RepaintBoundary(
      child: SizedBox(
        width: totalWidth,
        child: Row(
          children: limitedLabels.map((label) {
            return Container(
              width: columnWidth,
              decoration: BoxDecoration(
                color: label.isWeekend
                    ? Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.1)
                    : null,
                border: Border(
                  right: BorderSide(
                    color: Theme.of(context).dividerColor.withOpacity(0.1),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

}

class DependencyPainter extends CustomPainter {
  final List<Task> tasks;
  final TimelineCalculator calculator;
  final DateTime rangeStart;
  final double rowHeight;

  DependencyPainter({
    required this.tasks,
    required this.calculator,
    required this.rangeStart,
    required this.rowHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.textTertiary
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final taskMap = {for (var t in tasks) t.id: t};

    for (int i = 0; i < tasks.length; i++) {
      final task = tasks[i];
      if (task.predecessorIds.isEmpty) continue;

      final endX = _getTaskEndX(task);
      if (endX == null) continue; // Should not happen if we are drawing dependencies for it? 
      // Actually dependencies are FROM predecessor TO current task.
      // So we need to find predecessors.

      final startX = _getTaskStartX(task);
      if (startX == null) continue;

      final currentY = (i * rowHeight) + (rowHeight / 2);

      for (final predId in task.predecessorIds) {
        final predTask = taskMap[predId];
        if (predTask == null) continue;

        final predIndex = tasks.indexOf(predTask);
        if (predIndex == -1) continue;

        final predEndX = _getTaskEndX(predTask);
        if (predEndX == null) continue;

        final predY = (predIndex * rowHeight) + (rowHeight / 2);

        // Draw line from predEndX, predY to startX, currentY
        final path = Path();
        path.moveTo(predEndX, predY);
        path.lineTo(predEndX + 10, predY); // Small horizontal line out
        path.lineTo(predEndX + 10, currentY); // Vertical line
        path.lineTo(startX, currentY); // Horizontal line to target
        
        canvas.drawPath(path, paint);

        // Draw arrow at startX, currentY
        final arrowPath = Path();
        arrowPath.moveTo(startX, currentY);
        arrowPath.lineTo(startX - 6, currentY - 3);
        arrowPath.lineTo(startX - 6, currentY + 3);
        arrowPath.close();

        final arrowPaint = Paint()
          ..color = AppColors.textTertiary
          ..style = PaintingStyle.fill;

        canvas.drawPath(arrowPath, arrowPaint);
      }
    }
  }

  double? _getTaskStartX(Task task) {
    if (task.startDate != null) {
      return calculator.dateToPixel(task.startDate!, rangeStart);
    }
    if (task.dueDate != null && task.estimatedDuration != null) {
       // Estimate start based on due date - duration
       // For now just use due date as start if no start date? No that's wrong.
       // If only due date, we treat it as a milestone or point?
       return calculator.dateToPixel(task.dueDate!, rangeStart);
    }
    return null;
  }

  double? _getTaskEndX(Task task) {
     if (task.dueDate != null) {
      return calculator.dateToPixel(task.dueDate!, rangeStart);
    }
    if (task.startDate != null && task.estimatedDuration != null) {
       // Calculate end
       // This logic should match TaskTimelineBar
       final days = task.estimatedDuration! / 8.0;
       final endDate = task.startDate!.add(Duration(hours: (days * 24).round()));
       return calculator.dateToPixel(endDate, rangeStart);
    }
    return null;
  }

  @override
  bool shouldRepaint(covariant DependencyPainter oldDelegate) {
    return oldDelegate.tasks != tasks || 
           oldDelegate.calculator != calculator ||
           oldDelegate.rangeStart != rangeStart;
  }
}
