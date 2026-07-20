import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/generated_document.dart';
import '../../models/document_template.dart';
import '../../models/document_status.dart';
import '../../models/document_type.dart';
import '../../models/budget_item.dart';
import '../../models/document_line_item.dart';
import '../../utils/document_template_renderer.dart';
import '../../utils/app_logger.dart';
import '../../config/supabase_config.dart';
import 'budget_service.dart';
import 'selection_document_service.dart';
import 'automation_service.dart';
import 'storage_service.dart';
import 'financial_document_number_service.dart';
import 'document_numbering_config_service.dart';

/// A deposit document available for application to an invoice.
class AvailableDeposit {
  final String id;
  final double amount;
  final String? documentNumber;
  final bool isApplied;
  final String? appliedToDocumentId;

  const AvailableDeposit({
    required this.id,
    required this.amount,
    this.documentNumber,
    this.isApplied = false,
    this.appliedToDocumentId,
  });
}

/// Summary of invoicing progress for a project.
class ProjectInvoiceSummary {
  final double approvedAmount;
  final double previouslyInvoiced;
  final List<AvailableDeposit> deposits;

  const ProjectInvoiceSummary({
    required this.approvedAmount,
    required this.previouslyInvoiced,
    this.deposits = const [],
  });
}

class _DocumentBudgetLinkEntry {
  final String budgetItemId;
  final double amount;
  final String source;

  const _DocumentBudgetLinkEntry({
    required this.budgetItemId,
    required this.amount,
    required this.source,
  });
}

class _DocumentBudgetLinkPayload {
  final List<_DocumentBudgetLinkEntry> entries;

  const _DocumentBudgetLinkPayload(this.entries);

  List<String> get budgetItemIds =>
      entries.map((entry) => entry.budgetItemId).toList();

  Map<String, double>? get budgetItemAmounts {
    if (entries.isEmpty) return null;
    return {for (final entry in entries) entry.budgetItemId: entry.amount};
  }
}

