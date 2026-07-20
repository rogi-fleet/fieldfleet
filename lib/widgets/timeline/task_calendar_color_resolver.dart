import 'package:flutter/material.dart';

import '../../models/task.dart';
import '../../theme/theme.dart';

/// Resolves the primary task accent color for calendar surfaces.
class TaskCalendarColorResolver {
  TaskCalendarColorResolver({
    required List<Task> tasks,
    this.preferPhaseColors = false,
  }) : _tasksById = {for (final task in tasks) task.id: task};

  final bool preferPhaseColors;
  final Map<String, Task> _tasksById;

  Color accentColorFor(Task task) {
    if (preferPhaseColors) {
      final phaseColor = _phaseColorFor(task);
      if (phaseColor != null) return phaseColor;
    }

    if (_hasCustomGroupColor(task.groupColor)) {
      return task.groupColor;
    }

    return statusColorFor(task.status);
  }

  Color statusColorForTask(Task task) => statusColorFor(task.status);

  Color statusColorFor(String status) {
    switch (status.toLowerCase()) {
      case 'done':
      case 'complete':
      case 'completed':
        return AppColors.success;
      case 'working on it':
      case 'working_on_it':
      case 'in progress':
      case 'in_progress':
        return AppColors.info;
      case 'stuck':
      case 'blocked':
        return AppColors.error;
      case 'not started':
      case 'not_started':
      default:
        return AppColors.textTertiary;
    }
  }

  bool shouldShowStatusIndicator(Task task) {
    final accentColor = accentColorFor(task);
    final statusColor = statusColorForTask(task);
    return accentColor.toARGB32() != statusColor.toARGB32();
  }

  Color? _phaseColorFor(Task task) {
    if (task.taskType == TaskType.summary &&
        _hasCustomGroupColor(task.groupColor)) {
      return task.groupColor;
    }

    final visited = <String>{task.id};
    var current = task;

    while (current.parentId != null) {
      final parentId = current.parentId!;
      if (!visited.add(parentId)) break;

      final parent = _tasksById[parentId];
      if (parent == null) break;

      if (parent.taskType == TaskType.summary &&
          _hasCustomGroupColor(parent.groupColor)) {
        return parent.groupColor;
      }

      current = parent;
    }

    return null;
  }

  bool _hasCustomGroupColor(Color color) {
    return color.toARGB32() != Colors.blue.toARGB32() &&
        color.toARGB32() != AppColors.info.toARGB32();
  }
}
