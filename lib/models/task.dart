import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme/theme.dart';
import 'checklist_item.dart';

enum TaskType {
  summary,   // Group task - container for other tasks, shown as bracket
  standard,  // Regular task shown as bar
  milestone, // Single-point task shown as diamond
}

class Task {
  final String id;
  final String workspaceId;
  final String projectId;
  final String title;
  final String? description;
  final DateTime? dueDate;
  final DateTime? startDate;
  final DateTime? endDate; // Actual completion date/time (auto-set when marked done)
  final double? estimatedDuration; // in hours
  final bool isComplete;
  final String? assignedTo; // DEPRECATED: use assignedToIds instead
  final List<String> assignedToIds; // IDs of users assigned to this task
  final List<String> requiredAssetIds; // IDs of assets needed for this task
  final List<String> predecessorIds; // IDs of tasks that must be completed before this one
  final List<String> requiredSkillIds; // IDs of skills required for this task
  final List<String> propertyIds; // IDs of linked properties (for restoration workflows)
  final List<String> areaIds; // IDs of linked areas within properties
  final List<String> budgetItemIds; // IDs of linked budget items (for cost tracking)
  final DateTime createdAt;
  final DateTime updatedAt;
  final int progress; // 0-100
  
  // Gantt chart fields
  final String status; // e.g., "done", "working_on_it", "stuck", "not_started"
  final String priority; // e.g., "high", "medium", "low"
  final String? parentId; // For hierarchical relationships
  final TaskType taskType; // Summary, Standard, or Milestone
  final Color groupColor; // Visual grouping color
  final bool isExpanded; // UI state for collapsible groups
  final List<ChecklistItem> checklistItems; // Checklist items for this task

  // Recurrence fields
  final double sortOrder;

  // Recurrence fields
  final bool isRecurring;
  final Map<String, dynamic>? recurrenceRule;
  final String? recurringParentId;
  final int occurrenceIndex;

  Task({

    required this.id,
    required this.workspaceId,
    required this.projectId,
    required this.title,
    this.description,
    this.dueDate,
    this.startDate,
    this.endDate,
    this.estimatedDuration,
    this.isComplete = false,
    this.assignedTo, // DEPRECATED
    this.assignedToIds = const [],
    this.requiredAssetIds = const [],
    this.predecessorIds = const [],
    this.requiredSkillIds = const [],
    this.propertyIds = const [],
    this.areaIds = const [],
    this.budgetItemIds = const [],
    required this.createdAt,
    required this.updatedAt,
    this.progress = 0,
    this.status = 'not_started',
    this.priority = 'medium',
    this.parentId,
    this.taskType = TaskType.standard,
    this.groupColor = AppColors.info,
    this.isExpanded = true,
    this.checklistItems = const [],
    this.sortOrder = 0.0,
    this.isRecurring = false,
    this.recurrenceRule,
    this.recurringParentId,
    this.occurrenceIndex = 0,
  });

