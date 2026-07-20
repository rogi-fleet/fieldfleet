import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/gantt_task_extensions.dart';
import '../../models/schedule_baseline.dart';
import '../../models/task.dart';
import '../../utils/app_logger.dart';

/// Capture and retrieval of project [ScheduleBaseline]s.
///
/// A capture snapshots every task's *effective* dates (summary tasks store
/// their child-derived span) so the Gantt can render planned-vs-actual ghost
/// bars without re-deriving group spans against a historical task tree.
class ScheduleBaselineService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Snapshot the current schedule of [tasks] as a new baseline.
  /// Tasks with no effective dates are skipped (nothing to compare against).
  Future<ScheduleBaseline> captureBaseline({
    required String workspaceId,
    required String projectId,
    required List<Task> tasks,
    String name = 'Baseline',
    String? createdBy,
  }) async {
    final baselineRow = await _supabase
        .from('schedule_baselines')
        .insert({
          'workspace_id': workspaceId,
          'project_id': projectId,
          'name': name,
          if (createdBy != null) 'created_by': createdBy,
        })
        .select()
        .single();

    final baseline = ScheduleBaseline.fromSupabase(baselineRow);

    final snapshotRows = <Map<String, dynamic>>[];
    for (final task in tasks) {
      final start = task.getEffectiveStartDate(tasks);
      final end = task.getEffectiveEndDate(tasks);
      if (start == null && end == null) continue;
      snapshotRows.add({
        'baseline_id': baseline.id,
        'task_id': task.id,
        'start_date': start?.toUtc().toIso8601String(),
        'due_date': end?.toUtc().toIso8601String(),
        'estimated_duration': task.estimatedDuration,
      });
    }

    if (snapshotRows.isNotEmpty) {
      await _supabase.from('schedule_baseline_tasks').insert(snapshotRows);
    }

    AppLogger.info('Captured schedule baseline', metadata: {
      'baselineId': baseline.id,
      'projectId': projectId,
      'taskCount': snapshotRows.length,
    });

    return baseline;
  }

  /// The most recently captured baseline for a project, or null.
  Future<ScheduleBaseline?> getLatestBaseline(String projectId) async {
    final rows = await _supabase
        .from('schedule_baselines')
        .select()
        .eq('project_id', projectId)
        .order('created_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    return ScheduleBaseline.fromSupabase(rows.first);
  }

  /// Snapshot dates of a baseline, keyed by task id.
  Future<Map<String, BaselineTaskDates>> getBaselineTaskDates(
    String baselineId,
  ) async {
    final rows = await _supabase
        .from('schedule_baseline_tasks')
        .select()
        .eq('baseline_id', baselineId);
    return {
      for (final row in rows)
        row['task_id'] as String: BaselineTaskDates.fromSupabase(row),
    };
  }

  Future<void> deleteBaseline(String baselineId) async {
    await _supabase.from('schedule_baselines').delete().eq('id', baselineId);
  }
}
