/// Service for selections & allowances. Internal CRUD + summary rollups.
/// Portal-side reads/writes live in [SupabaseClientPortalService].
library;

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/selection.dart';

class SupabaseSelectionService {
  SupabaseSelectionService();

  SupabaseClient get _supabase => Supabase.instance.client;

  // ── Reads ────────────────────────────────────────────────────────────────

  /// Realtime stream of all selections for a project, with options hydrated.
  /// Re-emits whenever either the selections rows OR any of their options
  /// change, so option-only edits push live too.
  Stream<List<Selection>> watchByProject(String projectId) {
    final selStream = _supabase
        .from('selections')
        .stream(primaryKey: ['id']).eq('project_id', projectId);

    // Options stream is unfiltered per-project (Supabase realtime can't filter
    // by joined column), but is then narrowed to this project's selection IDs.
    final optStream =
        _supabase.from('selection_options').stream(primaryKey: ['id']);

    List<Map<String, dynamic>>? lastSels;
    List<Map<String, dynamic>>? lastOpts;

    final controller = StreamController<List<Selection>>();

    List<Selection> build() {
      final sels = lastSels ?? const [];
      final opts = lastOpts ?? const [];
      if (sels.isEmpty) return const [];
      final selIds = sels.map((r) => r['id'] as String).toSet();
      final byParent = <String, List<SelectionOption>>{};
      for (final r in opts) {
        final selId = r['selection_id'] as String?;
        if (selId == null || !selIds.contains(selId)) continue;
        final opt = SelectionOption.fromRow(Map<String, dynamic>.from(r));
        byParent.putIfAbsent(selId, () => []).add(opt);
      }
      for (final list in byParent.values) {
        list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      }
      final out = sels
          .map((r) => Selection.fromRow(
                Map<String, dynamic>.from(r),
                options: byParent[r['id']] ?? const [],
              ))
          .toList();
      out.sort((a, b) {
        final c = a.status.index.compareTo(b.status.index);
        if (c != 0) return c;
        return a.createdAt.compareTo(b.createdAt);
      });
      return out;
    }

    final subSel = selStream.listen((rows) {
      lastSels = rows;
      controller.add(build());
    }, onError: controller.addError);
    final subOpt = optStream.listen((rows) {
      lastOpts = rows;
      if (lastSels != null) controller.add(build());
    }, onError: controller.addError);

    controller.onCancel = () async {
      await subSel.cancel();
      await subOpt.cancel();
    };
    return controller.stream;
  }

  Future<List<Selection>> listByProject(String projectId) async {
    final rows = await _supabase
        .from('selections')
        .select()
        .eq('project_id', projectId)
        .order('sort_order')
        .order('created_at');
    final selectionIds =
        (rows as List).map((r) => r['id'] as String).toList(growable: false);

    final optsByParent = <String, List<SelectionOption>>{};
    if (selectionIds.isNotEmpty) {
      final optRows = await _supabase
          .from('selection_options')
          .select()
          .inFilter('selection_id', selectionIds)
          .order('sort_order');
      for (final row in (optRows as List)) {
        final opt = SelectionOption.fromRow(Map<String, dynamic>.from(row));
        optsByParent.putIfAbsent(opt.selectionId, () => []).add(opt);
      }
    }

    return rows
        .map((r) => Selection.fromRow(
              Map<String, dynamic>.from(r),
              options: optsByParent[r['id']] ?? const [],
            ))
        .toList();
  }

  Future<SelectionSummary> summaryForProject(String projectId) async {
    final list = await listByProject(projectId);
    return summarise(list);
  }

  /// Pure aggregation (also used by widgets that already have the list).
  SelectionSummary summarise(List<Selection> list) {
    final active =
        list.where((s) => s.status != SelectionStatus.cancelled).toList();
    var allow = 0.0, approvedAllow = 0.0, sel = 0.0, pending = 0.0;
    var awaiting = 0, approved = 0, declined = 0;
    for (final s in active) {
      allow += s.allowanceAmount;
      switch (s.status) {
        case SelectionStatus.approved:
          sel += s.selectedAmount;
          approvedAllow += s.allowanceAmount;
          approved++;
          break;
        case SelectionStatus.awaitingClient:
          pending += s.allowanceAmount;
          awaiting++;
          break;
        case SelectionStatus.declined:
          declined++;
          break;
        case SelectionStatus.pending:
          pending += s.allowanceAmount;
          break;
        case SelectionStatus.cancelled:
          break;
      }
    }
    return SelectionSummary(
      totalAllowance: allow,
      approvedAllowance: approvedAllow,
      totalSelected: sel,
      pendingAllowance: pending,
      countTotal: active.length,
      countAwaitingClient: awaiting,
      countApproved: approved,
      countDeclined: declined,
    );
  }

  // ── Writes ───────────────────────────────────────────────────────────────

