/// A named point-in-time snapshot of a project's schedule, used by the Gantt
/// to render planned-vs-actual ghost bars and per-task slip.
class ScheduleBaseline {
  final String id;
  final String workspaceId;
  final String projectId;
  final String name;
  final String? createdBy;
  final DateTime createdAt;

  const ScheduleBaseline({
    required this.id,
    required this.workspaceId,
    required this.projectId,
    required this.name,
    this.createdBy,
    required this.createdAt,
  });

  factory ScheduleBaseline.fromSupabase(Map<String, dynamic> json) {
    return ScheduleBaseline(
      id: json['id'] as String,
      workspaceId: json['workspace_id'] as String,
      projectId: json['project_id'] as String,
      name: json['name'] as String? ?? 'Baseline',
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// The snapshotted schedule dates for a single task within a baseline.
/// Group (summary) tasks store their child-derived effective span as captured
/// at snapshot time.
class BaselineTaskDates {
  final String taskId;
  final DateTime? startDate;
  final DateTime? dueDate;
  final double? estimatedDuration;

  const BaselineTaskDates({
    required this.taskId,
    this.startDate,
    this.dueDate,
    this.estimatedDuration,
  });

  factory BaselineTaskDates.fromSupabase(Map<String, dynamic> json) {
    return BaselineTaskDates(
      taskId: json['task_id'] as String,
      startDate: json['start_date'] != null
          ? DateTime.parse(json['start_date'] as String).toLocal()
          : null,
      dueDate: json['due_date'] != null
          ? DateTime.parse(json['due_date'] as String).toLocal()
          : null,
      estimatedDuration: (json['estimated_duration'] as num?)?.toDouble(),
    );
  }
}
