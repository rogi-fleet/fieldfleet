class DailyAiSummary {
  final String id;
  final String workspaceId;
  final String userId;
  final DateTime summaryDate;
  final String timezone;
  final String summaryMarkdown;
  final DateTime generatedAt;
  final String? status;
  final String? provider;
  final String? model;

  DailyAiSummary({
    required this.id,
    required this.workspaceId,
    required this.userId,
    required this.summaryDate,
    required this.timezone,
    required this.summaryMarkdown,
    required this.generatedAt,
    this.status,
    this.provider,
    this.model,
  });

  factory DailyAiSummary.fromSupabase(Map<String, dynamic> row) {
    return DailyAiSummary(
      id: row['id'] as String,
      workspaceId: row['workspace_id'] as String,
      userId: row['user_id'] as String,
      summaryDate: DateTime.parse(row['summary_date'] as String),
      timezone: row['timezone'] as String? ?? 'UTC',
      summaryMarkdown: row['summary_markdown'] as String? ?? '',
      generatedAt: row['generated_at'] != null
          ? DateTime.parse(row['generated_at'] as String)
          : DateTime.now(),
      status: row['status'] as String?,
      provider: row['provider'] as String?,
      model: row['model'] as String?,
    );
  }
}
