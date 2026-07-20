import 'package:flutter/material.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import '../../models/task.dart';
import '../../models/project.dart';
import '../../services/service_locator.dart';
import 'task_gantt_table.dart';
import 'timeline_widget.dart';
import 'gantt_toolbar.dart';
import 'timeline_calculator.dart';

class MondayGanttWidget extends StatefulWidget {
  final Project? project;
  final List<Task> tasks;
  final Function(Task) onTaskTap;
  final String workspaceId;

  const MondayGanttWidget({
    super.key,
    this.project,
    required this.tasks,
    required this.onTaskTap,
    required this.workspaceId,
  });

  @override
  State<MondayGanttWidget> createState() => _MondayGanttWidgetState();
}

class _MondayGanttWidgetState extends State<MondayGanttWidget> {
  final ScrollController _verticalScrollController1 = ScrollController();
  final ScrollController _verticalScrollController2 = ScrollController();
  final _taskService = ServiceLocator.taskService;
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
              // Left side: Gantt Table
              TaskGanttTable(
                tasks: widget.tasks,
                rowHeight: 50.0,
                scrollController: _verticalScrollController1,
                onTaskTap: widget.onTaskTap,
                onTaskCreated: _handleTaskCreated,
                onExpandChanged: _handleExpandChanged,
                onStatusChanged: _handleStatusChanged,
                onPriorityChanged: _handlePriorityChanged,
              ),

              // Right side: Timeline
              Expanded(
                child: TimelineWidget(
                  project: widget.project,
                  tasks: widget.tasks,
                  onTaskTap: widget.onTaskTap,
                  onTaskChanged: _handleTaskChanged,
                  verticalScrollController: _verticalScrollController2,
                  rowHeight: 50.0,
                  showUnscheduled: true,
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

  void _handleTaskCreated(String title, String? parentId) async {
    if (widget.project == null) return;

    try {
      if (parentId != null) {
        // Create child task
        await _taskService.createChildTask(
          workspaceId: widget.workspaceId,
          projectId: widget.project!.id,
          title: title,
          parentId: parentId,
        );
      } else {
        // Create root task
        await _taskService.createTask(
          workspaceId: widget.workspaceId,
          projectId: widget.project!.id,
          title: title,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'creating task'),
            ),
          ),
        );
      }
    }
  }

  void _handleExpandChanged(Task task, bool isExpanded) async {
    try {
      await _taskService.updateTaskExpansion(task.id, isExpanded);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'updating task'),
            ),
          ),
        );
      }
    }
  }

  void _handleStatusChanged(Task task, String newStatus) async {
    try {
      await _taskService.updateTaskStatus(task.id, newStatus);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'updating status'),
            ),
          ),
        );
      }
    }
  }

  void _handlePriorityChanged(Task task, String newPriority) async {
    try {
      await _taskService.updateTaskPriority(task.id, newPriority);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'updating priority'),
            ),
          ),
        );
      }
    }
  }

  void _handleTaskChanged(Task updatedTask) async {
    try {
      await _taskService.updateTask(
        taskId: updatedTask.id,
        startDate: updatedTask.startDate,
        dueDate: updatedTask.dueDate,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'updating task'),
            ),
          ),
        );
      }
    }
  }
}
