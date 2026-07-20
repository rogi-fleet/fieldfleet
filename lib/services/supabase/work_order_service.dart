/// Service for work orders: CRUD, items, signatures, history, summary,
/// realtime stream.
library;

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/work_order.dart';
import '../service_locator.dart';

class SupabaseWorkOrderService {
  SupabaseWorkOrderService();
  SupabaseClient get _supabase => Supabase.instance.client;

  // ── Reads ──────────────────────────────────────────────────────────────────

  /// Workspace-wide stream of all work orders (parent rows only — no items or
  /// signatures hydrated). Used by the top-level list screen.
  Stream<List<WorkOrder>> watchByWorkspace(String workspaceId) {
    return _supabase
        .from('work_orders')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .map((rows) {
          final out = rows
              .map((r) => WorkOrder.fromRow(Map<String, dynamic>.from(r)))
              .toList();
          out.sort((a, b) {
            final c = a.status.index.compareTo(b.status.index);
            if (c != 0) return c;
            return b.createdAt.compareTo(a.createdAt);
          });
          return out;
        });
  }

  /// Realtime stream of all work orders for a project, with items + signatures
  /// hydrated. Re-emits when either the parent rows or their children change.
  ///
  /// Optionally filter by [kind] ('materials' or 'rental') so the same
  /// service powers the Materials board and the Rentals board inside the
  /// project Purchase Orders tab.
  Stream<List<WorkOrder>> watchByProject(String projectId, {String? kind}) {
    final woStream = _supabase
        .from('work_orders')
        .stream(primaryKey: ['id']).eq('project_id', projectId);
    final itemStream =
        _supabase.from('work_order_items').stream(primaryKey: ['id']);
    final sigStream =
        _supabase.from('work_order_signatures').stream(primaryKey: ['id']);

    List<Map<String, dynamic>>? lastWos;
    List<Map<String, dynamic>>? lastItems;
    List<Map<String, dynamic>>? lastSigs;

    final controller = StreamController<List<WorkOrder>>();

    List<WorkOrder> build() {
      var wos = lastWos ?? const <Map<String, dynamic>>[];
      if (kind != null) {
        wos = wos
            .where((r) => ((r['kind'] as String?) ?? 'materials') == kind)
            .toList();
      }
      if (wos.isEmpty) return const [];
      final ids = wos.map((r) => r['id'] as String).toSet();
      final itemsByParent = <String, List<WorkOrderItem>>{};
      for (final r in (lastItems ?? const [])) {
        final pid = r['work_order_id'] as String?;
        if (pid == null || !ids.contains(pid)) continue;
        itemsByParent
            .putIfAbsent(pid, () => [])
            .add(WorkOrderItem.fromRow(Map<String, dynamic>.from(r)));
      }
      for (final list in itemsByParent.values) {
        list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      }
      final sigsByParent = <String, List<WorkOrderSignature>>{};
      for (final r in (lastSigs ?? const [])) {
        final pid = r['work_order_id'] as String?;
        if (pid == null || !ids.contains(pid)) continue;
        sigsByParent
            .putIfAbsent(pid, () => [])
            .add(WorkOrderSignature.fromRow(Map<String, dynamic>.from(r)));
      }
      for (final list in sigsByParent.values) {
        list.sort((a, b) => a.signedAt.compareTo(b.signedAt));
      }
      final out = wos
          .map((r) => WorkOrder.fromRow(
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

    final s1 = woStream.listen((rows) {
      lastWos = rows;
      controller.add(build());
    }, onError: controller.addError);
    final s2 = itemStream.listen((rows) {
      lastItems = rows;
      if (lastWos != null) controller.add(build());
    }, onError: controller.addError);
    final s3 = sigStream.listen((rows) {
      lastSigs = rows;
      if (lastWos != null) controller.add(build());
    }, onError: controller.addError);

    controller.onCancel = () async {
      await s1.cancel();
      await s2.cancel();
      await s3.cancel();
    };
    return controller.stream;
  }

  Future<WorkOrder?> get(String id) async {
    final row = await _supabase
        .from('work_orders')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    final items = await _supabase
        .from('work_order_items')
        .select()
        .eq('work_order_id', id)
        .order('sort_order');
    final sigs = await _supabase
        .from('work_order_signatures')
        .select()
        .eq('work_order_id', id)
        .order('signed_at');
    return WorkOrder.fromRow(
      Map<String, dynamic>.from(row),
      items: (items as List)
          .map((r) => WorkOrderItem.fromRow(Map<String, dynamic>.from(r)))
          .toList(),
      signatures: (sigs as List)
          .map((r) =>
              WorkOrderSignature.fromRow(Map<String, dynamic>.from(r)))
          .toList(),
    );
  }

  Future<List<WorkOrderHistoryEvent>> historyFor(String workOrderId) async {
    final rows = await _supabase
        .from('work_order_history')
        .select()
        .eq('work_order_id', workOrderId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) =>
            WorkOrderHistoryEvent.fromRow(Map<String, dynamic>.from(r)))
        .toList();
  }

  WorkOrderSummary summarise(List<WorkOrder> list) {
    var committed = 0.0, paid = 0.0;
    var nTotal = 0, nOpen = 0, nDone = 0, nCancelled = 0;
    for (final w in list) {
      nTotal++;
      paid += w.paidToDate;
      switch (w.status) {
        case WorkOrderStatus.completed:
          committed += w.totalAmount;
          nDone++;
          break;
        case WorkOrderStatus.cancelled:
          nCancelled++;
          break;
        default:
          committed += w.totalAmount;
          nOpen++;
      }
    }
    return WorkOrderSummary(
      countTotal: nTotal,
      countOpen: nOpen,
      countCompleted: nDone,
      countCancelled: nCancelled,
      totalCommitted: committed,
      totalPaid: paid,
      totalRemaining: committed - paid,
    );
  }

  Future<WorkOrderSummary> summaryForProject(
    String projectId, {
    String? kind,
  }) async {
    var query = _supabase
        .from('work_orders')
        .select('status, total_amount, paid_to_date, kind')
        .eq('project_id', projectId);
    if (kind != null) {
      query = query.eq('kind', kind);
    }
    final rows = await query;
    var committed = 0.0, paid = 0.0;
    var nTotal = 0, nOpen = 0, nDone = 0, nCancelled = 0;
    for (final r in (rows as List)) {
      final amt = (r['total_amount'] as num?)?.toDouble() ?? 0;
      final paidAmt = (r['paid_to_date'] as num?)?.toDouble() ?? 0;
      final status = WorkOrderStatus.fromWire(r['status'] as String?);
      nTotal++;
      paid += paidAmt;
      switch (status) {
        case WorkOrderStatus.completed:
          committed += amt;
          nDone++;
          break;
        case WorkOrderStatus.cancelled:
          nCancelled++;
          break;
        default:
          committed += amt;
          nOpen++;
      }
    }
    return WorkOrderSummary(
      countTotal: nTotal, countOpen: nOpen, countCompleted: nDone,
      countCancelled: nCancelled,
      totalCommitted: committed, totalPaid: paid,
      totalRemaining: committed - paid,
    );
  }

  // ── Writes ─────────────────────────────────────────────────────────────────

  Future<WorkOrder> create({
    required String workspaceId,
    required String projectId,
    required String number,
    required String title,
    String? description,
    String? scopeOfWork,
    WorkOrderPriority priority = WorkOrderPriority.normal,
    String? assignedTo,
    String? vendorId,
    String? location,
    DateTime? scheduledStart,
    DateTime? scheduledEnd,
    double? estimatedHours,
    String kind = 'materials',
  }) async {
    final row = await _supabase
        .from('work_orders')
        .insert({
          'workspace_id': workspaceId,
          'project_id': projectId,
          'number': number,
          'title': title,
          'description': description,
          'scope_of_work': scopeOfWork,
          'priority': priority.wireValue,
          'assigned_to': assignedTo,
          'vendor_id': vendorId,
          'location': location,
          'scheduled_start': scheduledStart?.toUtc().toIso8601String(),
          'scheduled_end': scheduledEnd?.toUtc().toIso8601String(),
          'estimated_hours': estimatedHours,
          'status': 'draft',
          'kind': kind,
        })
        .select()
        .single();
    final wo = WorkOrder.fromRow(Map<String, dynamic>.from(row));
    final createdLabel =
        kind == 'rental' ? 'Rental request created' : 'Work order created';
    await _addHistory(wo.id, workspaceId, 'created', message: createdLabel);
    return wo;
  }

  Future<void> update(String id, Map<String, dynamic> patch) =>
      _supabase.from('work_orders').update(patch).eq('id', id);

  Future<void> setStatus(String id, WorkOrderStatus status) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final patch = <String, dynamic>{'status': status.wireValue};
    switch (status) {
      case WorkOrderStatus.issued:
        patch['issued_by'] = _supabase.auth.currentUser?.id;
        break;
      case WorkOrderStatus.inProgress:
        patch['started_at'] = now;
        break;
      case WorkOrderStatus.completed:
        patch['completed_at'] = now;
        patch['completed_by'] = _supabase.auth.currentUser?.id;
        break;
      case WorkOrderStatus.cancelled:
        patch['cancelled_at'] = now;
        break;
      default:
        break;
    }
    await update(id, patch);
    // History row written automatically by trigger.
  }

  Future<void> delete(String id) =>
      _supabase.from('work_orders').delete().eq('id', id);

  /// Record a payment against a work order (Materials or Rental). Bumps
  /// `paid_to_date` and writes a history event so the Paid / Remaining
  /// KPIs and budget-side actuals stay accurate.
  Future<void> recordPayment(String id, double amount) async {
    final row = await _supabase
        .from('work_orders')
        .select('paid_to_date, workspace_id, kind')
        .eq('id', id)
        .single();
    final current = (row['paid_to_date'] as num?)?.toDouble() ?? 0;
    final next = current + amount;
    await update(id, {'paid_to_date': next});
    final kindLabel =
        (row['kind'] as String?) == 'rental' ? 'rental' : 'work order';
    await _addHistory(
      id,
      (row['workspace_id'] ?? '') as String,
      'payment_recorded',
      message:
          'Payment recorded on $kindLabel: \$${amount.toStringAsFixed(2)}',
    );
  }

  // Items
  Future<WorkOrderItem> addItem({
    required String workOrderId,
    required String workspaceId,
    required String description,
    double quantity = 1,
    String? unit,
    double unitCost = 0,
    String? budgetItemId,
    String? taskId,
    int sortOrder = 0,
  }) async {
    final row = await _supabase
        .from('work_order_items')
        .insert({
          'work_order_id': workOrderId,
          'workspace_id': workspaceId,
          'description': description,
          'quantity': quantity,
          'unit': unit,
          'unit_cost': unitCost,
          'budget_item_id': budgetItemId,
          'task_id': taskId,
          'sort_order': sortOrder,
        })
        .select()
        .single();
    await _recomputeTotal(workOrderId);
    if (budgetItemId != null) {
      await _budgetRecompute(budgetItemId);
    }
    await _addHistory(workOrderId, workspaceId, 'item_added',
        message: 'Added item: $description');
    return WorkOrderItem.fromRow(Map<String, dynamic>.from(row));
  }

  Future<void> updateItem(
      String id, String workOrderId, Map<String, dynamic> patch) async {
    final before = await _supabase
        .from('work_order_items')
        .select('budget_item_id')
        .eq('id', id)
        .maybeSingle();
    final oldBudgetId = before?['budget_item_id'] as String?;
    await _supabase.from('work_order_items').update(patch).eq('id', id);
    await _recomputeTotal(workOrderId);
    final newBudgetId =
        patch.containsKey('budget_item_id') ? patch['budget_item_id'] as String? : oldBudgetId;
    await _budgetRecompute(oldBudgetId);
    if (newBudgetId != oldBudgetId) {
      await _budgetRecompute(newBudgetId);
    }
  }

  Future<void> deleteItem(String id, String workOrderId) async {
    final before = await _supabase
        .from('work_order_items')
        .select('budget_item_id')
        .eq('id', id)
        .maybeSingle();
    final oldBudgetId = before?['budget_item_id'] as String?;
    await _supabase.from('work_order_items').delete().eq('id', id);
    await _recomputeTotal(workOrderId);
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

  Future<void> _recomputeTotal(String workOrderId) async {
    final rows = await _supabase
        .from('work_order_items')
        .select('quantity, unit_cost')
        .eq('work_order_id', workOrderId);
    var total = 0.0;
    for (final r in (rows as List)) {
      final q = (r['quantity'] as num?)?.toDouble() ?? 0;
      final c = (r['unit_cost'] as num?)?.toDouble() ?? 0;
      total += q * c;
    }
    await _supabase
        .from('work_orders')
        .update({'total_amount': total}).eq('id', workOrderId);
  }

  // Signatures
  Future<WorkOrderSignature> addSignature({
    required String workOrderId,
    required String workspaceId,
    required String role,
    required String signerName,
    String? signerEmail,
    required String signatureUrl,
  }) async {
    final row = await _supabase
        .from('work_order_signatures')
        .insert({
          'work_order_id': workOrderId,
          'workspace_id': workspaceId,
          'role': role,
          'signer_name': signerName,
          'signer_email': signerEmail,
          'signature_url': signatureUrl,
        })
        .select()
        .single();
    await _addHistory(workOrderId, workspaceId, 'signed',
        message: '$role signed by $signerName',
        actorName: signerName);
    return WorkOrderSignature.fromRow(Map<String, dynamic>.from(row));
  }

  Future<void> _addHistory(
    String workOrderId,
    String workspaceId,
    String eventType, {
    String? message,
    String? actorName,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _supabase.from('work_order_history').insert({
        'work_order_id': workOrderId,
        'workspace_id': workspaceId,
        'event_type': eventType,
        'message': message,
        'actor_id': _supabase.auth.currentUser?.id,
        'actor_name': actorName,
        'metadata': metadata ?? {},
      });
    } catch (_) {
      // Non-fatal — history is best-effort.
    }
  }

  /// Generate the next number for a project, scoped to the given [kind].
  /// Materials default to a WO- prefix; rentals default to RNT-.
  Future<String> nextNumber(
    String projectId, {
    String kind = 'materials',
    String? prefix,
  }) async {
    final usePrefix = prefix ?? (kind == 'rental' ? 'RNT' : 'WO');
    final rows = await _supabase
        .from('work_orders')
        .select('number, kind')
        .eq('project_id', projectId)
        .eq('kind', kind);
    var maxN = 0;
    final re = RegExp(r'(\d+)');
    for (final r in (rows as List)) {
      final m = re.firstMatch((r['number'] ?? '') as String);
      if (m != null) {
        final n = int.tryParse(m.group(1)!) ?? 0;
        if (n > maxN) maxN = n;
      }
    }
    return '$usePrefix-${(maxN + 1).toString().padLeft(3, '0')}';
  }
}
