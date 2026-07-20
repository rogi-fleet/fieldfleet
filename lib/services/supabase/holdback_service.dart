import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/holdback_release.dart';

/// All persistence for the holdback (retainage) feature.
///
/// Reads outstanding retainage from `generated_documents`, manages
/// holdback_releases / holdback_release_lines, and exposes the RPC that
/// atomically stamps source invoices when a release is issued.
class HoldbackService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ── Project-level summary ─────────────────────────────────────────────

  /// Aggregate retainage figures for a project. Computed from
  /// `generated_documents` retainage_* columns.
  Future<HoldbackSummary> getProjectSummary(String projectId) async {
    // Pull every invoice/progress invoice with non-zero retainage. RLS handles
    // the workspace scope.
    final rows = await _supabase
        .from('generated_documents')
        .select(
          'id, document_number, total_amount, retainage_percent, retainage_amount, '
          'retainage_released, retainage_released_date, customer_name, created_at',
        )
        .eq('project_id', projectId)
        .inFilter('document_type', ['invoice', 'progress_invoice'])
        .gt('retainage_amount', 0);

    double totalInvoiced = 0;
    double totalHeld = 0;
    double totalReleased = 0;
    double totalOutstanding = 0;
    final outstanding = <OutstandingRetainage>[];

    for (final r in (rows as List)) {
      final m = r as Map<String, dynamic>;
      final amt = _d(m['retainage_amount']);
      final pct = _d(m['retainage_percent']);
      final invTotal = _d(m['total_amount']);
      final released = m['retainage_released'] == true;
      totalInvoiced += invTotal;
      totalHeld += amt;
      if (released) {
        totalReleased += amt;
      } else {
        totalOutstanding += amt;
        outstanding.add(OutstandingRetainage(
          invoiceId: m['id'] as String,
          documentNumber: m['document_number'] as String?,
          createdAt: _dt(m['created_at']) ?? DateTime.now(),
          invoiceTotal: invTotal,
          retainagePercent: pct,
          retainageAmount: amt,
          customerName: m['customer_name'] as String?,
        ));
      }
    }

    outstanding.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    return HoldbackSummary(
      totalInvoicedWithHoldback: totalInvoiced,
      totalHeld: totalHeld,
      totalReleased: totalReleased,
      totalOutstanding: totalOutstanding,
      outstandingInvoices: outstanding,
    );
  }

  // ── Apply holdback to an existing invoice ─────────────────────────────

  /// Stamp retainage_percent + retainage_amount on a generated_documents row.
  /// Caller is responsible for passing the correct retainage_amount (typically
  /// `invoiceSubtotal * percent / 100`).
  Future<void> applyHoldbackToInvoice({
    required String invoiceId,
    required double percent,
    required double amount,
  }) async {
    await _supabase.from('generated_documents').update({
      'retainage_percent': percent,
      'retainage_amount': amount,
    }).eq('id', invoiceId);
  }

  // ── Releases CRUD ─────────────────────────────────────────────────────

  Future<List<HoldbackRelease>> listForProject(String projectId) async {
    final rows = await _supabase
        .from('holdback_releases')
        .select()
        .eq('project_id', projectId)
        .order('release_number', ascending: false);
    return (rows as List)
        .map((r) => HoldbackRelease.fromDb(r as Map<String, dynamic>))
        .toList();
  }

  Future<HoldbackRelease?> getById(String id) async {
    final row = await _supabase
        .from('holdback_releases')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    final lineRows = await _supabase
        .from('holdback_release_lines')
        .select()
        .eq('release_id', id)
        .order('sort_order');
    final lines = (lineRows as List)
        .map((r) => HoldbackReleaseLine.fromDb(r as Map<String, dynamic>))
        .toList();
    return HoldbackRelease.fromDb(row, lines: lines);
  }

  Future<int> getNextReleaseNumber(String projectId) async {
    final rows = await _supabase
        .from('holdback_releases')
        .select('release_number')
        .eq('project_id', projectId)
        .order('release_number', ascending: false)
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) return 1;
    return ((list.first as Map<String, dynamic>)['release_number'] as num)
            .toInt() +
        1;
  }

  /// Insert header + lines. Returns the new release id.
  Future<String> create(HoldbackRelease release) async {
    final res = await _supabase
        .from('holdback_releases')
        .insert(release.toDbHeader())
        .select('id')
        .single();
    final id = res['id'] as String;
    if (release.lines.isNotEmpty) {
      await _supabase.from('holdback_release_lines').insert(
            release.lines.map((l) => l.toDb(releaseId: id)).toList(),
          );
    }
    return id;
  }

  /// Replace header fields and lines in two statements (lines first deleted).
  Future<void> update(HoldbackRelease release) async {
    await _supabase
        .from('holdback_releases')
        .update(release.toDbHeader())
        .eq('id', release.id);
    await _supabase
        .from('holdback_release_lines')
        .delete()
        .eq('release_id', release.id);
    if (release.lines.isNotEmpty) {
      await _supabase.from('holdback_release_lines').insert(
            release.lines.map((l) => l.toDb(releaseId: release.id)).toList(),
          );
    }
  }

  Future<void> delete(String id) async {
    await _supabase.from('holdback_releases').delete().eq('id', id);
  }

  /// Atomic issue: flips status to issued and stamps the source invoices.
  Future<void> issue(String id) async {
    await _supabase.rpc(
      'issue_holdback_release',
      params: {'p_release_id': id},
    );
  }

  Future<void> markPaid(String id) async {
    await _supabase.from('holdback_releases').update({
      'status': 'paid',
      'paid_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> attachDocument(String id, String documentId) async {
    await _supabase.from('holdback_releases').update({
      'document_id': documentId,
    }).eq('id', id);
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  static double _d(dynamic v) =>
      v == null ? 0.0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0);
  static DateTime? _dt(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}

/// Aggregated retainage figures for a project.
class HoldbackSummary {
  final double totalInvoicedWithHoldback;
  final double totalHeld;
  final double totalReleased;
  final double totalOutstanding;
  final List<OutstandingRetainage> outstandingInvoices;

  const HoldbackSummary({
    required this.totalInvoicedWithHoldback,
    required this.totalHeld,
    required this.totalReleased,
    required this.totalOutstanding,
    required this.outstandingInvoices,
  });

  double get releasedPct =>
      totalHeld == 0 ? 0 : (totalReleased / totalHeld) * 100;
}
