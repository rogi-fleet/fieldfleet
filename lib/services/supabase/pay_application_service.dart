import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/budget_item.dart';
import '../../models/pay_app_line.dart';
import '../../models/pay_application.dart';

/// CRUD + rollover logic for AIA G702/G703 payment applications.
class PayApplicationService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ── Reads ──────────────────────────────────────────────────────────

  /// Stream all pay applications for a project, header-only (no lines),
  /// ordered by application_number desc.
  Stream<List<PayApplication>> watchForProject(String projectId) {
    return _supabase
        .from('aia_payment_applications')
        .stream(primaryKey: ['id'])
        .eq('project_id', projectId)
        .order('application_number')
        .map((rows) {
          final list = rows.map((r) => PayApplication.fromDb(r)).toList();
          list.sort(
              (a, b) => b.applicationNumber.compareTo(a.applicationNumber));
          return list;
        });
  }

  Future<List<PayApplication>> listForProject(String projectId) async {
    final rows = await _supabase
        .from('aia_payment_applications')
        .select()
        .eq('project_id', projectId)
        .order('application_number', ascending: false);
    return (rows as List)
        .map((r) => PayApplication.fromDb(r as Map<String, dynamic>))
        .toList();
  }

  Future<PayApplication?> getById(String id) async {
    final row = await _supabase
        .from('aia_payment_applications')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    final lineRows = await _supabase
        .from('aia_pay_app_lines')
        .select()
        .eq('pay_application_id', id)
        .order('sort_order');
    final lines = (lineRows as List)
        .map((r) => PayAppLine.fromDb(r as Map<String, dynamic>))
        .toList();
    return PayApplication.fromDb(row, lines: lines);
  }

  Future<PayApplication?> getPriorApplication(
    String projectId,
    int beforeApplicationNumber,
  ) async {
    final row = await _supabase
        .from('aia_payment_applications')
        .select()
        .eq('project_id', projectId)
        .lt('application_number', beforeApplicationNumber)
        .order('application_number', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;
    return getById(row['id'] as String);
  }

  Future<int> getNextApplicationNumber(String projectId) async {
    final rows = await _supabase
        .from('aia_payment_applications')
        .select('application_number')
        .eq('project_id', projectId)
        .order('application_number', ascending: false)
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) return 1;
    return ((list.first as Map<String, dynamic>)['application_number'] as num)
            .toInt() +
        1;
  }

  // ── Writes ─────────────────────────────────────────────────────────

  /// Create a new pay app header. Returns the created row's id.
  Future<String> createHeader(PayApplication app) async {
    final response = await _supabase
        .from('aia_payment_applications')
        .insert(app.toDb())
        .select('id')
        .single();
    return response['id'] as String;
  }

  Future<void> updateHeader(PayApplication app) async {
    await _supabase
        .from('aia_payment_applications')
        .update(app.toDb())
        .eq('id', app.id);
  }

  /// Replace all lines for a pay app **atomically** via a Postgres RPC
  /// (single transaction). Prevents the zero-line state if insert fails
  /// after delete.
  Future<void> replaceLines(
    String payApplicationId,
    List<PayAppLine> lines,
  ) async {
    final payload = lines.map((l) {
      final m = l.toDb();
      // The RPC supplies pay_application_id itself; the line-level value
      // would be ignored, but we strip it to keep the JSON minimal.
      m.remove('pay_application_id');
      return m;
    }).toList();
    await _supabase.rpc('replace_aia_pay_app_lines', params: {
      'p_app_id': payApplicationId,
      'p_lines': payload,
    });
  }

  Future<void> delete(String id) async {
    await _supabase.from('aia_payment_applications').delete().eq('id', id);
  }

  /// Architect/owner certification step. Moves status to [certified] and
  /// stamps amount/by/at. Only valid from [submitted]; the caller is
  /// expected to gate the UI accordingly.
  Future<void> certify({
    required String id,
    required double amountCertified,
    required String certifiedBy,
    DateTime? certifiedAt,
  }) async {
    await _supabase.from('aia_payment_applications').update({
      'status': PayApplicationStatus.certified.dbValue,
      'certified_amount': amountCertified,
      'certified_by': certifiedBy,
      'certified_at': (certifiedAt ?? DateTime.now()).toIso8601String(),
    }).eq('id', id);
  }

  /// Mark a certified pay app as paid.
  Future<void> markPaid(String id) async {
    await _supabase.from('aia_payment_applications').update({
      'status': PayApplicationStatus.paid.dbValue,
    }).eq('id', id);
  }

  // ── Builders ───────────────────────────────────────────────────────

  /// Build a fresh draft pay app for [projectId], auto-numbered as the
  /// next application. Lines are seeded from budget items, with
  /// `work_completed_previous` rolled over from the prior pay app's
  /// (previous + this_period + materials_stored) keyed by budget_item_id.
  ///
  /// Returns the draft in memory — caller must persist via [createHeader]
  /// + [replaceLines].
  Future<PayApplication> buildDraftFromBudget({
    required String workspaceId,
    required String projectId,
    required List<BudgetItem> budgetItems,
    String? contractorName,
    String? ownerName,
  }) async {
    final nextNo = await getNextApplicationNumber(projectId);
    final prior = nextNo > 1
        ? await getPriorApplication(projectId, nextNo)
        : null;

    // G702 line 7 (Less Previous Certificates) is *cumulative* across every
    // prior application. We persist it on the header during rollover so the
    // figure stays correct after the prior app's lines are mutated.
    final priorCertifiedSnapshot = prior == null
        ? 0.0
        : prior.previousCertificatesTotal +
            (prior.currentPaymentDueSnapshot ?? prior.currentPaymentDue);

    // Build rollover map: budget_item_id -> total completed/stored to date.
    final rolloverByBudget = <String, double>{};
    final rolloverByDescription = <String, double>{};
    if (prior != null) {
      for (final l in prior.lines) {
        final completedToDate = l.workCompletedPrevious +
            l.workCompletedThisPeriod +
            l.materialsStored;
        if (l.budgetItemId != null) {
          rolloverByBudget[l.budgetItemId!] = completedToDate;
        } else if (l.description.isNotEmpty) {
          rolloverByDescription[l.description] = completedToDate;
        }
      }
    }

    // Seed lines from budget items (leaves only — matches estimating logic).
    final leaves = budgetItems
        .where((b) => b.itemType == BudgetItemType.item)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    final now = DateTime.now();
    final headerId = ''; // assigned by DB on insert
    final lines = <PayAppLine>[];
    for (var i = 0; i < leaves.length; i++) {
      final b = leaves[i];
      final priorCompleted = rolloverByBudget[b.id] ?? 0.0;
      lines.add(PayAppLine(
        id: '', // assigned by DB
        payApplicationId: headerId,
        workspaceId: workspaceId,
        budgetItemId: b.id,
        itemNo: (i + 1).toString(),
        description: b.name,
        scheduledValue: b.approvedPrice,
        workCompletedPrevious: priorCompleted,
        sortOrder: i,
      ));
    }

    final originalContract = leaves.fold<double>(
      0,
      (s, b) =>
          b.sourceType == BudgetItemSource.base ? s + b.approvedPrice : s,
    );
    final changeOrderTotal = leaves.fold<double>(
      0,
      (s, b) => b.sourceType == BudgetItemSource.changeOrder
          ? s + b.approvedPrice
          : s,
    );

    return PayApplication(
      id: '',
      workspaceId: workspaceId,
      projectId: projectId,
      applicationNumber: nextNo,
      dateIssued: now,
      periodTo: now,
      periodFrom: prior?.periodTo,
      contractorName: contractorName,
      ownerName: ownerName,
      originalContractSum: prior?.originalContractSum ?? originalContract,
      netChangeByChangeOrders:
          prior?.netChangeByChangeOrders ?? changeOrderTotal,
      retainagePctCompleted: prior?.retainagePctCompleted ?? 10,
      retainagePctStored: prior?.retainagePctStored ?? 10,
      previousCertificatesTotal: priorCertifiedSnapshot,
      status: PayApplicationStatus.draft,
      createdAt: now,
      updatedAt: now,
      lines: lines,
    );
  }
}
