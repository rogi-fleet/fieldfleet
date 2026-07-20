import 'dart:io';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/generated_document.dart';
import '../../models/document_status.dart';
import '../../models/document_type.dart';
import '../../models/document_line_item.dart';
import '../../models/template_category.dart';
import '../../models/budget_item.dart';
import '../../models/workspace.dart';
import '../../models/project.dart';
import '../../models/file_attachment.dart';
import '../../services/service_locator.dart';
import '../../services/pdf_service.dart';
import '../../utils/currency_utils.dart';
import '../../providers/workspace_provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/document_preview_widget.dart';
import '../../widgets/documents/bid_review_panel.dart';
import '../bid_packages/bid_package_screen.dart' show BidPackageBanner;
import '../../services/supabase/document_service.dart';

import 'package:taskfleet_ops/widgets/forms/signature_dialog.dart';
import '../../widgets/send_document_dialog.dart';

class DocumentDetailScreen extends StatefulWidget {
  final String documentId;
  final bool embedded;
  final VoidCallback? onBack;

  /// Embedded only — when non-null, renders a fullscreen toggle in the header.
  final VoidCallback? onToggleExpand;
  final bool isExpanded;

  const DocumentDetailScreen({
    super.key,
    required this.documentId,
    this.embedded = false,
    this.onBack,
    this.onToggleExpand,
    this.isExpanded = false,
  });

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  final _documentService = ServiceLocator.documentService;
  final _templateService = ServiceLocator.documentTemplateService;
  final _budgetService = ServiceLocator.budgetService;
  final _workspaceService = ServiceLocator.workspaceService;
  final _storageService = ServiceLocator.storageService;
  final _projectService = ServiceLocator.projectService;
  final _pdfService = PDFService();
  GeneratedDocument? _document;
  List<GeneratedDocument> _derivedDocuments = [];
  _DocumentTreeNode? _treeRoot;
  List<_LinkedBudgetItemDisplay> _linkedBudgetItems = [];
  Workspace? _workspace;
  String? _projectName;
  bool _isLoading = true;
  bool _isExportingPdf = false;
  String _pdfExportStatus = '';
  bool _isSigning = false;
  ProjectInvoiceSummary? _invoiceSummary;

