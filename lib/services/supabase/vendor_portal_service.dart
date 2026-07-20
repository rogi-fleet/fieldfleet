import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/app_logger.dart';

/// Supabase-backed Vendor Portal service.
///
/// Mirrors the customer portal model: vendors authenticate via Supabase
/// magic-link, and all reads/writes are gated by `auth.jwt() -> email`
/// matching an active `vendor_contacts.email`. All RPCs are SECURITY
/// DEFINER and enforce that authorization server-side.
class SupabaseVendorPortalService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // -------------------------------------------------------------------------
  // Auth
  // -------------------------------------------------------------------------

  /// Returns true if the email is a recognized vendor contact (i.e. it is OK
  /// to send a magic link to it).
  Future<bool> canRequestAccess(String email) async {
    try {
      final res = await _supabase.rpc(
        'portal_vendor_can_request_access',
        params: {'p_email': email.toLowerCase().trim()},
      );
      return res == true;
    } catch (e, st) {
      AppLogger.error('vendor portal canRequestAccess failed',
          error: e, stackTrace: st);
      return false;
    }
  }

  /// Send a magic link. We intentionally do NOT pre-check whether the email
  /// belongs to an active vendor contact: doing so against an unauthenticated
  /// caller would let anyone enumerate the vendor directory. Supabase will
  /// deliver a usable link only if the email exists in auth; if the recipient
  /// has no matching vendor_contacts row, the server-side RPCs will simply
  /// return empty data after they sign in.
  Future<void> requestMagicLink(String email, {required String siteUrl}) async {
    final normalized = email.toLowerCase().trim();
    await _supabase.auth.signInWithOtp(
      email: normalized,
      emailRedirectTo: '$siteUrl/#/vendor-portal',
    );
  }

  Future<void> signOut() => _supabase.auth.signOut();

  String? getPortalEmail() {
    final raw = _supabase.auth.currentUser?.email;
    final n = raw?.toLowerCase().trim();
    return (n == null || n.isEmpty) ? null : n;
  }

  bool get isSignedIn => _supabase.auth.currentSession != null;

  // -------------------------------------------------------------------------
  // Reads
  // -------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getVendors() =>
      _list('portal_vendor_get_vendors');

  Future<List<Map<String, dynamic>>> getBidPackages() =>
      _list('portal_vendor_get_bid_packages');

  Future<List<Map<String, dynamic>>> getWorkOrders() =>
      _list('portal_vendor_get_work_orders');

  Future<List<Map<String, dynamic>>> getPurchaseOrders() =>
      _list('portal_vendor_get_purchase_orders');

  Future<List<Map<String, dynamic>>> getBills() =>
      _list('portal_vendor_get_bills');

  Future<List<Map<String, dynamic>>> getSelections() =>
      _list('portal_vendor_get_selections');

  Future<List<Map<String, dynamic>>> _list(String rpc) async {
    try {
      final raw = await _supabase.rpc(rpc);
      if (raw is! List) return const [];
      return raw
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList(growable: false);
    } catch (e, st) {
      AppLogger.error('Vendor portal RPC $rpc failed',
          error: e, stackTrace: st);
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

  /// Submit per-line-item bids on an RFB document. Delegates to the existing
  /// `submit_vendor_bid` RPC, which already authorizes portal vendors.
  Future<void> submitBid({
    required String documentId,
    required List<Map<String, dynamic>> lineItemBids,
    String? overallNote,
  }) async {
    try {
      await _supabase.rpc('submit_vendor_bid', params: {
        'p_document_id': documentId,
        'p_line_item_bids': lineItemBids,
        'p_overall_note': overallNote,
      });
    } catch (e, st) {
      AppLogger.error('vendor portal submitBid failed',
          error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Accept or decline a work order. On accept, status transitions
  /// issued → in_progress. On decline, status transitions → on_hold.
  Future<void> acknowledgeWorkOrder({
    required String workOrderId,
    required bool accept,
    String? signerName,
    String? note,
  }) async {
    try {
      await _supabase.rpc('portal_vendor_acknowledge_work_order', params: {
        'p_work_order_id': workOrderId,
        'p_accept': accept,
        'p_signer_name': signerName,
        'p_note': note,
      });
    } catch (e, st) {
      AppLogger.error('vendor portal acknowledgeWorkOrder failed',
          error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Submit a bill against an existing PO. Returns the new bill id.
  Future<String> submitBill({
    required String purchaseOrderId,
    required double amount,
    String? billNumber,
    DateTime? billDate,
    DateTime? dueDate,
    String? notes,
    List<Map<String, dynamic>>? lineItems,
  }) async {
    try {
      final res = await _supabase.rpc('portal_vendor_submit_bill', params: {
        'p_purchase_order_id': purchaseOrderId,
        'p_amount': amount,
        'p_bill_number': billNumber,
        'p_bill_date': billDate?.toIso8601String().substring(0, 10),
        'p_due_date': dueDate?.toIso8601String().substring(0, 10),
        'p_notes': notes,
        'p_line_items': lineItems,
      });
      if (res is String) return res;
      throw Exception('Unexpected response from submit_bill RPC');
    } catch (e, st) {
      AppLogger.error('vendor portal submitBill failed',
          error: e, stackTrace: st);
      rethrow;
    }
  }
}
