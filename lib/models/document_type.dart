import 'template_category.dart';

/// Document types for templates.
/// Each type belongs to a category and represents a specific document format.
enum DocumentType {
  // Customer Order types
  changeOrder,
  equipmentRental,
  inspectionForm,
  quotation,
  selections,
  serviceAgreement,
  workAuthEmergency,
  workAuthRestoration,
  workAuthServices,
  workOrder,
  workOrderEmergency,
  workOrderMaintenance,

  // Customer Invoice types
  credit,
  deposit,
  invoice,
  progressInvoice,
  refund,
  aiaPayApp,
  aiaContract,

  // Vendor Order types
  purchaseOrder,
  requestForBid,

  // Vendor Bill types
  bill,
  vendorCredit,
  expense,
  vendorRefund,

  // Custom type (user-created)
  custom,
}

/// Columns available for rendering line items in document previews and
/// exports. Each [DocumentType] declares which columns apply.
enum LineItemColumn {
  description,
  quantity,
  unit,
  unitPrice,
  total,
  bidPrice,
  bidTotal,
}

/// How a document type affects budget rollups.
///
/// Single source of truth for "which docs count where" — replaces hardcoded
/// `['invoice', 'progress_invoice', 'bill']` lists scattered across budget
/// queries. Add a new financial document type? Classify it here once and the
/// budget service picks it up everywhere.
enum BudgetImpact {
  /// Customer-facing revenue recognition. Counts toward `invoicedAmount`.
  customerRevenue,

  /// Vendor-facing cost recognition. Counts toward `billedAmount`.
  vendorCost,

  /// Vendor-facing commitment (issued PO, outstanding bid). Counts toward
  /// `committedCost`.
  vendorCommitment,

  /// Tracked via `budget_document_links` only, not via line-item rollups
  /// (e.g. quotes, change orders, work authorizations).
  none,
}

extension DocumentTypeExtension on DocumentType {
  /// PostgreSQL enum value used in Supabase.
  String get dbValue {
    switch (this) {
      case DocumentType.changeOrder:
        return 'change_order';
      case DocumentType.equipmentRental:
        return 'equipment_rental';
      case DocumentType.inspectionForm:
        return 'inspection_form';
      case DocumentType.quotation:
        return 'quotation';
      case DocumentType.selections:
        return 'selections';
      case DocumentType.serviceAgreement:
        return 'service_agreement';
      case DocumentType.workAuthEmergency:
        return 'work_auth_emergency';
      case DocumentType.workAuthRestoration:
        return 'work_auth_restoration';
      case DocumentType.workAuthServices:
        return 'work_auth_services';
      case DocumentType.workOrder:
        return 'work_order';
      case DocumentType.workOrderEmergency:
        return 'work_order_emergency';
      case DocumentType.workOrderMaintenance:
        return 'work_order_maintenance';
      case DocumentType.credit:
        return 'credit';
      case DocumentType.deposit:
        return 'deposit';
      case DocumentType.invoice:
        return 'invoice';
      case DocumentType.progressInvoice:
        return 'progress_invoice';
      case DocumentType.refund:
        return 'refund';
      case DocumentType.aiaPayApp:
        return 'aia_pay_app';
      case DocumentType.aiaContract:
        return 'aia_contract';
      case DocumentType.purchaseOrder:
        return 'purchase_order';
      case DocumentType.requestForBid:
        return 'request_for_bid';
      case DocumentType.bill:
        return 'bill';
      case DocumentType.vendorCredit:
        return 'vendor_credit';
      case DocumentType.expense:
        return 'expense';
      case DocumentType.vendorRefund:
        return 'vendor_refund';
      case DocumentType.custom:
        return 'custom';
    }
  }

