import 'task.dart';

/// Extensions for Task to support hierarchical Gantt chart operations
extension GanttTaskExtensions on Task {
  /// Get immediate children of this task
  List<Task> getChildren(List<Task> allTasks) {
    return allTasks.where((task) => task.parentId == id).toList();
  }

  /// Calculate nesting level (depth in tree)
  int getNestingLevel(List<Task> allTasks) {
    if (parentId == null) return 0;
    
    final parent = allTasks.firstWhere(
      (task) => task.id == parentId,
      orElse: () => this,
    );
    
    if (parent.id == id) return 0; // Prevent infinite loop
    return 1 + parent.getNestingLevel(allTasks);
  }

  /// Check if this task has children
  bool hasChildren(List<Task> allTasks) {
    return allTasks.any((task) => task.parentId == id);
  }

  /// Get all descendants (recursive)
  List<Task> getDescendants(List<Task> allTasks) {
    final children = getChildren(allTasks);
    final descendants = <Task>[...children];

    for (final child in children) {
      descendants.addAll(child.getDescendants(allTasks));
    }

    return descendants;
  }

  /// Calculate group progress as average of all descendant tasks (not groups)
  /// Returns 0 if no children or no tasks with progress
  int getGroupProgress(List<Task> allTasks) {
    final descendants = getDescendants(allTasks);
    // Only count standard tasks (not nested groups or milestones)
    final tasks = descendants.where((t) => t.taskType == TaskType.standard).toList();
    if (tasks.isEmpty) return 0;

    final totalProgress = tasks.fold<int>(0, (sum, t) => sum + t.progress);
    return (totalProgress / tasks.length).round();
  }

  /// Calculate group start date as earliest start date of all descendants
  /// Returns null if no children have start dates
  DateTime? getGroupStartDate(List<Task> allTasks) {
    final descendants = getDescendants(allTasks);
    DateTime? earliest;

    for (final child in descendants) {
      if (child.startDate != null) {
        if (earliest == null || child.startDate!.isBefore(earliest)) {
          earliest = child.startDate;
        }
      }
    }

    return earliest;
  }

  /// Calculate group end date as latest due date of all descendants
  /// Returns null if no children have due dates
  DateTime? getGroupEndDate(List<Task> allTasks) {
    final descendants = getDescendants(allTasks);
    DateTime? latest;

    for (final child in descendants) {
      final effectiveEndDate = child.dueDate ?? child.getEffectiveDueDate();
      if (effectiveEndDate != null) {
        if (latest == null || effectiveEndDate.isAfter(latest)) {
          latest = effectiveEndDate;
        }
      }
    }

    return latest;
  }

  /// Get effective progress - for groups, calculate from children; for tasks, use direct value
  int getEffectiveProgress(List<Task> allTasks) {
    if (taskType == TaskType.summary) {
      return getGroupProgress(allTasks);
    }
    return progress;
  }

  /// Get effective start date - for groups, calculate from children; for tasks, use direct value
  DateTime? getEffectiveStartDate(List<Task> allTasks) {
    if (taskType == TaskType.summary) {
      return getGroupStartDate(allTasks);
    }
    return startDate;
  }

  /// Get effective end date - for groups, calculate from children; for tasks, use direct value
  DateTime? getEffectiveEndDate(List<Task> allTasks) {
    if (taskType == TaskType.summary) {
      return getGroupEndDate(allTasks);
    }
    return dueDate ?? getEffectiveDueDate();
  }

  /// Get all unique assignee IDs from this task and all descendants
  /// For groups, aggregates assignees from all child tasks
  List<String> getAggregatedAssigneeIds(List<Task> allTasks) {
    final assigneeIds = <String>{};

    // Add this task's assignees
    assigneeIds.addAll(assignedToIds);

    // If this is a group, also add all descendant assignees
    if (taskType == TaskType.summary) {
      final descendants = getDescendants(allTasks);
      for (final child in descendants) {
        assigneeIds.addAll(child.assignedToIds);
      }
    }

    return assigneeIds.toList();
  }
}

/// Flattens a hierarchical task tree into a linear list for display
/// Respects the isExpanded state to hide collapsed children
List<Task> flattenTaskTree(List<Task> tasks) {
  final flattened = <Task>[];
  
  // Get root tasks (no parent)
  final roots = tasks.where((task) => task.parentId == null).toList();
  
  // Sort roots by creation date or other criteria
  roots.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  
  // Recursively add tasks with depth-first traversal
  void addTaskAndChildren(Task task) {
    flattened.add(task);
    
    // Only add children if this task is expanded
    if (task.isExpanded) {
      final children = task.getChildren(tasks);
      children.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      
      for (final child in children) {
        addTaskAndChildren(child);
      }
    }
  }
  
  for (final root in roots) {
    addTaskAndChildren(root);
  }
  
  return flattened;
}

/// Model representing a row in the flattened Gantt view
/// Can be either a task or a "footer" for inline add
class GanttRowViewModel {
  final Task? task;
  final bool isFooter;
  final String? parentId; // For footer rows, which parent they belong to
  
  GanttRowViewModel.task(this.task)
      : isFooter = false,
        parentId = null;
  
  GanttRowViewModel.footer(this.parentId)
      : task = null,
        isFooter = true;
}

/// Enhanced flattening that includes footer rows for "inline add" functionality
List<GanttRowViewModel> flattenTaskTreeWithFooters(List<Task> tasks) {
  final flattened = <GanttRowViewModel>[];
  final processedGroups = <String>{};
  
  // Get root tasks (no parent)
  final roots = tasks.where((task) => task.parentId == null).toList();
  roots.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  
  void addTaskAndChildren(Task task) {
    flattened.add(GanttRowViewModel.task(task));
    
    if (task.isExpanded) {
      final children = task.getChildren(tasks);
      children.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      
      for (final child in children) {
        addTaskAndChildren(child);
      }
      
      // Add footer row after children if this is a parent (summary task)
      if (task.hasChildren(tasks) && !processedGroups.contains(task.id)) {
        flattened.add(GanttRowViewModel.footer(task.id));
        processedGroups.add(task.id);
      }
    }
  }
  
  for (final root in roots) {
    addTaskAndChildren(root);
  }
  
  // Add footer for root level (no parent)
  flattened.add(GanttRowViewModel.footer(null));
  
  return flattened;
}
