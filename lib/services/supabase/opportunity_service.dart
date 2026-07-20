import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/opportunity.dart';
import '../../models/opportunity_activity.dart';
import '../../utils/app_logger.dart';
import 'automation_service.dart';

class SupabaseOpportunityService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ---------------- Opportunities ----------------

  Future<List<Opportunity>> listOpportunities(String workspaceId,
      {bool activeOnly = true}) async {
    try {
      var q = _supabase
          .from('opportunities')
          .select()
          .eq('workspace_id', workspaceId);
      if (activeOnly) q = q.eq('is_active', true);
      final rows = await q.order('updated_at', ascending: false);
      return (rows as List).map((r) => Opportunity.fromMap(r)).toList();
    } catch (e) {
      AppLogger.error('listOpportunities failed', error: e);
      return [];
    }
  }

  Stream<List<Opportunity>> watchOpportunities(String workspaceId) {
    return _supabase
        .from('opportunities')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .order('updated_at', ascending: false)
        .map((rows) => rows
            .where((r) => r['is_active'] == true)
            .map((r) => Opportunity.fromMap(r))
            .toList());
  }

  Future<Opportunity?> getOpportunity(String id) async {
    final row = await _supabase
        .from('opportunities')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return Opportunity.fromMap(row);
  }

  Future<Opportunity> createOpportunity(Opportunity draft) async {
    final payload = draft.toInsertMap();
    payload['created_by'] = _supabase.auth.currentUser?.id;
    final row =
        await _supabase.from('opportunities').insert(payload).select().single();
    final created = Opportunity.fromMap(row);

    // Fire-and-forget: automation failures must never fail lead creation.
    unawaited(SupabaseAutomationService().processOpportunityCreated(
      workspaceId: created.workspaceId,
      opportunityId: created.id,
      opportunityName: created.name,
      customerId: created.customerId,
      actorUserId: _supabase.auth.currentUser?.id ?? 'system',
    ));

    return created;
  }

  Future<Opportunity> updateOpportunity(
      String id, Map<String, dynamic> patch) async {
    final row = await _supabase
        .from('opportunities')
        .update(patch)
        .eq('id', id)
        .select()
        .single();
    return Opportunity.fromMap(row);
  }

  Future<Opportunity> changeStage(String id, OpportunityStage stage,
      {String? lostReason}) async {
    final patch = <String, dynamic>{'stage': stage.dbValue};
    if (stage == OpportunityStage.lost && lostReason != null) {
      patch['lost_reason'] = lostReason;
    }
    return updateOpportunity(id, patch);
  }

  Future<void> archiveOpportunity(String id) async {
    await _supabase
        .from('opportunities')
        .update({'is_active': false}).eq('id', id);
  }

  /// Mark won and seed a Project atomically via SECURITY DEFINER RPC.
  /// Returns the created (or existing) project id.
  Future<String> markWonAndCreateProject(
    Opportunity opp, {
    String? projectName,
  }) async {
    final result = await _supabase.rpc(
      'opportunity_mark_won_create_project',
      params: {
        'p_opportunity_id': opp.id,
        if (projectName != null) 'p_project_name': projectName,
      },
    );
    return result.toString();
  }

  // ---------------- Activities ----------------

  Future<List<OpportunityActivity>> listActivities(String opportunityId) async {
    final rows = await _supabase
        .from('opportunity_activities')
        .select()
        .eq('opportunity_id', opportunityId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => OpportunityActivity.fromMap(r))
        .toList();
  }

  Future<OpportunityActivity> addActivity({
    required String opportunityId,
    required String workspaceId,
    required OpportunityActivityKind kind,
    String? subject,
    String? body,
    DateTime? dueAt,
  }) async {
    final payload = <String, dynamic>{
      'opportunity_id': opportunityId,
      'workspace_id': workspaceId,
      'kind': kind.dbValue,
      if (subject != null) 'subject': subject,
      if (body != null) 'body': body,
      if (dueAt != null) 'due_at': dueAt.toIso8601String(),
      'created_by': _supabase.auth.currentUser?.id,
    };
    final row = await _supabase
        .from('opportunity_activities')
        .insert(payload)
        .select()
        .single();
    return OpportunityActivity.fromMap(row);
  }

  Future<void> completeActivity(String id) async {
    await _supabase
        .from('opportunity_activities')
        .update({'completed_at': DateTime.now().toIso8601String()})
        .eq('id', id);
  }

  // ---------------- Forecast ----------------

  /// Returns rows: { owner_id, stage, opportunity_count, total_value, weighted_value }.
  Future<List<Map<String, dynamic>>> getForecast(String workspaceId) async {
    final rows = await _supabase
        .from('opportunity_forecast_v')
        .select()
        .eq('workspace_id', workspaceId);
    return (rows as List).cast<Map<String, dynamic>>();
  }
}
