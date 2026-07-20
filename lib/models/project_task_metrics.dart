class ProjectTaskMetrics {
  final String projectId;
  final int openCount;
  final int overdueCount;
  final int dueTodayCount;
  final int totalCount;
  final int completedCount;
  final double progressPercent;

  const ProjectTaskMetrics({
    required this.projectId,
    required this.openCount,
    required this.overdueCount,
    required this.dueTodayCount,
    required this.totalCount,
    required this.completedCount,
    required this.progressPercent,
  });

  const ProjectTaskMetrics.empty(this.projectId)
    : openCount = 0,
      overdueCount = 0,
      dueTodayCount = 0,
      totalCount = 0,
      completedCount = 0,
      progressPercent = 0;

  factory ProjectTaskMetrics.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic value) => (value as num?)?.toInt() ?? 0;
    double asDouble(dynamic value) => (value as num?)?.toDouble() ?? 0;

    return ProjectTaskMetrics(
      projectId: json['project_id'] as String,
      openCount: asInt(json['open_count']),
      overdueCount: asInt(json['overdue_count']),
      dueTodayCount: asInt(json['due_today_count']),
      totalCount: asInt(json['total_count']),
      completedCount: asInt(json['completed_count']),
      progressPercent: asDouble(json['progress_percent']),
    );
  }
}
