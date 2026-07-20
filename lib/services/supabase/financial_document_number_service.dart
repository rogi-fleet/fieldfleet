import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/document_numbering_config.dart';

/// Supabase service for generating sequential document numbers for financial documents
class SupabaseFinancialDocumentNumberService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Document types (must match DocumentType.dbValue values)
  static const String bidRequest = 'request_for_bid';
  static const String changeOrder = 'change_order';
  static const String purchaseOrder = 'purchase_order';
  static const String bill = 'bill';
  static const String refund = 'refund';
  static const String invoice = 'invoice';
  static const String progressInvoice = 'progress_invoice';
  static const String quotation = 'quotation';
  static const String credit = 'credit';
  static const String deposit = 'deposit';
  static const String vendorCredit = 'vendor_credit';
  static const String expense = 'expense';
  static const String vendorRefund = 'vendor_refund';

  /// Default prefixes for each document type. Public so callers can check if a
  /// type supports auto-numbering without catching errors.
  static const Map<String, String> prefixes = defaultPrefixes;
  static const Map<String, String> defaultPrefixes = {
    bidRequest: 'BR',
    changeOrder: 'CO',
    purchaseOrder: 'PO',
    bill: 'BILL',
    refund: 'REF',
    invoice: 'INV',
    progressInvoice: 'PINV',
    quotation: 'QT',
    credit: 'CR',
    deposit: 'DEP',
    vendorCredit: 'VCR',
    expense: 'EXP',
    vendorRefund: 'VREF',
  };

  static const int defaultPaddingWidth = 3;
  static const String defaultSeparator = '-';

  /// Human-readable labels for each document type.
  static const Map<String, String> documentTypeLabels = {
    bidRequest: 'Bid Request',
    changeOrder: 'Change Order',
    purchaseOrder: 'Purchase Order',
    bill: 'Bill',
    refund: 'Refund',
    invoice: 'Invoice',
    progressInvoice: 'Progress Invoice',
    quotation: 'Quotation',
    credit: 'Credit',
    deposit: 'Deposit',
    vendorCredit: 'Vendor Credit',
    expense: 'Expense',
    vendorRefund: 'Vendor Refund',
  };

  /// Generate next document number for a specific type and workspace.
  ///
  /// Uses a Postgres RPC (`next_document_number`) with INSERT ... ON CONFLICT
  /// to atomically increment the counter, preventing duplicate numbers under
  /// concurrent requests.
  ///
  /// When [config] is provided, uses its prefix/padding/separator.
  /// Otherwise falls back to hard-coded defaults.
  Future<String> generateDocumentNumber({
    required String workspaceId,
    required String documentType,
    DocumentNumberingConfig? config,
  }) async {
    if (!defaultPrefixes.containsKey(documentType)) {
      throw ArgumentError('Invalid document type: $documentType');
    }

    final prefix = config?.prefix ?? defaultPrefixes[documentType]!;
    final separator = config?.separator ?? defaultSeparator;
    final padding = config?.paddingWidth ?? defaultPaddingWidth;

    final nextNumber = await _supabase.rpc('next_document_number', params: {
      'p_workspace_id': workspaceId,
      'p_document_type': documentType,
    }) as int;

    final numberStr = nextNumber.toString().padLeft(padding, '0');
    return '$prefix$separator$numberStr';
  }

  /// Get current counter value for a document type
  Future<int> getCurrentCounter({
    required String workspaceId,
    required String documentType,
  }) async {
    final result = await _supabase
        .from('document_counters')
        .select('current_value')
        .eq('workspace_id', workspaceId)
        .eq('document_type', documentType)
        .maybeSingle();

    return result?['current_value'] ?? 0;
  }

  /// Reset counter for a document type (use with caution)
  Future<void> resetCounter({
    required String workspaceId,
    required String documentType,
    int resetTo = 0,
  }) async {
    final now = DateTime.now();

    await _supabase.from('document_counters').upsert({
      'workspace_id': workspaceId,
      'document_type': documentType,
      'current_value': resetTo,
      'updated_at': now.toIso8601String(),
    });
  }
}
