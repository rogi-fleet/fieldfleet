import 'package:supabase_flutter/supabase_flutter.dart';

/// Receives inventory against a document-based purchase order.
///
/// A purchase order is a `generated_documents` row whose line items live in the
/// `line_items` JSONB column. Receiving a line bumps that line's
/// `quantityReceived` and records an `inventory_stock_movements` row that
/// increments on-hand stock — all atomically inside the
/// `receive_document_po_line` RPC so concurrent receives can't clobber the JSON.
class DocumentPoReceivingService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Receive [quantity] units against the PO line identified by [lineId] on
  /// document [documentId]. Throws if the line is not inventory-tracked.
  Future<void> receiveLine({
    required String documentId,
    required String lineId,
    required double quantity,
  }) async {
    await _supabase.rpc(
      'receive_document_po_line',
      params: {
        'p_document_id': documentId,
        'p_line_id': lineId,
        'p_quantity': quantity,
      },
    );
  }
}