  /// Display name for the document type
  String get displayName {
    switch (this) {
      // Customer Order types
      case DocumentType.changeOrder:
        return 'Change Order';
      case DocumentType.equipmentRental:
        return 'Equipment Rental Agreement';
      case DocumentType.inspectionForm:
        return 'Initial Inspection Form';
      case DocumentType.quotation:
        return 'Quotation';
      case DocumentType.selections:
        return 'Selections';
      case DocumentType.serviceAgreement:
        return 'Service Agreement';
      case DocumentType.workAuthEmergency:
        return 'Work Authorization - Emergency';
      case DocumentType.workAuthRestoration:
        return 'Work Authorization - Restoration';
      case DocumentType.workAuthServices:
        return 'Work Authorization - Services & Repairs';
      case DocumentType.workOrder:
        return 'Work Order';
      case DocumentType.workOrderEmergency:
        return 'Work Order - Emergency Service';
      case DocumentType.workOrderMaintenance:
        return 'Work Order - Maintenance';

      // Customer Invoice types
      case DocumentType.credit:
        return 'Credit';
      case DocumentType.deposit:
        return 'Deposit';
      case DocumentType.invoice:
        return 'Invoice';
      case DocumentType.progressInvoice:
        return 'Progress Invoice';
      case DocumentType.refund:
        return 'Refund';
      case DocumentType.aiaPayApp:
        return 'AIA Pay Application (G702/G703)';
      case DocumentType.aiaContract:
        return 'AIA Contract (A101/A102)';

      // Vendor Order types
      case DocumentType.purchaseOrder:
        return 'Purchase Order';
      case DocumentType.requestForBid:
        return 'Request for Bid';

      // Vendor Bill types
      case DocumentType.bill:
        return 'Bill';
      case DocumentType.vendorCredit:
        return 'Credit';
      case DocumentType.expense:
        return 'Expense';
      case DocumentType.vendorRefund:
        return 'Refund';

      case DocumentType.custom:
        return 'Custom';
    }
  }

  /// Icon name for the document type
  String get icon {
    switch (this) {
      case DocumentType.invoice:
      case DocumentType.progressInvoice:
      case DocumentType.aiaPayApp:
        return 'receipt_long';
      case DocumentType.workOrder:
      case DocumentType.workOrderEmergency:
      case DocumentType.workOrderMaintenance:
        return 'assignment';
      case DocumentType.quotation:
        return 'request_quote';
      case DocumentType.expense:
        return 'money_off';
      case DocumentType.bill:
        return 'receipt';
      case DocumentType.purchaseOrder:
        return 'shopping_cart';
      case DocumentType.changeOrder:
        return 'swap_horiz';
      case DocumentType.equipmentRental:
        return 'handyman';
      case DocumentType.inspectionForm:
        return 'checklist';
      case DocumentType.selections:
        return 'checklist_rtl';
      case DocumentType.serviceAgreement:
      case DocumentType.aiaContract:
        return 'handshake';
      case DocumentType.workAuthEmergency:
      case DocumentType.workAuthRestoration:
      case DocumentType.workAuthServices:
        return 'verified_user';
      case DocumentType.credit:
      case DocumentType.vendorCredit:
        return 'credit_card';
      case DocumentType.deposit:
        return 'account_balance_wallet';
      case DocumentType.refund:
      case DocumentType.vendorRefund:
        return 'money_off';
      case DocumentType.requestForBid:
        return 'gavel';
      case DocumentType.custom:
        return 'description';
    }
  }

