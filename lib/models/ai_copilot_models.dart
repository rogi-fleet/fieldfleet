class AiRiskDriver {
  final String key;
  final String label;
  final int severity;
  final String detail;

  const AiRiskDriver({
    required this.key,
    required this.label,
    required this.severity,
    required this.detail,
  });

  factory AiRiskDriver.fromJson(Map<String, dynamic> json) {
    return AiRiskDriver(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      severity: (json['severity'] as num?)?.toInt() ?? 0,
      detail: json['detail'] as String? ?? '',
    );
  }
}

class AiProjectRiskAssessment {
  final String projectId;
  final String projectName;
  final int riskScore;
  final String riskLevel;
  final double confidence;
  final List<AiRiskDriver> drivers;
  final List<String> recommendedActions;
  final Map<String, dynamic> metrics;

  const AiProjectRiskAssessment({
    required this.projectId,
    required this.projectName,
    required this.riskScore,
    required this.riskLevel,
    required this.confidence,
    required this.drivers,
    required this.recommendedActions,
    required this.metrics,
  });

  factory AiProjectRiskAssessment.fromJson(Map<String, dynamic> json) {
    return AiProjectRiskAssessment(
      projectId: json['project_id'] as String? ?? '',
      projectName: json['project_name'] as String? ?? '',
      riskScore: (json['risk_score'] as num?)?.toInt() ?? 0,
      riskLevel: json['risk_level'] as String? ?? 'low',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      drivers: (json['drivers'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => AiRiskDriver.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      recommendedActions: (json['recommended_actions'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      metrics: Map<String, dynamic>.from(
        (json['metrics'] as Map?) ?? const <String, dynamic>{},
      ),
    );
  }
}

class AiScheduleChange {
  final String taskId;
  final String? addPredecessorId;

  const AiScheduleChange({required this.taskId, this.addPredecessorId});

  factory AiScheduleChange.fromJson(Map<String, dynamic> json) {
    return AiScheduleChange(
      taskId: json['task_id'] as String? ?? '',
      addPredecessorId: json['add_predecessor_id'] as String?,
    );
  }
}

class AiScheduleSuggestion {
  final String id;
  final String title;
  final String impactSummary;
  final int estimatedDaysSaved;
  final List<String> riskNotes;
  final List<AiScheduleChange> changes;

  const AiScheduleSuggestion({
    required this.id,
    required this.title,
    required this.impactSummary,
    required this.estimatedDaysSaved,
    required this.riskNotes,
    required this.changes,
  });

  factory AiScheduleSuggestion.fromJson(Map<String, dynamic> json) {
    return AiScheduleSuggestion(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      impactSummary: json['impact_summary'] as String? ?? '',
      estimatedDaysSaved: (json['estimated_days_saved'] as num?)?.toInt() ?? 0,
      riskNotes: (json['risk_notes'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      changes: (json['changes'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => AiScheduleChange.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class AiScheduleOptimizationResult {
  final int suggestionCount;
  final List<AiScheduleSuggestion> suggestions;

  const AiScheduleOptimizationResult({
    required this.suggestionCount,
    required this.suggestions,
  });

  factory AiScheduleOptimizationResult.fromJson(Map<String, dynamic> json) {
    return AiScheduleOptimizationResult(
      suggestionCount: (json['suggestion_count'] as num?)?.toInt() ?? 0,
      suggestions: (json['suggestions'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map(
            (e) => AiScheduleSuggestion.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(),
    );
  }
}

class AiWeeklyProjectDigest {
  final String projectId;
  final String weekStartDate;
  final String weekEndDate;
  final String overview;
  final String digestMarkdown;
  final List<String> highlights;
  final List<String> risks;
  final List<String> nextWeekPriorities;
  final List<AiDigestItem> highlightItems;
  final List<AiDigestItem> riskItems;
  final List<AiDigestItem> priorityItems;
  final List<AiDigestItem> watchItems;

  const AiWeeklyProjectDigest({
    required this.projectId,
    required this.weekStartDate,
    required this.weekEndDate,
    required this.overview,
    required this.digestMarkdown,
    required this.highlights,
    required this.risks,
    required this.nextWeekPriorities,
    required this.highlightItems,
    required this.riskItems,
    required this.priorityItems,
    required this.watchItems,
  });

  factory AiWeeklyProjectDigest.fromJson(Map<String, dynamic> json) {
    return AiWeeklyProjectDigest(
      projectId: json['project_id'] as String? ?? '',
      weekStartDate: json['week_start_date'] as String? ?? '',
      weekEndDate: json['week_end_date'] as String? ?? '',
      overview: json['overview'] as String? ?? '',
      digestMarkdown: json['digest_markdown'] as String? ?? '',
      highlights: (json['highlights'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      risks: (json['risks'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      nextWeekPriorities: (json['next_week_priorities'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      highlightItems: (json['highlight_items'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => AiDigestItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      riskItems: (json['risk_items'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => AiDigestItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      priorityItems: (json['priority_items'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => AiDigestItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      watchItems: (json['watch_items'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => AiDigestItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class AiDigestItem {
  final String title;
  final String detail;
  final String? href;
  final String? badge;

  const AiDigestItem({
    required this.title,
    required this.detail,
    this.href,
    this.badge,
  });

  factory AiDigestItem.fromJson(Map<String, dynamic> json) {
    return AiDigestItem(
      title: json['title'] as String? ?? '',
      detail: json['detail'] as String? ?? '',
      href: json['href'] as String?,
      badge: json['badge'] as String?,
    );
  }
}