  String get _projectTerminologySingular {
    final plural = context.read<WorkspaceProvider>().projectTerminology;
    if (plural.endsWith('s') && plural.length > 1) {
      return plural.substring(0, plural.length - 1);
    }
    return plural;
  }

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  Future<void> _loadDocument() async {
    try {
      var document = await _documentService.getDocument(widget.documentId);
      if (mounted && document != null) {
        // Resync line items from budget if mode is resyncUntilSigned
        if (document.lineItemSourceMode ==
                LineItemSourceMode.resyncUntilSigned &&
            document.status != DocumentStatus.signed) {
          try {
            document = await _documentService.resyncLineItemsFromBudget(
              document,
            );
          } catch (_) {
            // Non-fatal — continue with stale line items
          }
        }

        // Load workspace
        final workspaceData =
            await _workspaceService.getWorkspace(document.workspaceId).first;
        Workspace? workspace;
        if (workspaceData != null) {
          workspace = Workspace.fromJson(workspaceData, document.workspaceId);
        }

        final linkedBudgetItems = await _loadLinkedBudgetItems(document);

        // Load project name
        String? projectName;
        if (document.projectId != null) {
          try {
            final project = await _projectService.getProject(
              document.projectId!,
            );
            projectName = project?.name;
          } catch (_) {}
        }

        // Immediate children — used by _nextStepsFor to suppress ghost
        // actions for derived types that already exist.
        final derivedDocs = await _documentService.getDocumentsBySourceId(
          document.id,
        );
        final treeRoot = await _loadDocumentTree(document);

        // Load invoice summary for invoices/progress invoices with a project
        ProjectInvoiceSummary? invoiceSummary;
        final isInvoiceType = document.documentType == DocumentType.invoice ||
            document.documentType == DocumentType.progressInvoice;
        if (isInvoiceType &&
            document.projectId != null &&
            _documentService is SupabaseDocumentService) {
          try {
            invoiceSummary = await _documentService.getProjectInvoiceSummary(
              document.projectId!,
              excludeDocumentId: document.id,
            );
          } catch (_) {}
        }

        setState(() {
          _document = document;
          _workspace = workspace;
          _projectName = projectName;
          _linkedBudgetItems = linkedBudgetItems;
          _derivedDocuments = derivedDocs;
          _treeRoot = treeRoot;
          _invoiceSummary = invoiceSummary;
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() {
          _document = document;
          _linkedBudgetItems = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'loading document'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _exportPdf() async {
    if (_document == null || _workspace == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document not ready for export')),
      );
      return;
    }

    setState(() {
      _isExportingPdf = true;
      _pdfExportStatus = 'Preparing…';
    });

    try {
      // Fetch logo bytes if workspace has an avatar
      Uint8List? logoBytes;
      if (_workspace!.avatarUrl != null && _workspace!.avatarUrl!.isNotEmpty) {
        if (mounted) setState(() => _pdfExportStatus = 'Loading logo…');
        logoBytes = await PDFService.fetchImageBytes(_workspace!.avatarUrl!);
      }

      // Fetch signature image bytes if document is signed
      Uint8List? signatureBytes;
      if (_document!.isSigned && _document!.signatureUrl != null) {
        if (mounted) setState(() => _pdfExportStatus = 'Loading signature…');
        signatureBytes = await PDFService.fetchImageBytes(
          _document!.signatureUrl!,
        );
      }

      // Load attached photos (metadata only for now)
      List<FileAttachment>? attachedPhotos;
      if (_document!.attachedPhotoIds.isNotEmpty &&
          _document!.projectId != null) {
        final photoCount = _document!.attachedPhotoIds.length;
        if (mounted) {
          setState(
            () => _pdfExportStatus =
                'Loading $photoCount photo${photoCount == 1 ? '' : 's'}…',
          );
        }
        final allFiles = await _storageService
            .getProjectFiles(_document!.workspaceId, _document!.projectId!)
            .first;
        attachedPhotos = allFiles
            .where((f) => _document!.attachedPhotoIds.contains(f.id))
            .toList();
      }

      // Generate PDF
      if (mounted) setState(() => _pdfExportStatus = 'Generating PDF…');
      final pdfBytes = await _pdfService.generateDocumentPDF(
        document: _document!,
        workspace: _workspace!,
        attachedPhotos: attachedPhotos,
        signatureImageBytes: signatureBytes,
        logoBytes: logoBytes,
      );

      // Share PDF
      final filename =
          '${_document!.templateName.replaceAll(' ', '_')}_${_document!.formattedCreatedAt.replaceAll('/', '-')}.pdf';
      await _pdfService.sharePDF(pdfBytes, filename);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF exported successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'exporting PDF'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExportingPdf = false);
      }
    }
  }

  Color _getStatusColor(DocumentStatus status) {
    switch (status) {
      case DocumentStatus.draft:
        return AppColors.textTertiary;
      case DocumentStatus.sent:
        return AppColors.info;
      case DocumentStatus.viewed:
        return AppColors.warning;
      case DocumentStatus.signed:
        return AppColors.success;
      case DocumentStatus.denied:
        return AppColors.error;
      case DocumentStatus.changesRequested:
        return AppColors.warning;
      case DocumentStatus.pending:
        return AppColors.warning;
      case DocumentStatus.approved:
        return AppColors.financialAccent;
      case DocumentStatus.responded:
        return AppColors.info;
      case DocumentStatus.applied:
        return AppColors.success;
      case DocumentStatus.notSelected:
      case DocumentStatus.withdrawn:
        return AppColors.textTertiary;
    }
  }

  Future<List<_LinkedBudgetItemDisplay>> _loadLinkedBudgetItems(
    GeneratedDocument document,
  ) async {
    // Try the normalized join table first, fall back to legacy arrays.
    Map<String, double> linkAmounts = {};
    try {
      linkAmounts = await _documentService.getDocumentBudgetLinks(document.id);
    } catch (_) {
      // Method may not exist on legacy Firestore service — ignore.
    }

    // Merge legacy budgetItemIds if the join table had no results.
    final budgetIds = linkAmounts.isNotEmpty
        ? linkAmounts.keys.toSet()
        : document.budgetItemIds.toSet();

    if (budgetIds.isEmpty) return [];

    final items = await Future.wait(
      budgetIds.map((id) async {
        try {
          final item = await _budgetService.getBudgetItem(id) as BudgetItem?;
          if (item == null) return null;
          final amount = linkAmounts[item.id] ??
              document.budgetItemAmounts?[item.id] ??
              item.approvedPrice;
          return _LinkedBudgetItemDisplay(
            id: item.id,
            name: item.name,
            amount: amount,
          );
        } catch (_) {
          return null;
        }
      }),
    );

    return items.whereType<_LinkedBudgetItemDisplay>().toList();
  }

  // ── Document chain helpers ──────────────────────────────────

  static IconData _iconForDocType(DocumentType type) {
    switch (type) {
      case DocumentType.invoice:
      case DocumentType.progressInvoice:
        return Icons.receipt_long;
      case DocumentType.quotation:
        return Icons.request_quote;
      case DocumentType.purchaseOrder:
        return Icons.shopping_cart;
      case DocumentType.requestForBid:
        return Icons.gavel;
      case DocumentType.bill:
        return Icons.receipt;
      case DocumentType.changeOrder:
        return Icons.swap_horiz;
      case DocumentType.expense:
        return Icons.money_off;
      default:
        return Icons.description;
    }
  }

  /// Build the list of suggested next steps based on the current document.
  Future<_DocumentTreeNode> _loadDocumentTree(
    GeneratedDocument document,
  ) async {
    if (document.projectId != null) {
      try {
        final all = await _documentService
            .getDocuments(
              document.workspaceId,
              projectId: document.projectId,
            )
            .first;
        final node = _buildTreeFromDocs(all, document.id);
        if (node != null) return node;
      } catch (_) {
        // Fall through to standalone walk on any error
      }
    }
    return _loadTreeStandalone(document);
  }

  _DocumentTreeNode? _buildTreeFromDocs(
    List<GeneratedDocument> docs,
    String currentId,
  ) {
    if (docs.isEmpty) return null;
    final byId = {for (final d in docs) d.id: d};
    if (!byId.containsKey(currentId)) return null;

    // Walk up from current to topmost ancestor (cycle-safe).
    var rootId = currentId;
    final seen = <String>{rootId};
    while (true) {
      final parentId = byId[rootId]?.sourceDocumentId;
      if (parentId == null ||
          !byId.containsKey(parentId) ||
          seen.contains(parentId)) {
        break;
      }
      rootId = parentId;
      seen.add(rootId);
    }

    final childrenById = <String, List<GeneratedDocument>>{};
    for (final d in docs) {
      final parent = d.sourceDocumentId;
      if (parent != null && byId.containsKey(parent)) {
        childrenById.putIfAbsent(parent, () => []).add(d);
      }
    }
    for (final entry in childrenById.entries) {
      entry.value.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }

    return _buildTreeNode(byId[rootId]!, childrenById, <String>{});
  }

  _DocumentTreeNode _buildTreeNode(
    GeneratedDocument doc,
    Map<String, List<GeneratedDocument>> childrenById,
    Set<String> visited,
  ) {
    visited.add(doc.id);
    final kids = (childrenById[doc.id] ?? const <GeneratedDocument>[])
        .where((c) => !visited.contains(c.id))
        .map((c) => _buildTreeNode(c, childrenById, visited))
        .toList(growable: false);
    return _DocumentTreeNode(document: doc, children: kids);
  }

  Future<_DocumentTreeNode> _loadTreeStandalone(
    GeneratedDocument document,
  ) async {
    final visited = <String>{document.id};
    var root = document;
    while (root.sourceDocumentId != null &&
        !visited.contains(root.sourceDocumentId)) {
      final parent = await _documentService.getDocument(
        root.sourceDocumentId!,
      );
      if (parent == null) break;
      visited.add(parent.id);
      root = parent;
    }
    return _expandTreeStandalone(root, visited);
  }

  Future<_DocumentTreeNode> _expandTreeStandalone(
    GeneratedDocument doc,
    Set<String> visited,
  ) async {
    final children = await _documentService.getDocumentsBySourceId(doc.id);
    final nodes = <_DocumentTreeNode>[];
    for (final c in children) {
      if (visited.contains(c.id)) continue;
      visited.add(c.id);
      nodes.add(await _expandTreeStandalone(c, visited));
    }
    return _DocumentTreeNode(document: doc, children: nodes);
  }

  List<_ChainNextStep> _nextStepsFor(GeneratedDocument document) {
    final steps = <_ChainNextStep>[];
    final cat = document.documentType.category;
    final type = document.documentType;
    final status = document.status;
    final signed = status == DocumentStatus.signed;

    // Track which derived document types already exist
    final derivedTypes = _derivedDocuments.map((d) => d.documentType).toSet();

    // Customer order → invoice / change order / RFB
    if (cat == TemplateCategory.customerOrder) {
      if (type != DocumentType.invoice &&
          !derivedTypes.contains(DocumentType.invoice)) {
        steps.add(
          _ChainNextStep(
            type: DocumentType.invoice,
            label: 'Create Invoice',
            hint: 'Bill the customer for this work',
            onTap: () => _showQuickConvertDialog(DocumentType.invoice),
            primary: true,
          ),
        );
      }
      if (type != DocumentType.changeOrder &&
          !derivedTypes.contains(DocumentType.changeOrder)) {
        steps.add(
          _ChainNextStep(
            type: DocumentType.changeOrder,
            label: 'Create Change Order',
            hint: 'Document scope or price changes',
            onTap: () => _createDerivedDocument(DocumentType.changeOrder),
          ),
        );
      }
      if (type != DocumentType.requestForBid &&
          !derivedTypes.contains(DocumentType.requestForBid)) {
        steps.add(
          _ChainNextStep(
            type: DocumentType.requestForBid,
            label: 'Create RFB',
            hint: 'Request vendor pricing',
            onTap: () => _createDerivedDocument(DocumentType.requestForBid),
          ),
        );
      }
    }

    // Accepted RFB → PO. Current RFBs become `applied` after the vendor bid is
    // pushed to the budget; `signed` is kept for older documents.
    if (type == DocumentType.requestForBid &&
        (signed || status == DocumentStatus.applied) &&
        !derivedTypes.contains(DocumentType.purchaseOrder)) {
      steps.add(
        _ChainNextStep(
          type: DocumentType.purchaseOrder,
          label: 'Convert to PO',
          hint: 'Accept this bid and issue a purchase order',
          onTap: () => _createDerivedDocument(DocumentType.purchaseOrder),
          primary: true,
        ),
      );
    }

    // Signed PO → Bill
    if (type == DocumentType.purchaseOrder &&
        signed &&
        !derivedTypes.contains(DocumentType.bill)) {
      steps.add(
        _ChainNextStep(
          type: DocumentType.bill,
          label: 'Convert to Bill',
          hint: 'Record the vendor bill for this PO',
          onTap: () => _createDerivedDocument(DocumentType.bill),
          primary: true,
        ),
      );
    }

    final customerPayable = type == DocumentType.invoice ||
        type == DocumentType.progressInvoice ||
        type == DocumentType.deposit;

    // Payable document → Receive Payment (invoices) / Pay Bill (bills).
    // Bills share the same dialog + posting path (DR A/P / CR Bank); without
    // this step there is no UI to clear A/P at all.
    final vendorPayable = type == DocumentType.bill;
    if ((customerPayable || vendorPayable) && document.paidDate == null) {
      final payableStatuses = {
        DocumentStatus.sent,
        DocumentStatus.viewed,
        DocumentStatus.approved,
        DocumentStatus.signed,
      };
      if (payableStatuses.contains(document.status)) {
        steps.add(
          _ChainNextStep(
            customIcon: Icons.payments_outlined,
            label: customerPayable ? 'Receive Payment' : 'Pay Bill',
            hint: customerPayable
                ? 'Record a payment received for this invoice'
                : 'Record a payment made to this vendor',
            onTap: () => _showReceivePaymentDialog(document),
            primary: true,
          ),
        );
      }
    }

    return steps;
  }

  /// Build contextual action steps based on the document's current status.
  List<_ActionNextStep> _actionNextStepsFor(GeneratedDocument document) {
    final steps = <_ActionNextStep>[];
    final status = document.status;
    final now = DateTime.now();
    final isTerminal = status == DocumentStatus.signed;
    final category = document.documentType.category;
    final isVendorRecipient = category == TemplateCategory.vendorOrder ||
        category == TemplateCategory.vendorBill;
    final recipientLabel = isVendorRecipient ? 'Vendor' : 'Customer';
    final recipientLower = recipientLabel.toLowerCase();
    final customerPayable = document.documentType == DocumentType.invoice ||
        document.documentType == DocumentType.progressInvoice ||
        document.documentType == DocumentType.deposit;
    final vendorPayable = document.documentType == DocumentType.bill ||
        document.documentType == DocumentType.expense;

    // --- Contextual alerts (prepended before status-specific steps) ---

    // Overdue / expired: dueDate is past, document not signed or paid
    if (!isTerminal &&
        document.dueDate != null &&
        document.dueDate!.isBefore(now) &&
        document.paidDate == null) {
      final daysOverdue = now.difference(document.dueDate!).inDays;
      final label = document.documentType.expiryDateLabel;
      steps.add(
        _ActionNextStep(
          icon: Icons.warning_amber,
          label:
              'Overdue — $daysOverdue ${daysOverdue == 1 ? 'day' : 'days'} past $label',
          hint:
              '$label: ${DateFormat('MMM d, yyyy').format(document.dueDate!)}',
          isInfo: true,
        ),
      );
    }

    // Unpaid invoice/bill/expense: signed but no payment recorded.
    if (status == DocumentStatus.signed &&
        document.paidDate == null &&
        (customerPayable || vendorPayable)) {
      steps.add(
        _ActionNextStep(
          icon: Icons.payments_outlined,
          label: customerPayable ? 'Awaiting Payment' : 'Payment Due',
          hint: customerPayable
              ? 'No customer payment has been recorded'
              : 'No vendor payment has been recorded',
          onTap: () => _showReceivePaymentDialog(document),
          primary: true,
        ),
      );
    }

    // No recipient contact: can't send without an email
    if (!isTerminal &&
        status != DocumentStatus.sent &&
        status != DocumentStatus.viewed &&
        document.preparedFor?.email == null) {
      steps.add(
        _ActionNextStep(
          icon: Icons.contact_mail,
          label: 'No Recipient Email',
          hint: 'Add a $recipientLower email to send this document',
          onTap: () => _editDocument(context, document),
        ),
      );
    }

    // --- Status-specific steps ---

    switch (status) {
      case DocumentStatus.pending:
      case DocumentStatus.draft:
        steps.add(
          _ActionNextStep(
            icon: Icons.verified,
            label: 'Approve Document',
            hint: 'Approve this document internally',
            onTap: () => _approveDocument(context),
            primary: true,
          ),
        );
        steps.add(
          _ActionNextStep(
            icon: Icons.send,
            label: 'Send to $recipientLabel',
            hint: 'Email this document for review or signing',
            onTap: () => _showSendDialog(context),
          ),
        );
        steps.add(
          _ActionNextStep(
            icon: Icons.picture_as_pdf,
            label: 'Download PDF',
            hint: 'Export and share a PDF copy',
            onTap: _isExportingPdf ? null : _exportPdf,
          ),
        );
      case DocumentStatus.approved:
        steps.add(
          _ActionNextStep(
            icon: Icons.send,
            label: 'Send to $recipientLabel',
            hint: 'Email this document for review or signing',
            onTap: () => _showSendDialog(context),
            primary: true,
          ),
        );
        steps.add(
          _ActionNextStep(
            icon: Icons.picture_as_pdf,
            label: 'Download PDF',
            hint: 'Export and share a PDF copy',
            onTap: _isExportingPdf ? null : _exportPdf,
          ),
        );
      case DocumentStatus.sent:
        steps.add(
          _ActionNextStep(
            icon: Icons.hourglass_top,
            label: 'Waiting for $recipientLabel',
            hint: 'Document has been sent and is awaiting a response',
            isInfo: true,
          ),
        );
        steps.add(
          _ActionNextStep(
            icon: Icons.send,
            label: 'Resend to $recipientLabel',
            hint: 'Follow up by resending this document',
            onTap: () => _showSendDialog(context),
          ),
        );
        steps.add(
          _ActionNextStep(
            icon: Icons.picture_as_pdf,
            label: 'Download PDF',
            hint: 'Export and share a PDF copy',
            onTap: _isExportingPdf ? null : _exportPdf,
          ),
        );
      case DocumentStatus.viewed:
        steps.add(
          _ActionNextStep(
            icon: Icons.visibility,
            label: '$recipientLabel Viewed',
            hint: 'The $recipientLower has opened this document',
            isInfo: true,
          ),
        );
        steps.add(
          _ActionNextStep(
            icon: Icons.send,
            label: 'Resend to $recipientLabel',
            hint: 'Follow up if the $recipientLower hasn\'t responded',
            onTap: () => _showSendDialog(context),
          ),
        );
        steps.add(
          _ActionNextStep(
            icon: Icons.picture_as_pdf,
            label: 'Download PDF',
            hint: 'Export and share a PDF copy',
            onTap: _isExportingPdf ? null : _exportPdf,
          ),
        );
      case DocumentStatus.denied:
        steps.add(
          _ActionNextStep(
            icon: Icons.block,
            label: '$recipientLabel Denied',
            hint: document.denialReason != null
                ? 'Reason: ${document.denialReason}'
                : 'The $recipientLower has denied this document',
            isInfo: true,
          ),
        );
        steps.add(
          _ActionNextStep(
            icon: Icons.edit,
            label: 'Edit Document',
            hint: 'Revise the document before resending',
            onTap: () => _editDocument(context, document),
            primary: true,
          ),
        );
        steps.add(
          _ActionNextStep(
            icon: Icons.send,
            label: 'Resend to $recipientLabel',
            hint: 'Send the document again as-is',
            onTap: () => _showSendDialog(context),
          ),
        );
      case DocumentStatus.changesRequested:
        steps.add(
          _ActionNextStep(
            icon: Icons.rate_review,
            label: 'Changes Requested',
            hint: 'The $recipientLower has requested changes to this document',
            isInfo: true,
          ),
        );
        steps.add(
          _ActionNextStep(
            icon: Icons.edit,
            label: 'Edit Document',
            hint: 'Revise the document before resending',
            onTap: () => _editDocument(context, document),
            primary: true,
          ),
        );
        steps.add(
          _ActionNextStep(
            icon: Icons.send,
            label: 'Resend to $recipientLabel',
            hint: 'Send the document again as-is',
            onTap: () => _showSendDialog(context),
          ),
        );
      case DocumentStatus.signed:
      case DocumentStatus.applied:
      case DocumentStatus.notSelected:
      case DocumentStatus.withdrawn:
        // Terminal states — no action steps needed
        break;
      case DocumentStatus.responded:
        steps.add(
          _ActionNextStep(
            icon: Icons.mark_email_read,
            label: 'Bid Received',
            hint: 'Vendor has submitted a bid — review and apply to budget',
            isInfo: true,
          ),
        );
    }

    return steps;
  }

  /// Builds a prominent card showing contextual next-step actions.
  /// Pass [overrideSteps] to render a filtered subset (used on mobile when
  /// some steps are already promoted to the top bar / urgent banner).
  Widget _buildActionNextStepsCard(
    GeneratedDocument document, {
    List<_ActionNextStep>? overrideSteps,
  }) {
    final steps = overrideSteps ?? _actionNextStepsFor(document);
    if (steps.isEmpty) return const SizedBox.shrink();

    final statusColor = _getStatusColor(document.status);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.base),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.06),
                border: Border(
                  bottom: BorderSide(
                    color: statusColor.withValues(alpha: 0.15),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline, size: 20, color: statusColor),
                  const SizedBox(width: 8),
                  Text(
                    'Next Steps',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
            ),
            // Step rows
            ...steps.map((step) => _buildActionStepRow(step, statusColor)),
          ],
        ),
      ),
    );
  }

  Widget _buildActionStepRow(_ActionNextStep step, Color accentColor) {
    if (step.isInfo) {
      return Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base, vertical: AppSpacing.md),
        child: Row(
          children: [
            Icon(step.icon, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    step.hint,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: step.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base, vertical: AppSpacing.md),
        child: Row(
          children: [
            Icon(
              step.icon,
              size: 20,
              color: step.primary ? accentColor : AppColors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          step.primary ? FontWeight.w700 : FontWeight.w600,
                      color: step.primary ? accentColor : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    step.hint,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: step.primary ? accentColor : AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the full document-chain timeline card including next-step actions.
  Widget _buildDocumentTreeCard(GeneratedDocument document) {
    final root = _treeRoot;
    if (root == null) return const SizedBox.shrink();
    final nextSteps = _nextStepsFor(document);
    final hasPaidNode = document.paidDate != null &&
        document.documentType.category == TemplateCategory.customerInvoice;

    // Single-node tree with nothing else to show: skip the card entirely so
    // the standalone document doesn't get an empty workflow box.
    final isOnlyNode = root.children.isEmpty && root.document.id == document.id;
    if (isOnlyNode && nextSteps.isEmpty && !hasPaidNode) {
      return const SizedBox.shrink();
    }

    final rows = <Widget>[];
    _appendTreeRows(
      rows: rows,
      node: root,
      currentId: document.id,
      nextSteps: nextSteps,
      hasPaidNode: hasPaidNode,
      depth: 0,
    );

    // Purchase orders and requests-for-bid commit against the budget
    // automatically when they reach signed/approved (see the derived
    // committed_cost trigger), so the manual "Update Budget" path is only
    // offered for the remaining document types (e.g. approved-price sync).
    final isVendorCommitmentDoc =
        document.documentType == DocumentType.purchaseOrder ||
            document.documentType == DocumentType.requestForBid;
    final showUpdateBudget = document.status == DocumentStatus.signed &&
        document.budgetItemIds.isNotEmpty &&
        !isVendorCommitmentDoc;
    final chrome = ChromeColors.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        color: chrome.isDark ? chrome.surface : null,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.account_tree,
                    size: 20,
                    color: chrome.isDark ? chrome.text : null,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Document Workflow',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: chrome.isDark ? chrome.textActive : null,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...rows,
              if (showUpdateBudget) ...[
                Divider(
                  height: 24,
                  color: chrome.isDark ? chrome.divider : null,
                ),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showUpdateBudgetDialog(document),
                    icon: const Icon(Icons.sync, size: 18),
                    label: const Text('Update Budget from Document'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Receiving panel for purchase orders that have inventory-tracked lines.
  /// Lets the user record deliveries against each line; each receive bumps the
  /// line's received quantity and stock on-hand via [receive_document_po_line].
  /// Returns an empty widget for any document without receivable lines.
  Widget _buildReceivingCard(GeneratedDocument document) {
    if (document.documentType != DocumentType.purchaseOrder ||
        !document.hasReceivableLines) {
      return const SizedBox.shrink();
    }
    final lines = document.receivableLineItems;
    final fulfillment = document.fulfillment;
    final chrome = ChromeColors.of(context);

    (String, Color) badge() {
      switch (fulfillment) {
        case PoFulfillment.received:
          return ('Received', AppColors.successDark);
        case PoFulfillment.partial:
          return ('Partial', AppColors.warningDark);
        case PoFulfillment.none:
        case null:
          return ('Not received', AppColors.textSecondary);
      }
    }

    final (badgeLabel, badgeColor) = badge();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 20,
                    color: chrome.isDark ? chrome.text : null,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Receiving',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: chrome.isDark ? chrome.textActive : null,
                        ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.r12),
                    ),
                    child: Text(
                      badgeLabel,
                      style: TextStyle(
                        color: badgeColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...lines.map((line) {
                final fullyReceived = line.quantityReceived >= line.quantity;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(line.name),
                            Text(
                              'Received ${line.formattedQuantityReceived} of ${line.formattedQuantity}',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: fullyReceived
                            ? null
                            : () => _receivePoLine(document, line),
                        icon: const Icon(Icons.add_box_outlined, size: 18),
                        label: Text(fullyReceived ? 'Done' : 'Receive'),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _receivePoLine(
    GeneratedDocument document,
    DocumentLineItem line,
  ) async {
    final controller = TextEditingController(
      text: line.quantityRemaining.toString(),
    );
    final qty = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Receive ${line.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Ordered: ${line.formattedQuantity}'),
            Text('Already received: ${line.formattedQuantityReceived}'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Quantity received now',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context)
                .pop(double.tryParse(controller.text.trim())),
            child: const Text('Receive'),
          ),
        ],
      ),
    );
    if (qty == null || qty <= 0) return;
    try {
      await ServiceLocator.documentPoReceivingService.receiveLine(
        documentId: document.id,
        lineId: line.id,
        quantity: qty,
      );
      if (mounted) await _loadDocument();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Received ${qty.toString()} × ${line.name}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to receive: $e')),
        );
      }
    }
  }

  void _appendTreeRows({
    required List<Widget> rows,
    required _DocumentTreeNode node,
    required String currentId,
    required List<_ChainNextStep> nextSteps,
    required bool hasPaidNode,
    required int depth,
  }) {
    final isCurrent = node.document.id == currentId;
    rows.add(
      _buildTreeNodeRow(
        doc: node.document,
        depth: depth,
        isCurrent: isCurrent,
      ),
    );

    // Real children before ghosts so existing branches read first.
    for (final child in node.children) {
      _appendTreeRows(
        rows: rows,
        node: child,
        currentId: currentId,
        nextSteps: nextSteps,
        hasPaidNode: hasPaidNode,
        depth: depth + 1,
      );
    }

    if (isCurrent) {
      if (hasPaidNode) {
        rows.add(
          _buildTreePaidRow(doc: node.document, depth: depth + 1),
        );
      }
      for (final step in nextSteps) {
        rows.add(_buildTreeGhostRow(step: step, depth: depth + 1));
      }
    }
  }

  Widget _buildTreeNodeRow({
    required GeneratedDocument doc,
    required int depth,
    required bool isCurrent,
  }) {
    final chrome = ChromeColors.of(context);
    final statusColor = _getStatusColor(doc.status);
    final dateStr = DateFormat('MMM d').format(doc.createdAt);
    final isInactive = doc.status == DocumentStatus.draft && !isCurrent;

    return Padding(
      padding: EdgeInsets.only(
        left: depth * 22.0,
        bottom: 4,
      ),
      child: InkWell(
        onTap: isCurrent ? null : () => context.push('/documents/${doc.id}'),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: isCurrent
                ? (chrome.isDark
                    ? AppColors.primaryLight.withValues(alpha: 0.12)
                    : AppColors.primary.withValues(alpha: 0.06))
                : null,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: isCurrent
                ? Border.all(
                    color: chrome.isDark
                        ? AppColors.primaryLight.withValues(alpha: 0.35)
                        : AppColors.primary.withValues(alpha: 0.25),
                  )
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: isCurrent ? 28 : 24,
                height: isCurrent ? 28 : 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCurrent
                      ? AppColors.primary
                      : statusColor.withValues(alpha: 0.15),
                  border: isCurrent
                      ? null
                      : Border.all(color: statusColor, width: 2),
                ),
                child: Icon(
                  _iconForDocType(doc.documentType),
                  size: isCurrent ? 14 : 12,
                  color: isCurrent ? Colors.white : statusColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.documentType.displayName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isCurrent ? FontWeight.w700 : FontWeight.w600,
                        color: isCurrent
                            ? (chrome.isDark
                                ? AppColors.primaryLight
                                : AppColors.primary)
                            : (isInactive
                                ? AppColors.textTertiary
                                : (chrome.isDark ? chrome.textActive : null)),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateStr,
                      style: TextStyle(
                        fontSize: 11,
                        color: chrome.isDark
                            ? chrome.text
                            : AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(
                    alpha: chrome.isDark ? 0.2 : 0.12,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.r12),
                ),
                child: Text(
                  doc.status.displayName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
              if (!isCurrent) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: chrome.isDark ? chrome.text : AppColors.textTertiary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTreeGhostRow({
    required _ChainNextStep step,
    required int depth,
  }) {
    final chrome = ChromeColors.of(context);
    final ghostColor = chrome.isDark
        ? chrome.text.withValues(alpha: 0.7)
        : AppColors.textSecondary;
    final borderColor = chrome.isDark ? chrome.divider : AppColors.cardBorder;

    return Padding(
      padding: EdgeInsets.only(left: depth * 22.0, bottom: 4),
      child: InkWell(
        onTap: step.onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: borderColor, style: BorderStyle.solid),
            color: chrome.isDark
                ? chrome.divider.withValues(alpha: 0.15)
                : AppColors.surfaceAlt,
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: chrome.isDark
                      ? chrome.divider.withValues(alpha: 0.4)
                      : Colors.white,
                  border: Border.all(color: borderColor, width: 1.5),
                ),
                child: Icon(
                  step.type != null
                      ? _iconForDocType(step.type!)
                      : (step.customIcon ?? Icons.add),
                  size: 12,
                  color: ghostColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            step.primary ? FontWeight.w600 : FontWeight.w500,
                        color: ghostColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      step.hint,
                      style: TextStyle(
                        fontSize: 11,
                        color: chrome.isDark
                            ? chrome.text.withValues(alpha: 0.6)
                            : AppColors.textTertiary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.add, size: 16, color: ghostColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTreePaidRow({
    required GeneratedDocument doc,
    required int depth,
  }) {
    final chrome = ChromeColors.of(context);
    final paidColor = AppColors.success;
    final dateStr = DateFormat('MMM d').format(doc.paidDate!);

    return Padding(
      padding: EdgeInsets.only(left: depth * 22.0, bottom: 4),
      child: InkWell(
        onTap: () => _showReceivePaymentDialog(doc),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            color: paidColor.withValues(alpha: chrome.isDark ? 0.18 : 0.08),
            border: Border.all(
              color: paidColor.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: paidColor.withValues(alpha: 0.2),
                  border: Border.all(color: paidColor, width: 2),
                ),
                child: Icon(
                  Icons.payments_outlined,
                  size: 12,
                  color: paidColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Payment received',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: paidColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateStr,
                      style: TextStyle(
                        fontSize: 11,
                        color: chrome.isDark
                            ? chrome.text
                            : AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.edit, size: 14, color: paidColor),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showReceivePaymentDialog(GeneratedDocument document) async {
    final isVendorPayable = document.documentType == DocumentType.bill ||
        document.documentType == DocumentType.expense;
    final currency = _workspace?.currencyCode ?? 'USD';
    final balance = (document.totalAmount - document.amountPaid)
        .clamp(0.0, double.infinity);
    final result = await showDialog<
        ({
          DateTime? date,
          double? amount,
          String? method,
          String? reference,
          String? attachmentUrl,
        })>(
      context: context,
      builder: (ctx) => _ReceivePaymentDialog(
        title: isVendorPayable ? 'Record Vendor Payment' : 'Receive Payment',
        amountLabel: isVendorPayable ? 'Amount to Pay' : 'Amount',
        existingDate: document.paidDate,
        existingMethod: document.paymentMethod,
        existingReference: document.paymentReference,
        existingAttachmentUrl: document.paymentAttachmentUrl,
        totalAmount: document.totalAmount,
        amountPaid: document.amountPaid,
        balance: balance,
        currencyCode: currency,
        workspaceId: document.workspaceId,
        documentId: document.id,
      ),
    );
    if (result == null) return;

    final removing = result.date == null;
    final metadataOnly = !removing && (result.amount ?? 0) <= 0.005;
    try {
      if (removing) {
        await _documentService.updateDocument(
          documentId: document.id,
          clearPaidDate: true,
          clearPaymentFields: true,
          amountPaid: 0,
        );
      } else if (metadataOnly) {
        // Already fully paid — just update the recorded payment metadata.
        await _documentService.updateDocument(
          documentId: document.id,
          paidDate: result.date,
          paymentMethod: result.method,
          paymentReference: result.reference,
          paymentAttachmentUrl: result.attachmentUrl,
        );
      } else {
        // Fold the new payment into the running total; stamp `paidDate`
        // once the document is paid in full (same convention the budget
        // rollups and Financials view read).
        final newPaid = document.amountPaid + (result.amount ?? balance);
        final fullyPaid = newPaid + 0.005 >= document.totalAmount;
        await _documentService.updateDocument(
          documentId: document.id,
          amountPaid: newPaid,
          paidDate: fullyPaid ? result.date : null,
          paymentMethod: result.method,
          paymentReference: result.reference,
          paymentAttachmentUrl: result.attachmentUrl,
        );
      }
      if (mounted) await _loadDocument();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to ${removing ? 'remove' : 'record'} payment: $e',
            ),
          ),
        );
      }
    }
  }

  Future<void> _toggleExcludeFromBudget(bool value) async {
    try {
      await _documentService.updateDocument(
        documentId: widget.documentId,
        excludeFromBudget: value,
      );
      setState(() {
        _document = _document!.copyWith(excludeFromBudget: value);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
      }
    }
  }

  Widget _buildProgressBillingSummary(
    GeneratedDocument document,
    ProjectInvoiceSummary summary,
  ) {
    final chrome = ChromeColors.of(context);
    final currencyCode = _workspace?.currencyCode ?? 'USD';
    String fmt(double amount) =>
        CurrencyUtils.formatCurrency(amount, currencyCode);

    final thisInvoice = document.totalAmount;
    final remaining =
        summary.approvedAmount - summary.previouslyInvoiced - thisInvoice;
    final depositAmount =
        (document.metadata['applied_deposit_amount'] as num?)?.toDouble() ?? 0;

    // Find the deposit that's applied to this document
    final appliedDepositId =
        document.metadata['applied_deposit_document_id'] as String?;
    final appliedDeposit = appliedDepositId != null
        ? summary.deposits.where((d) => d.id == appliedDepositId).firstOrNull
        : null;

    // Available deposits (not yet applied to any document, or applied to this one)
    final availableDeposits = summary.deposits
        .where((d) => !d.isApplied || d.appliedToDocumentId == document.id)
        .toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        color: chrome.isDark ? chrome.surface : null,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.trending_up,
                    size: 20,
                    color:
                        chrome.isDark ? chrome.text : AppColors.financialAccent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    document.documentType == DocumentType.progressInvoice
                        ? 'Progress Billing Summary'
                        : 'Billing Summary',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: chrome.isDark ? chrome.textActive : null,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              _billingSummaryRow(
                'Approved Contract Amount',
                fmt(summary.approvedAmount),
                chrome: chrome,
              ),
              const SizedBox(height: 8),
              _billingSummaryRow(
                'Previously Invoiced',
                summary.previouslyInvoiced > 0
                    ? '-${fmt(summary.previouslyInvoiced)}'
                    : fmt(0),
                chrome: chrome,
                valueColor: summary.previouslyInvoiced > 0
                    ? AppColors.textSecondary
                    : null,
              ),
              const SizedBox(height: 8),
              _billingSummaryRow(
                'This Invoice',
                fmt(thisInvoice),
                chrome: chrome,
                bold: true,
              ),
              if (depositAmount > 0) ...[
                const SizedBox(height: 8),
                _billingSummaryRow(
                  'Less Deposit${appliedDeposit?.documentNumber != null ? ' (${appliedDeposit!.documentNumber})' : ''}',
                  '-${fmt(depositAmount)}',
                  chrome: chrome,
                  valueColor: AppColors.textSecondary,
                ),
              ],
              Divider(height: 20, color: chrome.isDark ? chrome.divider : null),
              _billingSummaryRow(
                'Remaining to Invoice',
                fmt(remaining.clamp(0, double.infinity)),
                chrome: chrome,
                bold: true,
                valueColor: remaining < 0 ? AppColors.error : null,
              ),

              // Payment state — otherwise a half-paid invoice is
              // indistinguishable from an unpaid one outside the Receive
              // Payment dialog.
              if (document.amountPaid > 0 || document.paidDate != null) ...[
                const SizedBox(height: 8),
                _billingSummaryRow(
                  'Paid to Date',
                  fmt(document.amountPaid),
                  chrome: chrome,
                  valueColor: AppColors.success,
                ),
                const SizedBox(height: 8),
                _billingSummaryRow(
                  'Balance Due',
                  fmt((document.totalAmount - document.amountPaid)
                      .clamp(0, double.infinity)),
                  chrome: chrome,
                  bold: true,
                  valueColor: document.paidDate != null
                      ? AppColors.success
                      : AppColors.warningDark,
                ),
              ],

              // Deposit actions — only editable on draft/pending/approved documents
              if (availableDeposits.isNotEmpty || appliedDepositId != null) ...[
                const SizedBox(height: 16),
                Divider(
                  height: 1,
                  color: chrome.isDark ? chrome.divider : null,
                ),
                const SizedBox(height: 12),
                if (appliedDepositId != null)
                  _buildAppliedDepositChip(
                    document,
                    appliedDeposit,
                    fmt,
                    canEdit: _canEditDeposit(document),
                  )
                else if (_canEditDeposit(document))
                  _buildApplyDepositButton(document, availableDeposits, fmt),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _billingSummaryRow(
    String label,
    String value, {
    required ChromeColors chrome,
    bool bold = false,
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
            color: chrome.isDark ? chrome.text : AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: valueColor ?? (chrome.isDark ? chrome.textActive : null),
          ),
        ),
      ],
    );
  }

  bool _canEditDeposit(GeneratedDocument document) {
    const editableStatuses = {
      DocumentStatus.draft,
      DocumentStatus.pending,
      DocumentStatus.approved,
    };
    return editableStatuses.contains(document.status);
  }

  Widget _buildAppliedDepositChip(
    GeneratedDocument document,
    AvailableDeposit? deposit,
    String Function(double) fmt, {
    bool canEdit = true,
  }) {
    final label = deposit?.documentNumber ?? 'Deposit';
    final amount =
        (document.metadata['applied_deposit_amount'] as num?)?.toDouble() ?? 0;
    return Row(
      children: [
        Icon(Icons.account_balance_wallet, size: 16, color: AppColors.success),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$label applied (${fmt(amount)})',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
        if (canEdit)
          TextButton.icon(
            onPressed: () => _removeDeposit(document),
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Remove'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              visualDensity: VisualDensity.compact,
            ),
          ),
      ],
    );
  }

  Widget _buildApplyDepositButton(
    GeneratedDocument document,
    List<AvailableDeposit> deposits,
    String Function(double) fmt,
  ) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _showApplyDepositDialog(document, deposits, fmt),
        icon: const Icon(Icons.account_balance_wallet, size: 18),
        label: const Text('Apply Deposit'),
      ),
    );
  }

  Future<void> _showApplyDepositDialog(
    GeneratedDocument document,
    List<AvailableDeposit> deposits,
    String Function(double) fmt,
  ) async {
    final selected = await showDialog<AvailableDeposit>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.account_balance_wallet,
              size: 22,
              color: AppColors.primary,
            ),
            const SizedBox(width: 10),
            const Text('Apply Deposit'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Select a deposit to apply to this invoice.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              ...deposits.map(
                (d) => ListTile(
                  leading: const Icon(Icons.account_balance_wallet),
                  title: Text(d.documentNumber ?? 'Deposit'),
                  subtitle: Text(fmt(d.amount)),
                  trailing: const Icon(Icons.chevron_right),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  onTap: () => Navigator.of(ctx).pop(d),
                ),
              ),
              if (deposits.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Text(
                    'No deposits available for this project.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selected == null || !mounted) return;
    await _applyDeposit(document, selected);
  }

  Future<void> _applyDeposit(
    GeneratedDocument document,
    AvailableDeposit deposit,
  ) async {
    if (_documentService is! SupabaseDocumentService) return;
    try {
      await _documentService.applyDeposit(
        documentId: document.id,
        depositDocumentId: deposit.id,
        depositAmount: deposit.amount,
      );
      if (mounted) await _loadDocument();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to apply deposit: $e')));
      }
    }
  }

  Future<void> _removeDeposit(GeneratedDocument document) async {
    if (_documentService is! SupabaseDocumentService) return;
    try {
      await _documentService.removeDeposit(
        documentId: document.id,
      );
      if (mounted) await _loadDocument();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to remove deposit: $e')));
      }
    }
  }

  Future<void> _showUpdateBudgetDialog(GeneratedDocument document) async {
    // Build a map of budgetItemId → document line item amount
    final docAmounts = <String, double>{};
    for (final lineItem in document.lineItems) {
      if (lineItem.budgetItemId != null &&
          lineItem.isItem &&
          lineItem.isVisible) {
        docAmounts[lineItem.budgetItemId!] =
            (docAmounts[lineItem.budgetItemId!] ?? 0.0) + lineItem.total;
      }
    }
    // Also use budgetItemAmounts if line items don't have budgetItemId
    if (docAmounts.isEmpty && document.budgetItemAmounts != null) {
      docAmounts.addAll(document.budgetItemAmounts!);
    }

    if (docAmounts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No budget item amounts to update')),
        );
      }
      return;
    }

    // Load current budget items
    final budgetItems = <BudgetItem>[];
    try {
      for (final id in docAmounts.keys) {
        final item = await (_budgetService as dynamic).getBudgetItem(id);
        if (item != null) budgetItems.add(item as BudgetItem);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load budget items: $e')),
        );
      }
      return;
    }

    if (budgetItems.isEmpty || !mounted) return;

    final currencyCode = context.read<WorkspaceProvider>().currencyCode;
    final isVendorDoc = document.documentType == DocumentType.purchaseOrder ||
        document.documentType == DocumentType.requestForBid ||
        document.documentType == DocumentType.bill ||
        document.documentType == DocumentType.vendorCredit ||
        document.documentType == DocumentType.expense ||
        document.documentType == DocumentType.vendorRefund;
    final fieldLabel = isVendorDoc ? 'Committed Cost' : 'Approved Price';

    // Build diff items — only show items where amounts differ
    final diffs = <_BudgetDiffItem>[];
    for (final item in budgetItems) {
      final docAmount = docAmounts[item.id] ?? 0.0;
      final currentAmount =
          isVendorDoc ? item.committedCost : item.approvedPrice;
      if ((docAmount - currentAmount).abs() > 0.01) {
        diffs.add(
          _BudgetDiffItem(
            item: item,
            currentAmount: currentAmount,
            documentAmount: docAmount,
            selected: true,
          ),
        );
      }
    }

    if (diffs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Budget items are already up to date')),
        );
      }
      return;
    }

    final selectedDiffs = await showDialog<List<_BudgetDiffItem>>(
      context: context,
      builder: (context) => _UpdateBudgetDialog(
        diffs: diffs,
        fieldLabel: fieldLabel,
        currencyCode: currencyCode,
      ),
    );

    if (selectedDiffs == null || selectedDiffs.isEmpty || !mounted) return;

    try {
      final fieldKey = isVendorDoc ? 'committedCost' : 'approvedPrice';
      for (final diff in selectedDiffs) {
        await (_budgetService as dynamic).updateBudgetItemField(diff.item.id, {
          fieldKey: diff.documentAmount,
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Updated ${selectedDiffs.length} budget item${selectedDiffs.length == 1 ? '' : 's'}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update budget: $e')));
      }
    }
  }

  /// Shows a confirmation dialog and creates the invoice (or other customer
  /// document) directly, skipping the full creation wizard.
  Future<void> _showQuickConvertDialog(DocumentType targetType) async {
    final source = _document;
    if (source == null) return;

    final template = await _templateService.getDefaultTemplate(
      source.workspaceId,
      targetType,
    );
    if (template == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No default ${targetType.displayName} template found. Create one in Templates.',
            ),
          ),
        );
      }
      return;
    }

    final visibleItems = source.lineItems
        .where((item) => item.isVisible && item.isItem)
        .toList();
    final subtotal = visibleItems.fold(0.0, (sum, i) => sum + i.total);
    final taxAmount = source.computedTaxAmount; // per-line taxability [M002]
    final total = source.computedGrandTotal; // subtotal − discount + tax [M004]
    final currencyCode = context.read<WorkspaceProvider>().currencyCode;
    final defaultDueDate = DateTime.now().add(const Duration(days: 30));

    if (!mounted) return;
    final result = await showDialog<_QuickConvertResult>(
      context: context,
      builder: (ctx) => _QuickConvertDialog(
        sourceDocument: source,
        targetType: targetType,
        templateName: template.name,
        lineItemCount: visibleItems.length,
        subtotal: subtotal,
        taxAmount: taxAmount,
        total: total,
        currencyCode: currencyCode,
        defaultDueDate: defaultDueDate,
        customerName: source.preparedFor?.organization ??
            source.preparedFor?.name ??
            source.customerName ??
            '',
        projectName: _projectName ?? '',
      ),
    );

    if (result == null || !mounted) return;

    if (result.customize) {
      // Fall back to the full wizard
      _createDerivedDocument(targetType);
      return;
    }

    // Quick-create the document directly
    await _performQuickConvert(
      source: source,
      template: template,
      targetType: targetType,
      dueDate: result.dueDate,
    );
  }

  Future<void> _performQuickConvert({
    required GeneratedDocument source,
    required dynamic template,
    required DocumentType targetType,
    required DateTime dueDate,
  }) async {
    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.appUser?.id;
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    if (userId == null || workspaceId == null) return;

    setState(() => _isLoading = true);

    try {
      final now = DateTime.now();
      final dateFormat = DateFormat('MM/dd/yyyy');
      final dateSuffix = now.millisecondsSinceEpoch.toString().substring(7);

      // Carry forward visible line items from source
      final lineItems =
          source.lineItems.where((item) => item.isVisible).toList();
      final visibleLeafItems = lineItems.where((i) => i.isItem).toList();
      final subtotal = visibleLeafItems.fold(0.0, (sum, i) => sum + i.total);
      final taxAmount = source.computedTaxAmount; // per-line taxability [M002]
      final grandTotal = source.computedGrandTotal; // − discount [M004]

      // Build prepared-by from current user + workspace
      final preparedBy = DocumentContactInfo(
        name: authProvider.appUser?.displayName,
        organization: _workspace?.name,
        email: authProvider.appUser?.email,
        phone: source.preparedBy?.phone,
        address: _workspace?.fullCompanyAddress?.replaceAll('\n', ', ').trim(),
      );

      // Build template rendering context (mirrors CreateDocumentScreen._buildContextData)
      final templateContext = <String, dynamic>{
        'date': {
          'today': dateFormat.format(now),
          'day': now.day.toString(),
          'month': DateFormat('MMMM').format(now),
          'year': now.year.toString(),
          'time': DateFormat('hh:mm a').format(now),
        },
        'user': {
          'name': authProvider.appUser?.displayName ?? '',
          'email': authProvider.appUser?.email ?? '',
        },
        'workspace': {
          'name': _workspace?.name ?? preparedBy.organization ?? '',
          'address': preparedBy.address ?? '',
          'email': preparedBy.email ?? '',
          'phone': preparedBy.phone ?? '',
        },
        if (_projectName != null && source.projectId != null)
          'project': {
            'name': _projectName!,
            'address': '',
            'description': '',
            'status': '',
            'startDate': '',
            'endDate': '',
          },
        if (source.preparedFor != null)
          'customer': {
            'name': source.preparedFor!.name ?? '',
            'email': source.preparedFor!.email ?? '',
            'phone': source.preparedFor!.phone ?? '',
            'address': source.preparedFor!.address ?? '',
            'company': source.preparedFor!.organization ?? '',
          },
        'invoice': {
          'number': 'INV-$dateSuffix',
          'dueDate': dateFormat.format(dueDate),
          'subtotal': subtotal.toStringAsFixed(2),
          'taxPercent': source.taxRate.toStringAsFixed(2),
          'taxAmount': taxAmount.toStringAsFixed(2),
          'total': grandTotal.toStringAsFixed(2),
        },
        'lineItems': source.lineItemVisibility == LineItemVisibility.none
            ? visibleLeafItems
                .map(
                  (item) => {
                    'id': item.id,
                    'name': item.name,
                    'description': item.description?.trim().isNotEmpty == true
                        ? item.description!.trim()
                        : '',
                    'quantity': item.quantity.toStringAsFixed(2),
                    'rate': item.unitPrice.toStringAsFixed(2),
                    'amount': item.total.toStringAsFixed(2),
                  },
                )
                .toList()
            : <Map<String, dynamic>>[],
        'pricing': source.lineItemVisibility == LineItemVisibility.none,
      };

      final document = await _documentService.generateDocument(
        workspaceId: workspaceId,
        template: template,
        context: templateContext,
        projectId: source.projectId,
        customerId: source.customerId,
        customerName: source.customerName,
        createdBy: userId,
        documentDate: now,
        dueDate: dueDate,
        preparedBy: preparedBy,
        preparedFor: source.preparedFor,
        footerContent: source.footerContent,
        emailSubject: '${targetType.displayName} for your review',
        emailMessage:
            'Please review and sign the attached document at your earliest convenience.\n\n'
            'Click the link below to view and sign the document.',
        budgetItemAmounts: source.budgetItemAmounts,
        lineItems: lineItems,
        lineItemVisibility: source.lineItemVisibility,
        lineItemSourceMode: LineItemSourceMode.snapshot,
        collectTax: source.collectTax,
        taxName: source.collectTax ? source.taxName : null,
        taxRate: source.collectTax ? source.taxRate : 0,
        sourceDocumentId: source.id,
      );

      if (mounted) {
        // Update derived documents immediately so the workflow chain reflects
        // the new document and "Create Invoice" disappears — prevents the user
        // from thinking nothing happened and clicking again.
        setState(() {
          _derivedDocuments = [..._derivedDocuments, document];
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${targetType.displayName} created from ${source.templateName}',
            ),
          ),
        );
        context.push('/documents/${document.id}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(
                e,
                action: 'creating ${targetType.displayName}',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _createDerivedDocument(DocumentType targetType) async {
    final source = _document;
    if (source == null) return;

    try {
      final template = await _templateService.getDefaultTemplate(
        source.workspaceId,
        targetType,
      );
      if (template == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'No default ${targetType.displayName} template found. Create one in Templates.',
              ),
            ),
          );
        }
        return;
      }

      final prePopulatedLineItems = source.lineItems
          .where((item) => item.isVisible && item.isItem)
          .map(
            (item) => {
              'description': item.name,
              'quantity': item.quantity,
              'unit': item.unit ?? '',
              'amount': item.total,
              if (item.budgetItemId != null) 'budgetItemId': item.budgetItemId,
            },
          )
          .toList();

      final query = <String, String>{'templateId': template.id};
      if (source.projectId != null && source.projectId!.isNotEmpty) {
        query['projectId'] = source.projectId!;
      }

      if (!mounted) return;
      context.go(
        Uri(path: '/documents/create', queryParameters: query).toString(),
        extra: {
          'lineItems': prePopulatedLineItems,
          'selectedBudgetItemIds': source.budgetItemIds,
          'budgetItemAmounts': source.budgetItemAmounts ?? <String, double>{},
          'sourceDocumentId': source.id,
          if (source.vendorId != null) 'vendorId': source.vendorId,
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not start conversion: $e')));
    }
  }

  List<Widget> _buildActions(BuildContext context, GeneratedDocument document) {
    final primaryActionsLocked = document.status == DocumentStatus.signed ||
        document.status == DocumentStatus.applied;
    return [
      if (!primaryActionsLocked) ...[
        if (document.status == DocumentStatus.pending)
          IconButton(
            icon: const Icon(Icons.verified),
            tooltip: 'Approve Document',
            onPressed: () => _approveDocument(context),
          ),
        IconButton(
          icon: const Icon(Icons.edit),
          tooltip: 'Edit Document',
          onPressed: () => _editDocument(context, document),
        ),
        IconButton(
          icon: const Icon(Icons.draw),
          tooltip: 'Sign Document',
          onPressed: () => _showSignatureDialog(context),
        ),
        IconButton(
          icon: const Icon(Icons.send),
          tooltip: 'Send',
          onPressed: () => _showSendDialog(context),
        ),
      ],
      if (_linkedBudgetItems.isNotEmpty && document.projectId != null)
        IconButton(
          icon: const Icon(Icons.table_view),
          tooltip: 'Open $_projectTerminologySingular Budget',
          onPressed: () =>
              context.push('/projects/${document.projectId}/budget'),
        ),
      IconButton(
        icon: _isExportingPdf
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.picture_as_pdf),
        tooltip: _isExportingPdf ? _pdfExportStatus : 'Export PDF',
        onPressed: _isExportingPdf ? null : _exportPdf,
      ),
      PopupMenuButton<String>(
        onSelected: (value) async {
          switch (value) {
            case 'delete':
              await _deleteDocument(context);
              break;
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete, size: 20, color: AppColors.error),
                SizedBox(width: 12),
                Text('Delete', style: TextStyle(color: AppColors.error)),
              ],
            ),
          ),
        ],
      ),
    ];
  }

  Widget _buildSinglePaneBody(
    GeneratedDocument document,
    double bottomReserve,
  ) {
    final actionSteps = _actionNextStepsFor(document);
    _ActionNextStep? urgent;
    _ActionNextStep? primary;
    for (final s in actionSteps) {
      if (urgent == null && s.icon == Icons.warning_amber) urgent = s;
      if (primary == null && s.primary && s.onTap != null) primary = s;
      if (urgent != null && primary != null) break;
    }
    final filteredSteps = actionSteps
        .where((s) => s != urgent && s != primary)
        .toList(growable: false);

    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        _buildMobileContextBar(document, primary),
        if (urgent != null) _buildUrgentBanner(urgent),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomReserve),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDocumentPaneChild(document),
                const SizedBox(height: 16),
                _buildMobileDetailsExpander(
                  document,
                  filteredActionSteps: filteredSteps,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileContextBar(
    GeneratedDocument document,
    _ActionNextStep? primary,
  ) {
    final statusColor = _getStatusColor(document.status);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(AppRadius.r12),
            ),
            child: Text(
              document.status.displayName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Created ${document.formattedCreatedAt}',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (primary != null) ...[
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: primary.onTap,
              icon: Icon(primary.icon, size: 16),
              label: Text(primary.label),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUrgentBanner(_ActionNextStep step) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: 10),
      color: AppColors.warningLight,
      child: Row(
        children: [
          Icon(step.icon, size: 18, color: AppColors.warningDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.warningDark,
                  ),
                ),
                Text(
                  step.hint,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.warningDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileDetailsExpander(
    GeneratedDocument document, {
    required List<_ActionNextStep> filteredActionSteps,
  }) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base, vertical: AppSpacing.xs),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Row(
            children: [
              Icon(
                Icons.tune,
                size: 18,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              const Text(
                'Workflow & details',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          children: [
            _buildStatusCard(document),
            const SizedBox(height: 12),
            if (document.budgetItemIds.isNotEmpty) ...[
              Card(
                margin: EdgeInsets.zero,
                child: SwitchListTile(
                  title: const Text('Exclude from Budget'),
                  subtitle: Text(
                    document.excludeFromBudget
                        ? 'This document is excluded from budget calculations'
                        : 'This document contributes to budget totals',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  value: document.excludeFromBudget,
                  onChanged: (value) => _toggleExcludeFromBudget(value),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (filteredActionSteps.isNotEmpty)
              _buildActionNextStepsCard(
                document,
                overrideSteps: filteredActionSteps,
              ),
            _buildDocumentTreeCard(document),
            _buildReceivingCard(document),
            if (document.isSigned) ...[
              _buildSignedCard(document),
              const SizedBox(height: 12),
            ],
            if (_invoiceSummary != null &&
                (document.documentType == DocumentType.invoice ||
                    document.documentType == DocumentType.progressInvoice))
              _buildProgressBillingSummary(document, _invoiceSummary!),
            if (document.documentType == DocumentType.requestForBid &&
                document.bidPackageId != null)
              BidPackageBanner(packageId: document.bidPackageId!),
            if (document.documentType == DocumentType.requestForBid &&
                document.bidPackageId == null &&
                (document.status == DocumentStatus.responded ||
                    document.status == DocumentStatus.applied))
              BidReviewPanel(
                document: document,
                onApplied: () async {
                  if (mounted) await _loadDocument();
                },
                onRejected: () async {
                  if (mounted) await _loadDocument();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTwoPaneBody(
    GeneratedDocument document,
    double bottomReserve,
  ) {
    const sidePaneWidth = 380.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 24, 12, 24 + bottomReserve),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: _buildDocumentPaneChild(document),
              ),
            ),
          ),
        ),
        Container(
          width: 1,
          color: Theme.of(context).dividerColor,
        ),
        SizedBox(
          width: sidePaneWidth,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 24 + bottomReserve),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _buildSidePaneChildren(document),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildSidePaneChildren(GeneratedDocument document) {
    return [
      _buildStatusCard(document),
      const SizedBox(height: 16),
      if (document.budgetItemIds.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Card(
            child: SwitchListTile(
              title: const Text('Exclude from Budget'),
              subtitle: Text(
                document.excludeFromBudget
                    ? 'This document is excluded from budget calculations'
                    : 'This document contributes to budget totals',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              value: document.excludeFromBudget,
              onChanged: (value) => _toggleExcludeFromBudget(value),
            ),
          ),
        ),
      _buildActionNextStepsCard(document),
      _buildDocumentTreeCard(document),
      if (document.isSigned) ...[
        _buildSignedCard(document),
        const SizedBox(height: 16),
      ],
      if (_invoiceSummary != null &&
          (document.documentType == DocumentType.invoice ||
              document.documentType == DocumentType.progressInvoice))
        _buildProgressBillingSummary(document, _invoiceSummary!),
      if (document.documentType == DocumentType.requestForBid &&
          document.bidPackageId != null)
        BidPackageBanner(packageId: document.bidPackageId!),
      if (document.documentType == DocumentType.requestForBid &&
          document.bidPackageId == null &&
          (document.status == DocumentStatus.responded ||
              document.status == DocumentStatus.applied))
        BidReviewPanel(
          document: document,
          onApplied: () async {
            if (mounted) await _loadDocument();
          },
          onRejected: () async {
            if (mounted) await _loadDocument();
          },
        ),
    ];
  }

  Widget _buildDocumentPaneChild(GeneratedDocument document) {
    return DocumentPreviewWidget(
      logoUrl: _workspace?.avatarUrl,
      templateName: document.templateName,
      documentNumber: document.documentNumber,
      documentDate: document.createdAt,
      expiryDate: document.dueDate,
      expiryDateLabel: document.documentType.expiryDateLabel,
      documentType: document.documentType,
      preparedBy: document.preparedBy,
      preparedFor: document.preparedFor,
      renderedContent: document.renderedContent,
      lineItems: document.lineItems,
      lineItemVisibility: document.lineItemVisibility,
      footerContent: document.footerContent,
      showSignaturePlaceholder: false,
      collectTax: document.collectTax,
      taxName: document.taxName ?? 'Tax',
      taxRate: document.taxRate,
      discountAmount: document.discountAmount,
      depositAmount:
          (document.metadata['applied_deposit_amount'] as num?)?.toDouble() ??
              0,
      depositLabel: document.metadata['applied_deposit_document_id'] != null
          ? 'Less Deposit'
          : null,
      retainagePercent: document.retainagePercent,
      retainageAmount: document.retainageAmount,
    );
  }

  Widget _buildStatusCard(GeneratedDocument document) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: _getStatusColor(document.status).withAlpha(51),
              child: Icon(
                document.status == DocumentStatus.signed
                    ? Icons.check_circle
                    : Icons.description,
                color: _getStatusColor(document.status),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.templateName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Chip(
                        label: Text(
                          document.status.displayName,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        backgroundColor: _getStatusColor(document.status),
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Created ${document.formattedCreatedAt}',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  if (document.sentTo != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Sent to ${document.preparedFor?.name ?? document.sentTo} on ${document.formattedSentAt}',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (document.isApproved) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Approved by ${document.approvedBy} on ${document.formattedApprovedAt}',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (document.status == DocumentStatus.signed &&
                      document.signedByName != null &&
                      document.signedAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Signed by ${document.signedByName} on ${document.formattedSignedAt}',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignedCard(GeneratedDocument document) {
    return Card(
      color: AppColors.successLight,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified, color: AppColors.successDark),
                const SizedBox(width: 8),
                Text(
                  'Document Signed',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.successDark,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Signed by:',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        document.signedByName ?? 'Unknown',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      if (document.signedByEmail != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          document.signedByEmail!,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'Date: ${document.formattedSignedAt}',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (document.signatureUrl != null) ...[
                  Container(
                    width: 150,
                    height: 75,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: AppColors.cardBorder),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: CachedNetworkImage(
                        imageUrl: document.signatureUrl!,
                        fit: BoxFit.contain,
                        errorWidget: (context, url, error) => const Center(
                          child: Icon(
                            Icons.draw,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      if (widget.embedded) {
        return const Center(child: CircularProgressIndicator());
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_document == null) {
      if (widget.embedded) {
        return const Center(child: Text('Document not found'));
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Document Not Found')),
        body: const Center(child: Text('Document not found')),
      );
    }

    final document = _document!;

    // Reserve space below content on mobile so the floating bottom nav bar
    // (~70px + safe area + platform pad) doesn't cover the document footer.
    final isMobile = AppBreakpoints.isMobileContext(context);
    final platformBottomPad =
        Theme.of(context).platform == TargetPlatform.iOS ? 16.0 : 8.0;
    final bottomReserve = isMobile && !widget.embedded
        ? MediaQuery.paddingOf(context).bottom + platformBottomPad + 70 + 12
        : 0.0;

    final body = Stack(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= AppBreakpoints.tablet;
            if (isWide) {
              return _buildTwoPaneBody(document, bottomReserve);
            }
            return _buildSinglePaneBody(document, bottomReserve);
          },
        ),
        if (_isExportingPdf)
          Positioned.fill(
            child: Container(
              color: Colors.black26,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(_pdfExportStatus),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (_isSigning)
          Positioned.fill(
            child: Container(
              color: Colors.black26,
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Signing document...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    if (widget.embedded) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: widget.onBack,
                  tooltip: 'Back to documents',
                ),
                if (widget.onToggleExpand != null)
                  IconButton(
                    icon: Icon(
                      widget.isExpanded
                          ? Icons.close_fullscreen
                          : Icons.open_in_full,
                      size: 18,
                    ),
                    onPressed: widget.onToggleExpand,
                    tooltip: widget.isExpanded ? 'Collapse' : 'Expand',
                  ),
                Expanded(
                  child: Text(
                    document.templateName,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ..._buildActions(context, document),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(actions: _buildActions(context, document)),
      body: body,
    );
  }

  Future<void> _showSignatureDialog(BuildContext context) async {
    if (mounted) setState(() => _isSigning = true);
    try {
      await SignatureDialog.show(
        context,
        title: 'Sign Document',
        disclaimer:
            'By signing, you agree to the terms and conditions outlined in this document.',
        onSign: (name, email, pngBytes) async {
          final signatureUrl = await _uploadSignature(pngBytes);

          // Capture pre-sign project status so we can detect if the DB trigger
          // auto-advanced the project when the quotation was signed.
          final isQuotation = _document?.documentType == DocumentType.quotation;
          final projectId = _document?.projectId;
          ProjectStatus? preSignStatus;
          if (isQuotation && projectId != null) {
            try {
              final project = await _projectService.getProject(projectId);
              preSignStatus = project?.status;
            } catch (_) {}
          }

          await _documentService.signDocument(
            documentId: widget.documentId,
            signatureUrl: signatureUrl,
            signedByName: name,
            signedByEmail: email,
          );

          await _loadDocument();

          if (mounted) {
            String message = 'Document signed successfully!';
            if (preSignStatus != null && preSignStatus.isPipeline) {
              try {
                final project = await _projectService.getProject(projectId!);
                if (project != null &&
                    project.status == ProjectStatus.awarded) {
                  message =
                      'Document signed — ${project.name} updated to Awarded';
                }
              } catch (_) {}
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                duration: const Duration(seconds: 4),
              ),
            );
          }
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'signing document'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSigning = false);
    }
  }

  Future<String> _uploadSignature(Uint8List signatureBytes) async {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    if (workspaceId == null) {
      throw Exception('No workspace selected');
    }

    return await _storageService.uploadSignature(
      signatureBytes: signatureBytes,
      workspaceId: workspaceId,
      documentId: widget.documentId,
    );
  }

  Future<void> _approveDocument(BuildContext context) async {
    final doc = _document;
    if (doc == null) return;
    try {
      final authProvider = context.read<AuthProvider>();
      final approvedBy = authProvider.appUser?.displayName ?? '';
      await _documentService.approveDocument(
        documentId: doc.id,
        approvedBy: approvedBy,
      );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Document approved')));
        await _loadDocument();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error approving document: $e')));
      }
    }
  }

  Future<void> _showSendDialog(BuildContext context) async {
    final sent = await SendDocumentDialog.show(
      context,
      document: _document!,
      sendDocument: _sendDocument,
    );
    if (sent == true) {
      await _loadDocument();
    }
  }

  Future<void> _sendDocument(
    String email,
    String subject,
    String message, {
    bool requireSignature = true,
  }) async {
    try {
      // Capture pre-send project status so we can detect auto-advancement.
      final isQuotation = _document?.documentType == DocumentType.quotation;
      final projectId = _document?.projectId;
      ProjectStatus? preSendStatus;
      if (isQuotation && projectId != null) {
        try {
          final project = await _projectService.getProject(projectId);
          preSendStatus = project?.status;
        } catch (_) {}
      }

      await _documentService.sendDocument(
        documentId: widget.documentId,
        email: email,
        subject: subject,
        message: message,
        requireSignature: requireSignature,
      );
      await _loadDocument();
      if (mounted) {
        String snackMessage = 'Document sent to $email';
        // Check if project was auto-advanced to Proposal Sent
        if (preSendStatus != null &&
            (preSendStatus == ProjectStatus.lead ||
                preSendStatus == ProjectStatus.bidding)) {
          try {
            final project = await _projectService.getProject(projectId!);
            if (project != null &&
                project.status == ProjectStatus.proposalSent) {
              snackMessage =
                  'Document sent — ${project.name} updated to Proposal Sent';
            }
          } catch (_) {}
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(snackMessage),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'sending document'),
            ),
          ),
        );
      }
    }
  }

  void _editDocument(BuildContext context, GeneratedDocument document) {
    context.push(
      '/documents/create?templateId=${document.templateId}&projectId=${document.projectId ?? ''}&customerId=${document.customerId ?? ''}',
      extra: {'existingDocument': document},
    );
  }

  Future<void> _deleteDocument(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Document'),
        content: const Text('Are you sure you want to delete this document?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _documentService.deleteDocument(widget.documentId);
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Document deleted')));
          if (widget.embedded && widget.onBack != null) {
            widget.onBack!();
          } else if (GoRouter.of(context).canPop()) {
            context.pop(true);
          } else {
            context.go('/documents');
          }
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                UserFacingError.uiMessage(e, action: 'deleting document'),
              ),
            ),
          );
        }
      }
    }
  }
}

class _LinkedBudgetItemDisplay {
  final String id;
  final String name;
  final double amount;

  const _LinkedBudgetItemDisplay({
    required this.id,
    required this.name,
    required this.amount,
  });

  String get formattedAmount => '\$${amount.toStringAsFixed(2)}';
}

class _BudgetDiffItem {
  final BudgetItem item;
  final double currentAmount;
  final double documentAmount;
  bool selected;

  _BudgetDiffItem({
    required this.item,
    required this.currentAmount,
    required this.documentAmount,
    this.selected = true,
  });
}

class _UpdateBudgetDialog extends StatefulWidget {
  final List<_BudgetDiffItem> diffs;
  final String fieldLabel;
  final String currencyCode;

  const _UpdateBudgetDialog({
    required this.diffs,
    required this.fieldLabel,
    required this.currencyCode,
  });

  @override
  State<_UpdateBudgetDialog> createState() => _UpdateBudgetDialogState();
}

class _UpdateBudgetDialogState extends State<_UpdateBudgetDialog> {
  late List<_BudgetDiffItem> _diffs;

  @override
  void initState() {
    super.initState();
    _diffs = widget.diffs
        .map(
          (d) => _BudgetDiffItem(
            item: d.item,
            currentAmount: d.currentAmount,
            documentAmount: d.documentAmount,
            selected: d.selected,
          ),
        )
        .toList();
  }

  String _fmt(double amount) =>
      CurrencyUtils.formatCurrency(amount, widget.currencyCode);

  @override
  Widget build(BuildContext context) {
    final selectedCount = _diffs.where((d) => d.selected).length;

    return AlertDialog(
      title: const Text('Update Budget Items'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The following budget items have different amounts in this document. '
              'Select which items to update.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Row(
                children: [
                  const SizedBox(width: 40),
                  const Expanded(
                    flex: 3,
                    child: Text(
                      'Item',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Current ${widget.fieldLabel}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    flex: 2,
                    child: Text(
                      'Document Amount',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _diffs.length,
                itemBuilder: (context, index) {
                  final diff = _diffs[index];
                  final delta = diff.documentAmount - diff.currentAmount;
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 40,
                          child: Checkbox(
                            value: diff.selected,
                            onChanged: (val) {
                              setState(() => diff.selected = val ?? false);
                            },
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                diff.item.name,
                                style: const TextStyle(fontSize: 13),
                              ),
                              Text(
                                '${delta >= 0 ? '+' : ''}${_fmt(delta)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: delta >= 0
                                      ? AppColors.success
                                      : AppColors.error,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            _fmt(diff.currentAmount),
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        const Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                          child: Icon(Icons.arrow_forward, size: 14),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            _fmt(diff.documentAmount),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: selectedCount == 0
              ? null
              : () => Navigator.of(
                    context,
                  ).pop(_diffs.where((d) => d.selected).toList()),
          child: Text(
            'Update $selectedCount item${selectedCount == 1 ? '' : 's'}',
          ),
        ),
      ],
    );
  }
}

class _QuickConvertResult {
  final bool customize;
  final DateTime dueDate;
  _QuickConvertResult({required this.customize, required this.dueDate});
}

class _QuickConvertDialog extends StatefulWidget {
  final GeneratedDocument sourceDocument;
  final DocumentType targetType;
  final String templateName;
  final int lineItemCount;
  final double subtotal;
  final double taxAmount;
  final double total;
  final String currencyCode;
  final DateTime defaultDueDate;
  final String customerName;
  final String projectName;

  const _QuickConvertDialog({
    required this.sourceDocument,
    required this.targetType,
    required this.templateName,
    required this.lineItemCount,
    required this.subtotal,
    required this.taxAmount,
    required this.total,
    required this.currencyCode,
    required this.defaultDueDate,
    required this.customerName,
    required this.projectName,
  });

  @override
  State<_QuickConvertDialog> createState() => _QuickConvertDialogState();
}

class _QuickConvertDialogState extends State<_QuickConvertDialog> {
  late DateTime _dueDate;

  String get _projectTerminologySingular {
    final plural = context.read<WorkspaceProvider>().projectTerminology;
    if (plural.endsWith('s') && plural.length > 1) {
      return plural.substring(0, plural.length - 1);
    }
    return plural;
  }

  @override
  void initState() {
    super.initState();
    _dueDate = widget.defaultDueDate;
  }

  String _fmt(double amount) =>
      CurrencyUtils.formatCurrency(amount, widget.currencyCode);

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.sourceDocument;
    final sourceName = [
      if (source.documentNumber != null && source.documentNumber!.isNotEmpty)
        source.documentNumber!,
      source.templateName,
    ].join(' — ');

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.receipt_long, size: 22, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(child: Text('Create ${widget.targetType.displayName}')),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Source document info
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'From',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sourceName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Summary rows
            if (widget.customerName.isNotEmpty)
              _summaryRow('Customer', widget.customerName),
            if (widget.projectName.isNotEmpty)
              _summaryRow(_projectTerminologySingular, widget.projectName),
            _summaryRow(
              'Line items',
              '${widget.lineItemCount} item${widget.lineItemCount == 1 ? '' : 's'}',
            ),
            _summaryRow('Template', widget.templateName),
            const Divider(height: 24),

            // Financial summary
            _summaryRow('Subtotal', _fmt(widget.subtotal)),
            if (widget.taxAmount > 0)
              _summaryRow(
                'Tax (${source.taxName ?? 'Tax'} ${source.taxRate.toStringAsFixed(1)}%)',
                _fmt(widget.taxAmount),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    _fmt(widget.total),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Due date picker
            InkWell(
              onTap: _pickDueDate,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.cardBorder),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Due Date',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          Text(
                            DateFormat('MMM d, yyyy').format(_dueDate),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.edit, size: 14, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(_QuickConvertResult(customize: true, dueDate: _dueDate)),
          child: const Text('Customize...'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(
            context,
          ).pop(_QuickConvertResult(customize: false, dueDate: _dueDate)),
          icon: const Icon(Icons.receipt_long, size: 18),
          label: Text('Create ${widget.targetType.displayName}'),
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChainNextStep {
  final DocumentType? type;
  final IconData? customIcon;
  final String label;
  final String hint;
  final VoidCallback onTap;
  final bool primary;

  const _ChainNextStep({
    this.type,
    this.customIcon,
    required this.label,
    required this.hint,
    required this.onTap,
    this.primary = false,
  });
}

class _DocumentTreeNode {
  final GeneratedDocument document;
  final List<_DocumentTreeNode> children;

  const _DocumentTreeNode({
    required this.document,
    required this.children,
  });
}

class _ActionNextStep {
  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback? onTap;
  final bool primary;
  final bool isInfo;

  const _ActionNextStep({
    required this.icon,
    required this.label,
    required this.hint,
    this.onTap,
    this.primary = false,
    this.isInfo = false,
  });
}

class _ReceivePaymentDialog extends StatefulWidget {
  final String title;
  final String amountLabel;
  final DateTime? existingDate;
  final String? existingMethod;
  final String? existingReference;
  final String? existingAttachmentUrl;
  final double totalAmount;
  final double amountPaid;
  final double balance;
  final String currencyCode;
  final String workspaceId;
  final String documentId;

  const _ReceivePaymentDialog({
    required this.title,
    required this.amountLabel,
    this.existingDate,
    this.existingMethod,
    this.existingReference,
    this.existingAttachmentUrl,
    required this.totalAmount,
    required this.amountPaid,
    required this.balance,
    required this.currencyCode,
    required this.workspaceId,
    required this.documentId,
  });

  @override
  State<_ReceivePaymentDialog> createState() => _ReceivePaymentDialogState();
}

class _ReceivePaymentDialogState extends State<_ReceivePaymentDialog> {
  final _storageService = ServiceLocator.storageService;
  late DateTime _selectedDate;
  String? _selectedMethod;
  late TextEditingController _referenceController;
  late TextEditingController _amountController;
  String? _amountError;
  String? _attachmentUrl;
  String? _attachmentFileName;
  bool _isUploading = false;

  static const _methods = [
    'Cash',
    'Check',
    'Bank Transfer',
    'Credit Card',
    'E-Transfer',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.existingDate ?? DateTime.now();
    _selectedMethod = widget.existingMethod;
    _referenceController = TextEditingController(
      text: widget.existingReference ?? '',
    );
    _amountController = TextEditingController(
      text: widget.balance > 0 ? widget.balance.toStringAsFixed(2) : '',
    );
    _attachmentUrl = widget.existingAttachmentUrl;
    if (_attachmentUrl != null) {
      _attachmentFileName = _resolveAttachmentFileName(_attachmentUrl!);
    }
  }

  @override
  void dispose() {
    _referenceController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  String _resolveAttachmentFileName(String value) {
    final parsed = Uri.tryParse(value);
    final lastSegment = parsed?.pathSegments.lastOrNull;
    if (lastSegment != null && lastSegment.isNotEmpty) {
      return lastSegment;
    }

    final normalized =
        value.endsWith('/') ? value.substring(0, value.length - 1) : value;
    final slashIndex = normalized.lastIndexOf('/');
    if (slashIndex >= 0 && slashIndex < normalized.length - 1) {
      return normalized.substring(slashIndex + 1);
    }

    return 'Attachment';
  }

  Future<void> _pickAndUploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'doc', 'docx'],
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final fileName = file.name;

      setState(() {
        _isUploading = true;
        _attachmentFileName = fileName;
      });

      Uint8List bytes;
      if (kIsWeb) {
        bytes = file.bytes!;
      } else {
        bytes = await File(file.path!).readAsBytes();
      }

      final url = await _storageService.uploadPaymentAttachment(
        bytes: bytes,
        fileName: fileName,
        workspaceId: widget.workspaceId,
        documentId: widget.documentId,
      );

      if (mounted) {
        setState(() {
          _attachmentUrl = url;
          _isUploading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to upload file: $e')));
      }
    }
  }

  void _submitPayment() {
    // Already fully paid: this is an edit-metadata-only submit (amount 0).
    if (widget.balance <= 0.005) {
      Navigator.of(context).pop((
        date: _selectedDate,
        amount: 0.0,
        method: _selectedMethod,
        reference: _referenceController.text.trim().isEmpty
            ? null
            : _referenceController.text.trim(),
        attachmentUrl: _attachmentUrl,
      ));
      return;
    }
    final raw = _amountController.text.trim().replaceAll(',', '');
    final amount = double.tryParse(raw);
    if (amount == null || amount <= 0) {
      setState(() => _amountError = 'Enter a valid amount.');
      return;
    }
    if (amount > widget.balance + 0.005) {
      setState(
        () => _amountError = 'Amount exceeds the outstanding balance '
            '(${CurrencyUtils.formatCurrency(widget.balance, widget.currencyCode)}).',
      );
      return;
    }
    Navigator.of(context).pop((
      date: _selectedDate,
      amount: amount,
      method: _selectedMethod,
      reference: _referenceController.text.trim().isEmpty
          ? null
          : _referenceController.text.trim(),
      attachmentUrl: _attachmentUrl,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.amountPaid > 0) ...[
              Text(
                'Already paid '
                '${CurrencyUtils.formatCurrency(widget.amountPaid, widget.currencyCode)}'
                ' of '
                '${CurrencyUtils.formatCurrency(widget.totalAmount, widget.currencyCode)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).hintColor,
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (widget.balance > 0.005) ...[
              Text(
                '${widget.amountLabel} — balance '
                '${CurrencyUtils.formatCurrency(widget.balance, widget.currencyCode)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 10,
                  ),
                  errorText: _amountError,
                  helperText:
                      'Leave as the balance to pay in full, or enter a partial '
                      'amount.',
                ),
                onChanged: (_) {
                  if (_amountError != null) {
                    setState(() => _amountError = null);
                  }
                },
              ),
            ] else
              Text(
                'Paid in full.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            const SizedBox(height: 16),
            const Text(
              'Payment Date',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 6),
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _selectedDate = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 16),
                    const SizedBox(width: 8),
                    Text(DateFormat('MMM d, yyyy').format(_selectedDate)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Payment Method (optional)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              borderRadius: AppRadius.cardRadius,
              initialValue: _selectedMethod,
              hint: const Text('Select method'),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                isDense: true,
              ),
              items: _methods
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedMethod = v),
            ),
            const SizedBox(height: 16),
            const Text(
              'Reference # (optional)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _referenceController,
              decoration: InputDecoration(
                hintText: 'e.g. Check #, Wire transfer ID',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Attachment (optional)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 6),
            if (_isUploading)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Uploading...'),
                  ],
                ),
              )
            else if (_attachmentUrl != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.attach_file, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _attachmentFileName ?? 'Attachment',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => setState(() {
                        _attachmentUrl = null;
                        _attachmentFileName = null;
                      }),
                    ),
                  ],
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: _pickAndUploadFile,
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Upload File'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 40),
                ),
              ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        if (widget.existingDate != null)
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop((
              date: null,
              amount: null,
              method: null,
              reference: null,
              attachmentUrl: null,
            )),
            child: const Text('Remove'),
          )
        else
          const SizedBox.shrink(),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _isUploading ? null : _submitPayment,
              child: Text(
                widget.existingDate != null ? 'Update' : 'Record Payment',
              ),
            ),
          ],
        ),
      ],
    );
  }
}
