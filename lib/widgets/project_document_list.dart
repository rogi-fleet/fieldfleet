import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../models/generated_document.dart';
import '../models/document_type.dart';
import '../models/template_category.dart';
import '../services/service_locator.dart';
import '../providers/auth_provider.dart';
import '../providers/workspace_provider.dart';
import '../theme/theme.dart';
import '../utils/currency_utils.dart';
import '../utils/document_ui_helpers.dart';
import 'documents/document_selection_bar.dart';
import 'documents/document_status_pipeline.dart';

/// A reusable widget that displays a list of GeneratedDocuments
/// filtered by project and optionally by TemplateCategory.
class ProjectDocumentListWidget extends StatefulWidget {
  final String projectId;
  final TemplateCategory? category;

  const ProjectDocumentListWidget({
    super.key,
    required this.projectId,
    this.category,
  });

  @override
  State<ProjectDocumentListWidget> createState() =>
      _ProjectDocumentListWidgetState();
}

class _ProjectDocumentListWidgetState extends State<ProjectDocumentListWidget> {
  final _documentService = ServiceLocator.documentService;
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

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    if (workspaceId == null) {
      return const Center(child: Text('Error: No workspace found'));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search documents...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value.toLowerCase();
              });
            },
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
          child: StreamBuilder<List<GeneratedDocument>>(
            stream: _documentService.getDocuments(
              workspaceId,
              projectId: widget.projectId,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: SelectableText(
                    UserFacingError.uiMessage(
                      snapshot.error,
                      action: 'load data',
                    ),
                  ),
                );
              }

              var documents = snapshot.data ?? [];

              // Filter by category if specified
              if (widget.category != null) {
                documents = documents
                    .where(
                      (doc) => doc.documentType.category == widget.category,
                    )
                    .toList();
              }

              // Filter by search query
              if (_searchQuery.isNotEmpty) {
                documents = documents
                    .where(
                      (doc) =>
                          doc.templateName.toLowerCase().contains(
                            _searchQuery,
                          ) ||
                          (doc.customerName?.toLowerCase().contains(
                                _searchQuery,
                              ) ??
                              false),
                    )
                    .toList();
              }

              _currentDocuments = documents;

              if (_selectedDocumentIds.isNotEmpty) {
                final validIds = documents.map((d) => d.id).toSet();
                _selectedDocumentIds.retainAll(validIds);
              }

              if (documents.isEmpty) {
                return _buildEmptyState(context);
              }

              return ListView.builder(
                itemCount: documents.length,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                itemBuilder: (context, index) {
                  final document = documents[index];
                  return _buildDocumentCard(context, document);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDocumentCard(BuildContext context, GeneratedDocument document) {
    final typeColor = getDocumentTypeColor(document.documentType);
    final currencyCode = context.read<WorkspaceProvider>().currencyCode;
    final personName = document.preparedFor?.name;
    final personRole = document.preparedFor?.organization;
    final isSelected = _selectedDocumentIds.contains(document.id);
    final dateFormat = DateFormat('MMM dd, yyyy');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isSelected ? AppColors.info.withValues(alpha: 0.08) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.r12),
        onTap: _isSelectionMode
            ? () => _toggleSelection(document.id)
            : () => context.push('/documents/${document.id}'),
        onLongPress: () => _toggleSelection(document.id),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header: icon + type badge + doc number + amount ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isSelectionMode) ...[
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: isSelected,
                        onChanged: (_) => _toggleSelection(document.id),
                        activeColor: AppColors.info,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: typeColor.withValues(alpha: 0.12),
                    child: Icon(
                      getDocumentTypeIcon(document.documentType),
                      color: typeColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: typeColor,
                                borderRadius: BorderRadius.circular(AppRadius.xs),
                              ),
                              child: Text(
                                document.documentType.displayName
                                    .toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (document.documentNumber != null)
                              Text(
                                document.documentNumber!,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                          ],
                        ),
                        if (personRole != null &&
                            personRole.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            personRole,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (personName != null &&
                            personName.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(
                                Icons.person,
                                size: 14,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  personName,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (document.totalAmount > 0)
                    Text(
                      CurrencyUtils.formatCurrency(
                        document.totalAmount,
                        currencyCode,
                      ),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),

              // ── Status pipeline ──
              const SizedBox(height: 12),
              DocumentStatusPipeline(document: document),

              // ── Date rows ──
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (document.sentAt != null)
                          _buildDateRow(
                            Icons.send,
                            'Sent ${dateFormat.format(document.sentAt!)}',
                          ),
                        if (document.approvedAt != null)
                          _buildDateRow(
                            Icons.verified,
                            'Approved ${dateFormat.format(document.approvedAt!)}',
                            color: AppColors.success,
                          ),
                        if (document.signedAt != null)
                          _buildDateRow(
                            Icons.draw,
                            'Signed ${dateFormat.format(document.signedAt!)}',
                            color: AppColors.success,
                          ),
                        if (document.paidDate != null)
                          _buildDateRow(
                            Icons.payments,
                            'Paid ${dateFormat.format(document.paidDate!)}',
                            color: AppColors.success,
                          ),
                        if (document.deniedAt != null)
                          _buildDateRow(
                            Icons.cancel,
                            'Denied ${dateFormat.format(document.deniedAt!)}',
                            color: AppColors.error,
                          ),
                        if (document.sentAt == null &&
                            document.approvedAt == null &&
                            document.signedAt == null &&
                            document.paidDate == null &&
                            document.deniedAt == null)
                          _buildDateRow(
                            Icons.calendar_today,
                            'Created ${dateFormat.format(document.createdAt)}',
                          ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildActionButton(
                        icon: Icons.search,
                        tooltip: 'Preview',
                        onTap: () =>
                            context.push('/documents/${document.id}'),
                      ),
                      const SizedBox(width: 4),
                      _buildActionButton(
                        icon: Icons.download,
                        tooltip: 'Download',
                        onTap: () =>
                            context.push('/documents/${document.id}'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateRow(IconData icon, String text, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color ?? AppColors.textTertiary),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: color ?? AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Icon(icon, size: 18, color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final categoryName =
        widget.category?.displayName.toLowerCase() ?? 'document';

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            widget.category?.icon ?? Icons.description,
            size: 64,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            'No ${categoryName}s yet',
            style: TextStyle(fontSize: 18, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a document from a template',
            style: TextStyle(fontSize: 14, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}