/// Supabase implementation of DocumentService
class SupabaseDocumentService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final SupabaseBudgetService _budgetService = SupabaseBudgetService();
  final SupabaseStorageService _storageService = SupabaseStorageService();

  _DocumentBudgetLinkPayload _buildBudgetLinkPayload({
    List<BudgetItem>? budgetItems,
    Map<String, double>? budgetItemAmounts,
    List<DocumentLineItem>? lineItems,
  }) {
    final entries = <_DocumentBudgetLinkEntry>[];
    final selectedBudgetIds = <String>{};
    final manualAmounts = <String, double>{};

    if (budgetItems != null) {
      for (final item in budgetItems) {
        final amount = budgetItemAmounts?[item.id] ?? item.approvedPrice;
        entries.add(
          _DocumentBudgetLinkEntry(
            budgetItemId: item.id,
            amount: amount,
            source: 'from_budget_selection',
          ),
        );
        selectedBudgetIds.add(item.id);
      }
    }

    if (lineItems != null) {
      for (final item in lineItems) {
        final budgetItemId = item.budgetItemId;
        if (budgetItemId == null ||
            !item.isItem ||
            selectedBudgetIds.contains(budgetItemId)) {
          continue;
        }
        manualAmounts[budgetItemId] =
            (manualAmounts[budgetItemId] ?? 0.0) + item.total;
      }
    }

    manualAmounts.forEach((budgetItemId, amount) {
      entries.add(
        _DocumentBudgetLinkEntry(
          budgetItemId: budgetItemId,
          amount: amount,
          source: 'manual',
        ),
      );
    });

    return _DocumentBudgetLinkPayload(entries);
  }

  List<DocumentLineItem> _parseDocumentLineItems(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map(
          (item) => DocumentLineItem.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> _resolveDocumentAssetUrls(
    Map<String, dynamic> row,
  ) async {
    final resolved = Map<String, dynamic>.from(row);
    resolved['signature_url'] = await _storageService.resolveStorageUrl(
      row['signature_url'] as String?,
    );
    return resolved;
  }

  double _calculateDocumentSubtotal({
    List<DocumentLineItem>? lineItems,
    List<BudgetItem>? budgetItems,
    Map<String, double>? budgetItemAmounts,
  }) {
    if (lineItems != null && lineItems.isNotEmpty) {
      return lineItems
          .where((item) => item.isItem && item.isVisible)
          .fold(0.0, (sum, item) => sum + item.total);
    }

    if (budgetItems != null && budgetItems.isNotEmpty) {
      return budgetItems.fold(
        0.0,
        (total, item) =>
            total + (budgetItemAmounts?[item.id] ?? item.approvedPrice),
      );
    }

    if (budgetItemAmounts != null && budgetItemAmounts.isNotEmpty) {
      return budgetItemAmounts.values.fold(0.0, (sum, amount) => sum + amount);
    }

    return 0.0;
  }

  /// Subtotal of only the taxable inputs — sales tax is charged on this, not
  /// the full subtotal, so non-taxable lines (per-line `isTaxable`) are
  /// excluded from the tax base. Falls back to "all taxable" for the
  /// amounts-only path which carries no taxability info. [M002]
  double _calculateTaxableSubtotal({
    List<DocumentLineItem>? lineItems,
    List<BudgetItem>? budgetItems,
    Map<String, double>? budgetItemAmounts,
  }) {
    if (lineItems != null && lineItems.isNotEmpty) {
      return lineItems
          .where((item) => item.isItem && item.isVisible && item.isTaxable)
          .fold(0.0, (sum, item) => sum + item.total);
    }

    if (budgetItems != null && budgetItems.isNotEmpty) {
      return budgetItems
          .where((item) => item.isTaxable)
          .fold(
            0.0,
            (total, item) =>
                total + (budgetItemAmounts?[item.id] ?? item.approvedPrice),
          );
    }

    if (budgetItemAmounts != null && budgetItemAmounts.isNotEmpty) {
      return budgetItemAmounts.values.fold(0.0, (sum, amount) => sum + amount);
    }

    return 0.0;
  }

  double _calculateDocumentTotal({
    List<DocumentLineItem>? lineItems,
    List<BudgetItem>? budgetItems,
    Map<String, double>? budgetItemAmounts,
    required bool collectTax,
    required double taxRate,
    double shippingCost = 0,
    double discountAmount = 0,
    double? taxAmountOverride,
  }) {
    final subtotal = _calculateDocumentSubtotal(
      lineItems: lineItems,
      budgetItems: budgetItems,
      budgetItemAmounts: budgetItemAmounts,
    );

    // A flat tax amount (e.g. on purchase orders migrated from the legacy
    // inventory PO system) takes precedence over the percent-based rate.
    final double tax;
    if (taxAmountOverride != null) {
      tax = taxAmountOverride;
    } else if (!collectTax || taxRate <= 0) {
      tax = 0;
    } else {
      // Charge tax only on the taxable lines (per-line is_taxable). [M002]
      var taxableSubtotal = _calculateTaxableSubtotal(
        lineItems: lineItems,
        budgetItems: budgetItems,
        budgetItemAmounts: budgetItemAmounts,
      );
      // A pre-tax discount shrinks the taxable base, apportioned by the
      // taxable share of the subtotal. [M004]
      if (discountAmount > 0 && subtotal > 0) {
        taxableSubtotal -= discountAmount * (taxableSubtotal / subtotal);
        if (taxableSubtotal < 0) taxableSubtotal = 0;
      }
      tax = taxableSubtotal * (taxRate / 100);
    }

    return subtotal - discountAmount + tax + shippingCost;
  }

  bool _isBudgetSyncedChangeOrder(GeneratedDocument document) =>
      document.documentType == DocumentType.changeOrder &&
      (document.status == DocumentStatus.approved ||
          document.status == DocumentStatus.signed);

  /// Reconcile a change-order document's status with the budget items it has
  /// generated. Called any time a CO's status or line items change:
  ///
  /// - Approved / signed → upsert the CO's group + child budget items so the
  ///   budget rolls up the new scope.
  /// - Any other status (draft, sent, denied, withdrawn, …) → remove any
  ///   budget items left over from a previous approval, so the budget can't
  ///   keep counting scope the customer has since declined.
  ///
  /// Non-CO documents are a no-op. Both branches are idempotent so callers
  /// can fire-and-forget after every status transition.
  Future<void> _syncChangeOrderBudgetIfNeededById(String documentId) async {
    final document = await getDocument(documentId);
    if (document == null) return;
    if (document.documentType != DocumentType.changeOrder) return;
    if (_isBudgetSyncedChangeOrder(document)) {
      await _budgetService.applyChangeOrderToBudget(document);
    } else {
      await _budgetService.removeChangeOrderBudgetItems(documentId);
    }
  }

  /// Freeze the approved snapshot (quantity, unit price, total) on every
  /// budget item linked to this document that has not yet been approved.
  /// Idempotent: items already approved (from an earlier document) keep their
  /// original snapshot — the first approval is the contract. The RPC runs
  /// the read and the update in a single statement so concurrent approvals
  /// cannot clobber each other's snapshot.
  Future<void> _snapshotApprovedBudgetItems(String documentId) async {
    await _supabase.rpc(
      'snapshot_approved_budget_items',
      params: {'p_document_id': documentId},
    );
  }

  Future<void> _logDocumentActivity({
    required String documentId,
    required String action,
    String? actorName,
    String? actorEmail,
    required String actorType,
    Map<String, dynamic>? details,
    String? ipAddress,
  }) async {
    try {
      final documentRow = await _supabase
          .from('generated_documents')
          .select('workspace_id')
          .eq('id', documentId)
          .maybeSingle();
      if (documentRow == null) return;

      await _supabase.from('document_activity_log').insert({
        'workspace_id': documentRow['workspace_id'],
        'document_id': documentId,
        'action': action,
        'actor_name': actorName,
        'actor_email': actorEmail,
        'actor_type': actorType,
        'details': details ?? const <String, dynamic>{},
        'ip_address': ipAddress,
      });
    } catch (e) {
      AppLogger.warning(
        'Failed to log document activity',
        metadata: {
          'documentId': documentId,
          'action': action,
          'actorType': actorType,
          'error': e.toString(),
        },
      );
    }
  }

  Future<void> _syncBudgetLinksForDocument({
    required String documentId,
    required _DocumentBudgetLinkPayload payload,
  }) async {
    final entries = payload.entries
        .map(
          (entry) => <String, dynamic>{
            'budget_item_id': entry.budgetItemId,
            'amount': entry.amount,
            'source': entry.source,
          },
        )
        .toList(growable: false);

    await _supabase.rpc(
      'sync_budget_document_links',
      params: {
        'p_document_id': documentId,
        'p_entries': entries,
      },
    );
  }

  /// Get all generated documents for a workspace.
  ///
  /// When filters beyond workspace are provided, uses a SQL query to avoid
  /// transferring the entire document set to the client.  The stream still
  /// provides real-time updates via the Supabase realtime subscription on
  /// `workspace_id`.
  Stream<List<GeneratedDocument>> getDocuments(
    String workspaceId, {
    String? projectId,
    String? customerId,
    DocumentStatus? status,
    DocumentType? documentType,
    int? limit,
  }) {
    final hasFilters =
        projectId != null ||
        customerId != null ||
        status != null ||
        documentType != null;

    if (!hasFilters && limit == null) {
      // No extra filters — use real-time stream as-is.
      return _supabase
          .from('generated_documents')
          .stream(primaryKey: ['id'])
          .eq('workspace_id', workspaceId)
          .order('created_at', ascending: false)
          .map((data) => data.map((row) => _toGeneratedDocument(row)).toList());
    }

    // With filters or limit: build a SQL query for efficient server-side
    // filtering, then re-emit whenever the underlying workspace stream changes.
    return _supabase
        .from('generated_documents')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .asyncMap((_) async {
          var query = _supabase
              .from('generated_documents')
              .select()
              .eq('workspace_id', workspaceId);
          if (projectId != null) {
            query = query.eq('project_id', projectId);
          }
          if (customerId != null) {
            query = query.eq('customer_id', customerId);
          }
          if (status != null) {
            query = query.eq('status', status.dbValue);
          }
          if (documentType != null) {
            query = query.eq('document_type', documentType.dbValue);
          }
          final ordered = query.order('created_at', ascending: false);
          final data = limit != null
              ? await ordered.limit(limit)
              : await ordered;
          return (data as List)
              .map((row) => _toGeneratedDocument(row as Map<String, dynamic>))
              .toList();
        });
  }

  /// One-shot snapshot of [getDocuments] — a plain select with no realtime
  /// channel. Use when a view needs the documents once (e.g. the financials
  /// workflow canvas): taking `.first` of the realtime stream makes the
  /// fetch depend on a websocket join that can fail or stall on flaky
  /// connections.
  Future<List<GeneratedDocument>> getDocumentsOnce(
    String workspaceId, {
    String? projectId,
  }) async {
    var query = _supabase
        .from('generated_documents')
        .select()
        .eq('workspace_id', workspaceId);
    if (projectId != null) {
      query = query.eq('project_id', projectId);
    }
    final data = await query.order('created_at', ascending: false);
    return (data as List)
        .map((row) => _toGeneratedDocument(row as Map<String, dynamic>))
        .toList();
  }

  /// Get a single document
  Future<GeneratedDocument?> getDocument(String documentId) async {
    try {
      final response = await _supabase
          .from('generated_documents')
          .select()
          .eq('id', documentId)
          .maybeSingle();

      if (response == null) return null;
      return _toGeneratedDocument(await _resolveDocumentAssetUrls(response));
    } catch (e) {
      throw Exception('Error fetching document: $e');
    }
  }

  /// Get documents derived from a source document
  Future<List<GeneratedDocument>> getDocumentsBySourceId(
    String sourceDocumentId,
  ) async {
    try {
      final response = await _supabase
          .from('generated_documents')
          .select()
          .eq('source_document_id', sourceDocumentId)
          .order('created_at');
      final resolvedRows = await Future.wait(
        response.map(
          (row) => _resolveDocumentAssetUrls(Map<String, dynamic>.from(row)),
        ),
      );
      return resolvedRows.map(_toGeneratedDocument).toList();
    } catch (e) {
      throw Exception('Error fetching derived documents: $e');
    }
  }

  /// Generate a document from a template
  Future<GeneratedDocument> generateDocument({
    required String workspaceId,
    required DocumentTemplate template,
    required Map<String, dynamic> context,
    String? projectId,
    String? customerId,
    String? customerName,
    required String createdBy,
    DateTime? documentDate,
    DateTime? dueDate,
    DocumentContactInfo? preparedBy,
    DocumentContactInfo? preparedFor,
    String? footerContent,
    String? emailSubject,
    String? emailMessage,
    List<BudgetItem>? budgetItems,
    Map<String, double>? budgetItemAmounts,
    List<DocumentLineItem>? lineItems,
    LineItemVisibility? lineItemVisibility,
    LineItemSourceMode? lineItemSourceMode,
    List<String>? attachedPhotoIds,
    bool collectTax = false,
    String? taxName,
    double taxRate = 0,
    String? vendorId,
    String? sourceDocumentId,
    double? retainagePercent,
    double? retainageAmount,
    double discountAmount = 0,
  }) async {
    try {
      final enrichedContext = Map<String, dynamic>.from(context);
      final budgetLinkPayload = _buildBudgetLinkPayload(
        budgetItems: budgetItems,
        budgetItemAmounts: budgetItemAmounts,
        lineItems: lineItems,
      );

      // Budget links require a project. Resolve it before creating the
      // document row so a missing project fails fast instead of leaving a
      // dangling document whose budget-link sync will later reject.
      if (budgetLinkPayload.entries.isNotEmpty &&
          projectId == null &&
          (budgetItems?.first.projectId == null)) {
        throw Exception(
          'Cannot create document with budget links without a project',
        );
      }

      if (budgetItems != null && budgetItems.isNotEmpty) {
        enrichedContext['budgetItems'] = budgetItems.map((item) {
          final amount = budgetItemAmounts?[item.id] ?? item.approvedPrice;
          return {
            'id': item.id,
            'name': item.name,
            'description': item.description ?? '',
            'approvedPrice': item.approvedPrice.toStringAsFixed(2),
            'projectedCost': item.projectedCost.toStringAsFixed(2),
            'amount': amount.toStringAsFixed(2),
            'level': item.hierarchyLevel,
          };
        }).toList();

        double totalAmount = 0;
        double totalApproved = 0;
        double totalProjected = 0;
        for (final item in budgetItems) {
          totalAmount += budgetItemAmounts?[item.id] ?? item.approvedPrice;
          totalApproved += item.approvedPrice;
          totalProjected += item.projectedCost;
        }
        enrichedContext['budget'] = {
          'totalAmount': totalAmount.toStringAsFixed(2),
          'totalApproved': totalApproved.toStringAsFixed(2),
          'totalProjected': totalProjected.toStringAsFixed(2),
          'itemCount': budgetItems.length.toString(),
        };
      }

      final renderedContent = DocumentTemplateRenderer.render(
        template.markdownContent,
        enrichedContext,
      );
      final now = documentDate ?? DateTime.now();

      // Denormalized customer_name drives every list row ("(no customer)"
      // otherwise) — callers that pass only customerId get it resolved here
      // so no creation path can skip it.
      if ((customerName == null || customerName.trim().isEmpty) &&
          customerId != null) {
        try {
          final c = await _supabase
              .from('customers')
              .select('company_name, contacts:customer_contacts(name, is_primary, is_active)')
              .eq('id', customerId)
              .maybeSingle();
          if (c != null) {
            final company = (c['company_name'] as String?)?.trim();
            String? contactName;
            final contacts = (c['contacts'] as List?) ?? const [];
            for (final raw in contacts) {
              final m = Map<String, dynamic>.from(raw as Map);
              if (m['is_active'] == false) continue;
              contactName ??= (m['name'] as String?)?.trim();
              if (m['is_primary'] == true) {
                contactName = (m['name'] as String?)?.trim();
                break;
              }
            }
            customerName = (company != null && company.isNotEmpty)
                ? company
                : contactName;
          }
        } catch (_) {
          // Best-effort enrichment; the document still saves without it.
        }
      }

      final documentData = {
        'workspace_id': workspaceId,
        'project_id': projectId,
        'customer_id': customerId,
        'customer_name': customerName,
        'template_id': template.id,
        'template_name': template.name,
        'document_type': template.type.dbValue,
        'rendered_content': renderedContent,
        'status': DocumentStatus.pending.name,
        'created_by': createdBy,
        'created_at': now.toIso8601String(),
        'due_date': dueDate?.toIso8601String(),
        'prepared_by': preparedBy?.toJson(),
        'prepared_for': preparedFor?.toJson(),
        'footer_content': footerContent,
        'email_subject': emailSubject,
        'email_message': emailMessage,
        'budget_item_ids': budgetLinkPayload.budgetItemIds,
        'budget_item_amounts': budgetLinkPayload.budgetItemAmounts,
        'total_amount': _calculateDocumentTotal(
          lineItems: lineItems,
          budgetItems: budgetItems,
          budgetItemAmounts: budgetItemAmounts,
          collectTax: collectTax,
          taxRate: taxRate,
          discountAmount: discountAmount,
        ),
        'line_items': lineItems?.map((i) => i.toJson()).toList() ?? [],
        'line_item_visibility':
            (lineItemVisibility ?? LineItemVisibility.all).dbValue,
        'line_item_source_mode':
            (lineItemSourceMode ?? LineItemSourceMode.snapshot).dbValue,
        'attached_photo_ids': attachedPhotoIds ?? [],
        'collect_tax': collectTax,
        'tax_name': taxName,
        'tax_rate': taxRate,
        'discount_amount': discountAmount,
        if (vendorId != null) 'vendor_id': vendorId,
        if (sourceDocumentId != null) 'source_document_id': sourceDocumentId,
        if (retainagePercent != null) 'retainage_percent': retainagePercent,
        if (retainageAmount != null) 'retainage_amount': retainageAmount,
      };

      final response = await _supabase
          .from('generated_documents')
          .insert(documentData)
          .select()
          .single();

      // Auto-generate document number if the type has a prefix mapping.
      final docTypeDbValue = template.type.dbValue;
      if (SupabaseFinancialDocumentNumberService.prefixes.containsKey(
        docTypeDbValue,
      )) {
        try {
          final numberService = SupabaseFinancialDocumentNumberService();
          final configService = SupabaseDocumentNumberingConfigService();
          final config = await configService.getConfig(
            workspaceId,
            docTypeDbValue,
          );
          final docNumber = await numberService.generateDocumentNumber(
            workspaceId: workspaceId,
            documentType: docTypeDbValue,
            config: config,
          );
          await _supabase
              .from('generated_documents')
              .update({'document_number': docNumber})
              .eq('id', response['id']);
          response['document_number'] = docNumber;
        } catch (e) {
          AppLogger.warning('Failed to auto-generate document number: $e');
        }
      }

      // Normalized links table for generated_documents <-> budget_items.
      // The RPC resolves workspace and project from the document row.
      if (budgetLinkPayload.entries.isNotEmpty) {
        await _syncBudgetLinksForDocument(
          documentId: response['id'] as String,
          payload: budgetLinkPayload,
        );
      }

      return _toGeneratedDocument(response);
    } catch (e) {
      throw Exception('Error generating document: $e');
    }
  }

  /// Update document content and fields
  Future<void> updateDocument({
    required String documentId,
    String? renderedContent,
    String? projectId,
    bool clearProjectId = false,
    String? customerId,
    bool clearCustomerId = false,
    String? customerName,
    bool clearCustomerName = false,
    String? templateId,
    String? templateName,
    DocumentType? documentType,
    DocumentStatus? status,
    String? pdfUrl,
    bool? excludeFromBudget,
    DateTime? documentDate,
    DateTime? dueDate,
    bool clearDueDate = false,
    List<DocumentLineItem>? lineItems,
    LineItemVisibility? lineItemVisibility,
    LineItemSourceMode? lineItemSourceMode,
    DocumentContactInfo? preparedBy,
    DocumentContactInfo? preparedFor,
    String? footerContent,
    String? emailSubject,
    String? emailMessage,
    bool? collectTax,
    String? taxName,
    double? taxRate,
    List<BudgetItem>? budgetItems,
    Map<String, double>? budgetItemAmounts,
    List<String>? attachedPhotoIds,
    String? vendorId,
    bool clearVendorId = false,
    String? sourceDocumentId,
    bool clearSourceDocumentId = false,
    DateTime? paidDate,
    bool clearPaidDate = false,
    double? amountPaid,
    String? paymentMethod,
    String? paymentReference,
    String? paymentAttachmentUrl,
    bool clearPaymentFields = false,
    double? retainagePercent,
    double? retainageAmount,
    bool clearRetainage = false,
    double? discountAmount,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (discountAmount != null) {
        updates['discount_amount'] = discountAmount;
      }
      if (clearRetainage) {
        updates['retainage_percent'] = 0;
        updates['retainage_amount'] = 0;
      } else {
        if (retainagePercent != null) {
          updates['retainage_percent'] = retainagePercent;
        }
        if (retainageAmount != null) {
          updates['retainage_amount'] = retainageAmount;
        }
      }
      _DocumentBudgetLinkPayload? budgetLinkPayload;

      if (renderedContent != null) {
        updates['rendered_content'] = renderedContent;
      }
      if (projectId != null) {
        updates['project_id'] = projectId;
      } else if (clearProjectId) {
        updates['project_id'] = null;
      }
      if (customerId != null) {
        updates['customer_id'] = customerId;
      } else if (clearCustomerId) {
        updates['customer_id'] = null;
      }
      if (customerName != null) {
        updates['customer_name'] = customerName;
      } else if (clearCustomerName) {
        updates['customer_name'] = null;
      }
      if (templateId != null) {
        updates['template_id'] = templateId;
      }
      if (templateName != null) {
        updates['template_name'] = templateName;
      }
      if (documentType != null) {
        updates['document_type'] = documentType.dbValue;
      }
      if (status != null) {
        updates['status'] = status.dbValue;
      }
      if (pdfUrl != null) {
        updates['pdf_url'] = pdfUrl;
      }
      if (excludeFromBudget != null) {
        updates['exclude_from_budget'] = excludeFromBudget;
      }
      if (documentDate != null) {
        updates['created_at'] = documentDate.toIso8601String();
      }
      if (dueDate != null) {
        updates['due_date'] = dueDate.toIso8601String();
      } else if (clearDueDate) {
        updates['due_date'] = null;
      }
      if (lineItems != null || budgetItems != null) {
        budgetLinkPayload = _buildBudgetLinkPayload(
          budgetItems: budgetItems,
          budgetItemAmounts: budgetItemAmounts,
          lineItems: lineItems,
        );
      }
      if (lineItems != null) {
        updates['line_items'] = lineItems.map((i) => i.toJson()).toList();
      }
      if (budgetLinkPayload != null) {
        updates['budget_item_ids'] = budgetLinkPayload.budgetItemIds;
        updates['budget_item_amounts'] = budgetLinkPayload.budgetItemAmounts;
      }
      if (lineItemVisibility != null) {
        updates['line_item_visibility'] = lineItemVisibility.dbValue;
      }
      if (lineItemSourceMode != null) {
        updates['line_item_source_mode'] = lineItemSourceMode.dbValue;
      }
      if (preparedBy != null) {
        updates['prepared_by'] = preparedBy.toJson();
      }
      if (preparedFor != null) {
        updates['prepared_for'] = preparedFor.toJson();
      }
      if (footerContent != null) {
        updates['footer_content'] = footerContent;
      }
      if (emailSubject != null) {
        updates['email_subject'] = emailSubject;
      }
      if (emailMessage != null) {
        updates['email_message'] = emailMessage;
      }
      if (collectTax != null) {
        updates['collect_tax'] = collectTax;
      }
      if (taxName != null) {
        updates['tax_name'] = taxName;
      }
      if (taxRate != null) {
        updates['tax_rate'] = taxRate;
      }
      if (lineItems != null ||
          budgetItems != null ||
          collectTax != null ||
          taxRate != null ||
          discountAmount != null) {
        List<DocumentLineItem>? effectiveLineItems = lineItems;
        Map<String, double>? effectiveBudgetItemAmounts = budgetItemAmounts;
        var effectiveCollectTax = collectTax;
        var effectiveTaxRate = taxRate;
        var effectiveDiscount = discountAmount;

        if (effectiveLineItems == null ||
            effectiveCollectTax == null ||
            effectiveTaxRate == null ||
            effectiveDiscount == null) {
          final existingRow = await _supabase
              .from('generated_documents')
              .select(
                'line_items, budget_item_ids, budget_item_amounts, collect_tax, tax_rate, discount_amount',
              )
              .eq('id', documentId)
              .single();

          effectiveLineItems ??= _parseDocumentLineItems(
            existingRow['line_items'],
          );
          effectiveBudgetItemAmounts ??=
              (existingRow['budget_item_amounts'] as Map<String, dynamic>?)
                  ?.map(
                    (key, value) => MapEntry(key, (value as num).toDouble()),
                  );
          effectiveCollectTax ??= existingRow['collect_tax'] as bool? ?? false;
          effectiveTaxRate ??=
              (existingRow['tax_rate'] as num?)?.toDouble() ?? 0.0;
          effectiveDiscount ??=
              (existingRow['discount_amount'] as num?)?.toDouble() ?? 0.0;
        }

        updates['total_amount'] = _calculateDocumentTotal(
          lineItems: effectiveLineItems,
          budgetItems: budgetItems,
          budgetItemAmounts: effectiveBudgetItemAmounts,
          collectTax: effectiveCollectTax,
          taxRate: effectiveTaxRate,
          discountAmount: effectiveDiscount,
        );
      }
      if (attachedPhotoIds != null) {
        updates['attached_photo_ids'] = attachedPhotoIds;
      }
      if (vendorId != null) {
        updates['vendor_id'] = vendorId;
      } else if (clearVendorId) {
        updates['vendor_id'] = null;
      }
      if (sourceDocumentId != null) {
        updates['source_document_id'] = sourceDocumentId;
      } else if (clearSourceDocumentId) {
        updates['source_document_id'] = null;
      }
      if (paidDate != null) {
        updates['paid_date'] = paidDate.toIso8601String();
      } else if (clearPaidDate) {
        updates['paid_date'] = null;
      }
      if (amountPaid != null) {
        updates['amount_paid'] = amountPaid;
      }
      if (paymentMethod != null) {
        updates['payment_method'] = paymentMethod;
      }
      if (paymentReference != null) {
        updates['payment_reference'] = paymentReference;
      }
      if (paymentAttachmentUrl != null) {
        updates['payment_attachment_url'] = paymentAttachmentUrl;
      }
      if (clearPaymentFields) {
        updates['payment_method'] = null;
        updates['payment_reference'] = null;
        updates['payment_attachment_url'] = null;
      }

      if (updates.isNotEmpty) {
        await _supabase
            .from('generated_documents')
            .update(updates)
            .eq('id', documentId);
      }

      if (budgetLinkPayload != null) {
        await _syncBudgetLinksForDocument(
          documentId: documentId,
          payload: budgetLinkPayload,
        );
      }

      if (lineItems != null) {
        try {
          await _syncChangeOrderBudgetIfNeededById(documentId);
        } catch (e) {
          AppLogger.warning(
            'Updated document but failed to sync change order budget',
            metadata: {'documentId': documentId, 'error': e.toString()},
          );
        }
      }
    } catch (e) {
      throw Exception('Error updating document: $e');
    }
  }

  /// Send document via email
  Future<void> sendDocument({
    required String documentId,
    required String email,
    String? subject,
    String? message,
    bool requireSignature = true,
  }) async {
    try {
      final document = await getDocument(documentId);
      if (document == null) {
        throw Exception('Document not found');
      }
      final normalizedEmail = email.trim().toLowerCase();

      final accessToken =
          _supabase.auth.currentSession?.accessToken ??
          (await _supabase.auth.refreshSession()).session?.accessToken;
      if (accessToken == null) {
        throw Exception('User must be authenticated to send documents');
      }

      final effectiveSubject = (subject != null && subject.trim().isNotEmpty)
          ? subject.trim()
          : (document.emailSubject ?? 'Document for your signature');
      final effectiveMessage = (message != null && message.trim().isNotEmpty)
          ? message.trim()
          : (document.emailMessage ??
                'Please review and sign the attached document at your earliest convenience.');

      final edgeFunctionUrl =
          '${SupabaseConfig.url}/functions/v1/send-document-email';

      final emailResponse = await http.post(
        Uri.parse(edgeFunctionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
          'apikey': SupabaseConfig.anonKey,
        },
        body: jsonEncode({
          'documentId': documentId,
          'recipientEmail': normalizedEmail,
          'subject': effectiveSubject,
          'message': effectiveMessage,
          'documentTitle': document.templateName,
          'requireSignature': requireSignature,
        }),
      );

      if (emailResponse.statusCode != 200) {
        throw Exception(
          'Email sending failed (${emailResponse.statusCode}): ${emailResponse.body}',
        );
      }

      // Both metadata and status updates are guarded against an in-flight
      // sign/approve: if the doc has already advanced past `sent`, neither
      // write lands, preventing stale send metadata from clobbering an
      // approved record.
      final terminalStatuses =
          '(${DocumentStatus.signed.name},${DocumentStatus.approved.name})';
      await _supabase
          .from('generated_documents')
          .update({
            'sent_at': DateTime.now().toIso8601String(),
            'sent_to': normalizedEmail,
            'email_subject': effectiveSubject,
            'email_message': effectiveMessage,
          })
          .eq('id', documentId)
          .not('status', 'in', terminalStatuses);

      await _supabase
          .from('generated_documents')
          .update({'status': DocumentStatus.sent.name})
          .eq('id', documentId)
          .not('status', 'in', terminalStatuses);
    } catch (e) {
      throw Exception('Error sending document: $e');
    }
  }

  /// Approve a document (internal approval by workspace member).
  Future<void> approveDocument({
    required String documentId,
    required String approvedBy,
  }) async {
    try {
      await _supabase
          .from('generated_documents')
          .update({
            'status': DocumentStatus.approved.name,
            'approved_at': DateTime.now().toIso8601String(),
            'approved_by': approvedBy,
          })
          .eq('id', documentId);

      await _logDocumentActivity(
        documentId: documentId,
        action: 'approved',
        actorName: approvedBy,
        actorEmail: _supabase.auth.currentUser?.email,
        actorType: 'workspace_member',
      );

      try {
        await _syncChangeOrderBudgetIfNeededById(documentId);
      } catch (e) {
        AppLogger.warning(
          'Approved change order but failed to sync budget',
          metadata: {'documentId': documentId, 'error': e.toString()},
        );
      }

      try {
        await _snapshotApprovedBudgetItems(documentId);
      } catch (e) {
        AppLogger.warning(
          'Approved document but failed to snapshot budget items',
          metadata: {'documentId': documentId, 'error': e.toString()},
        );
      }

      await _applySelectionsIfSelectionSheet(documentId, actorName: approvedBy);
    } catch (e) {
      throw Exception('Error approving document: $e');
    }
  }

  /// When a Selection Sheet document reaches a binding state (approved or
  /// signed), apply the choices it captured: each selection is approved to its
  /// chosen option via the atomic RPC, which also lands the budget impact.
  /// Best-effort — a Selection Sheet is already binding once signed/approved,
  /// so we never throw back into the status transition.
  Future<void> _applySelectionsIfSelectionSheet(
    String documentId, {
    String? actorName,
  }) async {
    try {
      final doc = await getDocument(documentId);
      if (doc == null || doc.documentType != DocumentType.selections) return;
      final failed = await SelectionDocumentService().applySignedSelections(
        metadata: doc.metadata,
        actorName: actorName,
      );
      if (failed.isNotEmpty) {
        AppLogger.warning(
          'Selection Sheet bound but some selections failed to apply',
          metadata: {'documentId': documentId, 'failedSelectionIds': failed},
        );
      }
    } catch (e) {
      AppLogger.warning(
        'Failed to apply selections for Selection Sheet',
        metadata: {'documentId': documentId, 'error': e.toString()},
      );
    }
  }

  /// Decline a document (internal decline by workspace member).
  /// Mirrors [approveDocument] for audit-log parity: status → denied, with
  /// an explicit `declined` entry in `document_activity_log`.
  Future<void> declineDocument({
    required String documentId,
    required String declinedBy,
    String? reason,
  }) async {
    try {
      await _supabase
          .from('generated_documents')
          .update({'status': DocumentStatus.denied.dbValue})
          .eq('id', documentId);

      await _logDocumentActivity(
        documentId: documentId,
        action: 'declined',
        actorName: declinedBy,
        actorEmail: _supabase.auth.currentUser?.email,
        actorType: 'workspace_member',
        details: (reason != null && reason.trim().isNotEmpty)
            ? {'reason': reason.trim()}
            : null,
      );

      // If this was a previously-approved change order, strip the budget
      // items it added so the contract total stops counting the declined
      // scope.
      try {
        await _syncChangeOrderBudgetIfNeededById(documentId);
      } catch (e) {
        AppLogger.warning(
          'Declined document but failed to sync change order budget',
          metadata: {'documentId': documentId, 'error': e.toString()},
        );
      }
    } catch (e) {
      throw Exception('Error declining document: $e');
    }
  }

  /// Get budget item links for a document from the normalized join table.
  /// Returns a map of budgetItemId → amount.
  Future<Map<String, double>> getDocumentBudgetLinks(String documentId) async {
    try {
      final rows = await _supabase
          .from('budget_document_links')
          .select('budget_item_id, amount')
          .eq('generated_document_id', documentId);
      final result = <String, double>{};
      for (final row in rows) {
        final id = row['budget_item_id'] as String?;
        if (id != null) {
          result[id] = (row['amount'] as num?)?.toDouble() ?? 0.0;
        }
      }
      return result;
    } catch (e) {
      return {};
    }
  }

  /// Resync line items from current budget data for documents using
  /// [LineItemSourceMode.resyncUntilSigned]. Returns the updated document
  /// if any line items changed, or the original document if nothing changed.
  Future<GeneratedDocument> resyncLineItemsFromBudget(
    GeneratedDocument document,
  ) async {
    // Only resync if mode is resyncUntilSigned and document is not signed
    if (document.lineItemSourceMode != LineItemSourceMode.resyncUntilSigned ||
        document.status == DocumentStatus.signed) {
      return document;
    }

    // Collect budget item IDs from line items
    final budgetItemIds = document.lineItems
        .where((li) => li.budgetItemId != null)
        .map((li) => li.budgetItemId!)
        .toSet()
        .toList();

    if (budgetItemIds.isEmpty) return document;

    // Fetch current budget items (unit_cost for vendor docs, unit_price for customer docs)
    final budgetItems = <String, Map<String, dynamic>>{};
    try {
      final rows = await _supabase
          .from('budget_items')
          .select(
            'id, name, description, unit_price, unit_cost, quantity, unit',
          )
          .inFilter('id', budgetItemIds);
      for (final row in rows) {
        budgetItems[row['id'] as String] = row;
      }
    } catch (e) {
      AppLogger.warning('Failed to fetch budget items for resync: $e');
      return document;
    }

    if (budgetItems.isEmpty) return document;

    // Vendor documents bill against cost (unit_cost); customer documents use unit_price.
    final isVendorDoc =
        document.documentType == DocumentType.purchaseOrder ||
        document.documentType == DocumentType.requestForBid ||
        document.documentType == DocumentType.bill ||
        document.documentType == DocumentType.vendorCredit ||
        document.documentType == DocumentType.expense ||
        document.documentType == DocumentType.vendorRefund;

    // Update line items from budget data, skipping fields the user has overridden.
    bool changed = false;
    final updatedLineItems = document.lineItems.map((li) {
      if (li.budgetItemId == null) return li;
      final budgetData = budgetItems[li.budgetItemId!];
      if (budgetData == null) return li;

      final cf = li.customizedFields;

      final budgetName = budgetData['name'] as String? ?? li.name;
      final budgetDesc = budgetData['description'] as String?;
      final budgetPrice = isVendorDoc
          ? (budgetData['unit_cost'] as num?)?.toDouble() ?? li.unitPrice
          : (budgetData['unit_price'] as num?)?.toDouble() ?? li.unitPrice;
      final budgetQty =
          (budgetData['quantity'] as num?)?.toDouble() ?? li.quantity;
      final budgetUnit = budgetData['unit'] as String?;

      final newName = cf.contains('name') ? li.name : budgetName;
      final newDesc = cf.contains('description') ? li.description : budgetDesc;
      final newPrice = cf.contains('unitPrice') ? li.unitPrice : budgetPrice;
      final newQty = cf.contains('quantity') ? li.quantity : budgetQty;
      final newUnit = cf.contains('unit') ? li.unit : budgetUnit;

      if (li.name != newName ||
          li.description != newDesc ||
          li.unitPrice != newPrice ||
          li.quantity != newQty ||
          li.unit != newUnit) {
        changed = true;
        return li.copyWith(
          name: newName,
          description: newDesc,
          unitPrice: newPrice,
          quantity: newQty,
          unit: newUnit,
        );
      }
      return li;
    }).toList();

    if (!changed) return document;

    // Save updated line items to database. updateDocument recomputes
    // total_amount server-side, so re-fetch to keep totalAmount in sync with
    // the new lineItems — otherwise callers see stale totals on the returned doc.
    await updateDocument(documentId: document.id, lineItems: updatedLineItems);
    return await getDocument(document.id) ??
        document.copyWith(lineItems: updatedLineItems);
  }

  /// Soft-delete a document. The row stays in the table with `deleted_at`
  /// stamped, so it disappears from all reads (RLS filters soft-deleted rows)
  /// while preserving the audit trail. Storage blobs and change-order budget
  /// links are still cleaned up — those side effects are not reversible.
  /// Hard-purge of soft-deleted rows is admin-only and lives in SQL.
  Future<void> deleteDocument(String documentId) async {
    try {
      final document = await getDocument(documentId);
      if (document == null) return;
      if (document.documentType == DocumentType.changeOrder) {
        await _budgetService.removeChangeOrderBudgetItems(documentId);
      }
      await _removeDocumentStorageBlobs(document);
      final actorId = _supabase.auth.currentUser?.id;
      await _supabase
          .from('generated_documents')
          .update({
            'deleted_at': DateTime.now().toIso8601String(),
            if (actorId != null) 'deleted_by': actorId,
          })
          .eq('id', documentId);
      await _logDocumentActivity(
        documentId: documentId,
        action: 'deleted',
        actorEmail: _supabase.auth.currentUser?.email,
        actorType: 'workspace_member',
      );
    } catch (e) {
      throw Exception('Error deleting document: $e');
    }
  }

  /// Best-effort removal of storage blobs owned by a document. Only deletes
  /// objects stored under our private-storage scheme; public/foreign URLs and
  /// malformed refs are ignored. Failures are logged but do not prevent the
  /// row delete — a retry (or a periodic sweeper) can reclaim orphaned blobs.
  Future<void> _removeDocumentStorageBlobs(GeneratedDocument? document) async {
    if (document == null) return;
    final refs = <String>{
      if (document.pdfUrl != null) document.pdfUrl!,
      if (document.signatureUrl != null) document.signatureUrl!,
    };
    if (refs.isEmpty) return;

    final byBucket = <String, List<String>>{};
    for (final ref in refs) {
      final parsed = _storageService.parsePrivateStorageRef(ref);
      if (parsed == null) continue;
      byBucket.putIfAbsent(parsed.bucket, () => <String>[]).add(parsed.path);
    }

    for (final entry in byBucket.entries) {
      try {
        await _supabase.storage.from(entry.key).remove(entry.value);
      } catch (e) {
        AppLogger.warning(
          'Failed to remove document storage blobs',
          metadata: {
            'documentId': document.id,
            'bucket': entry.key,
            'paths': entry.value.join(','),
            'error': e.toString(),
          },
        );
      }
    }
  }

  /// Sign a document
  Future<void> signDocument({
    required String documentId,
    required String signatureUrl,
    required String signedByName,
    required String signedByEmail,
    String? signatureIp,
  }) async {
    try {
      await _supabase
          .from('generated_documents')
          .update({
            'status': DocumentStatus.signed.name,
            'signature_url': signatureUrl,
            'signed_by_name': signedByName,
            'signed_by_email': signedByEmail,
            'signed_at': DateTime.now().toIso8601String(),
            'signature_ip': signatureIp,
          })
          .eq('id', documentId);

      final signedDoc = await getDocument(documentId);
      if (signedDoc != null) {
        // Fire-and-forget automations. Only fires for authenticated in-app
        // signing: public-link signers have no session, so RLS hides the
        // rules and this becomes a no-op.
        if (_supabase.auth.currentUser != null) {
          unawaited(SupabaseAutomationService().processDocumentSigned(
            workspaceId: signedDoc.workspaceId,
            documentId: documentId,
            documentType: signedDoc.documentType.dbValue,
            documentNumber: signedDoc.documentNumber,
            projectId: signedDoc.projectId,
            actorUserId: _supabase.auth.currentUser!.id,
          ));
        }
      }

      await _logDocumentActivity(
        documentId: documentId,
        action: 'signed',
        actorName: signedByName,
        actorEmail: signedByEmail,
        actorType: 'in_app_signer',
        details: {
          if (_supabase.auth.currentUser?.id != null)
            'captured_by_user_id': _supabase.auth.currentUser!.id,
          if (_supabase.auth.currentUser?.email != null)
            'captured_by_email': _supabase.auth.currentUser!.email,
        },
        ipAddress: signatureIp,
      );

      try {
        await _syncChangeOrderBudgetIfNeededById(documentId);
      } catch (e) {
        AppLogger.warning(
          'Signed change order but failed to sync budget',
          metadata: {'documentId': documentId, 'error': e.toString()},
        );
      }

      try {
        await _snapshotApprovedBudgetItems(documentId);
      } catch (e) {
        AppLogger.warning(
          'Signed document but failed to snapshot budget items',
          metadata: {'documentId': documentId, 'error': e.toString()},
        );
      }

      await _applySelectionsIfSelectionSheet(documentId,
          actorName: signedByName);

      await _notifyDocumentSigned(
        documentId: documentId,
        signedByName: signedByName,
        signedByEmail: signedByEmail,
      );
    } catch (e) {
      throw Exception('Error signing document: $e');
    }
  }

  Future<void> _notifyDocumentSigned({
    required String documentId,
    required String signedByName,
    required String signedByEmail,
  }) async {
    try {
      await _supabase.rpc(
        'create_document_signed_notifications',
        params: {
          'p_document_id': documentId,
          'p_signed_by_name': signedByName,
          'p_signed_by_email': signedByEmail,
        },
      );
    } catch (e) {
      AppLogger.warning(
        'Failed to create document signed notifications',
        metadata: {
          'documentId': documentId,
          'signedByName': signedByName,
          'signedByEmail': signedByEmail,
          'error': e.toString(),
        },
      );
    }
  }

  /// Mark document as viewed
  Future<void> markAsViewed(String documentId) async {
    try {
      final response = await _supabase
          .from('generated_documents')
          .select('status')
          .eq('id', documentId)
          .maybeSingle();

      if (response != null) {
        final currentStatus = response['status'] as String?;
        if (currentStatus == DocumentStatus.sent.name) {
          await _supabase
              .from('generated_documents')
              .update({'status': DocumentStatus.viewed.name})
              .eq('id', documentId);
        }
      }
    } catch (e) {
      throw Exception('Error marking document as viewed: $e');
    }
  }

  /// List the child RFB documents of a bid package (multi-vendor flow),
  /// ordered by creation time.
  Future<List<GeneratedDocument>> listByBidPackageId(String packageId) async {
    final rows = await _supabase
        .from('generated_documents')
        .select()
        .eq('bid_package_id', packageId)
        .order('created_at', ascending: true);
    return (rows as List)
        .map((r) => _toGeneratedDocument(r as Map<String, dynamic>))
        .toList();
  }

  /// Submit an itemized vendor bid on a request-for-bid document.
  ///
  /// [lineItemBids] must list only the line items the vendor is pricing.
  /// Each entry carries `{id, vendorBidPrice, vendorBidNote?}`. The RPC
  /// merges these fields into the document's existing line items and
  /// updates status to `responded`.
  Future<void> submitVendorBid({
    required String documentId,
    required List<Map<String, dynamic>> lineItemBids,
    String? overallNote,
  }) async {
    try {
      await _supabase.rpc(
        'submit_vendor_bid',
        params: {
          'p_document_id': documentId,
          'p_line_item_bids': lineItemBids,
          'p_overall_note': overallNote,
        },
      );
    } catch (e) {
      throw Exception('Failed to submit vendor bid: $e');
    }
  }

  /// Convert database row to GeneratedDocument
  GeneratedDocument _toGeneratedDocument(Map<String, dynamic> row) {
    return GeneratedDocument.fromJson(_toFirestoreFormat(row), row['id']);
  }

  /// Convert Supabase snake_case row to camelCase map for GeneratedDocument.fromJson.
  Map<String, dynamic> _toFirestoreFormat(Map<String, dynamic> row) {
    final parsedLineItems = _parseDocumentLineItems(row['line_items']);
    final correctedTotalAmount = parsedLineItems.isNotEmpty
        ? _calculateDocumentTotal(
            lineItems: parsedLineItems,
            collectTax: row['collect_tax'] as bool? ?? false,
            taxRate: (row['tax_rate'] as num?)?.toDouble() ?? 0.0,
            shippingCost: (row['shipping_cost'] as num?)?.toDouble() ?? 0.0,
            discountAmount: (row['discount_amount'] as num?)?.toDouble() ?? 0.0,
            taxAmountOverride:
                (row['tax_amount_override'] as num?)?.toDouble(),
          )
        : row['total_amount'];

    return {
      'workspaceId': row['workspace_id'],
      'projectId': row['project_id'],
      'customerId': row['customer_id'],
      'customerName': row['customer_name'],
      'templateId': row['template_id'],
      'templateName': row['template_name'],
      'documentType': row['document_type'],
      'renderedContent': row['rendered_content'],
      'status': row['status'],
      'createdBy': row['created_by'],
      'createdAt': row['created_at'] != null
          ? DateTime.parse(row['created_at'])
          : DateTime.now(),
      'preparedBy': row['prepared_by'],
      'preparedFor': row['prepared_for'],
      'footerContent': row['footer_content'],
      'emailSubject': row['email_subject'],
      'emailMessage': row['email_message'],
      'budgetItemIds': row['budget_item_ids'],
      'budgetItemAmounts': row['budget_item_amounts'],
      'totalAmount': correctedTotalAmount,
      'lineItems': parsedLineItems.map((item) => item.toJson()).toList(),
      'lineItemVisibility': row['line_item_visibility'],
      'lineItemSourceMode': row['line_item_source_mode'],
      'attachedPhotoIds': row['attached_photo_ids'],
      'retainagePercent': row['retainage_percent'],
      'retainageAmount': row['retainage_amount'],
      'discountAmount': row['discount_amount'],
      'pdfUrl': row['pdf_url'],
      'sentAt': row['sent_at'] != null ? DateTime.parse(row['sent_at']) : null,
      'sentTo': row['sent_to'],
      'signatureUrl': row['signature_url'],
      'signedByName': row['signed_by_name'],
      'signedByEmail': row['signed_by_email'],
      'signedAt': row['signed_at'] != null
          ? DateTime.parse(row['signed_at'])
          : null,
      'signatureIp': row['signature_ip'],
      'deniedAt': row['denied_at'] != null
          ? DateTime.parse(row['denied_at'])
          : null,
      'deniedByName': row['denied_by_name'],
      'deniedByEmail': row['denied_by_email'],
      'denialReason': row['denial_reason'],
      'approvedAt': row['approved_at'] != null
          ? DateTime.parse(row['approved_at'])
          : null,
      'approvedBy': row['approved_by'],
      'collectTax': row['collect_tax'],
      'taxName': row['tax_name'],
      'taxRate': row['tax_rate'],
      'taxAmountOverride': row['tax_amount_override'],
      'expectedDate': row['expected_date'] != null
          ? DateTime.parse(row['expected_date'])
          : null,
      'receivedDate': row['received_date'] != null
          ? DateTime.parse(row['received_date'])
          : null,
      'shippingCost': row['shipping_cost'],
      'vendorId': row['vendor_id'],
      'sourceDocumentId': row['source_document_id'],
      'bidPackageId': row['bid_package_id'],
      'amountPaid': row['amount_paid'],
      'paidDate': row['paid_date'] != null
          ? DateTime.parse(row['paid_date'])
          : null,
      'paymentMethod': row['payment_method'],
      'paymentReference': row['payment_reference'],
      'paymentAttachmentUrl': row['payment_attachment_url'],
      'documentNumber': row['document_number'],
      'dueDate': row['due_date'] != null
          ? DateTime.parse(row['due_date'])
          : null,
      'metadata': row['metadata'],
      'excludeFromBudget': row['exclude_from_budget'] ?? false,
    };
  }

  /// Get activity log entries for a document (workspace member access).
  Future<List<Map<String, dynamic>>> getDocumentActivity(
    String documentId,
  ) async {
    try {
      final rows = await _supabase
          .from('document_activity_log')
          .select()
          .eq('document_id', documentId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      AppLogger.warning('Failed to fetch document activity: $e');
      return [];
    }
  }

  /// Get the progress billing summary for a project.
  /// Returns approved contract amount, previously invoiced total, and deposits applied.
  Future<ProjectInvoiceSummary> getProjectInvoiceSummary(
    String projectId, {
    String? excludeDocumentId,
  }) async {
    try {
      // Get approved amount from budget items
      final budgetRows = await _supabase
          .from('budget_items')
          .select('approved_price, item_type')
          .eq('project_id', projectId);
      final approvedAmount = (budgetRows as List)
          .where((r) => r['item_type'] == 'item')
          .fold<double>(
            0,
            (s, r) => s + ((r['approved_price'] as num?)?.toDouble() ?? 0),
          );

      // Get all invoices/progress invoices for this project (sent, viewed, signed, approved)
      final invoiceRows = await _supabase
          .from('generated_documents')
          .select(
            'id, total_amount, document_type, metadata, exclude_from_budget',
          )
          .eq('project_id', projectId)
          .inFilter(
            'document_type',
            DocumentTypeExtension.dbValuesWithBudgetImpact(
              BudgetImpact.customerRevenue,
            ),
          )
          .inFilter('status', ['sent', 'viewed', 'signed', 'approved']);
      double previouslyInvoiced = 0;
      for (final row in invoiceRows) {
        if (row['id'] == excludeDocumentId) continue;
        if (row['exclude_from_budget'] == true) continue;
        previouslyInvoiced += (row['total_amount'] as num?)?.toDouble() ?? 0;
      }

      // Get paid deposits for this project
      final depositRows = await _supabase
          .from('generated_documents')
          .select('id, total_amount, document_number, status, metadata')
          .eq('project_id', projectId)
          .eq('document_type', DocumentType.deposit.dbValue)
          .inFilter('status', ['sent', 'viewed', 'signed', 'approved']);
      final deposits = <AvailableDeposit>[];
      for (final row in depositRows) {
        final meta = row['metadata'] as Map<String, dynamic>? ?? {};
        final appliedTo = meta['applied_to_document_id'] as String?;
        deposits.add(
          AvailableDeposit(
            id: row['id'] as String,
            amount: (row['total_amount'] as num?)?.toDouble() ?? 0,
            documentNumber: row['document_number'] as String?,
            isApplied: appliedTo != null,
            appliedToDocumentId: appliedTo,
          ),
        );
      }

      return ProjectInvoiceSummary(
        approvedAmount: approvedAmount,
        previouslyInvoiced: previouslyInvoiced,
        deposits: deposits,
      );
    } catch (e) {
      throw Exception('Error fetching project invoice summary: $e');
    }
  }

  /// Apply a deposit to a document. The RPC records the deposit reference on
  /// both sides (invoice and deposit documents) in a single transaction and
  /// rejects reassigning a deposit that is already applied to a different
  /// invoice.
  Future<void> applyDeposit({
    required String documentId,
    required String depositDocumentId,
    required double depositAmount,
  }) async {
    try {
      await _supabase.rpc(
        'apply_deposit_to_document',
        params: {
          'p_document_id': documentId,
          'p_deposit_document_id': depositDocumentId,
          'p_deposit_amount': depositAmount,
        },
      );
    } catch (e) {
      throw Exception('Error applying deposit: $e');
    }
  }

  /// Remove a deposit from a document. The RPC clears the deposit reference
  /// on both sides in a single transaction.
  Future<void> removeDeposit({required String documentId}) async {
    try {
      await _supabase.rpc(
        'remove_deposit_from_document',
        params: {'p_document_id': documentId},
      );
    } catch (e) {
      throw Exception('Error removing deposit: $e');
    }
  }

  static Map<String, List<String>> getAvailablePlaceholders() {
    return {
      'workspace': ['name', 'address', 'phone', 'email', 'logo'],
      'customer': ['name', 'email', 'phone', 'address', 'company'],
      'project': ['name', 'description', 'status', 'startDate', 'endDate'],
      'invoice': [
        'number',
        'dueDate',
        'subtotal',
        'taxPercent',
        'taxAmount',
        'total',
      ],
      'date': ['today', 'day', 'month', 'year'],
      'user': ['name', 'email', 'phone'],
      'budget': ['totalAmount', 'totalApproved', 'totalProjected', 'itemCount'],
      'budgetItems': [
        '(loop) name, description, amount, approvedPrice, projectedCost',
      ],
    };
  }
}