  /// The category this document type belongs to
  TemplateCategory get category {
    switch (this) {
      // Customer Order types
      case DocumentType.changeOrder:
      case DocumentType.equipmentRental:
      case DocumentType.inspectionForm:
      case DocumentType.quotation:
      case DocumentType.selections:
      case DocumentType.serviceAgreement:
      case DocumentType.workAuthEmergency:
      case DocumentType.workAuthRestoration:
      case DocumentType.workAuthServices:
      case DocumentType.workOrder:
      case DocumentType.workOrderEmergency:
      case DocumentType.workOrderMaintenance:
        return TemplateCategory.customerOrder;

      // Customer Invoice types
      case DocumentType.credit:
      case DocumentType.deposit:
      case DocumentType.invoice:
      case DocumentType.progressInvoice:
      case DocumentType.refund:
      case DocumentType.aiaPayApp:
      case DocumentType.aiaContract:
        return TemplateCategory.customerInvoice;

      // Vendor Order types
      case DocumentType.purchaseOrder:
      case DocumentType.requestForBid:
        return TemplateCategory.vendorOrder;

      // Vendor Bill types
      case DocumentType.bill:
      case DocumentType.vendorCredit:
      case DocumentType.expense:
      case DocumentType.vendorRefund:
        return TemplateCategory.vendorBill;

      // Custom defaults to customer order
      case DocumentType.custom:
        return TemplateCategory.customerOrder;
    }
  }

  /// Whether this document type logically has an expiry / due date.
  bool get hasExpiryDate {
    switch (this) {
      case DocumentType.quotation:
      case DocumentType.invoice:
      case DocumentType.progressInvoice:
      case DocumentType.deposit:
      case DocumentType.serviceAgreement:
      case DocumentType.equipmentRental:
      case DocumentType.requestForBid:
      case DocumentType.bill:
      case DocumentType.purchaseOrder:
      case DocumentType.aiaPayApp:
      case DocumentType.custom:
        return true;
      case DocumentType.changeOrder:
      case DocumentType.inspectionForm:
      case DocumentType.selections:
      case DocumentType.aiaContract:
      case DocumentType.workAuthEmergency:
      case DocumentType.workAuthRestoration:
      case DocumentType.workAuthServices:
      case DocumentType.workOrder:
      case DocumentType.workOrderEmergency:
      case DocumentType.workOrderMaintenance:
      case DocumentType.credit:
      case DocumentType.refund:
      case DocumentType.vendorCredit:
      case DocumentType.expense:
      case DocumentType.vendorRefund:
        return false;
    }
  }

  /// Columns to show in line-item tables for this document type.
  /// Request-for-bid hides the GC's internal price and shows an empty bid
  /// price column for the vendor to fill in.
  List<LineItemColumn> get lineItemColumns {
    switch (this) {
      case DocumentType.requestForBid:
        return const [
          LineItemColumn.description,
          LineItemColumn.quantity,
          LineItemColumn.bidPrice,
          LineItemColumn.bidTotal,
        ];
      default:
        return const [
          LineItemColumn.description,
          LineItemColumn.quantity,
          LineItemColumn.unitPrice,
          LineItemColumn.total,
        ];
    }
  }

  /// Whether vendors will enter per-line bid prices for this document type.
  bool get collectsVendorBidPrice => this == DocumentType.requestForBid;

  /// Whether this document type is issued to / received from a Vendor
  /// (purchase orders, bills, expenses, requests-for-bid, etc.) as opposed
  /// to being addressed to a Customer (invoices, quotations, work orders…).
  /// Drives whether the create-document UI shows a Vendor selector or a
  /// Customer selector for the "prepared for" party.
  bool get isVendorSide {
    switch (category) {
      case TemplateCategory.vendorOrder:
      case TemplateCategory.vendorBill:
        return true;
      case TemplateCategory.customerOrder:
      case TemplateCategory.customerInvoice:
        return false;
    }
  }

  /// Whether this is a payable customer-invoice document the customer settles
  /// against (invoice, progress invoice, AIA pay app, deposit, credit, refund).
  ///
  /// False for [aiaContract], which is filed under the invoice category for
  /// grouping / billing context but is an agreement establishing the contract
  /// sum — not a bill. Gate pay-now routing, holdback/retainage, and
  /// "open invoice" pickers on this instead of a raw
  /// `category == customerInvoice` check.
  bool get isPayableCustomerInvoice =>
      category == TemplateCategory.customerInvoice &&
      this != DocumentType.aiaContract;

