import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'document_status.dart';
import 'document_type.dart';
import 'document_line_item.dart';

enum LineItemSourceMode {
  snapshot,
  resyncUntilSigned;

  String get dbValue {
    switch (this) {
      case LineItemSourceMode.snapshot:
        return 'snapshot';
      case LineItemSourceMode.resyncUntilSigned:
        return 'resync_until_signed';
    }
  }

  static LineItemSourceMode fromStoredValue(String? value) {
    if (value == null || value.isEmpty) return LineItemSourceMode.snapshot;
    return LineItemSourceMode.values.firstWhere(
      (mode) => mode.name == value || mode.dbValue == value,
      orElse: () => LineItemSourceMode.snapshot,
    );
  }

  String get displayName {
    switch (this) {
      case LineItemSourceMode.snapshot:
        return 'Snapshot';
      case LineItemSourceMode.resyncUntilSigned:
        return 'Re-sync Until Signed';
    }
  }

  String get description {
    switch (this) {
      case LineItemSourceMode.snapshot:
        return 'Lock line item values at document creation.';
      case LineItemSourceMode.resyncUntilSigned:
        return 'Refresh non-overridden line item values from budget until signed.';
    }
  }
}

/// Derived fulfillment state of a purchase order, computed from its
/// inventory-tracked line items' received quantities. Kept orthogonal to
/// [DocumentStatus] (which tracks the financial/approval lifecycle).
enum PoFulfillment { none, partial, received }

/// Contact info for document header (PREPARED BY / PREPARED FOR)
class DocumentContactInfo {
  final String? name;
  final String? organization;
  final String? phone;
  final String? email;
  final String? address;

  DocumentContactInfo({
    this.name,
    this.organization,
    this.phone,
    this.email,
    this.address,
  });

  factory DocumentContactInfo.fromJson(dynamic json) {
    if (json == null) return DocumentContactInfo();
    if (json is! Map) return DocumentContactInfo();
    final normalized = Map<String, dynamic>.from(json);
    return DocumentContactInfo(
      name: normalized['name'] as String?,
      organization: normalized['organization'] as String?,
      phone: normalized['phone'] as String?,
      email: normalized['email'] as String?,
      address: normalized['address'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'organization': organization,
      'phone': phone,
      'email': email,
      'address': address,
    };
  }

  bool get isEmpty =>
      (name == null || name!.isEmpty) &&
      (organization == null || organization!.isEmpty) &&
      (phone == null || phone!.isEmpty) &&
      (email == null || email!.isEmpty) &&
      (address == null || address!.isEmpty);

  DocumentContactInfo copyWith({
    String? name,
    String? organization,
    String? phone,
    String? email,
    String? address,
  }) {
    return DocumentContactInfo(
      name: name ?? this.name,
      organization: organization ?? this.organization,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
    );
  }
}

class GeneratedDocument {
  final String id;
  final String workspaceId;
  final String? projectId;
  final String? customerId;
  final String? customerName;
  final String templateId;
  final String templateName;
  final DocumentType documentType;
  final String renderedContent;
  final String? pdfUrl;
  final DocumentStatus status;
  final String createdBy;
  final DateTime createdAt;
  final DateTime? sentAt;
  final String? sentTo;

  // Header info
  final DocumentContactInfo? preparedBy;
  final DocumentContactInfo? preparedFor;

  // Footer content
  final String? footerContent;

  // Email message for sending
  final String? emailSubject;
  final String? emailMessage;

  // Signature fields
  final String? signatureUrl; // URL to stored signature image
  final String? signedByName; // Name of person who signed
  final String? signedByEmail; // Email of person who signed
  final DateTime? signedAt; // When the document was signed
  final String? signatureIp; // IP address when signed (for audit)

  // Denial fields
  final DateTime? deniedAt;
  final String? deniedByName;
  final String? deniedByEmail;
  final String? denialReason;

  // Approval fields
  final DateTime? approvedAt;
  final String? approvedBy;

  // Budget integration fields (legacy - maintained for backwards compatibility)
  final List<String> budgetItemIds; // Links to budget items
  final Map<String, double>?
  budgetItemAmounts; // Custom amounts per budget item (key = budgetItemId)
  final double totalAmount; // Total document amount
  final double amountPaid; // Cumulative amount paid (supports partial payments)

