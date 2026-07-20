import 'package:flutter/material.dart';
import '../../models/task.dart';
import '../../models/project.dart';
import 'task_simple_table.dart';
import 'timeline_widget.dart';
import 'gantt_toolbar.dart';
import 'timeline_calculator.dart';

class MondayTimelineWidget extends StatefulWidget {
  final Project? project;
  final List<Task> tasks;
  final Function(Task) onTaskTap;
  final Function(Task) onTaskChanged;
  final Function(String) onTaskCreated;

  const MondayTimelineWidget({
    super.key,
    this.project,
    required this.tasks,
    required this.onTaskTap,
    required this.onTaskChanged,
    required this.onTaskCreated,
  });

  @override
  State<MondayTimelineWidget> createState() => _MondayTimelineWidgetState();
}

class _MondayTimelineWidgetState extends State<MondayTimelineWidget> {
  final ScrollController _verticalScrollController1 = ScrollController();
  final ScrollController _verticalScrollController2 = ScrollController();
  bool _isSyncing = false;
  String _currentView = 'Week';

  @override
  void initState() {
    super.initState();
    _verticalScrollController1.addListener(
      () => _syncScroll(_verticalScrollController1, _verticalScrollController2),
    );
    _verticalScrollController2.addListener(
      () => _syncScroll(_verticalScrollController2, _verticalScrollController1),
    );
  }

  @override
  void dispose() {
    _verticalScrollController1.dispose();
    _verticalScrollController2.dispose();
    super.dispose();
  }

  void _syncScroll(ScrollController source, ScrollController target) {
    if (_isSyncing) return;
    _isSyncing = true;
    if (source.hasClients && target.hasClients) {
      target.jumpTo(source.offset);
    }
    _isSyncing = false;
  }

  @override
  Widget build(BuildContext context) {
    // Filter out tasks without dates for the timeline view, or keep them?
    // For now, let's keep all tasks to align with the table.
    // TimelineWidget will need to handle tasks without dates gracefully (e.g. not show a bar but keep the row).

    return Column(
      children: [
        GanttToolbar(
          currentView: _currentView,
          onViewChanged: (view) {
            setState(() {
              _currentView = view;
            });
          },
        ),
        Expanded(
          child: Row(
            children: [
              // Left side: Task Table
              TaskSimpleTable(
                tasks: widget.tasks,
                rowHeight: 50.0,
                scrollController: _verticalScrollController1,
                onTaskTap: widget.onTaskTap,
                onTaskCreated: widget.onTaskCreated,
              ),

              // Right side: Timeline
              Expanded(
                child: TimelineWidget(
                  project: widget.project,
                  tasks: widget.tasks,
                  onTaskTap: widget.onTaskTap,
                  onTaskChanged: widget.onTaskChanged,
                  verticalScrollController: _verticalScrollController2,
                  rowHeight: 50.0,
                  showUnscheduled: true, // Force showing rows for all tasks
                  initialView: _getTimelineView(_currentView),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  TimelineView _getTimelineView(String view) {
    switch (view) {
      case 'Day':
        return TimelineView.day;
      case 'Week':
        return TimelineView.week;
      case 'Month':
        return TimelineView.month;
      case 'Quarter':
        return TimelineView.quarter;
      case 'Year':
        return TimelineView.year;
      default:
        return TimelineView.week;
    }
  }
}
