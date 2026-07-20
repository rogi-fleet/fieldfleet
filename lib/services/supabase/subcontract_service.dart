/// Service for subcontracts: CRUD, items, signatures, history, summary,
/// realtime stream.
library;

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/subcontract.dart';
import '../service_locator.dart';

class SupabaseSubcontractService {
  SupabaseSubcontractService();
  SupabaseClient get _supabase => Supabase.instance.client;

  // ── Reads ──────────────────────────────────────────────────────────────────

  /// Workspace-wide stream of all subcontracts (parent rows only — no items
  /// or signatures hydrated). Used by the top-level list screen.
  Stream<List<Subcontract>> watchByWorkspace(String workspaceId) {
    return _supabase
        .from('subcontracts')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .map((rows) {
          final out = rows
              .map((r) => Subcontract.fromRow(Map<String, dynamic>.from(r)))
              .toList();
          out.sort((a, b) {
            final c = a.status.index.compareTo(b.status.index);
            if (c != 0) return c;
            return b.createdAt.compareTo(a.createdAt);
          });
          return out;
        });
  }

  Stream<List<Subcontract>> watchByProject(String projectId) {
    final scStream = _supabase
        .from('subcontracts')
        .stream(primaryKey: ['id']).eq('project_id', projectId);
    final itemStream =
        _supabase.from('subcontract_items').stream(primaryKey: ['id']);
    final sigStream =
        _supabase.from('subcontract_signatures').stream(primaryKey: ['id']);

    List<Map<String, dynamic>>? lastScs;
    List<Map<String, dynamic>>? lastItems;
    List<Map<String, dynamic>>? lastSigs;

    final controller = StreamController<List<Subcontract>>();

    List<Subcontract> build() {
      final scs = lastScs ?? const [];
      if (scs.isEmpty) return const [];
      final ids = scs.map((r) => r['id'] as String).toSet();
      final itemsByParent = <String, List<SubcontractItem>>{};
      for (final r in (lastItems ?? const [])) {
        final pid = r['subcontract_id'] as String?;
        if (pid == null || !ids.contains(pid)) continue;
        itemsByParent
            .putIfAbsent(pid, () => [])
            .add(SubcontractItem.fromRow(Map<String, dynamic>.from(r)));
      }
      for (final list in itemsByParent.values) {
        list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      }
      final sigsByParent = <String, List<SubcontractSignature>>{};
      for (final r in (lastSigs ?? const [])) {
        final pid = r['subcontract_id'] as String?;
        if (pid == null || !ids.contains(pid)) continue;
        sigsByParent
            .putIfAbsent(pid, () => [])
            .add(SubcontractSignature.fromRow(Map<String, dynamic>.from(r)));
      }
      for (final list in sigsByParent.values) {
        list.sort((a, b) => a.signedAt.compareTo(b.signedAt));
      }
      final out = scs
          .map((r) => Subcontract.fromRow(
                Map<String, dynamic>.from(r),
                items: itemsByParent[r['id']] ?? const [],
                signatures: sigsByParent[r['id']] ?? const [],
              ))
          .toList();
      out.sort((a, b) {
        final c = a.status.index.compareTo(b.status.index);
        if (c != 0) return c;
        return b.createdAt.compareTo(a.createdAt);
      });
      return out;
    }

    final s1 = scStream.listen((rows) {
      lastScs = rows;
      controller.add(build());
    }, onError: controller.addError);
    final s2 = itemStream.listen((rows) {
      lastItems = rows;
      if (lastScs != null) controller.add(build());
    }, onError: controller.addError);
    final s3 = sigStream.listen((rows) {
      lastSigs = rows;
      if (lastScs != null) controller.add(build());
    }, onError: controller.addError);

    controller.onCancel = () async {
      await s1.cancel();
      await s2.cancel();
      await s3.cancel();
    };
    return controller.stream;
  }

  Future<Subcontract?> get(String id) async {
    final row = await _supabase
        .from('subcontracts')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    final items = await _supabase
        .from('subcontract_items')
        .select()
        .eq('subcontract_id', id)
        .order('sort_order');
    final sigs = await _supabase
        .from('subcontract_signatures')
        .select()
        .eq('subcontract_id', id)
        .order('signed_at');
    return Subcontract.fromRow(
      Map<String, dynamic>.from(row),
      items: (items as List)
          .map((r) => SubcontractItem.fromRow(Map<String, dynamic>.from(r)))
          .toList(),
      signatures: (sigs as List)
          .map((r) =>
              SubcontractSignature.fromRow(Map<String, dynamic>.from(r)))
          .toList(),
    );
  }

