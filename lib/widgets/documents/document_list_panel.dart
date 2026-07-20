import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/document_status.dart';
import '../../models/document_type.dart';
import '../../models/document_view_type.dart';
import '../../models/template_category.dart';
import '../../models/generated_document.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../screens/documents/document_detail_screen.dart';
import '../../screens/documents/widgets/document_table_row.dart';
import '../../theme/theme.dart';
import '../../utils/currency_utils.dart';
import '../../services/service_locator.dart';
import '../../utils/document_ui_helpers.dart';
import '../../config/supabase_config.dart';
import 'document_status_pipeline.dart';
import '../common/draggable_divider.dart';
import '../common/view_icon_button.dart';
import '../common/view_toolbar.dart';
import '../table/table_column_schema.dart';
import '../table/table_header_cells_builder.dart';
import '../table/table_header_row.dart';
import '../table/table_layout_shell.dart';
import '../table/table_view_styles.dart';
import 'document_filter_dialog.dart';
import 'document_selection_bar.dart';

/// Reusable document list with card/table views, search, filters,
/// selection, and an inline detail split pane on desktop.
class DocumentListPanel extends StatefulWidget {
  final Stream<List<GeneratedDocument>> documentStream;
  final String? projectId;
  final VoidCallback? onCreateTap;
  final void Function(String documentId)? onNavigateToDocument;
  final List<Widget> extraQuickToggles;

  /// When set, the detail panel opens with this document on first build.
  final String? initialSelectedDocumentId;

  const DocumentListPanel({
    super.key,
    required this.documentStream,
    this.projectId,
    this.onCreateTap,
    this.onNavigateToDocument,
    this.extraQuickToggles = const [],
    this.initialSelectedDocumentId,
  });

  @override
  State<DocumentListPanel> createState() => _DocumentListPanelState();
}

class _DocumentListPanelState extends State<DocumentListPanel> {
  static const _savedViewsPrefKey = 'saved_document_views';
  DocumentViewType _currentView = DocumentViewType.card;
  String? _selectedDocumentId;
  String _searchQuery = '';
  DocumentStatus? _filterStatus;
  DocumentType? _filterType;
  /// Quick filter: only show documents awaiting a signer/approver response
  /// (status ∈ {sent, viewed}). Orthogonal to [_filterStatus] so it stacks.
  bool _filterNeedsApproval = false;
  String _selectedTypeTab = 'All';
  Set<String> _selectedDocumentIds = {};
  List<GeneratedDocument> _currentDocuments = [];
  List<_SavedDocumentView> _savedViews = [];
  String? _activeSavedViewId;

  // Table sorting
  String? _tableSortColumn;
  bool _tableSortAscending = true;
  final Map<String, double> _columnWidths = {};

  void _handleColumnResize(TableColumnResize resize) {
    setState(() {
      _columnWidths[resize.columnId] = resize.width;
    });
  }

  // Split pane
  double _splitRatio = 0.5;
  bool _isDetailExpanded = false;

  // Guard to avoid duplicate postFrameCallbacks
  bool _pendingDetailClear = false;

  // IDs deleted optimistically before the stream catches up
  final Set<String> _pendingDeleteIds = {};

  @override
  void initState() {
    super.initState();
    _selectedDocumentId = widget.initialSelectedDocumentId;
    _loadViewPreference();
    _loadSavedViews();
  }

