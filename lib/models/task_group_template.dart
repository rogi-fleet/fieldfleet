/// Model for task-group templates — a reusable set of tasks (a phase/group
/// with its full subtree) that can be imported into any existing project.
///
/// Unlike [ProjectTemplate], which snapshots a whole project and creates a new
/// one, a [TaskGroupTemplate] is scoped to a subtree of tasks and is
/// instantiated INTO an existing project.
class TaskGroupTemplate {
  final String id;
  final String workspaceId;
  final String name;
  final String? description;
  final List<TaskGroupTemplateTask> tasks;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  TaskGroupTemplate({
    required this.id,
    required this.workspaceId,
    required this.name,
    this.description,
    this.tasks = const [],
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  int get taskCount => tasks.length;

  /// Number of top-level (root) tasks in the template — i.e. the phases/tasks
  /// that will attach at the import point.
  int get rootCount => tasks.where((t) => t.parentTempId == null).length;

  factory TaskGroupTemplate.fromRow(Map<String, dynamic> row) {
    final tasksJson = row['tasks'] as List? ?? [];
    return TaskGroupTemplate(
      id: row['id'] as String,
      workspaceId: row['workspace_id'] as String,
      name: row['name'] as String? ?? '',
      description: row['description'] as String?,
      tasks: tasksJson
          .map((t) =>
              TaskGroupTemplateTask.fromJson(Map<String, dynamic>.from(t)))
          .toList(),
      createdBy: row['created_by'] as String? ?? '',
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'])
          : DateTime.now(),
      updatedAt: row['updated_at'] != null
          ? DateTime.parse(row['updated_at'])
          : DateTime.now(),
    );
  }
}

/// Snapshot of a single task within a task-group template.
///
/// Identity is by [tempId] (re-mapped to a real UUID on import). Scheduling is
/// stored relative to the template's earliest task via [startOffsetDays] so the
/// imported tasks lay out on the Gantt the same way regardless of import date.
class TaskGroupTemplateTask {
  final String tempId;
  final String? parentTempId;
  final String title;
  final String? description;
  final int sortOrder;
  final String taskType; // 'summary' | 'standard' | 'milestone'
  final String priority; // 'high' | 'medium' | 'low'
  final int? groupColor;
  final double? estimatedDuration; // hours
  final int startOffsetDays; // days after the template's earliest task
  final List<String> predecessorTempIds; // dependencies within the set
  final List<String> assignedToIds; // preserved user IDs (optional)
  final List<String> checklistTitles; // checklist item titles (reset state)

  TaskGroupTemplateTask({
    required this.tempId,
    this.parentTempId,
    required this.title,
    this.description,
    required this.sortOrder,
    this.taskType = 'standard',
    this.priority = 'medium',
    this.groupColor,
    this.estimatedDuration,
    this.startOffsetDays = 0,
    this.predecessorTempIds = const [],
    this.assignedToIds = const [],
    this.checklistTitles = const [],
  });

  factory TaskGroupTemplateTask.fromJson(Map<String, dynamic> json) {
    return TaskGroupTemplateTask(
      tempId: json['temp_id'] as String? ?? '',
      parentTempId: json['parent_temp_id'] as String?,
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      taskType: json['task_type'] as String? ?? 'standard',
      priority: json['priority'] as String? ?? 'medium',
      groupColor: (json['group_color'] as num?)?.toInt(),
      estimatedDuration: (json['estimated_duration'] as num?)?.toDouble(),
      startOffsetDays: (json['start_offset_days'] as num?)?.toInt() ?? 0,
      predecessorTempIds: (json['predecessor_temp_ids'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      assignedToIds: (json['assigned_to_ids'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      checklistTitles: (json['checklist_titles'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'temp_id': tempId,
      'parent_temp_id': parentTempId,
      'title': title,
      'description': description,
      'sort_order': sortOrder,
      'task_type': taskType,
      'priority': priority,
      'group_color': groupColor,
      'estimated_duration': estimatedDuration,
      'start_offset_days': startOffsetDays,
      'predecessor_temp_ids': predecessorTempIds,
      'assigned_to_ids': assignedToIds,
      'checklist_titles': checklistTitles,
    };
  }
}
