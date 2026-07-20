import 'package:flutter/material.dart';
import '../../models/task.dart';
import '../../theme/theme.dart';
import 'timeline_calculator.dart';

class TaskTimelineBar extends StatefulWidget {
  final Task task;
  final TimelineCalculator calculator;
  final DateTime rangeStart;
  final VoidCallback onTap;
  final Function(Task) onTaskChanged;
  final double height;

  const TaskTimelineBar({
    super.key,
    required this.task,
    required this.calculator,
    required this.rangeStart,
    required this.onTap,
    required this.onTaskChanged,
    this.height = 30.0,
  });

  @override
  State<TaskTimelineBar> createState() => _TaskTimelineBarState();
}

class _TaskTimelineBarState extends State<TaskTimelineBar> {
  double? _dragOffset;
  double? _resizeStartOffset;
  double? _resizeEndOffset;
  bool _isDragging = false;
  double _totalDragDistance = 0;

  @override
  Widget build(BuildContext context) {
    // Get task position and width
    final originalPosition = widget.calculator.getTaskPosition(
      widget.task.startDate,
      widget.task.dueDate,
      widget.rangeStart,
    );
    final originalWidth = widget.calculator.getTaskWidth(
      widget.task.startDate,
      widget.task.dueDate,
      widget.task.estimatedDuration,
    );

    // Apply drag/resize offsets
    final position = originalPosition + (_dragOffset ?? 0) + (_resizeStartOffset ?? 0);
    final width = (originalWidth + (_resizeEndOffset ?? 0) - (_resizeStartOffset ?? 0))
        .clamp(widget.calculator.pixelsPerDay * 0.5, double.infinity);

    // Determine bar color based on task status
    final barColor = _getTaskColor(context);

    return Positioned(
      left: position,
      child: SizedBox(
        width: width,
        height: 48,
        child: Stack(
          children: [
            // Main task bar (draggable to move)
            Positioned(
              left: 8,
              right: 8,
              top: 4,
              bottom: 4,
              child: GestureDetector(
                onHorizontalDragStart: (_) {
                  setState(() {
                    _isDragging = true;
                    _dragOffset = 0;
                    _totalDragDistance = 0;
                  });
                },
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _dragOffset = (_dragOffset ?? 0) + details.delta.dx;
                    _totalDragDistance += details.delta.dx.abs();
                  });
                },
                onHorizontalDragEnd: (_) {
                  if (_totalDragDistance < 5) {
                    widget.onTap();
                    setState(() {
                      _isDragging = false;
                      _dragOffset = null;
                      _totalDragDistance = 0;
                    });
                  } else {
                    _commitChange(originalPosition, originalWidth);
                  }
                },
                child: MouseRegion(
                  cursor: _isDragging ? SystemMouseCursors.grabbing : SystemMouseCursors.move,
                  child: Container(
                    decoration: BoxDecoration(
                      color: barColor.withOpacity(0.3), // Lighter background
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                      border: Border.all(
                        color: barColor.withOpacity(0.5),
                        width: 1,
                      ),
                    ),
                    child: Stack(
                      children: [
                        // Progress Fill
                        FractionallySizedBox(
                          widthFactor: widget.task.progress / 100,
                          child: Container(
                            decoration: BoxDecoration(
                              color: barColor, // Darker fill for progress
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        // Content
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                          child: Row(
                            children: [
                              if (width > 50) ...[
                                Icon(
                                  widget.task.isComplete
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 6),
                              ],
                              Expanded(
                                child: Text(
                                  widget.task.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    shadows: [
                                      Shadow(
                                        offset: Offset(0, 1),
                                        blurRadius: 2,
                                        color: Colors.black45,
                                      ),
                                    ],
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                              if (width > 100 && widget.task.assignedTo != null) ...[
                                const SizedBox(width: 4),
                                CircleAvatar(
                                  radius: 10,
                                  backgroundColor: Colors.white.withOpacity(0.3),
                                  child: Text(
                                    _getInitials(widget.task.assignedTo!),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Left Resize Handle
            Positioned(
              left: 0,
              top: 4,
              bottom: 4,
              child: GestureDetector(
                onHorizontalDragStart: (_) {
                  setState(() {
                    _resizeStartOffset = 0;
                  });
                },
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _resizeStartOffset = (_resizeStartOffset ?? 0) + details.delta.dx;
                  });
                },
                onHorizontalDragEnd: (_) => _commitChange(originalPosition, originalWidth),
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: Container(
                    width: 16,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        bottomLeft: Radius.circular(4),
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 3,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Right Resize Handle
            Positioned(
              right: 0,
              top: 4,
              bottom: 4,
              child: GestureDetector(
                onHorizontalDragStart: (_) {
                  setState(() {
                    _resizeEndOffset = 0;
                  });
                },
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _resizeEndOffset = (_resizeEndOffset ?? 0) + details.delta.dx;
                  });
                },
                onHorizontalDragEnd: (_) => _commitChange(originalPosition, originalWidth),
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: Container(
                    width: 16,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(4),
                        bottomRight: Radius.circular(4),
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 3,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(2),
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
    );
  }

  void _commitChange(double originalPosition, double originalWidth) {
    final dragHours = widget.calculator.pixelToDuration(_dragOffset ?? 0);
    final resizeStartHours = widget.calculator.pixelToDuration(_resizeStartOffset ?? 0);
    final resizeEndHours = widget.calculator.pixelToDuration(_resizeEndOffset ?? 0);

    DateTime? newStart = widget.task.startDate;
    DateTime? newEnd = widget.task.dueDate;

    if (_dragOffset != null) {
      // Moving the whole task
      final duration = Duration(minutes: (dragHours * 60).round());
      newStart = newStart?.add(duration);
      newEnd = newEnd?.add(duration);
    } else {
      // Resizing
      if (_resizeStartOffset != null) {
        final duration = Duration(minutes: (resizeStartHours * 60).round());
        newStart = newStart?.add(duration);
      }
      if (_resizeEndOffset != null) {
        final duration = Duration(minutes: (resizeEndHours * 60).round());
        newEnd = newEnd?.add(duration);
      }
    }

    // Snap to nearest 15 minutes
    if (newStart != null) {
      newStart = _snapToInterval(newStart);
    }
    if (newEnd != null) {
      newEnd = _snapToInterval(newEnd);
    }

    // Ensure end is after start
    if (newStart != null && newEnd != null && newEnd.isBefore(newStart)) {
      newEnd = newStart.add(const Duration(hours: 1));
    }

    setState(() {
      _isDragging = false;
      _dragOffset = null;
      _resizeStartOffset = null;
      _resizeEndOffset = null;
    });

    widget.onTaskChanged(widget.task.copyWith(
      startDate: newStart,
      dueDate: newEnd,
    ));
  }

  DateTime _snapToInterval(DateTime date) {
    final minute = date.minute;
    final interval = 15;
    final roundedMinute = ((minute + interval / 2) / interval).floor() * interval;
    return DateTime(
      date.year,
      date.month,
      date.day,
      date.hour,
      0,
    ).add(Duration(minutes: roundedMinute));
  }

  Color _getTaskColor(BuildContext context) {
    if (widget.task.isComplete) {
      return AppColors.success;
    } else if (widget.task.isOverdue()) {
      return AppColors.error;
    } else if (widget.task.startDate != null && DateTime.now().isAfter(widget.task.startDate!)) {
      return AppColors.info;
    } else {
      return AppColors.textSecondary;
    }
  }

  String _getInitials(String userId) {
    return userId.substring(0, 1).toUpperCase();
  }
}

class UnscheduledTasksSection extends StatelessWidget {
  final List<Task> unscheduledTasks;
  final Function(Task) onTaskTap;

  const UnscheduledTasksSection({
    super.key,
    required this.unscheduledTasks,
    required this.onTaskTap,
  });

  @override
  Widget build(BuildContext context) {
    if (unscheduledTasks.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: Theme.of(context).dividerColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.event_busy,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                'Unscheduled Tasks (${unscheduledTasks.length})',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...unscheduledTasks.map((task) => ListTile(
                dense: true,
                leading: Icon(
                  task.isComplete ? Icons.check_circle : Icons.circle_outlined,
                  size: 20,
                  color: task.isComplete ? AppColors.success : AppColors.textTertiary,
                ),
                title: Text(
                  task.title,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                subtitle: task.dueDate != null
                    ? Text('Due: ${_formatDate(task.dueDate!)}')
                    : null,
                onTap: () => onTaskTap(task),
              )),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }
}
