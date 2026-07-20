import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/project_task_metrics.dart';
import '../models/property_task_metrics.dart';
import '../models/property_status.dart';
import 'dart:ui' show Color;
import '../models/task.dart';
import '../models/checklist_item.dart';
import '../utils/user_facing_error.dart';

class TaskService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _normalizeTaskStatus(String status) {
    switch (status) {
      case 'complete':
        return 'done';
      case 'in_progress':
        return 'working_on_it';
      case 'blocked':
        return 'stuck';
      default:
        return status;
    }
  }

  int _defaultProgressForStatus(String status) {
    switch (status) {
      case 'done':
        return 100;
      case 'working_on_it':
        return 10;
      case 'not_started':
      case 'stuck':
      default:
        return 0;
    }
  }

  ({String status, int progress}) _normalizeStatusProgress({
    required String currentStatus,
    required int currentProgress,
    String? newStatus,
    int? newProgress,
  }) {
    final hasStatus = newStatus != null;
    final hasProgress = newProgress != null;

    var status = _normalizeTaskStatus(hasStatus ? newStatus : currentStatus);
    var progress = currentProgress;
    if (hasProgress) {
      progress = newProgress.clamp(0, 100).toInt();
    }

    if (status == 'done') {
      progress = 100;
    } else if (status == 'not_started') {
      if (hasProgress && progress > 0) {
        status = 'working_on_it';
      } else {
        progress = 0;
      }
    } else if (progress == 100) {
      status = 'done';
    } else {
      if (hasStatus && !hasProgress) {
        if (status == 'working_on_it' && progress == 0) {
          progress = 10;
        } else if (progress >= 100) {
          progress = 99;
        }
      }

      if (hasProgress &&
          !hasStatus &&
          currentStatus == 'done' &&
          progress < 100) {
        status = progress == 0 ? 'not_started' : 'working_on_it';
      }
    }

    if (status == 'done') {
      progress = 100;
    }
    if (progress == 100) {
      status = 'done';
    }
    if (status != 'done' && progress >= 100) {
      progress = 99;
    }

    return (status: status, progress: progress);
  }

  // Fetch all tasks for a project
  Stream<List<Task>> getTasks(String projectId, {String? workspaceId}) {
    var query = _firestore
        .collection('tasks')
        .where('projectId', isEqualTo: projectId);

    // Add workspaceId filter if provided (required for security rules)
    if (workspaceId != null) {
      query = query.where('workspaceId', isEqualTo: workspaceId);
    }

    return query.snapshots().map((snapshot) {
      final tasks = snapshot.docs
          .map((doc) => Task.fromJson(doc.data(), doc.id))
          .toList();

      // Sort tasks: incomplete first, then by sort_order, then by creation date
      tasks.sort((a, b) {
        // First, sort by completion status (incomplete first)
        if (a.isComplete != b.isComplete) {
          return a.isComplete ? 1 : -1;
        }

        // Then, sort by sort_order
        final orderCmp = a.sortOrder.compareTo(b.sortOrder);
        if (orderCmp != 0) return orderCmp;

        // Finally, sort by creation date (newest first)
        return b.createdAt.compareTo(a.createdAt);
      });

      return tasks;
    });
  }

  // Fetch all tasks for a workspace (across all projects)
  Stream<List<Task>> getAllWorkspaceTasks(String workspaceId) {
    return _firestore
        .collection('tasks')
        .where('workspaceId', isEqualTo: workspaceId)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => Task.fromJson(doc.data(), doc.id))
              .toList();
        });
  }

  Future<Map<String, ProjectTaskMetrics>> getProjectListMetrics(
    String workspaceId,
  ) async {
    final snapshot = await _firestore
        .collection('tasks')
        .where('workspaceId', isEqualTo: workspaceId)
        .get();

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final metrics =
        <
          String,
          ({int total, int completed, int open, int overdue, int dueToday})
        >{};

    for (final doc in snapshot.docs) {
      final task = Task.fromJson(doc.data(), doc.id);
      final current =
          metrics[task.projectId] ??
          (total: 0, completed: 0, open: 0, overdue: 0, dueToday: 0);
      final isDueToday =
          !task.isComplete &&
          task.dueDate != null &&
          !task.dueDate!.isBefore(todayStart) &&
          task.dueDate!.isBefore(todayEnd);

      metrics[task.projectId] = (
        total: current.total + 1,
        completed: current.completed + (task.isComplete ? 1 : 0),
        open: current.open + (task.isComplete ? 0 : 1),
        overdue:
            current.overdue + ((!task.isComplete && task.isOverdue()) ? 1 : 0),
        dueToday: current.dueToday + (isDueToday ? 1 : 0),
      );
    }

    return {
      for (final entry in metrics.entries)
        entry.key: ProjectTaskMetrics(
          projectId: entry.key,
          openCount: entry.value.open,
          overdueCount: entry.value.overdue,
          dueTodayCount: entry.value.dueToday,
          totalCount: entry.value.total,
          completedCount: entry.value.completed,
          progressPercent: entry.value.total == 0
              ? 0
              : (entry.value.completed / entry.value.total) * 100,
        ),
    };
  }

  // Stream of per-property task metrics for all properties in a project.
  Stream<Map<String, PropertyTaskMetrics>> getPropertyTaskMetrics(
    String projectId, {
    String? workspaceId,
  }) {
    return getTasks(projectId, workspaceId: workspaceId).map((tasks) {
      final grouped = <String, List<Task>>{};
      for (final task in tasks) {
        for (final propertyId in task.propertyIds) {
          grouped.putIfAbsent(propertyId, () => []).add(task);
        }
      }
      return {
        for (final entry in grouped.entries)
          entry.key: PropertyTaskMetrics.fromTasks(entry.key, entry.value),
      };
    });
  }

  // Fetch all tasks linked to a property (client-side filter on propertyIds array)
  Stream<List<Task>> getTasksByProperty(String propertyId) {
    return _firestore
        .collection('tasks')
        .where('propertyIds', arrayContains: propertyId)
        .snapshots()
        .map((snapshot) {
          final tasks = snapshot.docs
              .map((doc) => Task.fromJson(doc.data(), doc.id))
              .toList();

          tasks.sort((a, b) {
            if (a.isComplete != b.isComplete) {
              return a.isComplete ? 1 : -1;
            }
            if (a.dueDate != null && b.dueDate != null) {
              return a.dueDate!.compareTo(b.dueDate!);
            } else if (a.dueDate != null) {
              return -1;
            } else if (b.dueDate != null) {
              return 1;
            }
            return b.createdAt.compareTo(a.createdAt);
          });

          return tasks;
        });
  }

  // Fetch all tasks linked to an area
  Stream<List<Task>> getTasksByArea(String areaId) {
    return _firestore
        .collection('tasks')
        .where('areaIds', arrayContains: areaId)
        .snapshots()
        .map((snapshot) {
          final tasks = snapshot.docs
              .map((doc) => Task.fromJson(doc.data(), doc.id))
              .toList();

          tasks.sort((a, b) {
            if (a.isComplete != b.isComplete) {
              return a.isComplete ? 1 : -1;
            }
            if (a.dueDate != null && b.dueDate != null) {
              return a.dueDate!.compareTo(b.dueDate!);
            } else if (a.dueDate != null) {
              return -1;
            } else if (b.dueDate != null) {
              return 1;
            }
            return b.createdAt.compareTo(a.createdAt);
          });

          return tasks;
        });
  }

  // Fetch a single task by ID
  Future<Task?> getTask(String taskId, {String? workspaceId}) async {
    try {
      final doc = await _firestore.collection('tasks').doc(taskId).get();
      if (doc.exists) {
        if (workspaceId != null && doc.data()?['workspaceId'] != workspaceId) {
          return null; // Or throw an exception
        }
        return Task.fromJson(doc.data()!, doc.id);
      }
      return null;
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'fetching task'),
        cause: e,
      );
    }
  }

  // Create a new task
  Future<Task> createTask({
    required String workspaceId,
    required String projectId,
    required String title,
    String? description,
    DateTime? dueDate,
    DateTime? startDate,
    double? estimatedDuration,
    List<String> assignedToIds = const [],
    List<String> requiredAssetIds = const [],
    List<String> predecessorIds = const [],
    List<String> requiredSkillIds = const [],
    String? parentId,
    TaskType taskType = TaskType.standard,
    String status = 'not_started',
    String priority = 'medium',
    List<String> propertyIds = const [],
    List<String> areaIds = const [],
  }) async {
    try {
      final now = DateTime.now();
      final normalizedStatus = _normalizeTaskStatus(status);
      final normalizedProgress = _defaultProgressForStatus(normalizedStatus);

      // Set default dates if not provided: start today, end tomorrow (1 day duration)
      final defaultStartDate = DateTime(now.year, now.month, now.day);
      final defaultDueDate = defaultStartDate.add(const Duration(days: 1));
      final defaultDuration = 8.0; // 1 day = 8 hours

      final taskData = {
        'workspaceId': workspaceId,
        'projectId': projectId,
        'title': title,
        'description': description,
        'dueDate': Timestamp.fromDate(dueDate ?? defaultDueDate),
        'startDate': Timestamp.fromDate(startDate ?? defaultStartDate),
        'estimatedDuration': estimatedDuration ?? defaultDuration,
        'isComplete': false,
        'assignedToIds': assignedToIds,
        'requiredAssetIds': requiredAssetIds,
        'predecessorIds': predecessorIds,
        'requiredSkillIds': requiredSkillIds,
        'propertyIds': propertyIds,
        'areaIds': areaIds,
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
        'parentId': parentId,
        'taskType': taskType.toString().split('.').last,
        'status': normalizedStatus,
        'priority': priority,
        'groupColor': 0xFF2196F3, // Default blue
        'isExpanded': true,
        'progress': normalizedProgress,
      };

      final docRef = await _firestore.collection('tasks').add(taskData);
      return Task.fromJson(taskData, docRef.id);
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'creating task'),
        cause: e,
      );
    }
  }

  // Update an existing task
  Future<void> updateTask({
    required String taskId,
    String? title,
    String? description,
    DateTime? dueDate,
    DateTime? startDate,
    double? estimatedDuration,
    List<String>? assignedToIds,
    List<String>? requiredAssetIds,
    List<String>? predecessorIds,
    List<String>? requiredSkillIds,
    bool? isComplete,
    int? progress,
    String? parentId,
    String? status,
    String? priority,
    Color? groupColor,
    bool clearParentId = false, // Special flag to clear parent
    List<String>? propertyIds,
    List<String>? areaIds,
    double? sortOrder,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (title != null) updates['title'] = title;
      if (description != null) updates['description'] = description;
      if (dueDate != null) updates['dueDate'] = Timestamp.fromDate(dueDate);
      if (startDate != null)
        updates['startDate'] = Timestamp.fromDate(startDate);
      if (estimatedDuration != null)
        updates['estimatedDuration'] = estimatedDuration;
      if (assignedToIds != null) updates['assignedToIds'] = assignedToIds;
      if (requiredAssetIds != null)
        updates['requiredAssetIds'] = requiredAssetIds;
      if (predecessorIds != null) updates['predecessorIds'] = predecessorIds;
      if (requiredSkillIds != null)
        updates['requiredSkillIds'] = requiredSkillIds;
      if (isComplete != null) updates['isComplete'] = isComplete;
      if (parentId != null) updates['parentId'] = parentId;
      if (clearParentId) updates['parentId'] = null;
      if (priority != null) updates['priority'] = priority;
      if (groupColor != null) updates['groupColor'] = groupColor.value;
      if (propertyIds != null) updates['propertyIds'] = propertyIds;
      if (areaIds != null) updates['areaIds'] = areaIds;
      if (sortOrder != null) updates['sortOrder'] = sortOrder;

      if (status != null || progress != null) {
        final existing = await _firestore.collection('tasks').doc(taskId).get();
        final existingData = existing.data() ?? <String, dynamic>{};
        final currentStatus = _normalizeTaskStatus(
          (existingData['status'] as String?) ?? 'not_started',
        );
        final currentProgress =
            (existingData['progress'] as num?)?.toInt() ?? 0;
        final normalized = _normalizeStatusProgress(
          currentStatus: currentStatus,
          currentProgress: currentProgress,
          newStatus: status,
          newProgress: progress,
        );
        updates['status'] = normalized.status;
        updates['progress'] = normalized.progress;
        updates['isComplete'] = normalized.status == 'done';
      }

      if (updates.isNotEmpty) {
        updates['updatedAt'] = Timestamp.fromDate(DateTime.now());
        await _firestore.collection('tasks').doc(taskId).update(updates);
      }
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'updating task'),
        cause: e,
      );
    }
  }

  // Add progress update to history
  Future<void> addProgressUpdate({
    required String taskId,
    required int progress,
    required String notes,
  }) async {
    try {
      final update = {
        'progress': progress,
        'notes': notes,
        'timestamp': Timestamp.fromDate(DateTime.now()),
      };

      await _firestore
          .collection('tasks')
          .doc(taskId)
          .collection('progressHistory')
          .add(update);
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'adding progress update'),
        cause: e,
      );
    }
  }

  // Get progress history for a task
  Stream<List<Map<String, dynamic>>> getProgressHistory(String taskId) {
    return _firestore
        .collection('tasks')
        .doc(taskId)
        .collection('progressHistory')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => {...doc.data(), 'id': doc.id})
              .toList(),
        );
  }

  // Toggle task completion status
  Future<void> toggleTaskCompletion(String taskId, bool isComplete) async {
    try {
      final nextIsComplete = !isComplete;
      final nextStatus = nextIsComplete ? 'done' : 'not_started';
      final nextProgress = nextIsComplete ? 100 : 0;
      await _firestore.collection('tasks').doc(taskId).update({
        'isComplete': nextIsComplete,
        'status': nextStatus,
        'progress': nextProgress,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

      if (nextIsComplete) {
        final doc =
            await _firestore.collection('tasks').doc(taskId).get();
        if (doc.exists) {
          final task = Task.fromJson(doc.data()!, doc.id);
          if (task.propertyIds.isNotEmpty) {
            await _checkAndAutoCompleteProperties(task.propertyIds);
          }
        }
      }
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'toggling task completion'),
        cause: e,
      );
    }
  }

  Future<void> _checkAndAutoCompleteProperties(
      List<String> propertyIds) async {
    final completedDbValue = PropertyStatus.completed.toDbValue();
    final archivedDbValue = PropertyStatus.archived.toDbValue();
    await Future.wait(
      propertyIds.map((propertyId) async {
        try {
          final snapshot = await _firestore
              .collection('tasks')
              .where('propertyIds', arrayContains: propertyId)
              .where('isComplete', isEqualTo: false)
              .get();

          if (snapshot.docs.isEmpty) {
            final propSnapshot = await _firestore
                .collection('properties')
                .doc(propertyId)
                .get();
            if (propSnapshot.exists) {
              final status = propSnapshot.data()?['status'] as String?;
              if (status != null &&
                  status != completedDbValue &&
                  status != archivedDbValue) {
                await _firestore
                    .collection('properties')
                    .doc(propertyId)
                    .update({
                  'status': completedDbValue,
                  'updatedAt': Timestamp.fromDate(DateTime.now()),
                });
              }
            }
          }
        } catch (_) {
          // Non-critical — silently skip
        }
      }),
      eagerError: false,
    );
  }

  // Delete a task
  Future<void> deleteTask(String taskId) async {
    try {
      await _firestore.collection('tasks').doc(taskId).delete();
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'deleting task'),
        cause: e,
      );
    }
  }

  // Get task count for a project
  Future<int> getTaskCount(String projectId, {String? workspaceId}) async {
    try {
      var query = _firestore
          .collection('tasks')
          .where('projectId', isEqualTo: projectId);

      if (workspaceId != null) {
        query = query.where('workspaceId', isEqualTo: workspaceId);
      }

      final snapshot = await query.get();
      return snapshot.docs.length;
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'getting task count'),
        cause: e,
      );
    }
  }

  // Get incomplete task count for a project
  Future<int> getIncompleteTaskCount(
    String projectId, {
    String? workspaceId,
  }) async {
    try {
      var query = _firestore
          .collection('tasks')
          .where('projectId', isEqualTo: projectId)
          .where('isComplete', isEqualTo: false);

      if (workspaceId != null) {
        query = query.where('workspaceId', isEqualTo: workspaceId);
      }

      final snapshot = await query.get();
      return snapshot.docs.length;
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'getting incomplete task count'),
        cause: e,
      );
    }
  }

  // Get tasks within a due date range (for timeline/calendar views)
  Stream<List<Task>> getTasksInDueDateRange(
    String projectId,
    DateTime rangeStart,
    DateTime rangeEnd, {
    String? workspaceId,
  }) {
    var query = _firestore
        .collection('tasks')
        .where('projectId', isEqualTo: projectId)
        .where(
          'dueDate',
          isGreaterThanOrEqualTo: Timestamp.fromDate(rangeStart),
        )
        .where('dueDate', isLessThanOrEqualTo: Timestamp.fromDate(rangeEnd))
        .orderBy('dueDate');

    if (workspaceId != null) {
      query = query.where('workspaceId', isEqualTo: workspaceId);
    }

    return query.snapshots().map(
      (snapshot) => snapshot.docs
          .map((doc) => Task.fromJson(doc.data(), doc.id))
          .toList(),
    );
  }

  // Get tasks within a start date range (for timeline views)
  Stream<List<Task>> getTasksInStartDateRange(
    String projectId,
    DateTime rangeStart,
    DateTime rangeEnd, {
    String? workspaceId,
  }) {
    var query = _firestore
        .collection('tasks')
        .where('projectId', isEqualTo: projectId)
        .where(
          'startDate',
          isGreaterThanOrEqualTo: Timestamp.fromDate(rangeStart),
        )
        .where('startDate', isLessThanOrEqualTo: Timestamp.fromDate(rangeEnd))
        .orderBy('startDate');

    if (workspaceId != null) {
      query = query.where('workspaceId', isEqualTo: workspaceId);
    }

    return query.snapshots().map(
      (snapshot) => snapshot.docs
          .map((doc) => Task.fromJson(doc.data(), doc.id))
          .toList(),
    );
  }

  // Get tasks for a specific month (convenience method for calendar view)
  Stream<List<Task>> getTasksForMonth(
    String projectId,
    int year,
    int month, {
    String? workspaceId,
  }) {
    final rangeStart = DateTime(year, month, 1);
    final rangeEnd = DateTime(year, month + 1, 0, 23, 59, 59);
    return getTasksInDueDateRange(
      projectId,
      rangeStart,
      rangeEnd,
      workspaceId: workspaceId,
    );
  }

  // ===== Gantt-specific methods =====

  /// Create a child task under a parent group
  Future<Task> createChildTask({
    required String workspaceId,
    required String projectId,
    required String title,
    required String parentId,
  }) async {
    return createTask(
      workspaceId: workspaceId,
      projectId: projectId,
      title: title,
      parentId: parentId,
      taskType: TaskType.standard,
    );
  }

  /// Create a new group (summary task) at root level or under a parent
  Future<Task> createGroup({
    required String workspaceId,
    required String projectId,
    required String title,
    String? parentId, // For nested groups
  }) async {
    return createTask(
      workspaceId: workspaceId,
      projectId: projectId,
      title: title,
      parentId: parentId,
      taskType: TaskType.summary,
    );
  }

  /// Update task expansion state (for collapsible groups)
  Future<void> updateTaskExpansion(String taskId, bool isExpanded) async {
    try {
      await _firestore.collection('tasks').doc(taskId).update({
        'isExpanded': isExpanded,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'updating task expansion'),
        cause: e,
      );
    }
  }

  /// Update task status
  Future<void> updateTaskStatus(String taskId, String newStatus) async {
    try {
      await updateTask(taskId: taskId, status: newStatus);
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'updating task status'),
        cause: e,
      );
    }
  }

  /// Update task priority
  Future<void> updateTaskPriority(String taskId, String newPriority) async {
    try {
      await _firestore.collection('tasks').doc(taskId).update({
        'priority': newPriority,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'updating task priority'),
        cause: e,
      );
    }
  }

  /// Update task type
  Future<void> updateTaskType(String taskId, TaskType newType) async {
    try {
      await _firestore.collection('tasks').doc(taskId).update({
        'taskType': newType.toString().split('.').last,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'updating task type'),
        cause: e,
      );
    }
  }

  /// Update task progress
  Future<void> updateTaskProgress(String taskId, int progress) async {
    try {
      await updateTask(taskId: taskId, progress: progress);
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'updating task progress'),
        cause: e,
      );
    }
  }

  /// Clone a task (and optionally its children for groups)
  /// Returns the cloned task
  Future<Task> cloneTask({
    required Task task,
    required List<Task> allTasks,
    bool cloneChildren = true,
  }) async {
    try {
      final now = DateTime.now();

      // Create cloned task data with new timestamps and "(Copy)" suffix
      final clonedTaskData = <String, dynamic>{
        'workspaceId': task.workspaceId,
        'projectId': task.projectId,
        'title': '${task.title} (Copy)',
        'description': task.description,
        'dueDate': task.dueDate != null
            ? Timestamp.fromDate(task.dueDate!)
            : null,
        'startDate': task.startDate != null
            ? Timestamp.fromDate(task.startDate!)
            : null,
        'estimatedDuration': task.estimatedDuration,
        'isComplete': false, // Reset completion status
        'assignedToIds': List<String>.from(task.assignedToIds),
        'requiredAssetIds': List<String>.from(task.requiredAssetIds),
        'predecessorIds':
            <String>[], // Don't copy dependencies - they may not make sense
        'requiredSkillIds': List<String>.from(task.requiredSkillIds),
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
        'parentId': task.parentId, // Keep same parent
        'taskType': task.taskType.toString().split('.').last,
        'status': 'not_started', // Reset status
        'priority': task.priority,
        'groupColor': task.groupColor.value,
        'isExpanded': true,
        'progress': 0, // Reset progress
      };

      final docRef = await _firestore.collection('tasks').add(clonedTaskData);
      final clonedTask = Task.fromJson(clonedTaskData, docRef.id);

      // If this is a group/summary task and cloneChildren is true, clone all children
      if (cloneChildren && task.taskType == TaskType.summary) {
        await _cloneChildrenRecursively(
          originalParentId: task.id,
          newParentId: clonedTask.id,
          allTasks: allTasks,
        );
      }

      return clonedTask;
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'cloning task'),
        cause: e,
      );
    }
  }

  /// Recursively clone children of a task
  Future<void> _cloneChildrenRecursively({
    required String originalParentId,
    required String newParentId,
    required List<Task> allTasks,
  }) async {
    final now = DateTime.now();

    // Find all direct children of the original parent
    final children = allTasks
        .where((t) => t.parentId == originalParentId)
        .toList();
    children.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    for (final child in children) {
      // Clone this child with the new parent ID
      final clonedChildData = <String, dynamic>{
        'workspaceId': child.workspaceId,
        'projectId': child.projectId,
        'title': child.title, // Don't add "(Copy)" to children
        'description': child.description,
        'dueDate': child.dueDate != null
            ? Timestamp.fromDate(child.dueDate!)
            : null,
        'startDate': child.startDate != null
            ? Timestamp.fromDate(child.startDate!)
            : null,
        'estimatedDuration': child.estimatedDuration,
        'isComplete': false,
        'assignedToIds': List<String>.from(child.assignedToIds),
        'requiredAssetIds': List<String>.from(child.requiredAssetIds),
        'predecessorIds': <String>[],
        'requiredSkillIds': List<String>.from(child.requiredSkillIds),
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
        'parentId': newParentId,
        'taskType': child.taskType.toString().split('.').last,
        'status': 'not_started',
        'priority': child.priority,
        'groupColor': child.groupColor.value,
        'isExpanded': true,
        'progress': 0,
      };

      final docRef = await _firestore.collection('tasks').add(clonedChildData);

      // If this child is also a group, recursively clone its children
      if (child.taskType == TaskType.summary) {
        await _cloneChildrenRecursively(
          originalParentId: child.id,
          newParentId: docRef.id,
          allTasks: allTasks,
        );
      }
    }
  }

  /// Clone multiple selected tasks while preserving hierarchy
  /// This identifies the "root" tasks in the selection (those whose parents are not selected)
  /// and clones each root along with any of its descendants that are also selected.
  Future<List<Task>> cloneMultipleTasks({
    required List<Task> selectedTasks,
    required List<Task> allTasks,
  }) async {
    if (selectedTasks.isEmpty) return [];

    final selectedIds = selectedTasks.map((t) => t.id).toSet();
    final clonedTasks = <Task>[];

    // Find "root" tasks in the selection - tasks whose parent is NOT in the selection
    final rootsInSelection = selectedTasks.where((task) {
      if (task.parentId == null) return true;
      return !selectedIds.contains(task.parentId);
    }).toList();

    // Sort roots by creation order to maintain order
    rootsInSelection.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // Clone each root and its selected descendants
    for (final rootTask in rootsInSelection) {
      final clonedRoot = await _cloneTaskWithSelectedDescendants(
        task: rootTask,
        newParentId: rootTask.parentId, // Keep same parent as original
        selectedIds: selectedIds,
        allTasks: allTasks,
        isRoot: true,
      );
      clonedTasks.add(clonedRoot);
    }

    return clonedTasks;
  }

  /// Helper to clone a task and recursively clone only selected descendants
  Future<Task> _cloneTaskWithSelectedDescendants({
    required Task task,
    required String? newParentId,
    required Set<String> selectedIds,
    required List<Task> allTasks,
    required bool isRoot,
  }) async {
    final now = DateTime.now();

    final clonedTaskData = <String, dynamic>{
      'workspaceId': task.workspaceId,
      'projectId': task.projectId,
      'title': isRoot ? '${task.title} (Copy)' : task.title,
      'description': task.description,
      'dueDate': task.dueDate != null
          ? Timestamp.fromDate(task.dueDate!)
          : null,
      'startDate': task.startDate != null
          ? Timestamp.fromDate(task.startDate!)
          : null,
      'estimatedDuration': task.estimatedDuration,
      'isComplete': false,
      'assignedToIds': List<String>.from(task.assignedToIds),
      'requiredAssetIds': List<String>.from(task.requiredAssetIds),
      'predecessorIds': <String>[],
      'requiredSkillIds': List<String>.from(task.requiredSkillIds),
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
      'parentId': newParentId,
      'taskType': task.taskType.toString().split('.').last,
      'status': 'not_started',
      'priority': task.priority,
      'groupColor': task.groupColor.value,
      'isExpanded': true,
      'progress': 0,
    };

    final docRef = await _firestore.collection('tasks').add(clonedTaskData);
    final clonedTask = Task.fromJson(clonedTaskData, docRef.id);

    // Find direct children that are in the selection
    final selectedChildren = allTasks
        .where((t) => t.parentId == task.id && selectedIds.contains(t.id))
        .toList();
    selectedChildren.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // Recursively clone selected children
    for (final child in selectedChildren) {
      await _cloneTaskWithSelectedDescendants(
        task: child,
        newParentId: clonedTask.id,
        selectedIds: selectedIds,
        allTasks: allTasks,
        isRoot: false,
      );
    }

    return clonedTask;
  }

  // ===== Per-User Task Expansion Preferences =====

  /// Get user's task expansion preferences for a project
  /// Returns a map of taskId -> isExpanded (true/false)
  Future<Map<String, bool>> getUserTaskExpansionPreferences(
    String userId,
    String projectId,
  ) async {
    try {
      final doc = await _firestore
          .collection('userPreferences')
          .doc(userId)
          .collection('taskExpansion')
          .doc(projectId)
          .get();

      if (!doc.exists || doc.data() == null) {
        return {}; // No preferences saved yet
      }

      final data = doc.data()!;
      final Map<String, bool> preferences = {};
      data.forEach((key, value) {
        if (key != 'updatedAt' && value is bool) {
          preferences[key] = value;
        }
      });
      return preferences;
    } catch (e) {
      debugPrint('Error getting user task expansion preferences: $e');
      return {}; // Return empty on error, use defaults
    }
  }

  /// Update a single task's expansion state for a specific user
  Future<void> updateUserTaskExpansion(
    String userId,
    String projectId,
    String taskId,
    bool isExpanded,
  ) async {
    try {
      await _firestore
          .collection('userPreferences')
          .doc(userId)
          .collection('taskExpansion')
          .doc(projectId)
          .set({
            taskId: isExpanded,
            'updatedAt': Timestamp.fromDate(DateTime.now()),
          }, SetOptions(merge: true));
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(
          e,
          'updating user task expansion preference',
        ),
        cause: e,
      );
    }
  }

  /// Update multiple task expansion states at once for a specific user (for collapse all / expand all)
  Future<void> updateUserTaskExpansionBatch(
    String userId,
    String projectId,
    Map<String, bool> expansionStates,
  ) async {
    try {
      final data = Map<String, dynamic>.from(expansionStates);
      data['updatedAt'] = Timestamp.fromDate(DateTime.now());

      await _firestore
          .collection('userPreferences')
          .doc(userId)
          .collection('taskExpansion')
          .doc(projectId)
          .set(data, SetOptions(merge: true));
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(
          e,
          'updating user task expansion preferences',
        ),
        cause: e,
      );
    }
  }

  // ===== Checklist Item Methods =====

  /// Add a new checklist item to a task
  Future<ChecklistItem> addChecklistItem(String taskId, String title) async {
    try {
      final item = ChecklistItem.create(title: title);

      // Get current checklist items to calculate progress
      final doc = await _firestore.collection('tasks').doc(taskId).get();
      final data = doc.data()!;
      final currentItems = (data['checklistItems'] as List? ?? [])
          .map((item) => ChecklistItem.fromJson(item as Map<String, dynamic>))
          .toList();
      currentItems.add(item);

      // Calculate progress from checklist completion
      final progress = _calculateChecklistProgress(currentItems);
      final normalized = _normalizeStatusProgress(
        currentStatus: _normalizeTaskStatus(
          (data['status'] as String?) ?? 'not_started',
        ),
        currentProgress: (data['progress'] as num?)?.toInt() ?? 0,
        newProgress: progress,
      );

      await _firestore.collection('tasks').doc(taskId).update({
        'checklistItems': currentItems.map((item) => item.toJson()).toList(),
        'status': normalized.status,
        'progress': normalized.progress,
        'isComplete': normalized.status == 'done',
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

      return item;
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'adding checklist item'),
        cause: e,
      );
    }
  }

  /// Update an existing checklist item (title or completion status)
  Future<void> updateChecklistItem(
    String taskId,
    String itemId, {
    String? title,
    bool? isComplete,
  }) async {
    try {
      // Get current task to find and update the item
      final doc = await _firestore.collection('tasks').doc(taskId).get();
      if (!doc.exists) {
        throw Exception('Task not found');
      }

      final data = doc.data()!;
      final checklistItems = (data['checklistItems'] as List? ?? [])
          .map((item) => ChecklistItem.fromJson(item as Map<String, dynamic>))
          .toList();

      final itemIndex = checklistItems.indexWhere((item) => item.id == itemId);
      if (itemIndex == -1) {
        throw Exception('Checklist item not found');
      }

      // Update the item
      checklistItems[itemIndex] = checklistItems[itemIndex].copyWith(
        title: title,
        isComplete: isComplete,
      );

      // Calculate progress from checklist completion
      final progress = _calculateChecklistProgress(checklistItems);
      final normalized = _normalizeStatusProgress(
        currentStatus: _normalizeTaskStatus(
          (data['status'] as String?) ?? 'not_started',
        ),
        currentProgress: (data['progress'] as num?)?.toInt() ?? 0,
        newProgress: progress,
      );

      // Save back to Firestore with updated progress
      await _firestore.collection('tasks').doc(taskId).update({
        'checklistItems': checklistItems.map((item) => item.toJson()).toList(),
        'status': normalized.status,
        'progress': normalized.progress,
        'isComplete': normalized.status == 'done',
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'updating checklist item'),
        cause: e,
      );
    }
  }

  /// Toggle the completion status of a checklist item
  Future<void> toggleChecklistItemComplete(String taskId, String itemId) async {
    try {
      // Get current task to find and toggle the item
      final doc = await _firestore.collection('tasks').doc(taskId).get();
      if (!doc.exists) {
        throw Exception('Task not found');
      }

      final data = doc.data()!;
      final checklistItems = (data['checklistItems'] as List? ?? [])
          .map((item) => ChecklistItem.fromJson(item as Map<String, dynamic>))
          .toList();

      final itemIndex = checklistItems.indexWhere((item) => item.id == itemId);
      if (itemIndex == -1) {
        throw Exception('Checklist item not found');
      }

      // Toggle the completion status
      checklistItems[itemIndex] = checklistItems[itemIndex].copyWith(
        isComplete: !checklistItems[itemIndex].isComplete,
      );

      // Calculate progress from checklist completion
      final progress = _calculateChecklistProgress(checklistItems);
      final normalized = _normalizeStatusProgress(
        currentStatus: _normalizeTaskStatus(
          (data['status'] as String?) ?? 'not_started',
        ),
        currentProgress: (data['progress'] as num?)?.toInt() ?? 0,
        newProgress: progress,
      );

      // Save back to Firestore with updated progress
      await _firestore.collection('tasks').doc(taskId).update({
        'checklistItems': checklistItems.map((item) => item.toJson()).toList(),
        'status': normalized.status,
        'progress': normalized.progress,
        'isComplete': normalized.status == 'done',
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'toggling checklist item'),
        cause: e,
      );
    }
  }

  /// Calculate progress percentage from checklist items
  int _calculateChecklistProgress(List<ChecklistItem> items) {
    if (items.isEmpty) return 0;
    final completedCount = items.where((item) => item.isComplete).length;
    return ((completedCount / items.length) * 100).round();
  }

  /// Delete a checklist item from a task
  Future<void> deleteChecklistItem(String taskId, String itemId) async {
    try {
      // Get current task to find and remove the item
      final doc = await _firestore.collection('tasks').doc(taskId).get();
      if (!doc.exists) {
        throw Exception('Task not found');
      }

      final data = doc.data()!;
      final checklistItems = (data['checklistItems'] as List? ?? [])
          .map((item) => ChecklistItem.fromJson(item as Map<String, dynamic>))
          .toList();

      // Remove the item
      checklistItems.removeWhere((item) => item.id == itemId);

      // Calculate progress from checklist completion
      final progress = _calculateChecklistProgress(checklistItems);
      final normalized = _normalizeStatusProgress(
        currentStatus: _normalizeTaskStatus(
          (data['status'] as String?) ?? 'not_started',
        ),
        currentProgress: (data['progress'] as num?)?.toInt() ?? 0,
        newProgress: progress,
      );

      // Save back to Firestore with updated progress
      await _firestore.collection('tasks').doc(taskId).update({
        'checklistItems': checklistItems.map((item) => item.toJson()).toList(),
        'status': normalized.status,
        'progress': normalized.progress,
        'isComplete': normalized.status == 'done',
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'deleting checklist item'),
        cause: e,
      );
    }
  }

  /// Reorder checklist items
  Future<void> reorderChecklistItems(
    String taskId,
    List<ChecklistItem> reorderedItems,
  ) async {
    try {
      // Calculate progress from checklist completion (reordering doesn't change completion status)
      final progress = _calculateChecklistProgress(reorderedItems);
      final doc = await _firestore.collection('tasks').doc(taskId).get();
      final data = doc.data() ?? <String, dynamic>{};
      final normalized = _normalizeStatusProgress(
        currentStatus: _normalizeTaskStatus(
          (data['status'] as String?) ?? 'not_started',
        ),
        currentProgress: (data['progress'] as num?)?.toInt() ?? 0,
        newProgress: progress,
      );

      await _firestore.collection('tasks').doc(taskId).update({
        'checklistItems': reorderedItems.map((item) => item.toJson()).toList(),
        'status': normalized.status,
        'progress': normalized.progress,
        'isComplete': normalized.status == 'done',
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'reordering checklist items'),
        cause: e,
      );
    }
  }
}
