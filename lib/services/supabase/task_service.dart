import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui' show Color;
import '../../models/task.dart';
import '../../models/project_task_metrics.dart';
import '../../models/property_task_metrics.dart';
import '../../models/property_status.dart';
import '../../models/checklist_item.dart';
import '../../utils/app_logger.dart';
import '../../utils/user_facing_error.dart';
import 'automation_service.dart';
import 'notification_service.dart';

/// Supabase implementation of TaskService
class SupabaseTaskService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final SupabaseAutomationService _automationService =
      SupabaseAutomationService();

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

    if (hasStatus) {
      // An explicit status change always wins over progress-driven inference.
      // Otherwise switching a 100%-complete task to Stuck/Working would be
      // silently reverted to Done because the stale progress is still 100.
      if (status == 'done') {
        progress = 100;
      } else if (status == 'not_started') {
        progress = 0;
      } else if (status == 'working_on_it' && progress == 0) {
        progress = 10;
      } else if (progress >= 100) {
        progress = _defaultProgressForStatus(status);
      }
    } else {
      // No explicit status: infer status from the progress value.
      if (status == 'done' && hasProgress && progress < 100) {
        status = progress == 0 ? 'not_started' : 'working_on_it';
      } else if (status == 'not_started' && hasProgress && progress > 0) {
        status = 'working_on_it';
      } else if (progress == 100) {
        status = 'done';
      }
    }

    if (status == 'done') {
      progress = 100;
    } else if (progress >= 100) {
      progress = 99;
    }

    return (status: status, progress: progress);
  }

  /// Fetch all tasks for a project (realtime stream)
  Stream<List<Task>> getTasks(String projectId, {String? workspaceId}) {
    AppLogger.debug(
      'getTasks: Creating stream',
      metadata: {'projectId': projectId},
    );

    return _supabase
        .from('tasks')
        .stream(primaryKey: ['id'])
        .eq('project_id', projectId)
        .map((data) {
          AppLogger.debug(
            'getTasks stream received data',
            metadata: {'count': data.length, 'projectId': projectId},
          );
          var tasks = data
              .where(
                (row) =>
                    workspaceId == null || row['workspace_id'] == workspaceId,
              )
              .map((row) => Task.fromJson(_toFirestoreFormat(row), row['id']))
              .toList();

          // Sort tasks: incomplete first, then by sort_order, then by creation date
          tasks.sort((a, b) {
            if (a.isComplete != b.isComplete) {
              return a.isComplete ? 1 : -1;
            }

            final orderCmp = a.sortOrder.compareTo(b.sortOrder);
            if (orderCmp != 0) return orderCmp;

            return a.createdAt.compareTo(b.createdAt);
          });

          return tasks;
        });
  }

  /// Fetch all tasks for a workspace (realtime stream)
  Stream<List<Task>> getAllWorkspaceTasks(String workspaceId) {
    return _supabase
        .from('tasks')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .map((data) {
          return data
              .map((row) => Task.fromJson(_toFirestoreFormat(row), row['id']))
              .toList();
        });
  }

  /// Fetch task-derived metrics for every project in a workspace in one query.
  Future<Map<String, ProjectTaskMetrics>> getProjectListMetrics(
    String workspaceId,
  ) async {
    final response = await _supabase.rpc(
      'get_project_list_task_metrics',
      params: {'p_workspace_id': workspaceId},
    );

    final rows = (response as List<dynamic>).cast<Map<String, dynamic>>();
    return {
      for (final row in rows)
        row['project_id'] as String: ProjectTaskMetrics.fromJson(row),
    };
  }

  /// Stream of per-property task metrics for all properties in a project.
  /// Reuses the existing project task stream — no extra DB subscription.
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

  /// Fetch all tasks linked to a property (realtime stream)
  /// Uses workspace-level stream with client-side filtering since
  /// Supabase realtime streams don't support array containment filters.
  Stream<List<Task>> getTasksByProperty(String propertyId) {
    AppLogger.debug(
      'getTasksByProperty: Creating stream',
      metadata: {'propertyId': propertyId},
    );

    return _supabase.from('tasks').stream(primaryKey: ['id']).map((data) {
      // Client-side filter: check if property_ids array contains the propertyId
      final filtered = data.where((row) {
        final ids = row['property_ids'];
        if (ids is List) {
          return ids.contains(propertyId);
        }
        return false;
      }).toList();

      AppLogger.debug(
        'getTasksByProperty stream received data',
        metadata: {'count': filtered.length, 'propertyId': propertyId},
      );
      var tasks = filtered
          .map((row) => Task.fromJson(_toFirestoreFormat(row), row['id']))
          .toList();

      // Sort tasks: incomplete first, then by due date, then by creation date
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

  /// Fetch all tasks linked to an area (realtime stream)
  Stream<List<Task>> getTasksByArea(String areaId) {
    AppLogger.debug(
      'getTasksByArea: Creating stream',
      metadata: {'areaId': areaId},
    );

    return _supabase.from('tasks').stream(primaryKey: ['id']).map((data) {
      // Client-side filter: check if area_ids array contains the areaId
      final filtered = data.where((row) {
        final ids = row['area_ids'];
        if (ids is List) {
          return ids.contains(areaId);
        }
        return false;
      }).toList();

      AppLogger.debug(
        'getTasksByArea stream received data',
        metadata: {'count': filtered.length, 'areaId': areaId},
      );
      var tasks = filtered
          .map((row) => Task.fromJson(_toFirestoreFormat(row), row['id']))
          .toList();

      // Sort tasks: incomplete first, then by due date, then by creation date
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

  /// Fetch a single task by ID
  Future<Task?> getTask(String taskId, {String? workspaceId}) async {
    try {
      var query = _supabase.from('tasks').select().eq('id', taskId);

      if (workspaceId != null) {
        query = query.eq('workspace_id', workspaceId);
      }

      final response = await query.maybeSingle();

      if (response != null) {
        return Task.fromJson(_toFirestoreFormat(response), response['id']);
      }
      return null;
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'fetching task'),
        cause: e,
      );
    }
  }

  /// Create a new task
  Future<Task> createTask({
    required String workspaceId,
    required String projectId,
    required String title,
    String? description,
    DateTime? dueDate,
    DateTime? startDate,
    DateTime? endDate,
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
    bool isRecurring = false,
    Map<String, dynamic>? recurrenceRule,
    String? recurringParentId,
    int occurrenceIndex = 0,
  }) async {
    try {
      final now = DateTime.now();
      final normalizedStatus = _normalizeTaskStatus(status);
      final normalizedProgress = _defaultProgressForStatus(normalizedStatus);

      // Set default dates if not provided: start today, end tomorrow
      final defaultStartDate = DateTime(now.year, now.month, now.day);
      final defaultDueDate = defaultStartDate.add(const Duration(days: 1));
      final defaultDuration = 8.0; // 1 day = 8 hours

      // Filter out empty strings from UUID arrays
      final filteredAssignedToIds = assignedToIds
          .where((id) => id.isNotEmpty)
          .toList();
      final filteredRequiredAssetIds = requiredAssetIds
          .where((id) => id.isNotEmpty)
          .toList();
      final filteredPredecessorIds = predecessorIds
          .where((id) => id.isNotEmpty)
          .toList();
      final filteredRequiredSkillIds = requiredSkillIds
          .where((id) => id.isNotEmpty)
          .toList();

      final taskData = {
        'workspace_id': workspaceId,
        'project_id': projectId,
        'title': title,
        'description': description,
        'due_date': (dueDate ?? defaultDueDate).toIso8601String(),
        'start_date': (startDate ?? defaultStartDate).toIso8601String(),
        'end_date': endDate?.toIso8601String(),
        'estimated_duration': estimatedDuration ?? defaultDuration,
        'is_complete': false,
        'assigned_to_ids': filteredAssignedToIds,
        'required_asset_ids': filteredRequiredAssetIds,
        'predecessor_ids': filteredPredecessorIds,
        'required_skill_ids': filteredRequiredSkillIds,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'parent_id': (parentId != null && parentId.isNotEmpty)
            ? parentId
            : null,
        'task_type': taskType.toString().split('.').last,
        'status': normalizedStatus,
        'priority': priority,
        'group_color': 0xFF2196F3, // Default blue
        'is_expanded': true,
        'progress': normalizedProgress,
        'checklist_items': [],
        'property_ids': propertyIds.where((id) => id.isNotEmpty).toList(),
        'area_ids': areaIds.where((id) => id.isNotEmpty).toList(),
        'is_recurring': isRecurring,
        'recurrence_rule': recurrenceRule,
        'recurring_parent_id':
            (recurringParentId != null && recurringParentId.isNotEmpty)
            ? recurringParentId
            : null,
        'occurrence_index': occurrenceIndex,
      };

      final response = await _supabase
          .from('tasks')
          .insert(taskData)
          .select()
          .single();

      final createdTask = Task.fromJson(
        _toFirestoreFormat(response),
        response['id'],
      );

      // Fire-and-forget: notify assigned users
      if (filteredAssignedToIds.isNotEmpty) {
        final currentUserId = _supabase.auth.currentUser?.id;
        _notifyAssignedUsers(
          assignedUserIds: filteredAssignedToIds,
          taskTitle: title,
          taskId: response['id'] as String,
          projectId: projectId,
          workspaceId: workspaceId,
          currentUserId: currentUserId,
        );

        _automationService.processTaskAssigned(
          workspaceId: workspaceId,
          taskId: response['id'] as String,
          projectId: projectId,
          taskTitle: title,
          assignedUserIds: filteredAssignedToIds,
          actorUserId: currentUserId ?? 'system',
          eventKey:
              'task_assigned:${response['id']}:${now.toIso8601String()}:create',
        );
      }

      return createdTask;
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'creating task'),
        cause: e,
      );
    }
  }

  /// Update an existing task
  Future<void> updateTask({
    required String taskId,
    String? title,
    String? description,
    DateTime? dueDate,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEndDate = false,
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
    bool clearParentId = false,
    List<String>? propertyIds,
    List<String>? areaIds,
    bool? isRecurring,
    Map<String, dynamic>? recurrenceRule,
    bool clearRecurrence = false,
    double? sortOrder,
  }) async {
    try {
      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (title != null) updates['title'] = title;
      if (description != null) updates['description'] = description;
      if (dueDate != null) updates['due_date'] = dueDate.toIso8601String();
      if (startDate != null)
        updates['start_date'] = startDate.toIso8601String();
      if (endDate != null) updates['end_date'] = endDate.toIso8601String();
      if (clearEndDate) updates['end_date'] = null;
      if (estimatedDuration != null)
        updates['estimated_duration'] = estimatedDuration;
      // Filter out empty strings from UUID arrays
      if (assignedToIds != null)
        updates['assigned_to_ids'] = assignedToIds
            .where((id) => id.isNotEmpty)
            .toList();
      if (requiredAssetIds != null)
        updates['required_asset_ids'] = requiredAssetIds
            .where((id) => id.isNotEmpty)
            .toList();
      if (predecessorIds != null)
        updates['predecessor_ids'] = predecessorIds
            .where((id) => id.isNotEmpty)
            .toList();
      if (requiredSkillIds != null)
        updates['required_skill_ids'] = requiredSkillIds
            .where((id) => id.isNotEmpty)
            .toList();
      if (isComplete != null) updates['is_complete'] = isComplete;
      if (parentId != null && parentId.isNotEmpty)
        updates['parent_id'] = parentId;
      if (clearParentId || (parentId != null && parentId.isEmpty))
        updates['parent_id'] = null;
      if (priority != null) updates['priority'] = priority;
      if (groupColor != null) updates['group_color'] = groupColor.value;
      if (propertyIds != null)
        updates['property_ids'] = propertyIds
            .where((id) => id.isNotEmpty)
            .toList();
      if (areaIds != null)
        updates['area_ids'] = areaIds.where((id) => id.isNotEmpty).toList();
      if (isRecurring != null) updates['is_recurring'] = isRecurring;
      if (recurrenceRule != null) updates['recurrence_rule'] = recurrenceRule;
      if (sortOrder != null) updates['sort_order'] = sortOrder;
      if (clearRecurrence) {
        updates['is_recurring'] = false;
        updates['recurrence_rule'] = null;
      }

      // Fetch old assigned IDs before updating (for assignment notifications)
      List<String> oldAssignedIds = [];
      String? taskTitle;
      String? taskProjectId;
      String? taskWorkspaceId;
      var hasExistingTaskContext = false;
      String oldStatus = 'not_started';
      int oldProgress = 0;
      if (assignedToIds != null || status != null || progress != null) {
        try {
          final existing = await _supabase
              .from('tasks')
              .select(
                'assigned_to_ids, title, project_id, workspace_id, status, progress',
              )
              .eq('id', taskId)
              .maybeSingle();
          if (existing != null) {
            hasExistingTaskContext = true;
            oldAssignedIds = List<String>.from(
              existing['assigned_to_ids'] ?? [],
            );
            taskTitle = existing['title'] as String?;
            taskProjectId = existing['project_id'] as String?;
            taskWorkspaceId = existing['workspace_id'] as String?;
            oldStatus = _normalizeTaskStatus(
              (existing['status'] as String?) ?? 'not_started',
            );
            oldProgress = (existing['progress'] as num?)?.toInt() ?? 0;
          }
        } catch (_) {}
      }

      if (status != null || progress != null) {
        final normalized = _normalizeStatusProgress(
          currentStatus: oldStatus,
          currentProgress: oldProgress,
          newStatus: status,
          newProgress: progress,
        );
        updates['status'] = normalized.status;
        updates['progress'] = normalized.progress;
        updates['is_complete'] = normalized.status == 'done';

        // Auto-set end_date when task becomes done; clear it when un-done
        if (normalized.status == 'done' && oldStatus != 'done') {
          if (!updates.containsKey('end_date')) {
            updates['end_date'] = DateTime.now().toIso8601String();
          }
        } else if (normalized.status != 'done' && oldStatus == 'done') {
          if (!updates.containsKey('end_date')) {
            updates['end_date'] = null;
          }
        }
      }

      AppLogger.debug(
        'Updating task',
        metadata: {'taskId': taskId, 'updates': updates.toString()},
      );
      await _supabase.from('tasks').update(updates).eq('id', taskId);
      AppLogger.debug(
        'Task updated successfully',
        metadata: {'taskId': taskId},
      );

      // Fire-and-forget: notify newly assigned users
      if (assignedToIds != null && taskWorkspaceId != null) {
        final newlyAssigned = assignedToIds
            .where((id) => id.isNotEmpty && !oldAssignedIds.contains(id))
            .toList();
        if (newlyAssigned.isNotEmpty) {
          final currentUserId = _supabase.auth.currentUser?.id;
          _notifyAssignedUsers(
            assignedUserIds: newlyAssigned,
            taskTitle: taskTitle ?? title ?? 'a task',
            taskId: taskId,
            projectId: taskProjectId ?? '',
            workspaceId: taskWorkspaceId,
            currentUserId: currentUserId,
          );

          if ((taskProjectId ?? '').isNotEmpty) {
            _automationService.processTaskAssigned(
              workspaceId: taskWorkspaceId,
              taskId: taskId,
              projectId: taskProjectId!,
              taskTitle: taskTitle ?? title ?? 'a task',
              assignedUserIds: newlyAssigned,
              actorUserId: currentUserId ?? 'system',
              eventKey: 'task_assigned:$taskId:${updates['updated_at']}:update',
            );
          }
        }
      }

      final newStatus = updates['status'] as String?;
      if (newStatus != null &&
          hasExistingTaskContext &&
          oldStatus != newStatus &&
          taskWorkspaceId != null &&
          (taskProjectId ?? '').isNotEmpty) {
        final currentUserId = _supabase.auth.currentUser?.id;
        _automationService.processTaskStatusChanged(
          workspaceId: taskWorkspaceId,
          taskId: taskId,
          projectId: taskProjectId!,
          taskTitle: taskTitle ?? title ?? 'a task',
          fromStatus: oldStatus,
          toStatus: newStatus,
          actorUserId: currentUserId ?? 'system',
          eventKey: 'task_status_changed:$taskId:${updates['updated_at']}',
        );
      }
    } catch (e) {
      AppLogger.error(
        'Error updating task',
        error: e,
        metadata: {'taskId': taskId},
      );
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'updating task'),
        cause: e,
      );
    }
  }

  /// Add progress update to history
  Future<void> addProgressUpdate({
    required String taskId,
    required int progress,
    required String notes,
  }) async {
    try {
      await _supabase.from('task_progress_history').insert({
        'task_id': taskId,
        'progress': progress,
        'notes': notes,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'adding progress update'),
        cause: e,
      );
    }
  }

  /// Get progress history for a task
  Stream<List<Map<String, dynamic>>> getProgressHistory(String taskId) {
    return _supabase
        .from('task_progress_history')
        .stream(primaryKey: ['id'])
        .eq('task_id', taskId)
        .map((data) {
          final result = data
              .map(
                (row) => {
                  'id': row['id'],
                  'progress': row['progress'],
                  'notes': row['notes'],
                  'timestamp': DateTime.parse(row['created_at']),
                },
              )
              .toList();
          result.sort(
            (a, b) => (b['timestamp'] as DateTime).compareTo(
              a['timestamp'] as DateTime,
            ),
          );
          return result;
        });
  }

  /// Toggle task completion status
  Future<void> toggleTaskCompletion(String taskId, bool isComplete) async {
    try {
      final nextIsComplete = !isComplete;
      final nextStatus = nextIsComplete ? 'done' : 'not_started';
      final nextProgress = nextIsComplete ? 100 : 0;
      await _supabase
          .from('tasks')
          .update({
            'is_complete': nextIsComplete,
            'status': nextStatus,
            'progress': nextProgress,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', taskId);

      // If marking complete, check for recurrence and auto-create next occurrence
      if (!isComplete) {
        final task = await getTask(taskId);
        if (task != null) {
          // Notify assigned users about task completion
          if (task.assignedToIds.isNotEmpty) {
            final currentUserId = _supabase.auth.currentUser?.id;
            _notifyTaskCompletion(
              assignedUserIds: task.assignedToIds,
              taskTitle: task.title,
              taskId: taskId,
              projectId: task.projectId,
              workspaceId: task.workspaceId,
              currentUserId: currentUserId,
            );
          }

          if (task.isRecurring && task.recurrenceRule != null) {
            await _createNextOccurrence(task);
          }

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

  /// When a task is completed, check if all tasks for each linked property are
  /// now done and, if so, silently advance that property's status to completed.
  Future<void> _checkAndAutoCompleteProperties(
      List<String> propertyIds) async {
    final completedDbValue = PropertyStatus.completed.toDbValue();
    final archivedDbValue = PropertyStatus.archived.toDbValue();
    await Future.wait(
      propertyIds.map((propertyId) async {
        try {
          final remaining = await _supabase
              .from('tasks')
              .select('id')
              .filter('property_ids', 'cs', '["$propertyId"]')
              .eq('is_complete', false);

          if ((remaining as List<dynamic>).isEmpty) {
            await _supabase
                .from('properties')
                .update({
                  'status': completedDbValue,
                  'updated_at': DateTime.now().toIso8601String(),
                })
                .eq('id', propertyId)
                .not('status', 'in', '($completedDbValue,$archivedDbValue)');
          }
        } catch (e) {
          // Non-critical — log and continue
          AppLogger.warning(
            'Failed to auto-complete property $propertyId',
            metadata: {'error': e.toString()},
          );
        }
      }),
      eagerError: false,
    );
  }

  /// Fire-and-forget: create in-app notifications for assigned users
  Future<void> _notifyAssignedUsers({
    required List<String> assignedUserIds,
    required String taskTitle,
    required String taskId,
    required String projectId,
    required String workspaceId,
    String? currentUserId,
  }) async {
    try {
      final notificationService = SupabaseNotificationService();
      final deepLink = projectId.isNotEmpty
          ? '/projects/$projectId?tab=tasks&taskId=$taskId'
          : '/notifications';
      for (final userId in assignedUserIds) {
        if (userId == currentUserId) continue;
        notificationService.createNotification(
          userId: userId,
          workspaceId: workspaceId,
          type: 'task_assignment',
          title: 'You were assigned to "$taskTitle"',
          metadata: {
            'target_type': 'task',
            'task_id': taskId,
            'project_id': projectId,
            'tab': 'tasks',
            'deeplink_path': deepLink,
          },
        );
      }
    } catch (e) {
      AppLogger.error('Error creating assignment notifications', error: e);
    }
  }

  /// Fire-and-forget: notify assigned users about task completion
  Future<void> _notifyTaskCompletion({
    required List<String> assignedUserIds,
    required String taskTitle,
    required String taskId,
    required String projectId,
    required String workspaceId,
    String? currentUserId,
  }) async {
    try {
      final notificationService = SupabaseNotificationService();
      final deepLink = projectId.isNotEmpty
          ? '/projects/$projectId?tab=tasks&taskId=$taskId'
          : '/notifications';
      for (final userId in assignedUserIds) {
        if (userId == currentUserId) continue;
        notificationService.createNotification(
          userId: userId,
          workspaceId: workspaceId,
          type: 'task_completion',
          title: '"$taskTitle" was marked complete',
          metadata: {
            'target_type': 'task',
            'task_id': taskId,
            'project_id': projectId,
            'tab': 'tasks',
            'deeplink_path': deepLink,
          },
        );
      }
    } catch (e) {
      AppLogger.error('Error creating completion notifications', error: e);
    }
  }

  /// Create the next occurrence of a recurring task
  Future<void> _createNextOccurrence(Task task) async {
    final rule = task.recurrenceRule!;
    final frequency = rule['frequency'] as String?;
    if (frequency == null) return;

    // Check stop conditions
    if (rule['endDate'] != null) {
      final endDate = DateTime.parse(rule['endDate'] as String);
      if (DateTime.now().isAfter(endDate)) return;
    }
    if (rule['maxOccurrences'] != null) {
      final max = rule['maxOccurrences'] as int;
      final count = rule['occurrenceCount'] as int? ?? 0;
      if (count >= max) return;
    }

    // Calculate date shift
    DateTime shiftDate(DateTime date) {
      switch (frequency) {
        case 'daily':
          return date.add(const Duration(days: 1));
        case 'weekly':
          return date.add(const Duration(days: 7));
        case 'biweekly':
          return date.add(const Duration(days: 14));
        case 'monthly':
          return DateTime(
            date.year,
            date.month + 1,
            date.day,
            date.hour,
            date.minute,
            date.second,
          );
        default:
          return date.add(const Duration(days: 7));
      }
    }

    final newStartDate = task.startDate != null
        ? shiftDate(task.startDate!)
        : null;
    final newDueDate = task.dueDate != null ? shiftDate(task.dueDate!) : null;
    final parentId = task.recurringParentId ?? task.id;

    // Create next occurrence
    await createTask(
      workspaceId: task.workspaceId,
      projectId: task.projectId,
      title: task.title,
      description: task.description,
      dueDate: newDueDate,
      startDate: newStartDate,
      estimatedDuration: task.estimatedDuration,
      assignedToIds: task.assignedToIds,
      requiredAssetIds: task.requiredAssetIds,
      predecessorIds: task.predecessorIds,
      requiredSkillIds: task.requiredSkillIds,
      parentId: task.parentId,
      taskType: task.taskType,
      status: 'not_started',
      priority: task.priority,
      propertyIds: task.propertyIds,
      areaIds: task.areaIds,
      isRecurring: true,
      recurrenceRule: Map<String, dynamic>.from(rule),
      recurringParentId: parentId,
      occurrenceIndex: task.occurrenceIndex + 1,
    );

    // Increment occurrenceCount in the parent's recurrence rule
    final parentTask = await getTask(parentId);
    if (parentTask != null && parentTask.recurrenceRule != null) {
      final updatedRule = Map<String, dynamic>.from(parentTask.recurrenceRule!);
      updatedRule['occurrenceCount'] =
          (updatedRule['occurrenceCount'] as int? ?? 0) + 1;
      await _supabase
          .from('tasks')
          .update({
            'recurrence_rule': updatedRule,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', parentId);
    }
  }

  /// Delete a task
  Future<void> deleteTask(String taskId) async {
    try {
      await _supabase.from('tasks').delete().eq('id', taskId);
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'deleting task'),
        cause: e,
      );
    }
  }

  /// Get task count for a project
  Future<int> getTaskCount(String projectId, {String? workspaceId}) async {
    try {
      var query = _supabase.from('tasks').select().eq('project_id', projectId);

      if (workspaceId != null) {
        query = query.eq('workspace_id', workspaceId);
      }

      final result = await query.count();
      return result.count;
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'getting task count'),
        cause: e,
      );
    }
  }

  /// Get incomplete task count for a project
  Future<int> getIncompleteTaskCount(
    String projectId, {
    String? workspaceId,
  }) async {
    try {
      var query = _supabase
          .from('tasks')
          .select()
          .eq('project_id', projectId)
          .eq('is_complete', false);

      if (workspaceId != null) {
        query = query.eq('workspace_id', workspaceId);
      }

      final result = await query.count();
      return result.count;
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'getting incomplete task count'),
        cause: e,
      );
    }
  }

  /// Get tasks within a due date range
  Stream<List<Task>> getTasksInDueDateRange(
    String projectId,
    DateTime rangeStart,
    DateTime rangeEnd, {
    String? workspaceId,
  }) {
    return _supabase
        .from('tasks')
        .stream(primaryKey: ['id'])
        .eq('project_id', projectId)
        .map((data) {
          final filtered = data
              .where((row) {
                if (workspaceId != null && row['workspace_id'] != workspaceId)
                  return false;
                final dueDate = row['due_date'] != null
                    ? DateTime.parse(row['due_date'])
                    : null;
                if (dueDate == null) return false;
                return dueDate.isAfter(
                      rangeStart.subtract(const Duration(days: 1)),
                    ) &&
                    dueDate.isBefore(rangeEnd.add(const Duration(days: 1)));
              })
              .map((row) => Task.fromJson(_toFirestoreFormat(row), row['id']))
              .toList();
          filtered.sort(
            (a, b) => (a.dueDate ?? DateTime.now()).compareTo(
              b.dueDate ?? DateTime.now(),
            ),
          );
          return filtered;
        });
  }

  /// Get tasks within a start date range
  Stream<List<Task>> getTasksInStartDateRange(
    String projectId,
    DateTime rangeStart,
    DateTime rangeEnd, {
    String? workspaceId,
  }) {
    return _supabase
        .from('tasks')
        .stream(primaryKey: ['id'])
        .eq('project_id', projectId)
        .map((data) {
          final filtered = data
              .where((row) {
                if (workspaceId != null && row['workspace_id'] != workspaceId)
                  return false;
                final startDate = row['start_date'] != null
                    ? DateTime.parse(row['start_date'])
                    : null;
                if (startDate == null) return false;
                return startDate.isAfter(
                      rangeStart.subtract(const Duration(days: 1)),
                    ) &&
                    startDate.isBefore(rangeEnd.add(const Duration(days: 1)));
              })
              .map((row) => Task.fromJson(_toFirestoreFormat(row), row['id']))
              .toList();
          filtered.sort(
            (a, b) => (a.startDate ?? DateTime.now()).compareTo(
              b.startDate ?? DateTime.now(),
            ),
          );
          return filtered;
        });
  }

  /// Get tasks for a specific month
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
    String? parentId,
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
      await _supabase
          .from('tasks')
          .update({
            'is_expanded': isExpanded,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', taskId);
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
      await _supabase
          .from('tasks')
          .update({
            'priority': newPriority,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', taskId);
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
      await _supabase
          .from('tasks')
          .update({
            'task_type': newType.toString().split('.').last,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', taskId);
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
  Future<Task> cloneTask({
    required Task task,
    required List<Task> allTasks,
    bool cloneChildren = true,
  }) async {
    try {
      final now = DateTime.now();

      // Filter out empty strings from UUID arrays
      final filteredAssignedToIds = task.assignedToIds
          .where((id) => id.isNotEmpty)
          .toList();
      final filteredRequiredAssetIds = task.requiredAssetIds
          .where((id) => id.isNotEmpty)
          .toList();
      final filteredRequiredSkillIds = task.requiredSkillIds
          .where((id) => id.isNotEmpty)
          .toList();

      final clonedTaskData = {
        'workspace_id': task.workspaceId,
        'project_id': task.projectId,
        'title': '${task.title} (Copy)',
        'description': task.description,
        'due_date': task.dueDate?.toIso8601String(),
        'start_date': task.startDate?.toIso8601String(),
        'estimated_duration': task.estimatedDuration,
        'is_complete': false,
        'assigned_to_ids': filteredAssignedToIds,
        'required_asset_ids': filteredRequiredAssetIds,
        'predecessor_ids': <String>[],
        'required_skill_ids': filteredRequiredSkillIds,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'parent_id': (task.parentId != null && task.parentId!.isNotEmpty)
            ? task.parentId
            : null,
        'task_type': task.taskType.toString().split('.').last,
        'status': 'not_started',
        'priority': task.priority,
        'group_color': task.groupColor.value,
        'is_expanded': true,
        'progress': 0,
        'checklist_items': [],
        'property_ids': task.propertyIds,
        'area_ids': task.areaIds,
      };

      final response = await _supabase
          .from('tasks')
          .insert(clonedTaskData)
          .select()
          .single();

      final clonedTask = Task.fromJson(
        _toFirestoreFormat(response),
        response['id'],
      );

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

    final children = allTasks
        .where((t) => t.parentId == originalParentId)
        .toList();
    children.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    for (final child in children) {
      // Filter out empty strings from UUID arrays
      final filteredAssignedToIds = child.assignedToIds
          .where((id) => id.isNotEmpty)
          .toList();
      final filteredRequiredAssetIds = child.requiredAssetIds
          .where((id) => id.isNotEmpty)
          .toList();
      final filteredRequiredSkillIds = child.requiredSkillIds
          .where((id) => id.isNotEmpty)
          .toList();

      final clonedChildData = {
        'workspace_id': child.workspaceId,
        'project_id': child.projectId,
        'title': child.title,
        'description': child.description,
        'due_date': child.dueDate?.toIso8601String(),
        'start_date': child.startDate?.toIso8601String(),
        'estimated_duration': child.estimatedDuration,
        'is_complete': false,
        'assigned_to_ids': filteredAssignedToIds,
        'required_asset_ids': filteredRequiredAssetIds,
        'predecessor_ids': <String>[],
        'required_skill_ids': filteredRequiredSkillIds,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'parent_id': newParentId,
        'task_type': child.taskType.toString().split('.').last,
        'status': 'not_started',
        'priority': child.priority,
        'group_color': child.groupColor.value,
        'is_expanded': true,
        'progress': 0,
        'checklist_items': [],
        'property_ids': child.propertyIds,
        'area_ids': child.areaIds,
      };

      final response = await _supabase
          .from('tasks')
          .insert(clonedChildData)
          .select()
          .single();

      if (child.taskType == TaskType.summary) {
        await _cloneChildrenRecursively(
          originalParentId: child.id,
          newParentId: response['id'],
          allTasks: allTasks,
        );
      }
    }
  }

  /// Clone multiple selected tasks while preserving hierarchy
  Future<List<Task>> cloneMultipleTasks({
    required List<Task> selectedTasks,
    required List<Task> allTasks,
  }) async {
    if (selectedTasks.isEmpty) return [];

    final selectedIds = selectedTasks.map((t) => t.id).toSet();
    final clonedTasks = <Task>[];

    // Find "root" tasks in the selection
    final rootsInSelection = selectedTasks.where((task) {
      if (task.parentId == null) return true;
      return !selectedIds.contains(task.parentId);
    }).toList();

    rootsInSelection.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    for (final rootTask in rootsInSelection) {
      final clonedRoot = await _cloneTaskWithSelectedDescendants(
        task: rootTask,
        newParentId: rootTask.parentId,
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

    // Filter out empty strings from UUID arrays
    final filteredAssignedToIds = task.assignedToIds
        .where((id) => id.isNotEmpty)
        .toList();
    final filteredRequiredAssetIds = task.requiredAssetIds
        .where((id) => id.isNotEmpty)
        .toList();
    final filteredRequiredSkillIds = task.requiredSkillIds
        .where((id) => id.isNotEmpty)
        .toList();

    final clonedTaskData = {
      'workspace_id': task.workspaceId,
      'project_id': task.projectId,
      'title': isRoot ? '${task.title} (Copy)' : task.title,
      'description': task.description,
      'due_date': task.dueDate?.toIso8601String(),
      'start_date': task.startDate?.toIso8601String(),
      'estimated_duration': task.estimatedDuration,
      'is_complete': false,
      'assigned_to_ids': filteredAssignedToIds,
      'required_asset_ids': filteredRequiredAssetIds,
      'predecessor_ids': <String>[],
      'required_skill_ids': filteredRequiredSkillIds,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'parent_id': (newParentId != null && newParentId.isNotEmpty)
          ? newParentId
          : null,
      'task_type': task.taskType.toString().split('.').last,
      'status': 'not_started',
      'priority': task.priority,
      'group_color': task.groupColor.value,
      'is_expanded': true,
      'progress': 0,
      'checklist_items': [],
      'property_ids': task.propertyIds,
      'area_ids': task.areaIds,
    };

    final response = await _supabase
        .from('tasks')
        .insert(clonedTaskData)
        .select()
        .single();

    final clonedTask = Task.fromJson(
      _toFirestoreFormat(response),
      response['id'],
    );

    // Find direct children that are in the selection
    final selectedChildren = allTasks
        .where((t) => t.parentId == task.id && selectedIds.contains(t.id))
        .toList();
    selectedChildren.sort((a, b) => a.createdAt.compareTo(b.createdAt));

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
  Future<Map<String, bool>> getUserTaskExpansionPreferences(
    String userId,
    String projectId,
  ) async {
    try {
      final response = await _supabase
          .from('user_task_expansion_prefs')
          .select()
          .eq('user_id', userId)
          .eq('project_id', projectId)
          .maybeSingle();

      if (response == null) {
        return {};
      }

      final expansionStates =
          response['expansion_states'] as Map<String, dynamic>?;
      if (expansionStates == null) {
        return {};
      }

      final Map<String, bool> preferences = {};
      expansionStates.forEach((key, value) {
        if (value is bool) {
          preferences[key] = value;
        }
      });
      return preferences;
    } catch (e) {
      debugPrint('Error getting user task expansion preferences: $e');
      return {};
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
      // Get existing preferences
      final existing = await _supabase
          .from('user_task_expansion_prefs')
          .select()
          .eq('user_id', userId)
          .eq('project_id', projectId)
          .maybeSingle();

      final Map<String, dynamic> expansionStates = existing != null
          ? Map<String, dynamic>.from(existing['expansion_states'] ?? {})
          : {};

      expansionStates[taskId] = isExpanded;

      await _supabase.from('user_task_expansion_prefs').upsert({
        'user_id': userId,
        'project_id': projectId,
        'expansion_states': expansionStates,
        'updated_at': DateTime.now().toIso8601String(),
      });
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

  /// Update multiple task expansion states at once for a specific user
  Future<void> updateUserTaskExpansionBatch(
    String userId,
    String projectId,
    Map<String, bool> expansionStates,
  ) async {
    try {
      await _supabase.from('user_task_expansion_prefs').upsert({
        'user_id': userId,
        'project_id': projectId,
        'expansion_states': expansionStates,
        'updated_at': DateTime.now().toIso8601String(),
      });
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

      // Get current checklist items
      final task = await _supabase
          .from('tasks')
          .select('checklist_items')
          .eq('id', taskId)
          .single();

      final currentItems =
          (task['checklist_items'] as List?)
              ?.map(
                (item) =>
                    ChecklistItem.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList() ??
          [];
      currentItems.add(item);

      // Calculate progress from checklist completion
      final progress = _calculateChecklistProgress(currentItems);

      await _supabase
          .from('tasks')
          .update({
            'checklist_items': currentItems
                .map((item) => _checklistItemToJson(item))
                .toList(),
            'progress': progress,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', taskId);

      return item;
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'adding checklist item'),
        cause: e,
      );
    }
  }

  /// Update an existing checklist item
  Future<void> updateChecklistItem(
    String taskId,
    String itemId, {
    String? title,
    bool? isComplete,
  }) async {
    try {
      final task = await _supabase
          .from('tasks')
          .select('checklist_items')
          .eq('id', taskId)
          .single();

      final items =
          (task['checklist_items'] as List?)
              ?.map(
                (item) =>
                    ChecklistItem.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList() ??
          [];

      final itemIndex = items.indexWhere((item) => item.id == itemId);
      if (itemIndex == -1) {
        throw Exception('Checklist item not found');
      }

      items[itemIndex] = items[itemIndex].copyWith(
        title: title,
        isComplete: isComplete,
      );

      // Calculate progress from checklist completion
      final progress = _calculateChecklistProgress(items);

      await _supabase
          .from('tasks')
          .update({
            'checklist_items': items
                .map((item) => _checklistItemToJson(item))
                .toList(),
            'progress': progress,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', taskId);
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
      final task = await _supabase
          .from('tasks')
          .select('checklist_items')
          .eq('id', taskId)
          .single();

      final items =
          (task['checklist_items'] as List?)
              ?.map(
                (item) =>
                    ChecklistItem.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList() ??
          [];

      final itemIndex = items.indexWhere((item) => item.id == itemId);
      if (itemIndex == -1) {
        throw Exception('Checklist item not found');
      }

      items[itemIndex] = items[itemIndex].copyWith(
        isComplete: !items[itemIndex].isComplete,
      );

      // Calculate progress from checklist completion
      final progress = _calculateChecklistProgress(items);

      await _supabase
          .from('tasks')
          .update({
            'checklist_items': items
                .map((item) => _checklistItemToJson(item))
                .toList(),
            'progress': progress,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', taskId);
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
      final task = await _supabase
          .from('tasks')
          .select('checklist_items')
          .eq('id', taskId)
          .single();

      final items =
          (task['checklist_items'] as List?)
              ?.map(
                (item) =>
                    ChecklistItem.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList() ??
          [];

      items.removeWhere((item) => item.id == itemId);

      // Calculate progress from checklist completion
      final progress = _calculateChecklistProgress(items);

      await _supabase
          .from('tasks')
          .update({
            'checklist_items': items
                .map((item) => _checklistItemToJson(item))
                .toList(),
            'progress': progress,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', taskId);
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

      await _supabase
          .from('tasks')
          .update({
            'checklist_items': reorderedItems
                .map((item) => _checklistItemToJson(item))
                .toList(),
            'progress': progress,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', taskId);
    } catch (e) {
      throw UserFacingException(
        UserFacingError.operationMessage(e, 'reordering checklist items'),
        cause: e,
      );
    }
  }

  /// Convert checklist item to JSON without Timestamp (for Supabase)
  Map<String, dynamic> _checklistItemToJson(ChecklistItem item) {
    return {
      'id': item.id,
      'title': item.title,
      'isComplete': item.isComplete,
      'createdAt': item.createdAt.toIso8601String(),
    };
  }

  /// Convert PostgreSQL snake_case to Firestore camelCase for model compatibility
  Map<String, dynamic> _toFirestoreFormat(Map<String, dynamic> data) {
    // Parse checklist items
    List<Map<String, dynamic>> checklistItems = [];
    if (data['checklist_items'] != null) {
      checklistItems = (data['checklist_items'] as List).map((item) {
        final itemMap = Map<String, dynamic>.from(item);
        // Convert createdAt string to a format the model can parse
        return itemMap;
      }).toList();
    }

    return {
      'workspaceId': data['workspace_id'],
      'projectId': data['project_id'],
      'title': data['title'],
      'description': data['description'],
      'dueDate': data['due_date'] != null
          ? _parseTimestamp(data['due_date'])
          : null,
      'startDate': data['start_date'] != null
          ? _parseTimestamp(data['start_date'])
          : null,
      'endDate': data['end_date'] != null
          ? _parseTimestamp(data['end_date'])
          : null,
      'estimatedDuration': data['estimated_duration'],
      'isComplete': data['is_complete'] ?? false,
      'assignedTo': data['assigned_to'],
      'assignedToIds': data['assigned_to_ids'] ?? [],
      'requiredAssetIds': data['required_asset_ids'] ?? [],
      'predecessorIds': data['predecessor_ids'] ?? [],
      'requiredSkillIds': data['required_skill_ids'] ?? [],
      'propertyIds': data['property_ids'] ?? [],
      'areaIds': data['area_ids'] ?? [],
      'createdAt': _parseTimestamp(data['created_at']),
      'updatedAt': _parseTimestamp(data['updated_at']),
      'progress': data['progress'] ?? 0,
      'status': data['status'] ?? 'not_started',
      'priority': data['priority'] ?? 'medium',
      'parentId': data['parent_id'],
      'taskType': data['task_type'] ?? 'standard',
      'groupColor': data['group_color'] ?? 0xFF2196F3,
      'isExpanded': data['is_expanded'] ?? true,
      'checklistItems': checklistItems,
      'sortOrder': (data['sort_order'] as num?)?.toDouble() ?? 0.0,
      'isRecurring': data['is_recurring'] ?? false,
      'recurrenceRule': data['recurrence_rule'],
      'recurringParentId': data['recurring_parent_id'],
      'occurrenceIndex': data['occurrence_index'] ?? 0,
    };
  }

  /// Parse various timestamp formats to a Firestore-like Timestamp mock
  dynamic _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      return _FakeTimestamp(DateTime.parse(value));
    }
    return value;
  }
}

/// Fake Timestamp class to maintain compatibility with Task.fromJson
class _FakeTimestamp {
  final DateTime _dateTime;
  _FakeTimestamp(this._dateTime);
  DateTime toDate() => _dateTime;
}