  // Enhanced line items (new system - replaces budgetItemIds)
  final List<DocumentLineItem> lineItems;
  final LineItemVisibility lineItemVisibility;
  final LineItemSourceMode lineItemSourceMode;

  // Attached photos from project
  final List<String> attachedPhotoIds;

  // Tax settings
  final bool collectTax;
  final String? taxName;
  final double taxRate;

  /// Flat tax amount that overrides the percent-based [taxRate] when set.
  /// Used by purchase orders migrated from the legacy inventory PO system,
  /// whose tax was stored as a flat amount rather than a rate.
  final double? taxAmountOverride;

  // Purchase-order fulfillment fields (only meaningful for purchase orders).
  /// Vendor-promised delivery date.
  final DateTime? expectedDate;
  /// Set when every inventory-tracked line on a PO has been fully received.
  final DateTime? receivedDate;
  /// Flat shipping/freight charge on a purchase order.
  final double shippingCost;

  // Holdback (retainage) settings — only meaningful for customer invoices.
  final double retainagePercent;
  final double retainageAmount;

  /// Invoice-level discount (a flat reduction of the pre-tax subtotal). Posts
  /// to GL 4900 "Discounts Given" (contra-revenue) and shrinks the tax base
  /// proportionally to the taxable share. [M004]
  final double discountAmount;

  // Financial workflow fields (shared across document types)
  final String? vendorId;
  final String? sourceDocumentId;
  final String? bidPackageId;
  final DateTime? paidDate;
  final String? paymentMethod;
  final String? paymentReference;
  final String? paymentAttachmentUrl;
  final String? documentNumber;
  final DateTime? dueDate;
  final Map<String, dynamic> metadata;

  // Budget integration toggle
  final bool excludeFromBudget;

  GeneratedDocument({
    required this.id,
    required this.workspaceId,
    this.projectId,
    this.customerId,
    this.customerName,
    required this.templateId,
    required this.templateName,
    this.documentType = DocumentType.custom,
    required this.renderedContent,
    this.pdfUrl,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    this.sentAt,
    this.sentTo,
    this.preparedBy,
    this.preparedFor,
    this.footerContent,
    this.emailSubject,
    this.emailMessage,
    this.signatureUrl,
    this.signedByName,
    this.signedByEmail,
    this.signedAt,
    this.signatureIp,
    this.deniedAt,
    this.deniedByName,
    this.deniedByEmail,
    this.denialReason,
    this.approvedAt,
    this.approvedBy,
    this.budgetItemIds = const [],
    this.budgetItemAmounts,
    this.totalAmount = 0.0,
    this.amountPaid = 0.0,
    this.lineItems = const [],
    this.lineItemVisibility = LineItemVisibility.all,
    this.lineItemSourceMode = LineItemSourceMode.snapshot,
    this.attachedPhotoIds = const [],
    this.collectTax = false,
    this.taxName,
    this.taxRate = 0,
    this.taxAmountOverride,
    this.expectedDate,
    this.receivedDate,
    this.shippingCost = 0,
    this.retainagePercent = 0,
    this.retainageAmount = 0,
    this.discountAmount = 0,
    this.vendorId,
    this.sourceDocumentId,
    this.bidPackageId,
    this.paidDate,
    this.paymentMethod,
    this.paymentReference,
    this.paymentAttachmentUrl,
    this.documentNumber,
    this.dueDate,
    this.metadata = const {},
    this.excludeFromBudget = false,
  });

