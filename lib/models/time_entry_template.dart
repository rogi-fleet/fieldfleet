import 'package:cloud_firestore/cloud_firestore.dart';

class TimeEntryTemplate {
  final String id;
  final String workspaceId;
  final String? userId; // null = shared template
  final String name;
  final String projectId;
  final String taskId;
  final double defaultHours;
  final int defaultBreakMinutes;
  final String? notesTemplate;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TimeEntryTemplate({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.projectId,
    required this.taskId,
    this.userId,
    this.defaultHours = 0,
    this.defaultBreakMinutes = 0,
    this.notesTemplate,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isShared => userId == null;

  factory TimeEntryTemplate.fromJson(Map<String, dynamic> json, String id) {
    return TimeEntryTemplate(
      id: id,
      workspaceId: json['workspaceId'] as String,
      userId: json['userId'] as String?,
      name: json['name'] as String? ?? 'Template',
      projectId: json['projectId'] as String,
      taskId: json['taskId'] as String,
      defaultHours: (json['defaultHours'] as num?)?.toDouble() ?? 0,
      defaultBreakMinutes: json['defaultBreakMinutes'] as int? ?? 0,
      notesTemplate: json['notesTemplate'] as String?,
      createdAt: _parseTimestamp(json['createdAt']),
      updatedAt: _parseTimestamp(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'workspaceId': workspaceId,
      'userId': userId,
      'name': name,
      'projectId': projectId,
      'taskId': taskId,
      'defaultHours': defaultHours,
      'defaultBreakMinutes': defaultBreakMinutes,
      'notesTemplate': notesTemplate,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  static DateTime _parseTimestamp(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.parse(value);
    try {
      return value.toDate();
    } catch (_) {
      return DateTime.now();
    }
  }

  TimeEntryTemplate copyWith({
    String? id,
    String? workspaceId,
    String? userId,
    String? name,
    String? projectId,
    String? taskId,
    double? defaultHours,
    int? defaultBreakMinutes,
    String? notesTemplate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TimeEntryTemplate(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      projectId: projectId ?? this.projectId,
      taskId: taskId ?? this.taskId,
      defaultHours: defaultHours ?? this.defaultHours,
      defaultBreakMinutes: defaultBreakMinutes ?? this.defaultBreakMinutes,
      notesTemplate: notesTemplate ?? this.notesTemplate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
