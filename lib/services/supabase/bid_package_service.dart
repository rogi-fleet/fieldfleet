import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/bid_package.dart';
import '../../models/document_line_item.dart';
import '../../models/generated_document.dart';
import 'document_service.dart';

/// Thin service around the multi-vendor bidding RPCs and reads on
/// bid_packages / its linked generated_documents.
class BidPackageService {
  final SupabaseClient _supabase;
  final SupabaseDocumentService _documentService;

  BidPackageService({SupabaseClient? client, SupabaseDocumentService? documentService})
      : _supabase = client ?? Supabase.instance.client,
        _documentService = documentService ?? SupabaseDocumentService();

  /// Create a bid package and fan it out to one RFB document per vendor.
  /// Returns the new package id.
  ///
  /// [lineItemTemplate] should be a list of leaf [DocumentLineItem]s with
  /// quantity/unit/description and (optionally) unitPrice as the GC's
  /// internal estimate. The RPC clones the list for each vendor with
  /// fresh per-document ids but a shared `templateLineItemId` per row so
  /// the comparison grid aligns.
  Future<String> createPackage({
    required String workspaceId,
    String? projectId,
    required String name,
    String? scopeDescription,
    DateTime? dueDate,
    required List<String> vendorIds,
    required List<DocumentLineItem> lineItemTemplate,
    String? templateId,
    String? templateName,
  }) async {
    if (vendorIds.isEmpty) {
      throw ArgumentError('vendorIds must not be empty');
    }
    final templateJson = lineItemTemplate.map((li) => li.toJson()).toList();
    final result = await _supabase.rpc(
      'create_bid_package',
      params: {
        'p_workspace_id': workspaceId,
        'p_project_id': projectId,
        'p_name': name,
        'p_scope_description': scopeDescription,
        'p_due_date': dueDate?.toIso8601String(),
        'p_vendor_ids': vendorIds,
        'p_line_item_template': templateJson,
        'p_template_id': templateId,
        'p_template_name': templateName,
      },
    );
    return result as String;
  }

  /// Award a package to a single winning child document. Wraps
  /// apply_vendor_bid_to_budget and handles losing-doc transitions.
  /// Idempotent on the same winner.
  Future<void> awardPackage({
    required String packageId,
    required String winningDocumentId,
  }) async {
    await _supabase.rpc(
      'award_bid_package',
      params: {
        'p_package_id': packageId,
        'p_winning_document_id': winningDocumentId,
      },
    );
  }

  /// Cancel a package before any award. Transitions all children to
  /// withdrawn. Only valid from draft / sent states.
  Future<void> cancelPackage({
    required String packageId,
    String? reason,
  }) async {
    await _supabase.rpc(
      'cancel_bid_package',
      params: {
        'p_package_id': packageId,
        'p_reason': reason,
      },
    );
  }

  /// Load a single package by id.
  Future<BidPackage?> getPackage(String packageId) async {
    final row = await _supabase
        .from('bid_packages')
        .select()
        .eq('id', packageId)
        .maybeSingle();
    if (row == null) return null;
    return BidPackage.fromRow(row);
  }

  /// Packages scoped to a project, newest first.
  Future<List<BidPackage>> listForProject({
    required String workspaceId,
    required String projectId,
  }) async {
    final rows = await _supabase
        .from('bid_packages')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('project_id', projectId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => BidPackage.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  /// Fetch the child RFB documents for a package, for the comparison grid.
  Future<List<GeneratedDocument>> listChildDocuments(String packageId) {
    return _documentService.listByBidPackageId(packageId);
  }
}