  factory GeneratedDocument.fromJson(Map<String, dynamic> json, String id) {
    return GeneratedDocument(
      id: id,
      workspaceId: json['workspaceId'] as String,
      projectId: json['projectId'] as String?,
      customerId: json['customerId'] as String?,
      customerName: json['customerName'] as String?,
      // templateId can be NULL on documents created without a template
      // (e.g. bid-package RFB clones from create_bid_package RPC). The
      // model field stays non-nullable for backwards compatibility — use
      // empty string as the sentinel for "no template", matching how
      // callers historically guard with isEmpty.
      templateId: json['templateId'] as String? ?? '',
      templateName: json['templateName'] as String? ?? 'Document',
      documentType: DocumentTypeExtension.fromStoredValue(
        json['documentType'] as String?,
      ),
      renderedContent: json['renderedContent'] as String? ?? '',
      pdfUrl: json['pdfUrl'] as String?,
      status: DocumentStatusExtension.fromDbValue(json['status'] as String?),
      createdBy: json['createdBy'] as String,
      createdAt: _parseDateTime(json['createdAt']),
      sentAt: _parseNullableDateTime(json['sentAt']),
      sentTo: json['sentTo'] as String?,
      preparedBy: json['preparedBy'] != null
          ? DocumentContactInfo.fromJson(json['preparedBy'])
          : null,
      preparedFor: json['preparedFor'] != null
          ? DocumentContactInfo.fromJson(json['preparedFor'])
          : null,
      footerContent: json['footerContent'] as String?,
      emailSubject: json['emailSubject'] as String?,
      emailMessage: json['emailMessage'] as String?,
      signatureUrl: json['signatureUrl'] as String?,
      signedByName: json['signedByName'] as String?,
      signedByEmail: json['signedByEmail'] as String?,
      signedAt: _parseNullableDateTime(json['signedAt']),
      signatureIp: json['signatureIp'] as String?,
      deniedAt: _parseNullableDateTime(json['deniedAt']),
      deniedByName: json['deniedByName'] as String?,
      deniedByEmail: json['deniedByEmail'] as String?,
      denialReason: json['denialReason'] as String?,
      approvedAt: _parseNullableDateTime(json['approvedAt']),
      approvedBy: json['approvedBy'] as String?,
      budgetItemIds: _parseStringList(json['budgetItemIds']),
      budgetItemAmounts: _parseDoubleMap(json['budgetItemAmounts']),
      totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0.0,
      amountPaid: (json['amountPaid'] as num?)?.toDouble() ?? 0.0,
      lineItems: _parseLineItems(json['lineItems']),
      lineItemVisibility: LineItemVisibility.fromString(
        json['lineItemVisibility'] as String?,
      ),
      lineItemSourceMode: LineItemSourceMode.fromStoredValue(
        json['lineItemSourceMode'] as String?,
      ),
      attachedPhotoIds: _parseStringList(json['attachedPhotoIds']),
      collectTax: json['collectTax'] as bool? ?? false,
      taxName: json['taxName'] as String?,
      taxRate: (json['taxRate'] as num?)?.toDouble() ?? 0,
      taxAmountOverride: (json['taxAmountOverride'] as num?)?.toDouble(),
      expectedDate: _parseNullableDateTime(json['expectedDate']),
      receivedDate: _parseNullableDateTime(json['receivedDate']),
      shippingCost: (json['shippingCost'] as num?)?.toDouble() ?? 0,
      retainagePercent: (json['retainagePercent'] as num?)?.toDouble() ?? 0,
      retainageAmount: (json['retainageAmount'] as num?)?.toDouble() ?? 0,
      discountAmount: (json['discountAmount'] as num?)?.toDouble() ?? 0,
      vendorId: json['vendorId'] as String?,
      sourceDocumentId: json['sourceDocumentId'] as String?,
      bidPackageId: json['bidPackageId'] as String?,
      paidDate: _parseNullableDateTime(json['paidDate']),
      paymentMethod: json['paymentMethod'] as String?,
      paymentReference: json['paymentReference'] as String?,
      paymentAttachmentUrl: json['paymentAttachmentUrl'] as String?,
      documentNumber: json['documentNumber'] as String?,
      dueDate: _parseNullableDateTime(json['dueDate']),
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : const {},
      excludeFromBudget: json['excludeFromBudget'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'workspaceId': workspaceId,
      'projectId': projectId,
      'customerId': customerId,
      'customerName': customerName,
      'templateId': templateId,
      'templateName': templateName,
      'documentType': documentType.dbValue,
      'renderedContent': renderedContent,
      'pdfUrl': pdfUrl,
      'status': status.dbValue,
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'sentAt': sentAt != null ? Timestamp.fromDate(sentAt!) : null,
      'sentTo': sentTo,
      'preparedBy': preparedBy?.toJson(),
      'preparedFor': preparedFor?.toJson(),
      'footerContent': footerContent,
      'emailSubject': emailSubject,
      'emailMessage': emailMessage,
      'signatureUrl': signatureUrl,
      'signedByName': signedByName,
      'signedByEmail': signedByEmail,
      'signedAt': signedAt != null ? Timestamp.fromDate(signedAt!) : null,
      'signatureIp': signatureIp,
      'deniedAt': deniedAt != null ? Timestamp.fromDate(deniedAt!) : null,
      'deniedByName': deniedByName,
      'deniedByEmail': deniedByEmail,
      'denialReason': denialReason,
      'approvedAt': approvedAt != null ? Timestamp.fromDate(approvedAt!) : null,
      'approvedBy': approvedBy,
      'budgetItemIds': budgetItemIds,
      'budgetItemAmounts': budgetItemAmounts,
      'totalAmount': totalAmount,
      'amountPaid': amountPaid,
      'lineItems': lineItems.map((item) => item.toJson()).toList(),
      'lineItemVisibility': lineItemVisibility.dbValue,
      'lineItemSourceMode': lineItemSourceMode.dbValue,
      'attachedPhotoIds': attachedPhotoIds,
      'collectTax': collectTax,
      'taxName': taxName,
      'taxRate': taxRate,
      'taxAmountOverride': taxAmountOverride,
      'expectedDate':
          expectedDate != null ? Timestamp.fromDate(expectedDate!) : null,
      'receivedDate':
          receivedDate != null ? Timestamp.fromDate(receivedDate!) : null,
      'shippingCost': shippingCost,
      'retainagePercent': retainagePercent,
      'retainageAmount': retainageAmount,
      'discountAmount': discountAmount,
      'vendorId': vendorId,
      'sourceDocumentId': sourceDocumentId,
      'bidPackageId': bidPackageId,
      'paidDate': paidDate != null ? Timestamp.fromDate(paidDate!) : null,
      'paymentMethod': paymentMethod,
      'paymentReference': paymentReference,
      'paymentAttachmentUrl': paymentAttachmentUrl,
      'documentNumber': documentNumber,
      'dueDate': dueDate != null ? Timestamp.fromDate(dueDate!) : null,
      'metadata': metadata,
      'excludeFromBudget': excludeFromBudget,
    };
  }

  String get formattedCreatedAt {
    return DateFormat('MM/dd/yyyy').format(createdAt);
  }

  String get formattedSentAt {
    if (sentAt == null) return '';
    return DateFormat('MM/dd/yyyy').format(sentAt!);
  }

  GeneratedDocument copyWith({
    String? id,
    String? workspaceId,
    String? projectId,
    String? customerId,
    String? customerName,
    String? templateId,
    String? templateName,
    DocumentType? documentType,
    String? renderedContent,
    String? pdfUrl,
    DocumentStatus? status,
    String? createdBy,
    DateTime? createdAt,
    DateTime? sentAt,
    String? sentTo,
    DocumentContactInfo? preparedBy,
    DocumentContactInfo? preparedFor,
    String? footerContent,
    String? emailSubject,
    String? emailMessage,
    String? signatureUrl,
    String? signedByName,
    String? signedByEmail,
    DateTime? signedAt,
    String? signatureIp,
    DateTime? deniedAt,
    String? deniedByName,
    String? deniedByEmail,
    String? denialReason,
    DateTime? approvedAt,
    String? approvedBy,
    List<String>? budgetItemIds,
    Map<String, double>? budgetItemAmounts,
    double? totalAmount,
    double? amountPaid,
    List<DocumentLineItem>? lineItems,
    LineItemVisibility? lineItemVisibility,
    LineItemSourceMode? lineItemSourceMode,
    List<String>? attachedPhotoIds,
    bool? collectTax,
    String? taxName,
    double? taxRate,
    double? taxAmountOverride,
    DateTime? expectedDate,
    DateTime? receivedDate,
    double? shippingCost,
    double? retainagePercent,
    double? retainageAmount,
    double? discountAmount,
    String? vendorId,
    String? sourceDocumentId,
    String? bidPackageId,
    DateTime? paidDate,
    String? paymentMethod,
    String? paymentReference,
    String? paymentAttachmentUrl,
    String? documentNumber,
    DateTime? dueDate,
    Map<String, dynamic>? metadata,
    bool? excludeFromBudget,
  }) {
    return GeneratedDocument(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      projectId: projectId ?? this.projectId,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      templateId: templateId ?? this.templateId,
      templateName: templateName ?? this.templateName,
      documentType: documentType ?? this.documentType,
      renderedContent: renderedContent ?? this.renderedContent,
      pdfUrl: pdfUrl ?? this.pdfUrl,
      status: status ?? this.status,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      sentAt: sentAt ?? this.sentAt,
      sentTo: sentTo ?? this.sentTo,
      preparedBy: preparedBy ?? this.preparedBy,
      preparedFor: preparedFor ?? this.preparedFor,
      footerContent: footerContent ?? this.footerContent,
      emailSubject: emailSubject ?? this.emailSubject,
      emailMessage: emailMessage ?? this.emailMessage,
      signatureUrl: signatureUrl ?? this.signatureUrl,
      signedByName: signedByName ?? this.signedByName,
      signedByEmail: signedByEmail ?? this.signedByEmail,
      signedAt: signedAt ?? this.signedAt,
      signatureIp: signatureIp ?? this.signatureIp,
      deniedAt: deniedAt ?? this.deniedAt,
      deniedByName: deniedByName ?? this.deniedByName,
      deniedByEmail: deniedByEmail ?? this.deniedByEmail,
      denialReason: denialReason ?? this.denialReason,
      approvedAt: approvedAt ?? this.approvedAt,
      approvedBy: approvedBy ?? this.approvedBy,
      budgetItemIds: budgetItemIds ?? this.budgetItemIds,
      budgetItemAmounts: budgetItemAmounts ?? this.budgetItemAmounts,
      totalAmount: totalAmount ?? this.totalAmount,
      amountPaid: amountPaid ?? this.amountPaid,
      lineItems: lineItems ?? this.lineItems,
      lineItemVisibility: lineItemVisibility ?? this.lineItemVisibility,
      lineItemSourceMode: lineItemSourceMode ?? this.lineItemSourceMode,
      attachedPhotoIds: attachedPhotoIds ?? this.attachedPhotoIds,
      collectTax: collectTax ?? this.collectTax,
      taxName: taxName ?? this.taxName,
      taxRate: taxRate ?? this.taxRate,
      taxAmountOverride: taxAmountOverride ?? this.taxAmountOverride,
      expectedDate: expectedDate ?? this.expectedDate,
      receivedDate: receivedDate ?? this.receivedDate,
      shippingCost: shippingCost ?? this.shippingCost,
      retainagePercent: retainagePercent ?? this.retainagePercent,
      retainageAmount: retainageAmount ?? this.retainageAmount,
      discountAmount: discountAmount ?? this.discountAmount,
      vendorId: vendorId ?? this.vendorId,
      sourceDocumentId: sourceDocumentId ?? this.sourceDocumentId,
      bidPackageId: bidPackageId ?? this.bidPackageId,
      paidDate: paidDate ?? this.paidDate,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentReference: paymentReference ?? this.paymentReference,
      paymentAttachmentUrl: paymentAttachmentUrl ?? this.paymentAttachmentUrl,
      documentNumber: documentNumber ?? this.documentNumber,
      dueDate: dueDate ?? this.dueDate,
      metadata: metadata ?? this.metadata,
      excludeFromBudget: excludeFromBudget ?? this.excludeFromBudget,
    );
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    try {
      final dynamic dynamicValue = value;
      final dynamic maybeDate = dynamicValue?.toDate();
      if (maybeDate is DateTime) return maybeDate;
    } catch (_) {
      // Ignore and fallback to now.
    }
    return DateTime.now();
  }

  static DateTime? _parseNullableDateTime(dynamic value) {
    if (value == null) return null;
    return _parseDateTime(value);
  }

  static List<String> _parseStringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((item) => item?.toString())
        .whereType<String>()
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static Map<String, double>? _parseDoubleMap(dynamic value) {
    if (value is! Map) return null;
    final result = <String, double>{};
    value.forEach((key, rawValue) {
      final parsed = rawValue is num
          ? rawValue.toDouble()
          : double.tryParse(rawValue?.toString() ?? '');
      if (parsed != null) {
        result[key.toString()] = parsed;
      }
    });
    return result;
  }

  static List<DocumentLineItem> _parseLineItems(dynamic value) {
    if (value is! List) return const [];
    final items = <DocumentLineItem>[];
    for (final item in value) {
      if (item is Map) {
        items.add(DocumentLineItem.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return items;
  }

  /// Calculate the total from line items
  double get lineItemsTotal {
    return lineItems
        .where((item) => item.isVisible && item.isItem)
        .fold(0.0, (runningTotal, item) => runningTotal + item.total);
  }

  /// Sum of only the taxable visible line items — the base sales tax is
  /// charged on. Equals [lineItemsTotal] when every line is taxable. [M002]
  double get taxableLineItemsTotal {
    return lineItems
        .where((item) => item.isVisible && item.isItem && item.isTaxable)
        .fold(0.0, (runningTotal, item) => runningTotal + item.total);
  }

  /// Canonical sales-tax amount for display AND posting: tax is charged only
  /// on the taxable lines (`Σ taxable × rate`), rounded to cents. Every
  /// surface (PDF, preview, detail, client portal, GL) should use this rather
  /// than recomputing `subtotal × rate`, so the customer-facing tax matches
  /// the books. [M002] Returns 0 when tax isn't collected or no rate is set.
  double get computedTaxAmount {
    if (!collectTax || taxRate <= 0) return 0.0;
    var taxableBase = taxableLineItemsTotal;
    // An invoice-level discount reduces the tax base; with mixed taxability it
    // is apportioned by the taxable share of the subtotal. [M004]
    if (discountAmount > 0 && lineItemsTotal > 0) {
      taxableBase -= discountAmount * (taxableLineItemsTotal / lineItemsTotal);
      if (taxableBase < 0) taxableBase = 0;
    }
    return (taxableBase * (taxRate / 100) * 100).roundToDouble() / 100;
  }

  /// Net invoice total: subtotal − discount + tax. The single source of truth
  /// for the grand total every surface should display/post. [M004]
  double get computedGrandTotal =>
      lineItemsTotal - discountAmount + computedTaxAmount;

  /// Get visible line items based on visibility setting
  List<DocumentLineItem> get visibleLineItems {
    switch (lineItemVisibility) {
      case LineItemVisibility.none:
        return [];
      case LineItemVisibility.topLevel:
        return lineItems
            .where((item) => item.isTopLevel && item.isVisible)
            .toList();
      case LineItemVisibility.all:
        return lineItems.where((item) => item.isVisible).toList();
    }
  }

  static final _dateTimeFormat = DateFormat('MM/dd/yyyy h:mm a');

  String get formattedSignedAt {
    if (signedAt == null) return '';
    return _dateTimeFormat.format(signedAt!.toLocal());
  }

  String get formattedApprovedAt {
    if (approvedAt == null) return '';
    return _dateTimeFormat.format(approvedAt!.toLocal());
  }

  /// Purchase-order lines that track a stockable inventory item (and can
  /// therefore be received).
  List<DocumentLineItem> get receivableLineItems => lineItems
      .where((item) => item.isItem && item.inventoryItemId != null)
      .toList();

  /// Whether this document has any inventory-tracked lines to receive.
  bool get hasReceivableLines => receivableLineItems.isNotEmpty;

  /// Derived fulfillment state for a purchase order, based on per-line
  /// received quantities. Returns null when the PO has no receivable lines.
  PoFulfillment? get fulfillment {
    final lines = receivableLineItems;
    if (lines.isEmpty) return null;
    final anyReceived = lines.any((l) => l.quantityReceived > 0);
    if (!anyReceived) return PoFulfillment.none;
    final allReceived =
        lines.every((l) => l.quantityReceived >= l.quantity);
    return allReceived ? PoFulfillment.received : PoFulfillment.partial;
  }

  bool get isSigned => status == DocumentStatus.signed && signatureUrl != null;

  bool get isApproved => status == DocumentStatus.approved && approvedBy != null && approvedAt != null;

  bool get isDenied => status == DocumentStatus.denied;

  bool get hasChangesRequested => status == DocumentStatus.changesRequested;

  /// Whether this document is in a state where the customer needs to take action.
  bool get needsCustomerAction =>
      status == DocumentStatus.sent || status == DocumentStatus.viewed;
}
