import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import '../../models/customer.dart';
import '../../models/document_status.dart';
import '../../models/document_type.dart';
import '../../models/generated_document.dart';
import '../../models/template_category.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/currency_utils.dart';
import '../common/app_search_bar.dart';
import '../common/zero_items_action_empty_state.dart';
import '../documents/document_selection_bar.dart';
import '../table/table_controls_bar.dart';

class _EnrichedDocuments {
  final List<GeneratedDocument> documents;
  final Map<String, String?> projectSerials;
  final Map<String, String?> projectNames;
  final Map<String, DateTime?> firstViewedAt;

  _EnrichedDocuments(
    this.documents,
    this.projectSerials,
    this.projectNames,
    this.firstViewedAt,
  );
}

class CustomerDocumentsTab extends StatefulWidget {
  final Customer customer;

  const CustomerDocumentsTab({super.key, required this.customer});

  @override
  State<CustomerDocumentsTab> createState() => _CustomerDocumentsTabState();
}

class _CustomerDocumentsTabState extends State<CustomerDocumentsTab> {
  final dynamic _documentService = ServiceLocator.documentService;
  DocumentStatus? _filterStatus;
  DocumentType? _filterType;
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
    final authProvider = context.read<AuthProvider>();
    final approvedBy = authProvider.appUser?.displayName ?? '';
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

  static final _dateTimeFormat = DateFormat('MM/dd/yyyy h:mm a');

  String _singularTerminology(BuildContext context) {
    final plural = context.read<WorkspaceProvider>().projectTerminology;
    if (plural.endsWith('s') && plural.length > 1) {
      return plural.substring(0, plural.length - 1);
    }
    return plural;
  }

  Stream<_EnrichedDocuments> _enrichedStream(String workspaceId) {
    return _documentService
        .getDocuments(
          workspaceId,
          customerId: widget.customer.id,
          status: _filterStatus,
          documentType: _filterType,
        )
        .asyncMap((List<GeneratedDocument> documents) async {
      final supabase = Supabase.instance.client;
      final projectSerials = <String, String?>{};
      final projectNames = <String, String?>{};
      final firstViewedAt = <String, DateTime?>{};

      // Fetch project serial numbers and names
      try {
        final projectIds = documents
            .map((d) => d.projectId)
            .whereType<String>()
            .toSet()
            .toList();
        if (projectIds.isNotEmpty) {
          final rows = await supabase
              .from('projects')
              .select('id, serial_number, name')
              .inFilter('id', projectIds);
          for (final row in rows) {
            projectSerials[row['id'] as String] =
                row['serial_number'] as String?;
            projectNames[row['id'] as String] = row['name'] as String?;
          }
        }
      } catch (_) {
        // Non-critical — fall back to showing project without serial/name
      }

      // Fetch first-viewed timestamps from activity log
      try {
        final docIds = documents.map((d) => d.id).toList();
        if (docIds.isNotEmpty) {
          final rows = await supabase
              .from('document_activity_log')
              .select('document_id, created_at')
              .inFilter('document_id', docIds)
              .eq('action', 'viewed')
              .order('created_at', ascending: true);
          for (final row in rows) {
            final docId = row['document_id'] as String;
            if (!firstViewedAt.containsKey(docId)) {
              firstViewedAt[docId] =
                  DateTime.parse(row['created_at'] as String).toLocal();
            }
          }
        }
      } catch (_) {
        // Non-critical — viewed timestamps simply won't show
      }

      return _EnrichedDocuments(
        documents,
        projectSerials,
        projectNames,
        firstViewedAt,
      );
    });
  }

  IconData _getIconForType(DocumentType type) {
    switch (type) {
      case DocumentType.invoice:
      case DocumentType.progressInvoice:
        return Icons.receipt_long;
      case DocumentType.workOrder:
      case DocumentType.workOrderEmergency:
      case DocumentType.workOrderMaintenance:
        return Icons.assignment;
      case DocumentType.quotation:
        return Icons.request_quote;
      case DocumentType.expense:
        return Icons.money_off;
      case DocumentType.bill:
        return Icons.receipt;
      case DocumentType.purchaseOrder:
        return Icons.shopping_cart;
      case DocumentType.custom:
        return Icons.description;
      default:
        return type.category.icon;
    }
  }

  Color _getTypeColor(DocumentType type) {
    switch (type) {
      case DocumentType.invoice:
      case DocumentType.progressInvoice:
        return AppColors.info;
      case DocumentType.workOrder:
      case DocumentType.workOrderEmergency:
      case DocumentType.workOrderMaintenance:
        return AppColors.warning;
      case DocumentType.quotation:
        return AppColors.messageAccent;
      case DocumentType.expense:
        return AppColors.error;
      case DocumentType.bill:
        return Colors.brown;
      case DocumentType.purchaseOrder:
        return AppColors.financialAccent;
      case DocumentType.custom:
        return AppColors.textTertiary;
      default:
        return type.category.color;
    }
  }

