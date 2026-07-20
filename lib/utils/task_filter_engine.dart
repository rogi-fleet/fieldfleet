import '../models/project.dart';
import '../models/property.dart';
import '../models/task.dart';

class TaskFilterOptions {
  final bool myTasksOnly;
  final String? currentUserId;
  final String? propertyFilterId;
  final String query;
  final bool hideDone;
  final String? projectId;
  final String? customerId;
  final String? priority;
  final String? assigneeId;
  final DateTime? dueDateStart;
  final DateTime? dueDateEnd;
  final bool overdueOnly;

  const TaskFilterOptions({
    this.myTasksOnly = false,
    this.currentUserId,
    this.propertyFilterId,
    this.query = '',
    this.hideDone = false,
    this.projectId,
    this.customerId,
    this.priority,
    this.assigneeId,
    this.dueDateStart,
    this.dueDateEnd,
    this.overdueOnly = false,
  });

  TaskFilterOptions copyWith({
    bool? myTasksOnly,
    String? currentUserId,
    String? propertyFilterId,
    String? query,
    bool? hideDone,
    Object? projectId = _sentinel,
    String? customerId,
    String? priority,
    String? assigneeId,
    DateTime? dueDateStart,
    DateTime? dueDateEnd,
    bool? overdueOnly,
  }) {
    return TaskFilterOptions(
      myTasksOnly: myTasksOnly ?? this.myTasksOnly,
      currentUserId: currentUserId ?? this.currentUserId,
      propertyFilterId: propertyFilterId ?? this.propertyFilterId,
      query: query ?? this.query,
      hideDone: hideDone ?? this.hideDone,
      projectId: identical(projectId, _sentinel)
          ? this.projectId
          : projectId as String?,
      customerId: customerId ?? this.customerId,
      priority: priority ?? this.priority,
      assigneeId: assigneeId ?? this.assigneeId,
      dueDateStart: dueDateStart ?? this.dueDateStart,
      dueDateEnd: dueDateEnd ?? this.dueDateEnd,
      overdueOnly: overdueOnly ?? this.overdueOnly,
    );
  }
}

const Object _sentinel = Object();

class TaskFilterContext {
  final Map<String, Project> projectMap;
  final Map<String, Property> propertyMap;

  const TaskFilterContext({
    this.projectMap = const {},
    this.propertyMap = const {},
  });
}

class TaskFilterEngine {
  static List<Task> apply(
    List<Task> tasks, {
    required TaskFilterOptions options,
    TaskFilterContext context = const TaskFilterContext(),
  }) {
    Iterable<Task> filtered = tasks;

    if (options.hideDone) {
      filtered = filtered.where((t) => !t.isComplete && t.status != 'done');
    }

    if (options.myTasksOnly && options.currentUserId != null) {
      final userId = options.currentUserId!;
      filtered = filtered.where((t) => t.assignedToIds.contains(userId));
    }

    if (options.projectId != null) {
      final projectId = options.projectId!;
      filtered = filtered.where((t) => t.projectId == projectId);
    }

    if (options.propertyFilterId != null) {
      final propertyId = options.propertyFilterId!;
      filtered = filtered.where((t) => t.propertyIds.contains(propertyId));
    }

    if (options.customerId != null) {
      final customerProjectIds = context.projectMap.values
          .where((p) => p.clientId == options.customerId)
          .map((p) => p.id)
          .toSet();
      filtered =
          filtered.where((t) => customerProjectIds.contains(t.projectId));
    }

    if (options.priority != null) {
      filtered = filtered.where((t) => t.priority == options.priority);
    }

    if (options.assigneeId != null) {
      final assigneeId = options.assigneeId!;
      filtered = filtered.where((t) => t.assignedToIds.contains(assigneeId));
    }

    if (options.dueDateStart != null || options.dueDateEnd != null) {
      final start = options.dueDateStart;
      final end = options.dueDateEnd?.add(const Duration(days: 1));
      filtered = filtered.where((t) {
        if (t.dueDate == null) return false;
        if (start != null && t.dueDate!.isBefore(start)) return false;
        if (end != null && t.dueDate!.isAfter(end)) return false;
        return true;
      });
    }

    if (options.overdueOnly) {
      final now = DateTime.now();
      filtered = filtered.where((t) =>
          !t.isComplete &&
          t.status != 'done' &&
          t.dueDate != null &&
          t.dueDate!.isBefore(now));
    }

    final query = options.query.trim().toLowerCase();
    if (query.isNotEmpty) {
      filtered = filtered.where(
        (t) => matchesQuery(t, query: query, context: context),
      );
    }

    return filtered.toList();
  }

  static bool matchesQuery(
    Task task, {
    required String query,
    TaskFilterContext context = const TaskFilterContext(),
  }) {
    if (query.isEmpty) return true;

    if (task.title.toLowerCase().contains(query)) return true;
    if ((task.description?.toLowerCase().contains(query) ?? false)) return true;

    final project = context.projectMap[task.projectId];
    if (project != null) {
      if (project.name.toLowerCase().contains(query) ||
          (project.serialNumber?.toLowerCase().contains(query) ?? false) ||
          project.address.toLowerCase().contains(query)) {
        return true;
      }
    }

    for (final propertyId in task.propertyIds) {
      final property = context.propertyMap[propertyId];
      if (property != null) {
        if (property.name.toLowerCase().contains(query) ||
            property.identifier.toLowerCase().contains(query)) {
          return true;
        }
      }
    }

    return false;
  }
}