  /// How this document type affects budget rollups. See [BudgetImpact].
  BudgetImpact get budgetImpact {
    switch (this) {
      case DocumentType.invoice:
      case DocumentType.progressInvoice:
      case DocumentType.aiaPayApp:
        return BudgetImpact.customerRevenue;
      case DocumentType.bill:
        return BudgetImpact.vendorCost;
      case DocumentType.purchaseOrder:
      case DocumentType.requestForBid:
        return BudgetImpact.vendorCommitment;
      case DocumentType.changeOrder:
      case DocumentType.equipmentRental:
      case DocumentType.inspectionForm:
      case DocumentType.quotation:
      case DocumentType.selections:
      case DocumentType.serviceAgreement:
      case DocumentType.workAuthEmergency:
      case DocumentType.workAuthRestoration:
      case DocumentType.workAuthServices:
      case DocumentType.workOrder:
      case DocumentType.workOrderEmergency:
      case DocumentType.workOrderMaintenance:
      case DocumentType.credit:
      case DocumentType.deposit:
      case DocumentType.refund:
      case DocumentType.aiaContract:
      case DocumentType.vendorCredit:
      case DocumentType.expense:
      case DocumentType.vendorRefund:
      case DocumentType.custom:
        return BudgetImpact.none;
    }
  }

  /// Whether line items imported from the budget should use the budget item's
  /// cost-side unit value instead of the customer-facing unit price.
  bool get usesBudgetUnitCostForLineItems {
    switch (category) {
      case TemplateCategory.vendorOrder:
      case TemplateCategory.vendorBill:
        return true;
      case TemplateCategory.customerOrder:
      case TemplateCategory.customerInvoice:
        return false;
    }
  }

  /// Label for the expiry date field depending on document type.
  String get expiryDateLabel {
    switch (this) {
      case DocumentType.invoice:
      case DocumentType.progressInvoice:
      case DocumentType.aiaPayApp:
      case DocumentType.deposit:
      case DocumentType.bill:
        return 'Due Date';
      case DocumentType.quotation:
      case DocumentType.requestForBid:
        return 'Valid Until';
      case DocumentType.serviceAgreement:
      case DocumentType.equipmentRental:
        return 'End Date';
      default:
        return 'Expiry Date';
    }
  }

  /// Get all document types for a specific category
  static List<DocumentType> forCategory(TemplateCategory category) {
    return DocumentType.values
        .where(
          (type) => type != DocumentType.custom && type.category == category,
        )
        .toList();
  }

  /// Database enum values (snake_case) for all document types with a given
  /// budget impact. Use for `inFilter('document_type', ...)` in budget queries.
  static List<String> dbValuesWithBudgetImpact(BudgetImpact impact) {
    return DocumentType.values
        .where((t) => t.budgetImpact == impact)
        .map((t) => t.dbValue)
        .toList();
  }

  /// Types excluded from default template seeding.
  static const Set<DocumentType> _noDefaultSeed = {
    DocumentType.inspectionForm,
    DocumentType.workAuthEmergency,
  };

  /// Get all document types for a category that should be seeded as defaults.
  static List<DocumentType> forCategoryDefaults(TemplateCategory category) {
    return forCategory(category)
        .where((t) => !_noDefaultSeed.contains(t))
        .toList();
  }

  /// Core templates seeded by default for each workspace.
  static List<DocumentType> get coreDefaults => const [
    DocumentType.quotation,
    DocumentType.changeOrder,
    DocumentType.invoice,
    DocumentType.progressInvoice,
    DocumentType.purchaseOrder,
    DocumentType.requestForBid,
    DocumentType.serviceAgreement,
  ];

  /// Parse either app enum name (camelCase) or DB enum value (snake_case).
  static DocumentType fromStoredValue(String? value) {
    if (value == null || value.isEmpty) return DocumentType.custom;

    for (final type in DocumentType.values) {
      if (type.name == value || type.dbValue == value) {
        return type;
      }
    }
    return DocumentType.custom;
  }
}