  Color _getStatusColor(DocumentStatus status) {
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

  @override
  Widget build(BuildContext context) {
    final workspaceId = context
        .watch<AuthProvider>()
        .appUser
        ?.currentWorkspaceId;

    if (workspaceId == null) {
      return const Center(child: Text('Error: No workspace found'));
    }

    return Column(
      children: [
        TableControlsBar(
          children: [
            Expanded(
              child: AppSearchBar(
                hintText: 'Search documents...',
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.toLowerCase();
                  });
                },
              ),
            ),
            FilledButton.icon(
              onPressed: () {
                context.go(
                  '/documents/create?customerId=${widget.customer.id}',
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('Create Document'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
          child: Row(
            children: [
              PopupMenuButton<DocumentType?>(
                icon: Icon(Icons.category,
                    color: ChromeColors.of(context).scaffoldText),
                tooltip: 'Filter by type',
                onSelected: (type) {
                  setState(() => _filterType = type);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: null, child: Text('All Types')),
                  ...DocumentType.values.map(
                    (type) => PopupMenuItem(
                      value: type,
                      child: Row(
                        children: [
                          Icon(
                            _getIconForType(type),
                            size: 18,
                            color: _getTypeColor(type),
                          ),
                          const SizedBox(width: 8),
                          Text(type.displayName),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              PopupMenuButton<DocumentStatus?>(
                icon: Icon(Icons.filter_list,
                    color: ChromeColors.of(context).scaffoldText),
                tooltip: 'Filter by status',
                onSelected: (status) {
                  setState(() => _filterStatus = status);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: null, child: Text('All Statuses')),
                  ...DocumentStatus.values.map(
                    (status) => PopupMenuItem(
                      value: status,
                      child: Text(status.displayName),
                    ),
                  ),
                ],
              ),
              if (_filterType != null || _filterStatus != null) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _filterType = null;
                      _filterStatus = null;
                    });
                  },
                  child: const Text('Clear Filters'),
                ),
              ],
            ],
          ),
        ),
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
          child: StreamBuilder<_EnrichedDocuments>(
            stream: _enrichedStream(workspaceId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Text(
                      UserFacingError.uiMessage(
                        snapshot.error,
                        action: 'load customer documents',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              final enriched = snapshot.data;
              var documents = enriched?.documents ?? [];
              if (_searchQuery.isNotEmpty) {
                documents = documents.where((document) {
                  return document.templateName.toLowerCase().contains(
                        _searchQuery,
                      ) ||
                      document.documentType.displayName.toLowerCase().contains(
                        _searchQuery,
                      ) ||
                      (document.sentTo?.toLowerCase().contains(_searchQuery) ??
                          false);
                }).toList();
              }

              _currentDocuments = documents;

              if (_selectedDocumentIds.isNotEmpty) {
                final validIds = documents.map((d) => d.id).toSet();
                _selectedDocumentIds.retainAll(validIds);
              }

              if (documents.isEmpty) {
                return _buildEmptyState(context);
              }

              final singular = _singularTerminology(context);

              return ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.base),
                itemCount: documents.length,
                itemBuilder: (context, index) {
                  final document = documents[index];
                  final typeColor = _getTypeColor(document.documentType);
                  final serial = enriched?.projectSerials[document.projectId];
                  final projectName =
                      enriched?.projectNames[document.projectId];
                  final viewedAt = enriched?.firstViewedAt[document.id];

                  final currencyCode = context.read<WorkspaceProvider>().currencyCode;
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
                                _getIconForType(document.documentType),
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
                            'Created ${document.formattedCreatedAt}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (document.projectId != null) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.work_outline,
                                  size: 14,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    serial != null
                                        ? '$singular #$serial'
                                        : projectName ?? singular,
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
                          if (document.sentAt != null) ...[
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
                                    'Sent ${_dateTimeFormat.format(document.sentAt!.toLocal())}${document.sentTo != null ? ' to ${document.preparedFor?.name ?? document.sentTo}' : ''}',
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
                          if (viewedAt != null) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.visibility,
                                  size: 14,
                                  color: AppColors.secondary,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Viewed ${_dateTimeFormat.format(viewedAt)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.secondary,
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
                              CurrencyUtils.formatCurrency(document.totalAmount, currencyCode),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          const SizedBox(height: 4),
                          Chip(
                            label: Text(
                              document.status.displayName,
                              style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                            backgroundColor: _getStatusColor(document.status),
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
  }

  Widget _buildEmptyState(BuildContext context) {
    return ZeroItemsActionEmptyState(
      icon: Icons.description_outlined,
      title: 'No customer documents yet',
      subtitle:
          'Create a document linked to ${widget.customer.displayName}.',
      ctaLabel: 'Create Document',
      onTap: () {
        context.go(
          '/documents/create?customerId=${widget.customer.id}',
        );
      },
    );
  }
}