  /// Parse timestamp from various formats (Firestore Timestamp, DateTime, or objects with toDate())
  static DateTime _parseTimestamp(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    } else if (value is DateTime) {
      return value;
    } else if (value != null) {
      // Handle _FakeTimestamp or similar objects with toDate() method
      return (value as dynamic).toDate();
    }
    return DateTime.now();
  }

  factory Task.fromJson(Map<String, dynamic> json, String id) {
    return Task(
      id: id,
      workspaceId: json['workspaceId'] as String,
      projectId: json['projectId'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      dueDate: json['dueDate'] != null
          ? _parseTimestamp(json['dueDate'])
          : null,
      startDate: json['startDate'] != null
          ? _parseTimestamp(json['startDate'])
          : null,
      endDate: json['endDate'] != null
          ? _parseTimestamp(json['endDate'])
          : null,
      estimatedDuration: json['estimatedDuration'] != null
          ? (json['estimatedDuration'] as num).toDouble()
          : null,
      isComplete: json['isComplete'] as bool? ?? false,
      assignedTo: json['assignedTo'] as String?, // DEPRECATED
      assignedToIds: json['assignedToIds'] != null
          ? List<String>.from(json['assignedToIds'] as List)
          : (json['assignedTo'] != null ? [json['assignedTo'] as String] : []), // Migrate legacy field
      requiredAssetIds: json['requiredAssetIds'] != null
          ? List<String>.from(json['requiredAssetIds'] as List)
          : [],
      predecessorIds: json['predecessorIds'] != null
          ? List<String>.from(json['predecessorIds'] as List)
          : [],
      requiredSkillIds: json['requiredSkillIds'] != null
          ? List<String>.from(json['requiredSkillIds'] as List)
          : [],
      propertyIds: json['propertyIds'] != null
          ? List<String>.from(json['propertyIds'] as List)
          : (json['propertyId'] != null ? [json['propertyId'] as String] : []),
      areaIds: json['areaIds'] != null
          ? List<String>.from(json['areaIds'] as List)
          : (json['areaId'] != null ? [json['areaId'] as String] : []),
      budgetItemIds: json['budgetItemIds'] != null
          ? List<String>.from(json['budgetItemIds'] as List)
          : [],
      createdAt: _parseTimestamp(json['createdAt']),
      updatedAt: _parseTimestamp(json['updatedAt']),
      progress: json['progress'] as int? ?? (json['isComplete'] == true ? 100 : 0),
      status: json['status'] as String? ?? 'not_started',
      priority: json['priority'] as String? ?? 'medium',
      parentId: json['parentId'] as String?,
      taskType: json['taskType'] != null 
          ? TaskType.values.firstWhere(
              (e) => e.toString() == 'TaskType.${json['taskType']}',
              orElse: () => TaskType.standard,
            )
          : TaskType.standard,
      groupColor: json['groupColor'] != null
          ? Color(json['groupColor'] as int)
          : AppColors.info,
      isExpanded: json['isExpanded'] as bool? ?? true,
      checklistItems: json['checklistItems'] != null
          ? (json['checklistItems'] as List)
              .map((item) => ChecklistItem.fromJson(item as Map<String, dynamic>))
              .toList()
          : [],
      sortOrder: (json['sortOrder'] as num?)?.toDouble() ?? 0.0,
      isRecurring: json['isRecurring'] as bool? ?? false,
      recurrenceRule: json['recurrenceRule'] != null
          ? Map<String, dynamic>.from(json['recurrenceRule'] as Map)
          : null,
      recurringParentId: json['recurringParentId'] as String?,
      occurrenceIndex: json['occurrenceIndex'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'workspaceId': workspaceId,
      'projectId': projectId,
      'title': title,
      'description': description,
      'dueDate': dueDate != null ? Timestamp.fromDate(dueDate!) : null,
      'startDate': startDate != null ? Timestamp.fromDate(startDate!) : null,
      'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
      'estimatedDuration': estimatedDuration,
      'isComplete': isComplete,
      'assignedTo': assignedTo, // Keep for backward compatibility
      'assignedToIds': assignedToIds,
      'requiredAssetIds': requiredAssetIds,
      'predecessorIds': predecessorIds,
      'requiredSkillIds': requiredSkillIds,
      'propertyIds': propertyIds,
      'areaIds': areaIds,
      'budgetItemIds': budgetItemIds,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'progress': progress,
      'status': status,
      'priority': priority,
      'parentId': parentId,
      'taskType': taskType.toString().split('.').last,
      'groupColor': groupColor.value, // Use .value for backward compatibility
      'isExpanded': isExpanded,
      'checklistItems': checklistItems.map((item) => item.toJson()).toList(),
      'sortOrder': sortOrder,
      'isRecurring': isRecurring,
      'recurrenceRule': recurrenceRule,
      'recurringParentId': recurringParentId,
      'occurrenceIndex': occurrenceIndex,
    };
  }

  Task copyWith({
    String? id,
    String? workspaceId,
    String? projectId,
    String? title,
    String? description,
    DateTime? dueDate,
    DateTime? startDate,
    DateTime? endDate,
    double? estimatedDuration,
    bool? isComplete,
    String? assignedTo,
    List<String>? assignedToIds,
    List<String>? requiredAssetIds,
    List<String>? predecessorIds,
    List<String>? requiredSkillIds,
    List<String>? propertyIds,
    List<String>? areaIds,
    List<String>? budgetItemIds,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? progress,
    String? status,
    String? priority,
    String? parentId,
    TaskType? taskType,
    Color? groupColor,
    bool? isExpanded,
    List<ChecklistItem>? checklistItems,
    double? sortOrder,
    bool? isRecurring,
    Map<String, dynamic>? recurrenceRule,
    String? recurringParentId,
    int? occurrenceIndex,
  }) {
    return Task(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      projectId: projectId ?? this.projectId,
      title: title ?? this.title,
      description: description ?? this.description,
      dueDate: dueDate ?? this.dueDate,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      estimatedDuration: estimatedDuration ?? this.estimatedDuration,
      isComplete: isComplete ?? this.isComplete,
      assignedTo: assignedTo ?? this.assignedTo,
      assignedToIds: assignedToIds ?? this.assignedToIds,
      requiredAssetIds: requiredAssetIds ?? this.requiredAssetIds,
      predecessorIds: predecessorIds ?? this.predecessorIds,
      requiredSkillIds: requiredSkillIds ?? this.requiredSkillIds,
      propertyIds: propertyIds ?? this.propertyIds,
      areaIds: areaIds ?? this.areaIds,
      budgetItemIds: budgetItemIds ?? this.budgetItemIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      parentId: parentId ?? this.parentId,
      taskType: taskType ?? this.taskType,
      groupColor: groupColor ?? this.groupColor,
      isExpanded: isExpanded ?? this.isExpanded,
      checklistItems: checklistItems ?? this.checklistItems,
      sortOrder: sortOrder ?? this.sortOrder,
      isRecurring: isRecurring ?? this.isRecurring,
      recurrenceRule: recurrenceRule ?? this.recurrenceRule,
      recurringParentId: recurringParentId ?? this.recurringParentId,
      occurrenceIndex: occurrenceIndex ?? this.occurrenceIndex,
    );
  }

  bool validate() {
    return title.isNotEmpty;
  }

  /// Title for display — falls back to a placeholder for unnamed tasks so
  /// they don't render as a blank card/row.
  String get displayTitle =>
      title.trim().isEmpty ? '(Untitled task)' : title;

  bool isOverdue() {
    if (dueDate == null || isComplete) {
      return false;
    }
    final due = dueDate!;
    final now = DateTime.now();
    // Date-only due dates are stored at exactly midnight and mean "due that
    // day" — the task turns overdue when that day ends, not the moment it
    // starts (a raw isBefore(now) flagged every wizard-created task as
    // overdue all day on its due date).
    final hasTimeComponent =
        due.hour != 0 || due.minute != 0 || due.second != 0;
    if (hasTimeComponent) {
      return due.isBefore(now);
    }
    final endOfDueDay = DateTime(
      due.year,
      due.month,
      due.day,
    ).add(const Duration(days: 1));
    return !now.isBefore(endOfDueDay);
  }

  /// Due on the current calendar day (and not complete).
  bool isDueToday() {
    if (dueDate == null || isComplete) {
      return false;
    }
    final due = dueDate!;
    final now = DateTime.now();
    return due.year == now.year &&
        due.month == now.month &&
        due.day == now.day;
  }

  /// Predecessor tasks (from [predecessorIds]) that are not yet complete.
  /// Dependencies are advisory: this surfaces a "blocked" flag in the UI
  /// rather than hard-blocking actions. [G2]
  List<Task> incompletePredecessors(Iterable<Task> allTasks) {
    if (predecessorIds.isEmpty) return const [];
    final byId = {for (final t in allTasks) t.id: t};
    return predecessorIds
        .map((id) => byId[id])
        .whereType<Task>()
        .where((t) => !t.isComplete)
        .toList();
  }

  /// True when this (incomplete) task is waiting on at least one predecessor
  /// that isn't done yet. [G2]
  bool isBlockedByDependencies(Iterable<Task> allTasks) {
    if (isComplete || predecessorIds.isEmpty) return false;
    return incompletePredecessors(allTasks).isNotEmpty;
  }

  /// Calculate due date from start date + estimated duration
  /// Returns null if startDate or estimatedDuration is not set
  DateTime? calculateDueDate() {
    if (startDate == null || estimatedDuration == null) {
      return null;
    }
    // Convert hours to days (8 hours = 1 work day)
    final days = estimatedDuration! / 8.0;
    return startDate!.add(Duration(hours: (days * 24).round()));
  }

  /// Calculate duration in hours from start date to due date
  /// Returns null if startDate or dueDate is not set
  double? calculateDuration() {
    if (startDate == null || dueDate == null) {
      return null;
    }
    final diff = dueDate!.difference(startDate!);
    // Convert difference to hours
    return diff.inHours.toDouble();
  }

  /// Get the effective due date (uses dueDate if set, otherwise calculates from start + duration)
  DateTime? getEffectiveDueDate() {
    if (dueDate != null) {
      return dueDate;
    }
    return calculateDueDate();
  }

  /// Get the effective duration (uses estimatedDuration if set, otherwise calculates from dates)
  double? getEffectiveDuration() {
    if (estimatedDuration != null) {
      return estimatedDuration;
    }
    return calculateDuration();
  }

  /// Get the count of completed checklist items
  int get completedChecklistCount =>
      checklistItems.where((item) => item.isComplete).length;

  /// Get the total count of checklist items
  int get totalChecklistCount => checklistItems.length;

  /// Get the checklist completion progress as a percentage (0-100)
  double get checklistProgress {
    if (checklistItems.isEmpty) return 0;
    return (completedChecklistCount / totalChecklistCount) * 100;
  }

  /// Check if the task has any checklist items
  bool get hasChecklist => checklistItems.isNotEmpty;
}