  Future<List<SubcontractHistoryEvent>> historyFor(String subcontractId) async {
    final rows = await _supabase
        .from('subcontract_history')
        .select()
        .eq('subcontract_id', subcontractId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) =>
            SubcontractHistoryEvent.fromRow(Map<String, dynamic>.from(r)))
        .toList();
  }

  SubcontractSummary summarise(List<Subcontract> list) {
    var committed = 0.0, paid = 0.0;
    var nTotal = 0, nActive = 0, nDone = 0;
    for (final s in list) {
      nTotal++;
      committed += s.contractAmount;
      paid += s.paidToDate;
      switch (s.status) {
        case SubcontractStatus.completed:
          nDone++;
          break;
        case SubcontractStatus.active:
        case SubcontractStatus.signed:
        case SubcontractStatus.sent:
          nActive++;
          break;
        default:
          break;
      }
    }
    return SubcontractSummary(
      countTotal: nTotal, countActive: nActive, countCompleted: nDone,
      totalCommitted: committed, totalPaid: paid,
      totalRemaining: committed - paid,
    );
  }

  Future<SubcontractSummary> summaryForProject(String projectId) async {
    final rows = await _supabase
        .from('subcontracts')
        .select('status, contract_amount, paid_to_date')
        .eq('project_id', projectId);
    var committed = 0.0, paid = 0.0;
    var nTotal = 0, nActive = 0, nDone = 0;
    for (final r in (rows as List)) {
      final amt = (r['contract_amount'] as num?)?.toDouble() ?? 0;
      final paidAmt = (r['paid_to_date'] as num?)?.toDouble() ?? 0;
      final status = SubcontractStatus.fromWire(r['status'] as String?);
      nTotal++;
      committed += amt;
      paid += paidAmt;
      switch (status) {
        case SubcontractStatus.completed:
          nDone++;
          break;
        case SubcontractStatus.active:
        case SubcontractStatus.signed:
        case SubcontractStatus.sent:
          nActive++;
          break;
        default:
          break;
      }
    }
    return SubcontractSummary(
      countTotal: nTotal, countActive: nActive, countCompleted: nDone,
      totalCommitted: committed, totalPaid: paid,
      totalRemaining: committed - paid,
    );
  }

  // ── Writes ─────────────────────────────────────────────────────────────────

  Future<Subcontract> create({
    required String workspaceId,
    required String projectId,
    required String vendorId,
    required String number,
    required String title,
    String? description,
    String? scopeOfWork,
    double contractAmount = 0,
    double retainagePercent = 0,
    DateTime? startDate,
    DateTime? endDate,
    String? paymentTerms,
    bool insuranceRequired = true,
  }) async {
    final row = await _supabase
        .from('subcontracts')
        .insert({
          'workspace_id': workspaceId,
          'project_id': projectId,
          'vendor_id': vendorId,
          'number': number,
          'title': title,
          'description': description,
          'scope_of_work': scopeOfWork,
          'contract_amount': contractAmount,
          'retainage_percent': retainagePercent,
          'start_date': startDate?.toIso8601String().split('T').first,
          'end_date': endDate?.toIso8601String().split('T').first,
          'payment_terms': paymentTerms,
          'insurance_required': insuranceRequired,
          'status': 'draft',
        })
        .select()
        .single();
    final sc = Subcontract.fromRow(Map<String, dynamic>.from(row));
    await _addHistory(sc.id, workspaceId, 'created', message: 'Subcontract created');
    return sc;
  }

  Future<void> update(String id, Map<String, dynamic> patch) =>
      _supabase.from('subcontracts').update(patch).eq('id', id);

  Future<void> setStatus(String id, SubcontractStatus status) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final patch = <String, dynamic>{'status': status.wireValue};
    switch (status) {
      case SubcontractStatus.sent:       patch['sent_at']       = now; break;
      case SubcontractStatus.signed:     patch['signed_at']     = now; break;
      case SubcontractStatus.completed:  patch['completed_at']  = now; break;
      case SubcontractStatus.terminated: patch['terminated_at'] = now; break;
      default: break;
    }
    await update(id, patch);
  }

  Future<void> markInsuranceVerified(String id) =>
      update(id, {
        'insurance_verified': true,
        'insurance_verified_at': DateTime.now().toUtc().toIso8601String(),
      });

  /// Records a subcontract payment by bumping `subcontracts.paid_to_date`
  /// and writing a history entry, mirroring the work-order payment flow.
  Future<void> recordPayment(
    String id,
    double amount, {
    DateTime? paymentDate,
    String? method,
    String? reference,
    String? memo,
  }) async {
    final row = await _supabase
        .from('subcontracts')
        .select('paid_to_date, workspace_id')
        .eq('id', id)
        .single();
    final current = (row['paid_to_date'] as num?)?.toDouble() ?? 0;
    await update(id, {'paid_to_date': current + amount});
    await _addHistory(
      id,
      (row['workspace_id'] ?? '') as String,
      'payment_recorded',
      message:
          'Payment recorded: \$${amount.toStringAsFixed(2)}'
          '${method != null && method.isNotEmpty ? ' via $method' : ''}'
          '${reference != null && reference.isNotEmpty ? ' (ref $reference)' : ''}',
    );
  }

  Future<void> delete(String id) =>
      _supabase.from('subcontracts').delete().eq('id', id);

  // Items
  Future<SubcontractItem> addItem({
    required String subcontractId,
    required String workspaceId,
    required String description,
    double quantity = 1,
    String? unit,
    double unitCost = 0,
    String? budgetItemId,
    int sortOrder = 0,
  }) async {
    final row = await _supabase
        .from('subcontract_items')
        .insert({
          'subcontract_id': subcontractId,
          'workspace_id': workspaceId,
          'description': description,
          'quantity': quantity,
          'unit': unit,
          'unit_cost': unitCost,
          'budget_item_id': budgetItemId,
          'sort_order': sortOrder,
        })
        .select()
        .single();
    await _recomputeAmount(subcontractId);
    if (budgetItemId != null) {
      await _budgetRecompute(budgetItemId);
    }
    await _addHistory(subcontractId, workspaceId, 'item_added',
        message: 'Added item: $description');
    return SubcontractItem.fromRow(Map<String, dynamic>.from(row));
  }

  Future<void> updateItem(
      String id, String subcontractId, Map<String, dynamic> patch) async {
    final before = await _supabase
        .from('subcontract_items')
        .select('budget_item_id')
        .eq('id', id)
        .maybeSingle();
    final oldBudgetId = before?['budget_item_id'] as String?;
    await _supabase.from('subcontract_items').update(patch).eq('id', id);
    await _recomputeAmount(subcontractId);
    final newBudgetId = patch.containsKey('budget_item_id')
        ? patch['budget_item_id'] as String?
        : oldBudgetId;
    await _budgetRecompute(oldBudgetId);
    if (newBudgetId != oldBudgetId) {
      await _budgetRecompute(newBudgetId);
    }
  }

  Future<void> deleteItem(String id, String subcontractId) async {
    final before = await _supabase
        .from('subcontract_items')
        .select('budget_item_id')
        .eq('id', id)
        .maybeSingle();
    final oldBudgetId = before?['budget_item_id'] as String?;
    await _supabase.from('subcontract_items').delete().eq('id', id);
    await _recomputeAmount(subcontractId);
    await _budgetRecompute(oldBudgetId);
  }

  Future<void> _budgetRecompute(String? budgetItemId) async {
    if (budgetItemId == null) return;
    try {
      await ServiceLocator.budgetService
          .recomputeCommittedForBudgetItem(budgetItemId);
    } catch (_) {
      // Best-effort: budget rollup must not fail the PO write.
    }
  }

  Future<void> _recomputeAmount(String subcontractId) async {
    final rows = await _supabase
        .from('subcontract_items')
        .select('quantity, unit_cost')
        .eq('subcontract_id', subcontractId);
    var total = 0.0;
    for (final r in (rows as List)) {
      final q = (r['quantity'] as num?)?.toDouble() ?? 0;
      final c = (r['unit_cost'] as num?)?.toDouble() ?? 0;
      total += q * c;
    }
    await _supabase
        .from('subcontracts')
        .update({'contract_amount': total}).eq('id', subcontractId);
  }

  // Signatures
  Future<SubcontractSignature> addSignature({
    required String subcontractId,
    required String workspaceId,
    required String role,
    required String signerName,
    String? signerEmail,
    required String signatureUrl,
  }) async {
    final row = await _supabase
        .from('subcontract_signatures')
        .insert({
          'subcontract_id': subcontractId,
          'workspace_id': workspaceId,
          'role': role,
          'signer_name': signerName,
          'signer_email': signerEmail,
          'signature_url': signatureUrl,
        })
        .select()
        .single();
    await _addHistory(subcontractId, workspaceId, 'signed',
        message: '$role signed by $signerName', actorName: signerName);
    return SubcontractSignature.fromRow(Map<String, dynamic>.from(row));
  }

  Future<void> _addHistory(
    String subcontractId,
    String workspaceId,
    String eventType, {
    String? message,
    String? actorName,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _supabase.from('subcontract_history').insert({
        'subcontract_id': subcontractId,
        'workspace_id': workspaceId,
        'event_type': eventType,
        'message': message,
        'actor_id': _supabase.auth.currentUser?.id,
        'actor_name': actorName,
        'metadata': metadata ?? {},
      });
    } catch (_) {/* best-effort */}
  }

  Future<String> nextNumber(String projectId) async {
    final rows = await _supabase
        .from('subcontracts')
        .select('number')
        .eq('project_id', projectId);
    var maxN = 0;
    final re = RegExp(r'(\d+)');
    for (final r in (rows as List)) {
      final m = re.firstMatch((r['number'] ?? '') as String);
      if (m != null) {
        final n = int.tryParse(m.group(1)!) ?? 0;
        if (n > maxN) maxN = n;
      }
    }
    return 'SC-${(maxN + 1).toString().padLeft(3, '0')}';
  }
}

