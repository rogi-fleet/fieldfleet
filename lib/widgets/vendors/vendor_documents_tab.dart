import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../models/document_status.dart';
import '../../models/document_type.dart';
import '../../models/generated_document.dart';
import '../../models/template_category.dart';
import '../../models/vendor.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/currency_utils.dart';
import '../../utils/project_terminology.dart';
import '../common/app_search_bar.dart';
import '../common/zero_items_action_empty_state.dart';
import '../documents/document_selection_bar.dart';
import '../table/table_controls_bar.dart';
import 'vendor_related_project_scope.dart';

class VendorDocumentsTab extends StatefulWidget {
  final Vendor vendor;

  const VendorDocumentsTab({super.key, required this.vendor});

  @override
  State<VendorDocumentsTab> createState() => _VendorDocumentsTabState();
}

class _VendorDocumentsTabState extends State<VendorDocumentsTab> {
  final dynamic _documentService = ServiceLocator.documentService;
  late final Future<VendorRelatedProjectScope> _scopeFuture;
  String _searchQuery = '';

  Set<String> _selectedDocumentIds = {};
  List<GeneratedDocument> _currentDocuments = [];

  bool get _isSelectionMode => _selectedDocumentIds.isNotEmpty;

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedDocumentIds.contains(id)) {
        _selectedDocumentIds.remove(id);
      } else {
        _selectedDocumentIds.add(id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedDocumentIds = _currentDocuments.map((d) => d.id).toSet();
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedDocumentIds.clear();
    });
  }

  Future<void> _handleBulkDelete() async {
    final count = _selectedDocumentIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Documents'),
        content: Text('Are you sure you want to delete $count document${count == 1 ? '' : 's'}? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ids = _selectedDocumentIds.toList();
    _clearSelection();
    await Future.wait(
      ids.map((id) => _documentService.deleteDocument(id)),
      eagerError: false,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted $count document${count == 1 ? '' : 's'}')),
      );
    }
  }

  Future<void> _handleBulkApprove() async {
    final approvedBy = context.read<AuthProvider>().appUser?.displayName ?? '';
    final count = _selectedDocumentIds.length;
    final ids = _selectedDocumentIds.toList();
    _clearSelection();
    await Future.wait(
      ids.map((id) => _documentService.approveDocument(
        documentId: id,
        approvedBy: approvedBy,
      )),
      eagerError: false,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Approved $count document${count == 1 ? '' : 's'}')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _scopeFuture = loadVendorRelatedProjectScope(widget.vendor);
  }

  @override
  Widget build(BuildContext context) {
    final pluralTerminology =
        context.watch<WorkspaceProvider>().projectTerminology;
    final singularTerminology =
        singularProjectTerminology(pluralTerminology);

    return FutureBuilder<VendorRelatedProjectScope>(
      future: _scopeFuture,
      builder: (context, scopeSnapshot) {
        if (scopeSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final scope = scopeSnapshot.data;
        if (scope == null || !scope.hasRelatedProjects) {
          return _buildNoProjectsState(pluralTerminology);
        }

        return Column(
          children: [
            TableControlsBar(
              children: [
                Expanded(
                  child: AppSearchBar(
                    hintText: 'Search vendor documents...',
                    onChanged: (value) {
                      setState(() => _searchQuery = value.toLowerCase());
                    },
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  child: Text(
                    'Showing vendor-order and vendor-bill documents from ${scope.projects.length} related ${projectTerminologyForCount(scope.projects.length, pluralTerminology).toLowerCase()}.',
                    style: TextStyle(
                        color: ChromeColors.of(context).scaffoldTextSecondary),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_isSelectionMode)
              DocumentSelectionBar(
                selectedCount: _selectedDocumentIds.length,
                totalCount: _currentDocuments.length,
                onSelectAll: _selectAll,
                onClearSelection: _clearSelection,
                onDelete: _handleBulkDelete,
                onApprove: _handleBulkApprove,
              ),
            Expanded(
              child: StreamBuilder<List<GeneratedDocument>>(
                stream: _documentService.getDocuments(
                  widget.vendor.workspaceId,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final documents =
                      (snapshot.data ?? const <GeneratedDocument>[])
                          .where((document) {
                            final category = document.documentType.category;
                            return document.projectId != null &&
                                scope.projectsById.containsKey(
                                  document.projectId,
                                ) &&
                                (category == TemplateCategory.vendorOrder ||
                                    category == TemplateCategory.vendorBill);
                          })
                          .where((document) {
                            if (_searchQuery.isEmpty) return true;
                            final projectName =
                                scope.projectsById[document.projectId]?.name
                                    .toLowerCase() ??
                                '';
                            return document.templateName.toLowerCase().contains(
                                  _searchQuery,
                                ) ||
                                document.documentType.displayName
                                    .toLowerCase()
                                    .contains(_searchQuery) ||
                                projectName.contains(_searchQuery);
                          })
                          .toList();

                  _currentDocuments = documents;

                  if (_selectedDocumentIds.isNotEmpty) {
                    final validIds = documents.map((d) => d.id).toSet();
                    _selectedDocumentIds.retainAll(validIds);
                  }

                  if (documents.isEmpty) {
                    return _buildEmptyState(
                      singularTerminology,
                      pluralTerminology,
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(AppSpacing.base),
                    itemCount: documents.length,
                    itemBuilder: (context, index) {
                      final document = documents[index];
                      final typeColor = _typeColor(document.documentType);
                      final isSelected = _selectedDocumentIds.contains(document.id);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        color: isSelected ? AppColors.info.withValues(alpha: 0.08) : null,
                        child: ListTile(
                          onLongPress: () => _toggleSelection(document.id),
                          leading: _isSelectionMode
                              ? SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: Center(
                                    child: Checkbox(
                                      value: isSelected,
                                      onChanged: (_) => _toggleSelection(document.id),
                                      activeColor: AppColors.info,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(AppRadius.xs),
                                      ),
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                )
                              : CircleAvatar(
                                  backgroundColor: typeColor.withAlpha(51),
                                  child: Icon(
                                    _typeIcon(document.documentType),
                                    color: typeColor,
                                  ),
                                ),
                          title: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: typeColor,
                                  borderRadius: BorderRadius.circular(AppRadius.r12),
                                ),
                                child: Text(
                                  document.documentNumber != null
                                      ? '${document.documentType.displayName} #${document.documentNumber}'
                                      : document.documentType.displayName,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                scope.projectsById[document.projectId]?.name ??
                                    '$singularTerminology ${document.projectId}',
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Created ${document.formattedCreatedAt}',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              if (document.sentTo != null) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.send,
                                      size: 14,
                                      color: AppColors.textSecondary,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        'Sent to ${document.preparedFor?.name ?? document.sentTo}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if (document.isSigned) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.check_circle,
                                      size: 14,
                                      color: AppColors.success,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        'Signed by ${document.signedByName} on ${document.formattedSignedAt}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.success,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (document.totalAmount > 0)
                                Text(
                                  CurrencyUtils.formatCurrency(
                                    document.totalAmount,
                                    context.read<WorkspaceProvider>().currencyCode,
                                  ),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              const SizedBox(height: 4),
                              Chip(
                                label: Text(
                                  document.status.displayName,
                                  style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
                                ),
                                backgroundColor: _statusColor(document.status),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ],
                          ),
                          onTap: _isSelectionMode
                              ? () => _toggleSelection(document.id)
                              : () => context.go('/documents/${document.id}'),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildNoProjectsState(String pluralTerminology) {
    return ZeroItemsActionEmptyState(
      icon: Icons.description_outlined,
      title: 'No vendor-linked ${pluralTerminology.toLowerCase()} yet',
      subtitle:
          'Purchase orders, bills, or bid requests need to reference this vendor before vendor documents can be inferred.',
      ctaLabel: '',
      onTap: null,
      hintText:
          'Documents will appear automatically once vendor-linked ${pluralTerminology.toLowerCase()} exist',
    );
  }

  Widget _buildEmptyState(
    String singularTerminology,
    String pluralTerminology,
  ) {
    return ZeroItemsActionEmptyState(
      icon: Icons.article_outlined,
      title: 'No generated vendor documents yet',
      subtitle:
          'Vendor-facing purchase orders and bill documents from related ${pluralTerminology.toLowerCase()} will appear here.',
      ctaLabel: '',
      onTap: null,
      hintText:
          'Create a purchase order or bill on a related ${singularTerminology.toLowerCase()} to get started',
    );
  }

  IconData _typeIcon(DocumentType type) {
    switch (type) {
      case DocumentType.purchaseOrder:
        return Icons.shopping_cart_outlined;
      case DocumentType.requestForBid:
        return Icons.gavel_outlined;
      case DocumentType.bill:
        return Icons.receipt_outlined;
      case DocumentType.vendorCredit:
      case DocumentType.vendorRefund:
        return Icons.credit_card_outlined;
      case DocumentType.expense:
        return Icons.money_off_outlined;
      default:
        return Icons.description_outlined;
    }
  }

  Color _typeColor(DocumentType type) {
    switch (type.category) {
      case TemplateCategory.vendorOrder:
        return AppColors.info;
      case TemplateCategory.vendorBill:
        return AppColors.warning;
      case TemplateCategory.customerOrder:
        return AppColors.messageAccent;
      case TemplateCategory.customerInvoice:
        return AppColors.financialAccent;
    }
  }

  Color _statusColor(DocumentStatus status) {
    switch (status) {
      case DocumentStatus.draft:
        return AppColors.textTertiary;
      case DocumentStatus.sent:
        return AppColors.info;
      case DocumentStatus.viewed:
        return AppColors.secondary;
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
}
