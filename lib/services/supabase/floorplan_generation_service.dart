import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/app_logger.dart';

/// Thrown when [SupabaseFloorplanGenerationService.beginGeneration] is
/// called while another generation for the same plan is still
/// `'generating'`. The UI catches this and shows a non-fatal hint.
class FloorplanGenerationConflict implements Exception {
  final String message;
  const FloorplanGenerationConflict(this.message);
  @override
  String toString() => message;
}

/// Persistence layer for AI text-to-floorplan generation runs. Mirrors
/// the [SupabaseFloorplanSceneService] pattern: insert immediately on
/// dispatch, update status when done, expose a stream for the editor
/// UI to react to status flips.
class SupabaseFloorplanGenerationService {
  SupabaseFloorplanGenerationService({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const String _table = 'floorplan_generations';

  /// Insert a `status='generating'` row and return its id. The caller
  /// then dispatches the AI call via `unawaited()` and updates this row
  /// when the generation completes (or fails).
  ///
  /// Throws [FloorplanGenerationConflict] if there's already a
  /// 'generating' row for this plan — preventing duplicate LLM calls
  /// (which cost money and produce racy results). Also enforced by a
  /// partial unique index on the table as a backstop.
  Future<String> beginGeneration({
    required String planId,
    required String workspaceId,
    required String projectId,
    required String prompt,
    String? userId,
  }) async {
    // Snappy client-side check so the UI can show a clear message
    // instead of a Postgres unique-violation. The DB index is the
    // backstop in case two clients race past this check.
    final inflight = await _supabase
        .from(_table)
        .select('id')
        .eq('plan_id', planId)
        .eq('status', 'generating')
        .limit(1)
        .maybeSingle();
    if (inflight != null) {
      throw const FloorplanGenerationConflict(
        'A generation is already in progress for this plan. '
        'Wait for it to finish before starting another.',
      );
    }
    try {
      final response = await _supabase
          .from(_table)
          .insert({
            'plan_id': planId,
            'workspace_id': workspaceId,
            'project_id': projectId,
            if (userId != null) 'user_id': userId,
            'prompt': prompt,
            'status': 'generating',
          })
          .select('id')
          .single();
      return response['id'] as String;
    } on PostgrestException catch (e) {
      // 23505 = unique_violation — the partial index fired. Surface
      // as our typed error so the UI gets a clean message.
      if (e.code == '23505') {
        throw const FloorplanGenerationConflict(
          'A generation is already in progress for this plan.',
        );
      }
      rethrow;
    }
  }

  Future<void> markReady(
    String generationId, {
    required Map<String, dynamic> aiPlanJson,
  }) async {
    await _supabase
        .from(_table)
        .update({
          'status': 'ready',
          'ai_plan_json': aiPlanJson,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', generationId);
  }

  Future<void> markFailed(
    String generationId, {
    required String errorMessage,
  }) async {
    try {
      await _supabase
          .from(_table)
          .update({
            'status': 'failed',
            'error_message': errorMessage,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', generationId);
    } catch (e) {
      AppLogger.warning(
        'failed to mark floorplan generation as failed',
        metadata: {'generationId': generationId, 'error': e.toString()},
      );
    }
  }

  /// Stream the most recent generation row for [planId]. Editor UI
  /// uses this to know when the AI call is in flight, succeeds, or
  /// fails — and surfaces a "Generating…" overlay accordingly.
  Stream<({String status, String prompt, String? error})?> streamLatestForPlan(
    String planId,
  ) {
    return _supabase
        .from(_table)
        .stream(primaryKey: ['id'])
        .eq('plan_id', planId)
        .order('created_at')
        .map((rows) {
          if (rows.isEmpty) return null;
          final row = rows.last;
          return (
            status: row['status'] as String,
            prompt: row['prompt'] as String,
            error: row['error_message'] as String?,
          );
        });
  }
}
