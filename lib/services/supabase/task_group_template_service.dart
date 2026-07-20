import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../models/task_group_template.dart';
import '../../utils/app_logger.dart';

/// Supabase service for task-group templates.
///
/// A task-group template snapshots a subtree of tasks (a phase/group and its
/// descendants) and can re-instantiate them into any existing project,
/// preserving hierarchy, relative schedule, dependencies, checklists, and
/// (optionally) assignees.
class SupabaseTaskGroupTemplateService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final _uuid = const Uuid();

  /// Stream all task-group templates for a workspace.
  Stream<List<TaskGroupTemplate>> getTemplates(String workspaceId) {
    return _supabase
        .from('task_group_templates')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .order('updated_at', ascending: false)
        .map((data) =>
            data.map((row) => TaskGroupTemplate.fromRow(row)).toList());
  }

  /// Fetch a single task-group template.
  Future<TaskGroupTemplate?> getTemplate(String templateId) async {
    final row = await _supabase
        .from('task_group_templates')
        .select()
        .eq('id', templateId)
        .maybeSingle();
    if (row == null) return null;
    return TaskGroupTemplate.fromRow(row);
  }

  /// Snapshot [rootTaskId] and all of its descendants into a reusable template.
  ///
  /// - Hierarchy is preserved via temp ids; the root's own parent is dropped so
  ///   it imports at the chosen insertion point.
  /// - Scheduling is stored relative to the earliest start date in the set.
  /// - Dependencies are kept only when both endpoints are inside the set.
  /// - Assignees / checklists are included based on the flags.
  Future<TaskGroupTemplate> createTemplateFromGroup({
    required String rootTaskId,
    required String projectId,
    required String workspaceId,
    required String name,
    String? description,
    required String createdBy,
    bool includeAssignees = true,
    bool includeChecklists = true,
  }) async {
    try {
      final rows = await _supabase
          .from('tasks')
          .select()
          .eq('project_id', projectId)
          .order('sort_order', ascending: true);

      final byId = <String, Map<String, dynamic>>{
        for (final r in rows) r['id'] as String: r,
      };
      final childrenOf = <String, List<Map<String, dynamic>>>{};
      for (final r in rows) {
        final pid = r['parent_id'] as String?;
        if (pid != null) {
          childrenOf.putIfAbsent(pid, () => []).add(r);
        }
      }

      // Collect the root + descendants via BFS.
      final selected = <Map<String, dynamic>>[];
      final queue = <String>[rootTaskId];
      while (queue.isNotEmpty) {
        final id = queue.removeAt(0);
        final node = byId[id];
        if (node == null) continue;
        selected.add(node);
        for (final child in childrenOf[id] ?? const []) {
          queue.add(child['id'] as String);
        }
      }
      if (selected.isEmpty) {
        throw Exception('Source task not found');
      }

      final selectedIds = selected.map((t) => t['id'] as String).toSet();

      // Map real ids -> temp ids.
      final tempIdFor = <String, String>{
        for (final t in selected) t['id'] as String: _uuid.v4(),
      };

      // Base date = earliest start_date in the set (for relative scheduling).
      // Normalized to midnight so offsets are whole calendar days regardless of
      // each task's time-of-day.
      DateTime? base;
      for (final t in selected) {
        final raw = t['start_date'];
        if (raw == null) continue;
        final d = DateTime.tryParse(raw.toString());
        if (d != null && (base == null || d.isBefore(base))) base = d;
      }
      final DateTime? baseDay =
          base == null ? null : DateTime(base.year, base.month, base.day);

      final templateTasks = selected.map<TaskGroupTemplateTask>((t) {
        final id = t['id'] as String;
        final parentId = t['parent_id'] as String?;
        // Drop the parent link when it points outside the set (the root) so the
        // task attaches at the import point.
        final parentTempId =
            (parentId != null && selectedIds.contains(parentId) && id != rootTaskId)
                ? tempIdFor[parentId]
                : null;

        final preds = (t['predecessor_ids'] as List?)
                ?.map((e) => e.toString())
                .where((pid) => selectedIds.contains(pid))
                .map((pid) => tempIdFor[pid]!)
                .toList() ??
            const <String>[];

        final assignees = includeAssignees
            ? ((t['assigned_to_ids'] as List?)
                    ?.map((e) => e.toString())
                    .where((e) => e.isNotEmpty)
                    .toList() ??
                const <String>[])
            : const <String>[];

        final checklist = includeChecklists
            ? ((t['checklist_items'] as List?)
                    ?.map((e) => (Map<String, dynamic>.from(e)['title'] ?? '')
                        .toString())
                    .where((title) => title.isNotEmpty)
                    .toList() ??
                const <String>[])
            : const <String>[];

        int offsetDays = 0;
        final startRaw = t['start_date'];
        if (baseDay != null && startRaw != null) {
          final d = DateTime.tryParse(startRaw.toString());
          if (d != null) {
            final startDay = DateTime(d.year, d.month, d.day);
            offsetDays = startDay.difference(baseDay).inDays;
          }
          if (offsetDays < 0) offsetDays = 0;
        }

        return TaskGroupTemplateTask(
          tempId: tempIdFor[id]!,
          parentTempId: parentTempId,
          title: t['title'] as String? ?? '',
          description: t['description'] as String?,
          sortOrder: (t['sort_order'] as num?)?.toInt() ?? 0,
          taskType: t['task_type'] as String? ?? 'standard',
          priority: t['priority'] as String? ?? 'medium',
          groupColor: (t['group_color'] as num?)?.toInt(),
          estimatedDuration: (t['estimated_duration'] as num?)?.toDouble(),
          startOffsetDays: offsetDays,
          predecessorTempIds: preds,
          assignedToIds: assignees,
          checklistTitles: checklist,
        );
      }).toList();

      final now = DateTime.now();
      final templateId = _uuid.v4();

      await _supabase.from('task_group_templates').insert({
        'id': templateId,
        'workspace_id': workspaceId,
        'name': name,
        'description': description,
        'tasks': templateTasks.map((t) => t.toJson()).toList(),
        'created_by': createdBy,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      AppLogger.info('Task group template created', metadata: {
        'templateId': templateId,
        'name': name,
        'taskCount': templateTasks.length,
      });

      return TaskGroupTemplate(
        id: templateId,
        workspaceId: workspaceId,
        name: name,
        description: description,
        tasks: templateTasks,
        createdBy: createdBy,
        createdAt: now,
        updatedAt: now,
      );
    } catch (e) {
      AppLogger.error('Failed to create task group template', error: e);
      throw Exception('Error creating task group template: $e');
    }
  }

  /// Instantiate a template's tasks into [projectId].
  ///
  /// New tasks are appended after any existing tasks. When [parentId] is given,
  /// the template's root tasks attach beneath that group; otherwise they land at
  /// the project root. Scheduling is anchored at [baseDate] (defaults to today).
  Future<int> applyTemplateToProject({
    required String templateId,
    required String projectId,
    required String workspaceId,
    String? parentId,
    DateTime? baseDate,
  }) async {
    try {
      final template = await getTemplate(templateId);
      if (template == null) throw Exception('Template not found');
      if (template.tasks.isEmpty) return 0;

      final now = DateTime.now();
      final base = baseDate ?? DateTime(now.year, now.month, now.day);

      // Append after the current max sort order.
      final existing = await _supabase
          .from('tasks')
          .select('sort_order')
          .eq('project_id', projectId)
          .order('sort_order', ascending: false)
          .limit(1);
      double sortCursor = existing.isNotEmpty
          ? ((existing.first['sort_order'] as num?)?.toDouble() ?? 0.0) + 1.0
          : 0.0;

      // Map temp ids -> new real ids.
      final newIdFor = <String, String>{
        for (final t in template.tasks) t.tempId: _uuid.v4(),
      };

      // Preserve template ordering when assigning sort orders.
      final ordered = [...template.tasks]
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

      final rows = <Map<String, dynamic>>[];
      for (final t in ordered) {
        final start = base.add(Duration(days: t.startOffsetDays));
        final durationHours = t.estimatedDuration ?? 8.0;
        // Mirror Task.calculateDueDate (8 work-hours = 1 calendar day). Floor at
        // 1h so the bar is never zero-width, but don't force short tasks to a
        // full day (keeps due_date consistent with the stored duration).
        final spanHours = ((durationHours / 8.0) * 24).round();
        final due = start.add(Duration(hours: spanHours < 1 ? 1 : spanHours));

        final parentRealId = t.parentTempId != null
            ? newIdFor[t.parentTempId]
            : (parentId != null && parentId.isNotEmpty ? parentId : null);

        final checklistItems = t.checklistTitles
            .map((title) => {
                  'id': _uuid.v4(),
                  'title': title,
                  'isComplete': false,
                  'createdAt': now.toIso8601String(),
                })
            .toList();

        rows.add({
          'id': newIdFor[t.tempId],
          'workspace_id': workspaceId,
          'project_id': projectId,
          'parent_id': parentRealId,
          'title': t.title,
          'description': t.description,
          'task_type': t.taskType,
          'status': 'not_started',
          'priority': t.priority,
          'progress': 0,
          'is_complete': false,
          'is_expanded': true,
          'group_color': t.groupColor ?? 0xFF2196F3,
          'start_date': start.toIso8601String(),
          'due_date': due.toIso8601String(),
          'estimated_duration': durationHours,
          // Only remap predecessors still present in the template; a dangling
          // temp id (e.g. from a future edit) is dropped rather than crashing
          // the whole import.
          'predecessor_ids': t.predecessorTempIds
              .where(newIdFor.containsKey)
              .map((tid) => newIdFor[tid]!)
              .toList(),
          'assigned_to_ids': t.assignedToIds,
          'checklist_items': checklistItems,
          'sort_order': sortCursor,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
        sortCursor += 1.0;
      }

      await _supabase.from('tasks').insert(rows);

      AppLogger.info('Task group template applied', metadata: {
        'templateId': templateId,
        'projectId': projectId,
        'taskCount': rows.length,
      });

      return rows.length;
    } catch (e) {
      AppLogger.error('Failed to apply task group template', error: e);
      throw Exception('Error importing task template: $e');
    }
  }

  /// Rename / re-describe a template.
  Future<void> updateTemplate({
    required String templateId,
    String? name,
    String? description,
  }) async {
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (name != null) updates['name'] = name;
    if (description != null) updates['description'] = description;
    await _supabase
        .from('task_group_templates')
        .update(updates)
        .eq('id', templateId);
  }

  /// Delete a template.
  Future<void> deleteTemplate(String templateId) async {
    await _supabase
        .from('task_group_templates')
        .delete()
        .eq('id', templateId);
  }
}