  @override
  void didUpdateWidget(DocumentListPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSelectedDocumentId !=
            oldWidget.initialSelectedDocumentId &&
        widget.initialSelectedDocumentId != null) {
      _selectedDocumentId = widget.initialSelectedDocumentId;
    }
  }

  Future<void> _loadViewPreference() async {
    final pref = await loadDocumentViewPreference();
    if (mounted) setState(() => _currentView = pref);
  }

  void _setView(DocumentViewType view) {
    setState(() {
      _currentView = view;
      _activeSavedViewId = null;
    });
    saveDocumentViewPreference(view);
  }

  Future<void> _loadSavedViews() async {
    final raw = await ServiceLocator.userPreferencesService.getSavedViews(
      _savedViewsPrefKey,
    );
    if (!mounted) return;
    setState(() {
      _savedViews = raw.map(_SavedDocumentView.fromMap).toList();
    });
  }

  // ── Selection ──

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
    setState(() => _selectedDocumentIds.clear());
  }

  // ── Bulk Actions ──

  Future<void> _handleBulkDelete() async {
    final count = _selectedDocumentIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Documents'),
        content: Text(
          'Are you sure you want to delete $count document${count == 1 ? '' : 's'}? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
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
    final documentService = ServiceLocator.documentService;
    await Future.wait(
      ids.map((id) => documentService.deleteDocument(id)),
      eagerError: false,
    );
    if (mounted) {
      setState(() {
        _pendingDeleteIds.addAll(ids);
        if (_selectedDocumentId != null && ids.contains(_selectedDocumentId)) {
          _selectedDocumentId = null;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted $count document${count == 1 ? '' : 's'}'),
        ),
      );
    }
  }

  Future<void> _handleBulkApprove() async {
    final authProvider = context.read<AuthProvider>();
    final approvedBy = authProvider.appUser?.displayName ?? '';
    final count = _selectedDocumentIds.length;
    final ids = _selectedDocumentIds.toList();
    _clearSelection();
    final documentService = ServiceLocator.documentService;
    await Future.wait(
      ids.map(
        (id) => documentService.approveDocument(
          documentId: id,
          approvedBy: approvedBy,
        ),
      ),
      eagerError: false,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Approved $count document${count == 1 ? '' : 's'}'),
        ),
      );
    }
  }

  // ── Filtering ──

  int get _activeFilterCount =>
      (_filterStatus != null ? 1 : 0) + (_filterType != null ? 1 : 0);

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (ctx) => DocumentFilterDialog(
        selectedType: _filterType,
        selectedStatus: _filterStatus,
        savedViews: _savedViews
            .map((view) => (id: view.id, name: view.name))
            .toList(growable: false),
        activeSavedViewId: _activeSavedViewId,
        onApply: (type, status) {
          setState(() {
            _filterType = type;
            _filterStatus = status;
            _activeSavedViewId = null;
            // Clear the approval toggle when a status filter is explicitly set
            if (status != null) _filterNeedsApproval = false;
          });
          Navigator.of(ctx).pop();
        },
        onApplySavedView: (viewId) {
          Navigator.of(ctx).pop();
          _applySavedViewById(viewId);
        },
        onSaveView: (type, status) {
          Navigator.of(ctx).pop();
          _showSaveViewDialog(type: type, status: status);
        },
        onDeleteSavedView: (viewId) {
          _deleteSavedViewById(viewId);
        },
      ),
    );
  }

  void _applySavedViewById(String viewId) {
    _SavedDocumentView? view;
    for (final candidate in _savedViews) {
      if (candidate.id == viewId) {
        view = candidate;
        break;
      }
    }
    if (view == null) return;
    final selectedView = view;
    setState(() {
      _currentView = selectedView.viewType;
      _searchQuery = selectedView.searchQuery;
      _filterStatus = selectedView.status;
      _filterType = selectedView.type;
      _tableSortColumn = selectedView.tableSortColumn;
      _tableSortAscending = selectedView.tableSortAscending;
      _activeSavedViewId = selectedView.id;
    });
    saveDocumentViewPreference(selectedView.viewType);
  }

  Future<void> _showSaveViewDialog({
    required DocumentType? type,
    required DocumentStatus? status,
  }) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save current view'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Pending estimates'),
          onSubmitted: (value) {
            final trimmed = value.trim();
            if (trimmed.isNotEmpty) {
              Navigator.of(context).pop(trimmed);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isEmpty) return;
              Navigator.of(context).pop(trimmed);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    final view = _SavedDocumentView(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      searchQuery: _searchQuery,
      viewType: _currentView,
      status: status,
      type: type,
      tableSortColumn: _tableSortColumn,
      tableSortAscending: _tableSortAscending,
      createdAt: DateTime.now(),
    );

    await ServiceLocator.userPreferencesService.upsertSavedView(
      _savedViewsPrefKey,
      view.toMap(),
    );
    if (!mounted) return;
    setState(() => _activeSavedViewId = view.id);
    await _loadSavedViews();
  }

  Future<void> _deleteSavedViewById(String viewId) async {
    await ServiceLocator.userPreferencesService.deleteSavedView(
      _savedViewsPrefKey,
      viewId,
    );
    if (!mounted) return;
    if (_activeSavedViewId == viewId) {
      setState(() => _activeSavedViewId = null);
    }
    await _loadSavedViews();
  }

  // ── Table sorting ──

  void _onColumnSortTap(String columnId) {
    setState(() {
      if (_tableSortColumn == columnId) {
        if (_tableSortAscending) {
          _tableSortAscending = false;
        } else {
          _tableSortColumn = null;
          _tableSortAscending = true;
        }
      } else {
        _tableSortColumn = columnId;
        _tableSortAscending = true;
      }
      _activeSavedViewId = null;
    });
  }

  List<GeneratedDocument> _sortDocuments(List<GeneratedDocument> documents) {
    if (_tableSortColumn == null) return documents;
    final sorted = List<GeneratedDocument>.from(documents);
    sorted.sort((a, b) {
      int cmp;
      switch (_tableSortColumn) {
        case 'type':
          cmp = a.documentType.displayName.compareTo(
            b.documentType.displayName,
          );
          break;
        case 'recipient':
          cmp = (a.preparedFor?.name ?? '').compareTo(
            b.preparedFor?.name ?? '',
          );
          break;
        case 'status':
          cmp = a.status.index.compareTo(b.status.index);
          break;
        case 'amount':
          cmp = a.totalAmount.compareTo(b.totalAmount);
          break;
        case 'date':
          cmp = a.createdAt.compareTo(b.createdAt);
          break;
        case 'dueDate':
          final aDue = a.dueDate ?? DateTime(9999);
          final bDue = b.dueDate ?? DateTime(9999);
          cmp = aDue.compareTo(bDue);
          break;
        default:
          cmp = 0;
      }
      return _tableSortAscending ? cmp : -cmp;
    });
    return sorted;
  }

  // ── Document tap ──

  void _onDocumentTap(GeneratedDocument document, bool isDesktop) {
    if (!isDesktop && _isSelectionMode) {
      _toggleSelection(document.id);
      return;
    }
    if (isDesktop) {
      setState(() => _selectedDocumentId = document.id);
    } else {
      _showDocumentActions(document);
    }
  }

  void _showDocumentActions(GeneratedDocument document) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final typeColor = getDocumentTypeColor(document.documentType);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: typeColor.withValues(alpha: 0.12),
                      child: Icon(
                        getDocumentTypeIcon(document.documentType),
                        color: typeColor,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        document.documentNumber != null
                            ? '${document.documentType.displayName} ${document.documentNumber}'
                            : document.documentType.displayName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Divider(),
              if (document.status == DocumentStatus.draft)
                _actionTile(
                  ctx,
                  icon: Icons.send,
                  label: 'Send',
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onNavigateToDocument?.call(document.id);
                  },
                ),
              _actionTile(
                ctx,
                icon: Icons.search,
                label: 'Preview',
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onNavigateToDocument?.call(document.id);
                },
              ),
              _actionTile(
                ctx,
                icon: Icons.download,
                label: 'Download',
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onNavigateToDocument?.call(document.id);
                },
              ),
              _actionTile(
                ctx,
                icon: Icons.edit,
                label: 'Edit',
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onNavigateToDocument?.call(document.id);
                },
              ),
              _actionTile(
                ctx,
                icon: Icons.link,
                label: 'Share Link',
                onTap: () async {
                  Navigator.pop(ctx);
                  final link =
                      '${SupabaseConfig.siteUrl}/documents/${document.id}';
                  await Clipboard.setData(ClipboardData(text: link));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Link copied to clipboard'),
                      ),
                    );
                  }
                },
              ),
              _actionTile(
                ctx,
                icon: Icons.delete_outline,
                label: 'Delete',
                isDestructive: true,
                onTap: () async {
                  Navigator.pop(ctx);
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dCtx) => AlertDialog(
                      title: const Text('Delete Document'),
                      content: const Text(
                        'Are you sure you want to delete this document? This cannot be undone.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dCtx, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dCtx, true),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.error,
                          ),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true && mounted) {
                    try {
                      await ServiceLocator.documentService.deleteDocument(
                        document.id,
                      );
                      if (mounted) {
                        setState(() => _pendingDeleteIds.add(document.id));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Document deleted')),
                        );
                      }
                    } catch (_) {}
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _actionTile(
    BuildContext ctx, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: isDestructive ? AppColors.error : AppColors.textSecondary,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: isDestructive ? AppColors.error : null,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ViewToolbar(
          searchHint: 'Search documents...',
          searchQuery: _searchQuery,
          onSearch: (query) => setState(() {
            _searchQuery = query.toLowerCase();
            _activeSavedViewId = null;
          }),
          centerSlot: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ViewIconButton(
                icon: Icons.grid_view,
                isSelected: _currentView == DocumentViewType.card,
                onTap: () => _setView(DocumentViewType.card),
                tooltip: 'Card view',
              ),
              const SizedBox(width: 4),
              ViewIconButton(
                icon: Icons.view_list,
                isSelected: _currentView == DocumentViewType.table,
                onTap: () => _setView(DocumentViewType.table),
                tooltip: 'Table view',
              ),
            ],
          ),
          quickToggles: [
            ViewIconButton(
              icon: Icons.pending_actions_outlined,
              isSelected: _filterNeedsApproval,
              onTap: () => setState(() {
                _filterNeedsApproval = !_filterNeedsApproval;
                // Clear status filter so the two don't silently conflict
                if (_filterNeedsApproval) _filterStatus = null;
              }),
              tooltip: 'Awaiting approval',
            ),
            if (widget.onCreateTap != null)
              ViewIconButton(
                icon: Icons.note_add_outlined,
                isSelected: false,
                onTap: widget.onCreateTap!,
                tooltip: 'Create Document',
              ),
            ...widget.extraQuickToggles,
          ],
          filterCount: _activeFilterCount,
          onFilterTap: _showFilterDialog,
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
        _buildTypeTabs(),
        Expanded(
          child: StreamBuilder<List<GeneratedDocument>>(
            stream: widget.documentStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                final raw = snapshot.error.toString();
                final clipped = raw.length > 240 ? '${raw.substring(0, 240)}…' : raw;
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 48,
                          color: AppColors.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Failed to load documents',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Surface the underlying error so support / users can
                        // actually diagnose. Previously just the title with
                        // no details — looked like an indefinite blank state.
                        SelectableText(
                          'Details: $clipped',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              var documents = snapshot.data ?? [];

              // Optimistically hide documents deleted before the stream catches up
              if (_pendingDeleteIds.isNotEmpty) {
                final rawIds = documents.map((d) => d.id).toSet();
                final confirmed =
                    _pendingDeleteIds.where((id) => !rawIds.contains(id)).toSet();
                if (confirmed.isNotEmpty && !_pendingDetailClear) {
                  _pendingDetailClear = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _pendingDetailClear = false;
                    if (!mounted) return;
                    setState(() => _pendingDeleteIds.removeAll(confirmed));
                  });
                }
                documents = documents
                    .where((d) => !_pendingDeleteIds.contains(d.id))
                    .toList();
              }

              // Search filter
              if (_searchQuery.isNotEmpty) {
                documents = documents
                    .where(
                      (doc) =>
                          doc.templateName.toLowerCase().contains(
                            _searchQuery,
                          ) ||
                          (doc.preparedFor?.name?.toLowerCase().contains(
                                _searchQuery,
                              ) ??
                              false) ||
                          (doc.customerName?.toLowerCase().contains(
                                _searchQuery,
                              ) ??
                              false),
                    )
                    .toList();
              }

              // Status filter
              if (_filterStatus != null) {
                documents = documents
                    .where((doc) => doc.status == _filterStatus)
                    .toList();
              }

              // Awaiting approval quick filter (sent + viewed)
              if (_filterNeedsApproval) {
                documents = documents.where((doc) {
                  return doc.status == DocumentStatus.sent ||
                      doc.status == DocumentStatus.viewed;
                }).toList();
              }

              // Type filter
              if (_filterType != null) {
                documents = documents
                    .where((doc) => doc.documentType == _filterType)
                    .toList();
              }

              // Type tab filter
              documents = _applyTypeTabFilter(documents);

              // Sort (table view)
              if (_currentView == DocumentViewType.table) {
                documents = _sortDocuments(documents);
              }

              // Defer state mutations to after build
              if (!identical(_currentDocuments, documents)) {
                final validIds = documents.map((d) => d.id).toSet();
                final hasStaleSelections =
                    _selectedDocumentIds.isNotEmpty &&
                    !_selectedDocumentIds.every(validIds.contains);
                final hasStaleDetail =
                    _selectedDocumentId != null &&
                    !validIds.contains(_selectedDocumentId);

                if (hasStaleSelections ||
                    hasStaleDetail ||
                    !identical(_currentDocuments, documents)) {
                  if (!_pendingDetailClear) {
                    _pendingDetailClear = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _pendingDetailClear = false;
                      if (!mounted) return;
                      setState(() {
                        _currentDocuments = documents;
                        if (hasStaleSelections) {
                          _selectedDocumentIds.retainAll(validIds);
                        }
                        if (hasStaleDetail) {
                          _selectedDocumentId = null;
                        }
                      });
                    });
                  }
                }
                // Eagerly update for reads within this build (e.g., _selectAll)
                _currentDocuments = documents;
              }

              if (documents.isEmpty) {
                return _buildEmptyState();
              }

              return LayoutBuilder(
                builder: (context, constraints) {
                  final isDesktop = constraints.maxWidth >= AppBreakpoints.desktop;

                  if (isDesktop && _selectedDocumentId != null) {
                    return _buildSplitLayout(documents, constraints, isDesktop);
                  }

                  return _buildList(documents, isDesktop);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Split layout ──

  Widget _buildSplitLayout(
    List<GeneratedDocument> documents,
    BoxConstraints constraints,
    bool isDesktop,
  ) {
    final detail = DocumentDetailScreen(
      key: ValueKey(_selectedDocumentId),
      documentId: _selectedDocumentId!,
      embedded: true,
      onBack: () => setState(() {
        _selectedDocumentId = null;
        _isDetailExpanded = false;
      }),
      onToggleExpand: () =>
          setState(() => _isDetailExpanded = !_isDetailExpanded),
      isExpanded: _isDetailExpanded,
    );

    if (_isDetailExpanded) {
      return detail;
    }

    const dividerWidth = 8.0;
    final available = constraints.maxWidth - dividerWidth;
    final detailWidth = (available * _splitRatio).clamp(
      300.0,
      available - 300.0,
    );
    final listWidth = available - detailWidth;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: listWidth,
          child: ClipRect(child: _buildList(documents, isDesktop)),
        ),
        GestureDetector(
          onHorizontalDragUpdate: (details) {
            setState(() {
              _splitRatio =
                  ((_splitRatio * available - details.delta.dx) / available)
                      .clamp(300.0 / available, 1.0 - 300.0 / available);
            });
          },
          child: DraggableDivider(width: dividerWidth),
        ),
        SizedBox(width: detailWidth, child: detail),
      ],
    );
  }

  // ── List (card or table) ──

  Widget _buildList(List<GeneratedDocument> documents, bool isDesktop) {
    if (_currentView == DocumentViewType.table) {
      return _buildTableView(documents, isDesktop);
    }
    return _buildCardView(documents, isDesktop);
  }

  // ── Card view ──

  Widget _buildCardView(List<GeneratedDocument> documents, bool isDesktop) {
    return ListView.builder(
      itemCount: documents.length,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      itemBuilder: (context, index) {
        final document = documents[index];
        return _buildDocumentCard(context, document, isDesktop);
      },
    );
  }

  Widget _buildDocumentCard(
    BuildContext context,
    GeneratedDocument document,
    bool isDesktop,
  ) {
    final typeColor = getDocumentTypeColor(document.documentType);
    final currencyCode = context.read<WorkspaceProvider>().currencyCode;
    final personName = document.preparedFor?.name;
    final personRole = document.preparedFor?.organization;
    final isSelected = _selectedDocumentIds.contains(document.id);
    final isHighlighted = _selectedDocumentId == document.id;
    final dateFormat = DateFormat('MMM dd, yyyy');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isSelected
          ? AppColors.info.withValues(alpha: 0.08)
          : isHighlighted
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.05)
              : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.r12),
        side: isHighlighted
            ? BorderSide(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.3),
              )
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.r12),
        onTap: () => _onDocumentTap(document, isDesktop),
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
                  if (_isSelectionMode || isDesktop) ...[
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

              // ── Date rows + action buttons ──
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
                      _CardActionButton(
                        icon: Icons.search,
                        tooltip: 'Preview',
                        onTap: () =>
                            _onDocumentTap(document, isDesktop),
                      ),
                      const SizedBox(width: 4),
                      _CardActionButton(
                        icon: Icons.download,
                        tooltip: 'Download',
                        onTap: () =>
                            _onDocumentTap(document, isDesktop),
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

  // ── Table view ──

  static const _tableColumns = [
    TableColumnSchema(id: 'type', label: 'Type', defaultWidth: kDocTableColType, minWidth: 100, maxWidth: 300),
    TableColumnSchema(id: 'recipient', label: 'Recipient', defaultWidth: kDocTableColRecipient, minWidth: 100, maxWidth: 350),
    TableColumnSchema(id: 'status', label: 'Status', defaultWidth: kDocTableColStatus, minWidth: 80, maxWidth: 200),
    TableColumnSchema(id: 'amount', label: 'Amount', defaultWidth: kDocTableColAmount, minWidth: 80, maxWidth: 200),
    TableColumnSchema(id: 'date', label: 'Date', defaultWidth: kDocTableColDate, minWidth: 90, maxWidth: 220),
    TableColumnSchema(id: 'dueDate', label: 'Due', defaultWidth: kDocTableColDueDate, minWidth: 80, maxWidth: 200),
  ];

  Widget _buildTableView(List<GeneratedDocument> documents, bool isDesktop) {
    final allSelected =
        documents.isNotEmpty &&
        documents.every((d) => _selectedDocumentIds.contains(d.id));

    final headerStyle = TableViewStyles.headerLabelStyle(context);

    final headerCells = buildTableHeaderCells(
      context: context,
      columns: _tableColumns,
      widths: {
        for (final c in _tableColumns)
          c.id: _columnWidths[c.id] ?? c.defaultWidth,
      },
      onColumnResize: _handleColumnResize,
      textStyle: headerStyle,
      onSortTap: (column) => _onColumnSortTap(column.id),
      sortedColumnId: _tableSortColumn,
      sortAscending: _tableSortAscending,
    );

    final showCheckboxes = _isSelectionMode || isDesktop;
    final headerChildren = <Widget>[
      if (showCheckboxes) ...[
        SizedBox(
          width: 40,
          child: Checkbox(
            value: allSelected,
            onChanged: (val) {
              setState(() {
                if (val == true) {
                  _selectedDocumentIds = documents.map((d) => d.id).toSet();
                } else {
                  _selectedDocumentIds.clear();
                }
              });
            },
          ),
        ),
        const SizedBox(width: 4),
      ],
    ];
    for (int i = 0; i < headerCells.length; i++) {
      if (i > 0) headerChildren.add(const SizedBox(width: kDocTableColGap));
      headerChildren.add(headerCells[i]);
    }

    return TableLayoutShell(
      minTableWidth: 920,
      header: TableHeaderRow(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
        children: headerChildren,
      ),
      body: ListView.builder(
        itemCount: documents.length,
        itemBuilder: (context, index) {
          final document = documents[index];
          return DocumentTableRow(
            document: document,
            isSelected: _selectedDocumentIds.contains(document.id),
            selectionMode: showCheckboxes,
            columnWidths: _columnWidths,
            onSelectionChanged: (selected) {
              if (selected) {
                _selectedDocumentIds.add(document.id);
              } else {
                _selectedDocumentIds.remove(document.id);
              }
              setState(() {});
            },
            onLongPress: () => _toggleSelection(document.id),
            onTap: () => _onDocumentTap(document, isDesktop),
            isHighlighted: _selectedDocumentId == document.id,
          );
        },
      ),
    );
  }

  // ── Empty state ──

  // ── Type tab pills ──

  static const _typeTabs = [
    'All',
    'Quotations',
    'Invoices',
    'Contracts',
    'Purchase Orders',
    'Expenses',
  ];

  List<GeneratedDocument> _applyTypeTabFilter(List<GeneratedDocument> docs) {
    switch (_selectedTypeTab) {
      case 'Quotations':
        return docs
            .where(
              (d) =>
                  d.documentType == DocumentType.quotation ||
                  d.documentType == DocumentType.requestForBid,
            )
            .toList();
      case 'Invoices':
        return docs
            .where(
              (d) =>
                  d.documentType.category == TemplateCategory.customerInvoice,
            )
            .toList();
      case 'Contracts':
        return docs
            .where(
              (d) =>
                  d.documentType == DocumentType.serviceAgreement ||
                  d.documentType == DocumentType.changeOrder ||
                  d.documentType == DocumentType.workOrder ||
                  d.documentType == DocumentType.workOrderEmergency ||
                  d.documentType == DocumentType.workOrderMaintenance ||
                  d.documentType == DocumentType.workAuthEmergency ||
                  d.documentType == DocumentType.workAuthRestoration ||
                  d.documentType == DocumentType.workAuthServices,
            )
            .toList();
      case 'Purchase Orders':
        return docs
            .where(
              (d) =>
                  d.documentType.category == TemplateCategory.vendorOrder ||
                  (d.documentType.category == TemplateCategory.vendorBill &&
                      d.documentType != DocumentType.expense),
            )
            .toList();
      case 'Expenses':
        return docs
            .where((d) => d.documentType == DocumentType.expense)
            .toList();
      default:
        return docs;
    }
  }

  Widget _buildTypeTabs() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: 6),
        itemCount: _typeTabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = _typeTabs[index];
          final isActive = _selectedTypeTab == tab;
          return ChoiceChip(
            label: Text(
              tab,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isActive ? Colors.white : AppColors.textSecondary,
              ),
            ),
            selected: isActive,
            selectedColor: AppColors.primary,
            backgroundColor: AppColors.surfaceAlt,
            side: BorderSide(
              color: isActive
                  ? AppColors.primary
                  : AppColors.cardBorder,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.xl),
            ),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onSelected: (_) {
              setState(() => _selectedTypeTab = tab);
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    if (_searchQuery.isNotEmpty ||
        _filterStatus != null ||
        _filterType != null ||
        _selectedTypeTab != 'All') {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            Text(
              'No documents match your filters',
              style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.description, size: 48, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          Text(
            'No documents yet',
            style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            'Create a document from a template',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
          if (widget.onCreateTap != null) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: widget.onCreateTap,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Create Document'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SavedDocumentView {
  final String id;
  final String name;
  final String searchQuery;
  final DocumentViewType viewType;
  final DocumentStatus? status;
  final DocumentType? type;
  final String? tableSortColumn;
  final bool tableSortAscending;
  final DateTime createdAt;

  const _SavedDocumentView({
    required this.id,
    required this.name,
    required this.searchQuery,
    required this.viewType,
    required this.status,
    required this.type,
    required this.tableSortColumn,
    required this.tableSortAscending,
    required this.createdAt,
  });

  factory _SavedDocumentView.fromMap(Map<String, dynamic> map) {
    DocumentStatus? parsedStatus;
    final statusName = map['status'] as String?;
    if (statusName != null) {
      for (final value in DocumentStatus.values) {
        if (value.name == statusName) {
          parsedStatus = value;
          break;
        }
      }
    }

    DocumentType? parsedType;
    final typeName = map['type'] as String?;
    if (typeName != null) {
      for (final value in DocumentType.values) {
        if (value.name == typeName) {
          parsedType = value;
          break;
        }
      }
    }

    final rawViewType = map['view_type'] as String?;
    final viewType = rawViewType == DocumentViewType.table.name
        ? DocumentViewType.table
        : DocumentViewType.card;

    return _SavedDocumentView(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Saved view',
      searchQuery: map['search_query'] as String? ?? '',
      viewType: viewType,
      status: parsedStatus,
      type: parsedType,
      tableSortColumn: map['table_sort_column'] as String?,
      tableSortAscending: map['table_sort_ascending'] as bool? ?? true,
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'search_query': searchQuery,
      'view_type': viewType.name,
      'status': status?.name,
      'type': type?.name,
      'table_sort_column': tableSortColumn,
      'table_sort_ascending': tableSortAscending,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class _CardActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _CardActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
            child: Icon(
              icon,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

