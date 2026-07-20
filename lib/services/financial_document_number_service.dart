import 'package:cloud_firestore/cloud_firestore.dart';

/// Service for generating sequential document numbers for financial documents
class FinancialDocumentNumberService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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

  /// Prefixes for each document type
  static const Map<String, String> _prefixes = {
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

  /// Generate next document number for a specific type and workspace
  /// 
  /// Returns formatted number like: BR-001, CO-042, PO-123, etc.
  Future<String> generateDocumentNumber({
    required String workspaceId,
    required String documentType,
  }) async {
    if (!_prefixes.containsKey(documentType)) {
      throw ArgumentError('Invalid document type: $documentType');
    }

    final prefix = _prefixes[documentType]!;
    
    // Use Firestore transaction to ensure atomic increment
    final counterRef = _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('counters')
        .doc(documentType);

    String documentNumber = '';

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(counterRef);
      
      int nextNumber = 1;
      if (snapshot.exists) {
        nextNumber = (snapshot.data()?['current'] ?? 0) + 1;
      }

      // Update counter
      transaction.set(counterRef, {
        'current': nextNumber,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Format with leading zeros (e.g., 001, 042, 123)
      final numberStr = nextNumber.toString().padLeft(3, '0');
      documentNumber = '$prefix-$numberStr';
    });

    return documentNumber;
  }

  /// Get current counter value for a document type
  Future<int> getCurrentCounter({
    required String workspaceId,
    required String documentType,
  }) async {
    final snapshot = await _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('counters')
        .doc(documentType)
        .get();

    return snapshot.data()?['current'] ?? 0;
  }

  /// Reset counter for a document type (use with caution)
  Future<void> resetCounter({
    required String workspaceId,
    required String documentType,
    int resetTo = 0,
  }) async {
    await _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('counters')
        .doc(documentType)
        .set({
      'current': resetTo,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
