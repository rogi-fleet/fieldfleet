import 'package:cloud_firestore/cloud_firestore.dart';
import 'document_type.dart';
import 'template_category.dart';

class DocumentTemplate {
  final String id;
  final String workspaceId;
  final String name;
  final DocumentType type;
  final String markdownContent;
  final bool isDefault;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  DocumentTemplate({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.type,
    required this.markdownContent,
    this.isDefault = false,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Get the category this template belongs to
  TemplateCategory get category => type.category;

  factory DocumentTemplate.fromJson(Map<String, dynamic> json, String id) {
    return DocumentTemplate(
      id: id,
      workspaceId: json['workspaceId'] as String,
      name: json['name'] as String,
      type: DocumentTypeExtension.fromStoredValue(json['type'] as String?),
      markdownContent: json['markdownContent'] as String? ?? '',
      isDefault: json['isDefault'] as bool? ?? false,
      createdBy: json['createdBy'] as String,
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'workspaceId': workspaceId,
      'name': name,
      'type': type.name,
      'markdownContent': markdownContent,
      'isDefault': isDefault,
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
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

  DocumentTemplate copyWith({
    String? id,
    String? workspaceId,
    String? name,
    DocumentType? type,
    String? markdownContent,
    bool? isDefault,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DocumentTemplate(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      name: name ?? this.name,
      type: type ?? this.type,
      markdownContent: markdownContent ?? this.markdownContent,
      isDefault: isDefault ?? this.isDefault,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Default templates for each document type
  static String getDefaultTemplate(DocumentType type) {
    switch (type) {
      // ============ CUSTOMER ORDER TEMPLATES ============

      case DocumentType.changeOrder:
        return '''# Change Order {{changeOrder.number}}

**{{project_terminology}}:** {{project.name}}
**Original Contract Amount:** \${{contract.originalAmount}}

---

## Change Description

{{changeOrder.description}}

---

{{#if pricing}}## Cost Impact

| Description | Amount |
|-------------|--------|
{{#lineItems}}
| {{description}} | \${{amount}} |
{{/lineItems}}

**Change Order Total:** \${{changeOrder.total}}
**New Contract Total:** \${{contract.newTotal}}

---

{{/if}}## Authorization

**Customer Signature:** ______________________ **Date:** __________

**Contractor Signature:** ______________________ **Date:** __________
''';

      case DocumentType.equipmentRental:
        return '''# Equipment Rental Agreement

**Agreement #:** {{rental.number}}

---

## Equipment Details

| Equipment | Serial # | Daily Rate | Rental Period |
|-----------|----------|------------|---------------|
{{#equipment}}
| {{name}} | {{serialNumber}} | \${{dailyRate}} | {{rentalDays}} days |
{{/equipment}}

**Start Date:** {{rental.startDate}}
**End Date:** {{rental.endDate}}

---

## Total Rental Cost: \${{rental.total}}

---

## Terms & Conditions

1. Lessee agrees to return equipment in same condition
2. Lessee is responsible for any damage during rental period
3. Late returns will incur additional daily charges

---

**Lessee Signature:** ______________________ **Date:** __________
''';

      case DocumentType.inspectionForm:
        return '''# Initial Inspection Form

**Inspection #:** {{inspection.number}}
**{{project_terminology}}:** {{project.name}}

---

## Inspection Checklist

{{#inspectionItems}}
- [ ] {{item}} - {{status}}
  - Notes: {{notes}}
{{/inspectionItems}}

---

## Photos

{{inspection.photoNotes}}

---

## Inspector Notes

{{inspection.notes}}

---

## Summary & Recommendations

{{inspection.recommendations}}

---

**Inspector:** {{inspector.name}}
**Signature:** ______________________ **Date:** __________
''';

      case DocumentType.quotation:
        return '''# Quotation {{quote.number}}

**{{project_terminology}}:** {{project.name}}

---

## Scope

{{quote.description}}

---

## Terms & Conditions

1. This quotation is valid for 30 days from the date above.
2. Payment terms: 50% upfront, 50% upon completion.
3. Work will commence within 5 business days of acceptance.

---

**Accepted By:** ______________________ **Date:** __________
''';

      case DocumentType.selections:
        return '''# Selections Form

**{{project_terminology}}:** {{project.name}}

---

{{#if pricing}}## Selections

{{#categories}}
### {{categoryName}}

| Item | Selection | Price |
|------|-----------|-------|
{{#items}}
| {{itemName}} | {{selection}} | \${{price}} |
{{/items}}

{{/categories}}

---

## Total Selections Value: \${{selections.total}}

---

{{/if}}## Notes

{{selections.notes}}

---

**Customer Approval:** ______________________ **Date:** __________
''';

      case DocumentType.serviceAgreement:
        return '''# Service Agreement

**Agreement #:** {{agreement.number}}

---

## Services

{{agreement.servicesDescription}}

---

{{#if pricing}}## Pricing

| Service | Frequency | Price |
|---------|-----------|-------|
{{#services}}
| {{name}} | {{frequency}} | \${{price}} |
{{/services}}

---

{{/if}}## Terms

**Agreement Duration:** {{agreement.duration}}
**Payment Terms:** {{agreement.paymentTerms}}

---

## Cancellation Policy

{{agreement.cancellationPolicy}}

---

**Customer Signature:** ______________________ **Date:** __________

**Provider Signature:** ______________________ **Date:** __________
''';

      case DocumentType.workAuthEmergency:
        return '''# Work Authorization - Emergency

**Authorization #:** {{auth.number}}
**Time:** {{date.time}}

---

## EMERGENCY SERVICE

---

## Nature of Emergency

{{auth.emergencyDescription}}

---

## Authorized Work

{{auth.workDescription}}

---

## Estimated Cost Range: \${{auth.minEstimate}} - \${{auth.maxEstimate}}

*Final cost may vary based on actual conditions found.*

---

## Authorization

I authorize {{workspace.name}} to perform the emergency work described above.

**Customer Signature:** ______________________ **Date:** __________

**Technician:** {{technician.name}}
''';

      case DocumentType.workAuthRestoration:
        return '''# Work Authorization - Restoration

**Authorization #:** {{auth.number}}

---

## Damage Assessment

{{auth.damageDescription}}

---

## Restoration Scope

{{#restorationItems}}
- {{item}}
{{/restorationItems}}

---

## Estimated Cost: \${{auth.estimate}}

---

## Authorization

I authorize {{workspace.name}} to perform restoration work as described.

**Property Owner Signature:** ______________________ **Date:** __________

**Insurance Adjuster (if applicable):** ______________________ **Date:** __________
''';

      case DocumentType.workAuthServices:
        return '''# Work Authorization - Services & Repairs

**Authorization #:** {{auth.number}}

---

## Work to be Performed

{{auth.workDescription}}

---

## Materials

| Material | Quantity | Cost |
|----------|----------|------|
{{#materials}}
| {{name}} | {{quantity}} | \${{cost}} |
{{/materials}}

---

{{#if pricing}}## Labor: \${{auth.laborCost}}
## Materials Total: \${{auth.materialsTotal}}
## **Total Estimate:** \${{auth.total}}

---

{{/if}}## Authorization

**Customer Signature:** ______________________ **Date:** __________
''';

      case DocumentType.workOrder:
        return '''# Work Order {{workOrder.number}}

**{{project_terminology}}:** {{project.name}}

---

## Work Description

{{workOrder.description}}

---

## Tasks

{{#tasks}}
- [ ] {{name}} - {{description}}
{{/tasks}}

---

## Materials Required

| Item | Quantity | Notes |
|------|----------|-------|
{{#materials}}
| {{name}} | {{quantity}} | {{notes}} |
{{/materials}}

---

## Authorization

**Customer Signature:** ______________________ **Date:** __________

**Technician:** {{assignee.name}}
''';

      case DocumentType.workOrderEmergency:
        return '''# Work Order - Emergency Service

**Work Order #:** {{workOrder.number}}
**Time Received:** {{workOrder.timeReceived}}

---

## PRIORITY: EMERGENCY

---

## Emergency Description

{{workOrder.emergencyDescription}}

---

## Immediate Actions Required

{{#actions}}
- [ ] {{action}}
{{/actions}}

---

## Assigned Technician: {{technician.name}}
## Dispatch Time: {{workOrder.dispatchTime}}

---

## Completion Notes

{{workOrder.completionNotes}}

---

**Technician Signature:** ______________________ **Date:** __________
''';

      case DocumentType.workOrderMaintenance:
        return '''# Work Order - Maintenance

**Work Order #:** {{workOrder.number}}
**Scheduled Date:** {{workOrder.scheduledDate}}
**Equipment/System:** {{equipment.name}}

---

## Maintenance Checklist

{{#maintenanceItems}}
- [ ] {{item}} - {{status}}
{{/maintenanceItems}}

---

## Parts Used

| Part | Quantity |
|------|----------|
{{#parts}}
| {{name}} | {{quantity}} |
{{/parts}}

---

## Technician Notes

{{workOrder.notes}}

---

## Next Scheduled Maintenance: {{workOrder.nextScheduled}}

---

**Technician:** {{technician.name}}
**Signature:** ______________________ **Date:** __________
''';

      // ============ CUSTOMER INVOICE TEMPLATES ============

      case DocumentType.credit:
        return '''# Credit Memo {{credit.number}}

**Original Invoice #:** {{credit.originalInvoice}}

---

{{#if pricing}}## Credit Details

| Description | Amount |
|-------------|--------|
{{#lineItems}}
| {{description}} | \${{amount}} |
{{/lineItems}}

---

**Total Credit:** \${{credit.total}}

---

{{/if}}## Reason for Credit

{{credit.reason}}

---

This credit will be applied to your account.
''';

      case DocumentType.deposit:
        return '''# Deposit Receipt {{deposit.number}}

---

## Deposit Details

**{{project_terminology}}:** {{project.name}}
**Total Contract Amount:** \${{contract.total}}
**Deposit Amount:** \${{deposit.amount}}
**Remaining Balance:** \${{contract.balance}}

---

## Payment Method: {{deposit.paymentMethod}}

---

Thank you for your deposit. Work will commence as scheduled.

---

**Received By:** ______________________ **Date:** __________
''';

      case DocumentType.invoice:
        return '''# Invoice {{invoice.number}}

**{{project_terminology}}:** {{project.name}}
{{#if project.purchaseOrderNumber}}**Purchase Order:** {{project.purchaseOrderNumber}}
{{/if}}
---

{{#if pricing}}## Items

| Description | Qty | Rate | Amount |
|-------------|-----|------|--------|
{{#lineItems}}
| {{description}} | {{quantity}} | \${{rate}} | \${{amount}} |
{{/lineItems}}

---

**Subtotal:** \${{invoice.subtotal}}
**Tax ({{invoice.taxPercent}}%):** \${{invoice.taxAmount}}
**Total:** \${{invoice.total}}

---

{{/if}}### Payment Terms
Payment is due within 30 days of invoice date.

Thank you for your business!
''';

      case DocumentType.progressInvoice:
        return '''# Progress Invoice {{invoice.number}}

**{{project_terminology}}:** {{project.name}}
{{#if project.purchaseOrderNumber}}**Purchase Order:** {{project.purchaseOrderNumber}}
{{/if}}**Billing Period:** {{invoice.billingPeriod}}

---

## Progress Summary

**Total Contract Value:** \${{contract.total}}
**Previous Billings:** \${{invoice.previousBillings}}
**This Invoice:** \${{invoice.currentAmount}}
**Total Billed to Date:** \${{invoice.totalBilled}}
**Remaining:** \${{contract.remaining}}

---

{{#if pricing}}## Work Completed This Period

| Description | % Complete | Amount |
|-------------|------------|--------|
{{#lineItems}}
| {{description}} | {{percentComplete}}% | \${{amount}} |
{{/lineItems}}

---

**Amount Due:** \${{invoice.total}}
**Due Date:** {{invoice.dueDate}}
{{/if}}''';

      case DocumentType.refund:
        return '''# Refund {{refund.number}}

**Original Transaction:** {{refund.originalTransaction}}

---

{{#if pricing}}## Refund Details

| Description | Amount |
|-------------|--------|
{{#lineItems}}
| {{description}} | \${{amount}} |
{{/lineItems}}

---

**Total Refund:** \${{refund.total}}

---

{{/if}}## Refund Method: {{refund.method}}

---

## Reason for Refund

{{refund.reason}}
''';

      // ============ VENDOR ORDER TEMPLATES ============

      case DocumentType.purchaseOrder:
        return '''# Purchase Order {{po.number}}

**Delivery Date:** {{po.deliveryDate}}

---

{{#if pricing}}## Order Details

| Item | Quantity | Unit Price | Total |
|------|----------|------------|-------|
{{#lineItems}}
| {{description}} | {{quantity}} | \${{unitPrice}} | \${{total}} |
{{/lineItems}}

---

**Subtotal:** \${{po.subtotal}}
**Tax:** \${{po.tax}}
**Total:** \${{po.total}}

---

{{/if}}## Shipping Address
{{po.shippingAddress}}

## Notes
{{po.notes}}

---

**Authorized By:** ______________________ **Date:** __________
''';

      case DocumentType.requestForBid:
        return '''# Request for Bid

**RFB #:** {{rfb.number}}
**{{project_terminology}}:** {{project.name}}

---

## Scope of Work

{{rfb.scopeOfWork}}

---

## Requested Pricing

Please enter your bid price for each line item below. Leave blank any items you are not able to quote.

| Description | Qty | Unit | Bid Price | Bid Total |
|-------------|-----|------|-----------|-----------|
{{#lineItems}}
| {{description}} | {{quantity}} | {{unit}} |  |  |
{{/lineItems}}

---

## Requirements

{{#requirements}}
- {{requirement}}
{{/requirements}}

---

## Bid Submission Instructions

Please submit your bid to:
{{workspace.name}}
{{workspace.email}}

Include:
- Timeline
- References
- Insurance certificates

---

**Questions Due By:** {{rfb.questionsDueDate}}
**Contact:** {{rfb.contact}}
''';

      // ============ VENDOR BILL TEMPLATES ============

      case DocumentType.bill:
        return '''# Bill {{bill.number}}

---

{{#if pricing}}## Items

| Description | Amount |
|-------------|--------|
{{#lineItems}}
| {{description}} | \${{amount}} |
{{/lineItems}}

---

**Total:** \${{bill.total}}

---

{{/if}}**Payment Status:** {{bill.status}}
''';

      case DocumentType.vendorCredit:
        return '''# Vendor Credit {{credit.number}}

**Original Bill #:** {{credit.originalBill}}

---

{{#if pricing}}## Credit Details

| Description | Amount |
|-------------|--------|
{{#lineItems}}
| {{description}} | \${{amount}} |
{{/lineItems}}

---

**Total Credit:** \${{credit.total}}

---

{{/if}}## Reason

{{credit.reason}}
''';

      case DocumentType.expense:
        return '''# Expense Report

**Employee:** {{user.name}}
**{{project_terminology}}:** {{project.name}}

---

{{#if pricing}}## Expenses

| Date | Description | Category | Amount |
|------|-------------|----------|--------|
{{#expenses}}
| {{date}} | {{description}} | {{category}} | \${{amount}} |
{{/expenses}}

---

**Total Expenses:** \${{expense.total}}

---

{{/if}}## Approval

**Submitted By:** {{user.name}}
**Approved By:** ______________________
**Date:** __________
''';

      case DocumentType.vendorRefund:
        return '''# Vendor Refund {{refund.number}}

**Original Transaction:** {{refund.originalTransaction}}

---

{{#if pricing}}## Refund Details

| Description | Amount |
|-------------|--------|
{{#lineItems}}
| {{description}} | \${{amount}} |
{{/lineItems}}

---

**Total Refund:** \${{refund.total}}

---

{{/if}}## Reason

{{refund.reason}}
''';

      case DocumentType.aiaPayApp:
        return '''# AIA Pay Application (G702 / G703)

**Project:** {{project.name}}
**Application Number:** {{payApp.number}}
**Application Date:** {{document.date}}
**Period To:** {{payApp.periodTo}}

---

## G702 — Application and Certification for Payment

| | Amount |
|---|---:|
| 1. Original Contract Sum | {{payApp.originalContractSum}} |
| 2. Net Change by Change Orders | {{payApp.netChangeByCO}} |
| 3. Contract Sum to Date (Line 1 + 2) | {{payApp.contractSumToDate}} |
| 4. Total Completed & Stored to Date | {{payApp.totalCompletedAndStored}} |
| 5. Retainage | {{payApp.retainage}} |
| 6. Total Earned Less Retainage | {{payApp.totalEarnedLessRetainage}} |
| 7. Less Previous Certificates for Payment | {{payApp.lessPreviousCertificates}} |
| 8. Current Payment Due | {{payApp.currentPaymentDue}} |
| 9. Balance to Finish, Including Retainage | {{payApp.balanceToFinish}} |

---

## G703 — Continuation Sheet (Schedule of Values)

This document is generated and edited in the dedicated AIA Pay Application
editor. Selecting this template will open that editor so the G702 summary
and G703 schedule-of-values line items stay in sync.
''';

      case DocumentType.aiaContract:
        return '''# AIA Contract (A101 / A102)

**{{project_terminology}}:** {{project.name}}
**Contract Date:** {{date.today}}

---

## Parties

**Owner:** {{customer.name}}
{{customer.address}}

**Contractor:** {{workspace.name}}
{{workspace.address}}

---

## Article 1 — The Work of This Contract

The Contractor shall fully execute the Work described in the Contract Documents for the {{project_terminology}} identified above.

---

{{#if pricing}}## Article 2 — Contract Sum

The Owner shall pay the Contractor the Contract Sum for the Contractor's performance of the Contract.

| Description | Qty | Rate | Amount |
|-------------|-----|------|--------|
{{#lineItems}}
| {{description}} | {{quantity}} | \${{rate}} | \${{amount}} |
{{/lineItems}}

---

**Subtotal:** \${{invoice.subtotal}}
**Tax ({{invoice.taxPercent}}%):** \${{invoice.taxAmount}}
**Contract Sum:** \${{invoice.total}}

---

{{/if}}## Article 3 — Date of Commencement and Substantial Completion

The date of commencement of the Work and the date of Substantial Completion shall be as established in the Contract Documents.

---

## Article 4 — Progress Payments

Progress payments and the final payment shall be made in accordance with AIA G702/G703 Applications for Payment.

---

**Owner Signature:** ______________________ **Date:** __________

**Contractor Signature:** ______________________ **Date:** __________
''';

      case DocumentType.custom:
        return '''# Document Title

---

## Content

Your content here...

---

**Signature:** ______________________ **Date:** __________
''';
    }
  }
}