  Future<Selection> create({
    required String workspaceId,
    required String projectId,
    required String name,
    String? description,
    String? category,
    String? location,
    double allowanceAmount = 0,
    DateTime? dueDate,
    String? budgetItemId,
    String? internalNotes,
    bool excludeFromBudget = false,
    bool showAmountDifferences = true,
    bool allowMultipleSelections = false,
  }) async {
    final row = await _supabase
        .from('selections')
        .insert({
          'workspace_id': workspaceId,
          'project_id': projectId,
          'name': name,
          'description': description,
          'category': category,
          'location': location,
          'allowance_amount': allowanceAmount,
          'due_date': dueDate?.toIso8601String().split('T').first,
          'budget_item_id': budgetItemId,
          'internal_notes': internalNotes,
          'exclude_from_budget': excludeFromBudget,
          'show_amount_differences': showAmountDifferences,
          'allow_multiple_selections': allowMultipleSelections,
          'status': 'pending',
        })
        .select()
        .single();
    return Selection.fromRow(Map<String, dynamic>.from(row));
  }

  Future<void> update(String id, Map<String, dynamic> patch) async {
    await _supabase.from('selections').update(patch).eq('id', id);
  }

  Future<void> setStatus(String id, SelectionStatus status) =>
      update(id, {'status': status.wireValue});

  Future<void> sendToClient(String id) => setStatus(id, SelectionStatus.awaitingClient);

  Future<void> delete(String id) =>
      _supabase.from('selections').delete().eq('id', id);

  // Options
  Future<SelectionOption> addOption({
    required String selectionId,
    required String workspaceId,
    required String name,
    String? description,
    String? vendor,
    String? sku,
    double unitCost = 0,
    double quantity = 1,
    String? imageUrl,
    List<String> imageUrls = const [],
    String? externalUrl,
    int sortOrder = 0,
  }) async {
    final images = imageUrls.isNotEmpty
        ? imageUrls
        : (imageUrl != null && imageUrl.isNotEmpty ? [imageUrl] : <String>[]);
    final row = await _supabase
        .from('selection_options')
        .insert({
          'selection_id': selectionId,
          'workspace_id': workspaceId,
          'name': name,
          'description': description,
          'vendor': vendor,
          'sku': sku,
          'unit_cost': unitCost,
          'quantity': quantity,
          'image_url': images.isNotEmpty ? images.first : imageUrl,
          'image_urls': images,
          'external_url': externalUrl,
          'sort_order': sortOrder,
        })
        .select()
        .single();
    return SelectionOption.fromRow(Map<String, dynamic>.from(row));
  }

  // ── Selection-sheet templates (reusable; RLS = workspace member) ───────────
  Future<List<Map<String, dynamic>>> listTemplates(String workspaceId) async {
    final rows = await _supabase
        .from('selection_templates')
        .select()
        .eq('workspace_id', workspaceId)
        .order('name');
    return (rows as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  }

  Future<void> saveTemplate({
    required String workspaceId,
    required String name,
    required List<Map<String, dynamic>> payload,
  }) async {
    await _supabase.from('selection_templates').insert({
      'workspace_id': workspaceId,
      'name': name,
      'payload': payload,
    });
  }

  Future<void> deleteTemplate(String id) =>
      _supabase.from('selection_templates').delete().eq('id', id);

  // ── Signatures (builder read; RLS = workspace member) ──────────────────────
  Future<List<SelectionSignature>> listSignatures(String selectionId) async {
    final rows = await _supabase
        .from('selection_signatures')
        .select()
        .eq('selection_id', selectionId)
        .order('signed_at');
    return (rows as List)
        .map((r) => SelectionSignature.fromRow(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Message counts per selection for a project, for board badges. One query.
  Future<Map<String, int>> commentCountsByProject(String projectId) async {
    final rows = await _supabase
        .from('selection_comments')
        .select('selection_id, selections!inner(project_id)')
        .eq('selections.project_id', projectId);
    final counts = <String, int>{};
    for (final r in (rows as List)) {
      final sid = (r as Map)['selection_id']?.toString();
      if (sid != null) counts[sid] = (counts[sid] ?? 0) + 1;
    }
    return counts;
  }

  // ── Per-selection messaging (builder side; RLS = workspace member) ──────────
  Future<List<SelectionComment>> listComments(String selectionId) async {
    final rows = await _supabase
        .from('selection_comments')
        .select()
        .eq('selection_id', selectionId)
        .order('created_at');
    return (rows as List)
        .map((r) => SelectionComment.fromRow(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<void> addComment({
    required String selectionId,
    required String workspaceId,
    required String body,
    String? authorName,
  }) async {
    await _supabase.from('selection_comments').insert({
      'selection_id': selectionId,
      'workspace_id': workspaceId,
      'body': body.trim(),
      'author_name': authorName,
      'is_from_client': false,
    });
  }

  Future<void> updateOption(String id, Map<String, dynamic> patch) =>
      _supabase.from('selection_options').update(patch).eq('id', id);

  Future<void> deleteOption(String id) =>
      _supabase.from('selection_options').delete().eq('id', id);

  /// Internal "team picks for client" path. Routes through the atomic
  /// `approve_selection_and_apply_budget` RPC so the chosen cost is applied to
  /// the linked allowance budget line in the same transaction — never a bare
  /// UPDATE that could leave the selection approved but the budget untouched.
  Future<void> approveInternally({
    required String selectionId,
    required SelectionOption option,
    String? actorName,
  }) async {
    await _supabase.rpc('approve_selection_and_apply_budget', params: {
      'p_selection_id': selectionId,
      'p_option_id': option.id,
      'p_actor_name': actorName ?? 'Team',
    });
  }
}
