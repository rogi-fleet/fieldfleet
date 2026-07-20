import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/catalog_item.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../theme/theme.dart';
import '../../utils/currency_utils.dart';
import '../../utils/hierarchy_flatten.dart';
import '../../utils/hierarchy_utils.dart';
import '../../utils/table_column_visibility.dart';
import '../../utils/table_sort_state.dart';
import '../../utils/raw_data_export.dart';
import '../../utils/user_facing_error.dart';
import '../../widgets/catalog/catalog_inline_add_row.dart';
import '../../widgets/catalog/catalog_csv_import_dialog.dart';
import '../../widgets/catalog/catalog_web_import_dialog.dart';
import '../../widgets/catalog/catalog_item_form_popup.dart';
import '../../widgets/catalog/catalog_mass_edit_dialog.dart';
import '../../widgets/catalog/catalog_view_row.dart';
import '../../widgets/table/table_add_item_group_row.dart';
import '../../widgets/table/table_column_picker_button.dart';
import '../../widgets/table/table_column_schema.dart';
import '../../widgets/table/table_header_cells_builder.dart';
import '../../widgets/table/table_header_row.dart';
import '../../widgets/table/table_layout_shell.dart';
import '../../widgets/table/table_summary_footer.dart';
import '../../widgets/table/tree_drop_zone.dart';
import '../../widgets/common/list_skeleton.dart';
import '../../widgets/common/view_icon_button.dart';
import '../../widgets/common/searchable_filter_chips.dart';
import '../../widgets/common/view_toolbar.dart';
import '../../widgets/table/table_view_styles.dart';
import '../../services/supabase/catalog_service.dart';

enum _CatalogQuickFilter {
  all,
  items,
  groups,
  ready,
  missingSku,
  missingCategory,
  missingUnit,
  missingPricing,
  missingCostType,
  taxable,
  recentlyUpdated,
}

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  static const List<TableColumnSchema> _catalogHeaderColumns = [
    TableColumnSchema(
      id: 'unit',
      label: 'Unit',
      defaultWidth: 80,
      minWidth: 60,
      maxWidth: 150,
    ),
    TableColumnSchema(
      id: 'unitCost',
      label: 'Unit cost',
      defaultWidth: 120,
      minWidth: 80,
      maxWidth: 200,
    ),
    TableColumnSchema(
      id: 'unitPrice',
      label: 'Unit price',
      defaultWidth: 120,
      minWidth: 80,
      maxWidth: 200,
    ),
    TableColumnSchema(
      id: 'markup',
      label: 'Markup %',
      defaultWidth: 100,
      minWidth: 70,
      maxWidth: 180,
    ),
    TableColumnSchema(
      id: 'margin',
      label: 'Margin %',
      defaultWidth: 100,
      minWidth: 70,
      maxWidth: 180,
      borderLeft: true,
    ),
    TableColumnSchema(
      id: 'taxable',
      label: 'Taxable',
      defaultWidth: 80,
      minWidth: 60,
      maxWidth: 130,
    ),
    TableColumnSchema(
      id: 'sku',
      label: 'SKU',
      defaultWidth: 140,
      minWidth: 80,
      maxWidth: 250,
    ),
    TableColumnSchema(
      id: 'category',
      label: 'Category',
      defaultWidth: 160,
      minWidth: 80,
      maxWidth: 300,
    ),
  ];

  static const List<String> _allColumns = [
    'unit',
    'unitCost',
    'unitPrice',
    'markup',
    'margin',
    'taxable',
    'sku',
    'category',
  ];

  static const List<String> _defaultColumns = [
    'unit',
    'unitCost',
    'unitPrice',
    'markup',
    'margin',
    'taxable',
  ];

  static const Map<String, String> _columnNames = {
    'unit': 'Unit',
    'unitCost': 'Unit cost',
    'unitPrice': 'Unit price',
    'markup': 'Markup %',
    'margin': 'Margin %',
    'taxable': 'Taxable',
    'sku': 'SKU',
    'category': 'Category',
  };

  static const _columnPrefsKey = 'catalog_visible_columns';
  static const _expandedPrefsKey = 'catalog_all_expanded';
  static const _fitToScreenPrefsKey = 'catalog_fit_to_screen';
  static const _cardLayoutPrefsKey = 'catalog_card_layout';
  static const _savedViewsPrefsKey = 'catalog_saved_views';
  static const double _checkboxColumnWidth = 24;
  static const double _afterCheckboxGap = 4;
  static const double _nameHeaderInset = 25;
  static const double _tableHorizontalPadding = 10;

  final SupabaseCatalogService _catalogService = SupabaseCatalogService();
  final RawDataExportService _rawDataExportService = RawDataExportService();
  final Set<String> _expandedItems = {};
  final Set<String> _selectedItemIds = {};
  final Map<String, GlobalKey> _rowKeysByItemId = {};

  String _searchQuery = '';
  TableSortState _sortState = const TableSortState();
  final Map<String, double> _columnWidths = {};
  Stream<List<CatalogItem>>? _catalogStream;
  String? _cachedWorkspaceId;

  void _maybeRebuildStream(String workspaceId) {
    if (_catalogStream == null || _cachedWorkspaceId != workspaceId) {
      _cachedWorkspaceId = workspaceId;
      _catalogStream = _catalogService.getCatalogItems(workspaceId);
    }
  }

  void _handleColumnResize(TableColumnResize resize) {
    setState(() {
      _columnWidths[resize.columnId] = resize.width;
    });
  }
  _CatalogQuickFilter _quickFilter = _CatalogQuickFilter.all;
  bool _allExpanded = true;
  bool _expandInitialized = false;
  bool _fitToScreen = false;
  bool _isCardLayout = true;
  bool _isExportingCatalogCsv = false;
  String? _activeSavedViewId;
  List<_CatalogSavedView> _savedViews = const [];
  TableColumnVisibility _colVis = TableColumnVisibility(_defaultColumns);
  List<CatalogItem> _allCatalogItems = [];
  // Stable signature of the catalog stats — used to decide whether the
  // header chips need a setState-triggered rebuild after a stream emit.
  String _lastCatalogStatsSig = '';
  String? _addingToParentId;
  int? _addingHierarchyLevel;
  bool _addingAsGroup = false;

  Map<String, List<CatalogItem>> _childrenByParentId = {};
  Map<String, CatalogItem> _catalogItemsById = {};
  Map<String, List<CatalogItem>> _descendantsByItemId = {};
  Map<String, List<CatalogItem>> _leafDescendantsByItemId = {};

  bool get _isNarrowScreen => MediaQuery.sizeOf(context).width < AppBreakpoints.mobile;
  bool get _isMobileView => _isNarrowScreen || _isCardLayout;

  // Currency formatting helpers
  String get _currencyCode => context.read<WorkspaceProvider>().currencyCode;
  String _formatCurrency(double amount) =>
      CurrencyUtils.formatCurrency(amount, _currencyCode);

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final savedColumns = prefs.getStringList(_columnPrefsKey);
    final savedExpanded = prefs.getBool(_expandedPrefsKey);
    final savedFit = prefs.getBool(_fitToScreenPrefsKey);
    final savedCardLayout = prefs.getBool(_cardLayoutPrefsKey);
    final savedViewsJson = prefs.getString(_savedViewsPrefsKey);
    final savedViews = _decodeSavedViews(savedViewsJson);

    setState(() {
      _colVis = TableColumnVisibility(savedColumns ?? _defaultColumns);
      _allExpanded = savedExpanded ?? true;
      _fitToScreen = savedFit ?? false;
      if (savedCardLayout != null) _isCardLayout = savedCardLayout;
      _savedViews = savedViews;
    });
  }

  Future<void> _saveColumnPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_columnPrefsKey, _colVis.toList());
  }

  Future<void> _saveExpandedPreference(bool expanded) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_expandedPrefsKey, expanded);
  }

  Future<void> _saveFitToScreenPreference(bool fit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_fitToScreenPrefsKey, fit);
  }

  Future<void> _saveCardLayoutPreference(bool isCard) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cardLayoutPrefsKey, isCard);
  }

  Future<void> _saveSavedViews() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(
      _savedViews.map((view) => view.toMap()).toList(growable: false),
    );
    await prefs.setString(_savedViewsPrefsKey, payload);
  }

  void _toggleColumn(String columnId) {
    setState(() {
      _colVis = _colVis.toggle(columnId);
      _activeSavedViewId = null;
    });
    _saveColumnPreferences();
  }

  bool _isColumnVisible(String columnId) => _colVis.isVisible(columnId);

  void _toggleSort(String columnId) {
    setState(() {
      _sortState = _sortState.toggle(columnId);
      _activeSavedViewId = null;
    });
  }



  void _buildHierarchyMaps(List<CatalogItem> items) {
    _catalogItemsById = {for (final item in items) item.id: item};
    _childrenByParentId = HierarchyUtils.buildChildrenMap<CatalogItem>(
      items,
      idOf: (i) => i.id,
      parentIdOf: (i) => i.parentId,
      sort: (a, b) => a.sortOrder.compareTo(b.sortOrder),
    );
    _descendantsByItemId = {
      for (final item in items)
        item.id: HierarchyUtils.collectDescendants<CatalogItem>(
          item.id,
          _childrenByParentId,
          idOf: (i) => i.id,
        ),
    };
    _leafDescendantsByItemId = {
      for (final item in items)
        item.id: (_descendantsByItemId[item.id] ?? const <CatalogItem>[])
            .where((d) => d.itemType == CatalogItemType.item)
            .toList(),
    };

    if (_allExpanded && !_expandInitialized) {
      _expandedItems
        ..clear()
        ..addAll(
          items
              .where((item) => item.itemType == CatalogItemType.group)
              .map((item) => item.id),
        );
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query.trim().toLowerCase();
      _activeSavedViewId = null;
    });
    _expandVisibleMatches();
  }

  void _expandVisibleMatches() {
    if (_searchQuery.isEmpty && _quickFilter == _CatalogQuickFilter.all) {
      return;
    }
    if (!mounted) return;
    setState(() {
      for (final item in _allCatalogItems) {
        if (_matchesSelf(item)) {
          _expandAncestors(item);
        }
      }
    });
  }

  void _expandAncestors(CatalogItem item) {
    final ancestors = HierarchyUtils.collectAncestorIds<CatalogItem>(
      item: item,
      itemsById: _catalogItemsById,
      idOf: (i) => i.id,
      parentIdOf: (i) => i.parentId,
    );
    _expandedItems.addAll(ancestors);
  }

  bool _matchesSelf(CatalogItem item) {
    if (!_matchesQuickFilter(item)) return false;
    if (_searchQuery.isEmpty) return true;
    final fields = [
      item.name,
      item.description,
      item.sku,
      item.category,
      item.costTypeName,
      item.costCodeName,
    ];
    return fields.any(
      (field) => field?.toLowerCase().contains(_searchQuery) ?? false,
    );
  }

  bool _matchesSearch(CatalogItem item) {
    if (_matchesSelf(item)) return true;
    final descendants = _descendantsByItemId[item.id] ?? const <CatalogItem>[];
    return descendants.any(_matchesSelf);
  }

  bool _matchesQuickFilter(CatalogItem item) {
    final isLeaf = _isLeafCatalogItem(item);

    switch (_quickFilter) {
      case _CatalogQuickFilter.all:
        return true;
      case _CatalogQuickFilter.items:
        return isLeaf;
      case _CatalogQuickFilter.groups:
        return item.itemType == CatalogItemType.group;
      case _CatalogQuickFilter.ready:
        return _isCatalogItemReady(item);
      case _CatalogQuickFilter.missingSku:
        return _isMissingSku(item);
      case _CatalogQuickFilter.missingCategory:
        return _isMissingCategory(item);
      case _CatalogQuickFilter.missingUnit:
        return _isMissingUnit(item);
      case _CatalogQuickFilter.missingPricing:
        return _isMissingPricing(item);
      case _CatalogQuickFilter.missingCostType:
        return _isMissingCostType(item);
      case _CatalogQuickFilter.taxable:
        return isLeaf && item.isTaxable;
      case _CatalogQuickFilter.recentlyUpdated:
        return DateTime.now().difference(item.updatedAt) <=
            const Duration(days: 30);
    }
  }

  bool _isItemVisibleInSearch(CatalogItem item) {
    if (!_matchesSearch(item)) return false;
    var parentId = item.parentId;
    var iterations = 0;
    while (parentId != null && iterations < 100) {
      iterations++;
      final parent = _catalogItemsById[parentId];
      if (parent == null) break;
      if (!_matchesSearch(parent)) return false;
      parentId = parent.parentId;
    }
    return true;
  }

  void _expandAll() {
    setState(() {
      _expandedItems
        ..clear()
        ..addAll(
          _allCatalogItems
              .where((item) => item.itemType == CatalogItemType.group)
              .map((item) => item.id),
        );
      _allExpanded = true;
    });
    _saveExpandedPreference(true);
  }

  void _collapseAll() {
    setState(() {
      _expandedItems.clear();
      _allExpanded = false;
    });
    _saveExpandedPreference(false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceAlt,
      body: Column(
        children: [
          _buildCatalogPageHeader(context),
          Expanded(child: _buildCatalogBody(context)),
        ],
      ),
    );
  }

  Widget _buildCatalogPageHeader(BuildContext context) {
    final total = _allCatalogItems.length;
    final active = _allCatalogItems.where((i) => i.isActive).length;
    final used = _allCatalogItems.where((i) => i.usageCount > 0).length;
    final inventoryTracked =
        _allCatalogItems.where((i) => i.inventoryTracked).length;

    final statChips = Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        _headerStatChip(
          icon: Icons.list_alt_outlined,
          label: 'Items',
          value: '$total',
          tone: AppColors.info,
        ),
        _headerStatChip(
          icon: Icons.check_circle_outline,
          label: 'Active',
          value: '$active',
          tone: AppColors.success,
        ),
        _headerStatChip(
          icon: Icons.trending_up_outlined,
          label: 'In use',
          value: '$used',
          tone: AppColors.primary,
        ),
        _headerStatChip(
          icon: Icons.inventory_outlined,
          label: 'Tracked',
          value: '$inventoryTracked',
          tone: AppColors.warning,
        ),
      ],
    );

    final titleBlock = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.inventory_2_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Catalog',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: ChromeColors.of(context).textActive,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                'Canonical product & service registry — feeds quotes, '
                'invoices, bills, expenses, vendors and inventory.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ChromeColors.of(context).text,
                    ),
              ),
            ],
          ),
        ),
      ],
    );

    return Container(
      color: ChromeColors.of(context).background,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // On wide layouts the stat chips sit beside the title; on narrow
          // (mobile) layouts they wrap below so the title never gets squeezed
          // to a near-zero width column (which made the text render one
          // character per line).
          final wide = constraints.maxWidth >= 620;
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: titleBlock),
                const SizedBox(width: 12),
                statChips,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleBlock,
              const SizedBox(height: 12),
              statChips,
            ],
          );
        },
      ),
    );
  }

  Widget _headerStatChip({
    required IconData icon,
    required String label,
    required String value,
    required Color tone,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: tone),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: tone,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: tone,
            ),
          ),
        ],
      ),
    );
  }

  int get _activeFilterCount => _quickFilter != _CatalogQuickFilter.all ? 1 : 0;

  Widget _buildCatalogBody(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    if (workspaceId == null) {
      return const ListSkeleton();
    }

    _maybeRebuildStream(workspaceId);

    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<CatalogItem>>(
            stream: _catalogStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const ListSkeleton();
              }

              if (snapshot.hasError) {
                return Center(
                  child: SelectableText(
                    UserFacingError.uiMessage(
                      snapshot.error,
                      action: 'load catalog',
                    ),
                  ),
                );
              }

              final items = snapshot.data ?? const <CatalogItem>[];
              // The page header (Items/Active/In use/Tracked chips) reads
              // `_allCatalogItems` directly — it's built ABOVE this
              // StreamBuilder in the widget tree, so on first stream emit
              // we need to schedule a rebuild for the chips to update.
              // Without this, the chips report 0 even when items exist.
              // Use a stable signature (length + active count) to avoid
              // looping on every same-shape stream emit.
              final newSig =
                  '${items.length}:${items.where((i) => i.isActive).length}'
                  ':${items.where((i) => i.usageCount > 0).length}'
                  ':${items.where((i) => i.inventoryTracked).length}';
              if (newSig != _lastCatalogStatsSig) {
                _lastCatalogStatsSig = newSig;
                _allCatalogItems = items;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() {});
                });
              } else {
                _allCatalogItems = items;
              }
              _buildHierarchyMaps(items);
              if (!_expandInitialized && items.isNotEmpty) {
                _expandInitialized = true;
              }

              return _buildCatalogTable(items, workspaceId);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildInlineSelectionBar() {
    final descendantCount = _selectedDescendantIds().length;
    final editableCount = _selectedLeafItems().length;
    final count = _selectedItemIds.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(AppRadius.r12),
            ),
            child: Text(
              '$count selected',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          if (editableCount > 0 && editableCount != count) ...[
            const SizedBox(width: 6),
            Text(
              '($editableCount editable)',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
          if (descendantCount > 0) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.account_tree_outlined,
              size: 13,
              color: AppColors.infoDark,
            ),
            const SizedBox(width: 2),
            Text(
              '+$descendantCount',
              style: TextStyle(
                color: AppColors.infoDark,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(width: 6),
          SizedBox(
            height: 26,
            child: FilledButton.icon(
              onPressed: editableCount == 0 ? null : () => _handleMassEdit(),
              icon: const Icon(Icons.edit_outlined, size: 14),
              label: const Text('Edit', style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          SizedBox(
            height: 26,
            width: 22,
            child: PopupMenuButton<CatalogMassEditPreset>(
              enabled: editableCount > 0,
              tooltip: 'Quick edit',
              padding: EdgeInsets.zero,
              iconSize: 18,
              offset: const Offset(0, 28),
              onSelected: (preset) => _handleMassEdit(preset: preset),
              icon: const Icon(Icons.arrow_drop_down),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: CatalogMassEditPreset.pricing,
                  child: Text('Pricing'),
                ),
                PopupMenuItem(
                  value: CatalogMassEditPreset.category,
                  child: Text('Category'),
                ),
                PopupMenuItem(
                  value: CatalogMassEditPreset.unit,
                  child: Text('Unit'),
                ),
                PopupMenuItem(
                  value: CatalogMassEditPreset.sku,
                  child: Text('SKU'),
                ),
                PopupMenuItem(
                  value: CatalogMassEditPreset.costType,
                  child: Text('Cost Type'),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            height: 26,
            child: FilledButton.icon(
              onPressed: editableCount == 0 ? null : _showMoveToGroupDialog,
              icon: const Icon(Icons.drive_file_move_outlined, size: 14),
              label: const Text('Move', style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.infoDark,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            height: 26,
            child: FilledButton.icon(
              onPressed: _handleMassDelete,
              icon: const Icon(Icons.delete_outline, size: 14),
              label: const Text('Delete', style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 22,
            height: 22,
            child: IconButton(
              onPressed: _clearSelection,
              icon: const Icon(Icons.close, size: 14),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Clear selection',
              color: AppColors.info,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogTable(List<CatalogItem> allItems, String workspaceId) {
    if (_isMobileView) {
      return _buildMobileCatalogView(allItems, workspaceId);
    }

    final visibleEntries = _visibleCatalogEntries(allItems);
    final displayedItems = visibleEntries
        .map((entry) => entry.item)
        .toList(growable: false);
    final rows = _buildFlattenedCatalogRows(
      allItems,
      workspaceId,
      visibleEntries: visibleEntries,
    );

    return Stack(
      children: [
        Column(
          children: [
            ViewToolbar(
              searchHint: 'Search catalog items...',
              searchQuery: _searchQuery,
              onSearch: _onSearchChanged,
              quickToggles: [
                _buildCardListViewToggle(),
                _buildExpandCollapseToggle(),
                _buildFitToScreenToggle(),
                _buildColumnPicker(),
                _buildSavedViewsToggle(),
                _buildCatalogActionsMenu(),
                if (_selectedItemIds.isNotEmpty)
                  _buildInlineSelectionBar(),
              ],
              filterCount: _activeFilterCount,
              onFilterTap: () => _showCatalogFilterDialog(allItems),
            ),
            Expanded(
              child: TableLayoutShell(
                minTableWidth: _fitToScreen ? 0 : 1280,
                header: _buildTableHeader(displayedItems),
                footer: _buildSummaryFooter(displayedItems),
                body: ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) => rows[index],
                ),
                showHeaderDivider: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Mobile / Card View ──────────────────────────────────────────────

  Widget _buildMobileCatalogView(
    List<CatalogItem> allItems,
    String workspaceId,
  ) {
    final entries = flattenHierarchy<CatalogItem>(
      items: allItems,
      idOf: (item) => item.id,
      parentIdOf: (item) => item.parentId,
      isExpandedOf: (item) => _expandedItems.contains(item.id),
      sortSiblings:
          _catalogSortComparator ?? (a, b) => a.sortOrder.compareTo(b.sortOrder),
    );
    final visibleEntries = entries
        .where((entry) => _isItemVisibleInSearch(entry.item))
        .toList(growable: false);

    final rows = <Widget>[_buildMobileCatalogControls(allItems, workspaceId)];

    if (_addingToParentId == null && _addingHierarchyLevel == 0) {
      rows.add(
        _buildInlineCatalogAddRow(
          workspaceId: workspaceId,
          parentId: null,
          hierarchyLevel: 0,
          indentLevel: 0,
        ),
      );
    }

    if (allItems.isEmpty && _addingHierarchyLevel == null) {
      rows.add(_buildMobileCatalogEmptyState());
    } else if (visibleEntries.isEmpty) {
      rows.add(_buildMobileNoResultsState());
    } else {
      for (var i = 0; i < visibleEntries.length; i++) {
        final entry = visibleEntries[i];
        rows.add(_buildMobileCatalogCard(entry));

        if (_addingToParentId != null &&
            _addingHierarchyLevel != null &&
            _isLastVisibleRowInParentSubtree(
              visibleEntries,
              rowIndex: i,
              parentId: _addingToParentId!,
            )) {
          rows.add(
            _buildInlineCatalogAddRow(
              workspaceId: workspaceId,
              parentId: _addingToParentId!,
              hierarchyLevel: _addingHierarchyLevel!,
              indentLevel: (entry.depth + 1).clamp(0, 4),
            ),
          );
        }
      }
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 16),
            children: rows,
          ),
        ),
      ],
    );
  }

  Widget _buildMobileCatalogControls(
    List<CatalogItem> allItems,
    String workspaceId,
  ) {
    return ViewToolbar(
      searchHint: 'Search catalog items...',
      searchQuery: _searchQuery,
      onSearch: _onSearchChanged,
      quickToggles: _isNarrowScreen
          ? [
              _buildCatalogActionsMenu(),
              if (_selectedItemIds.isNotEmpty)
                _buildInlineSelectionBar(),
            ]
          : [
              _buildCardListViewToggle(),
              _buildExpandCollapseToggle(),
              _buildFitToScreenToggle(),
              _buildColumnPicker(),
              _buildSavedViewsToggle(),
              _buildCatalogActionsMenu(),
              if (_selectedItemIds.isNotEmpty)
                _buildInlineSelectionBar(),
            ],
      filterCount: _activeFilterCount,
      onFilterTap: () => _showCatalogFilterDialog(allItems),
    );
  }

  Widget _buildMobileCatalogEmptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
      child: Column(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 52,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 12),
          Text(
            'No catalog items yet',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add groups and items to build a catalog that is easier to review on mobile.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileNoResultsState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 36, 20, 24),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 44, color: AppColors.textTertiary),
          const SizedBox(height: 10),
          const Text(
            'No catalog items match your search',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => _onSearchChanged(''),
            child: const Text('Clear search'),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileCatalogCard(HierarchyFlatEntry<CatalogItem> entry) {
    final item = entry.item;
    final isGroup = item.itemType == CatalogItemType.group;
    final isExpanded = _expandedItems.contains(item.id);
    final siblings =
        _childrenByParentId[item.parentId ?? ''] ?? const <CatalogItem>[];
    final siblingIndex = siblings.indexWhere(
      (sibling) => sibling.id == item.id,
    );
    final canMoveUp = siblingIndex > 0;
    final canMoveDown = siblingIndex >= 0 && siblingIndex < siblings.length - 1;
    final childCount =
        (_childrenByParentId[item.id] ?? const <CatalogItem>[]).length;
    final descendantLeafCount =
        (_leafDescendantsByItemId[item.id] ?? const <CatalogItem>[]).length;
    final indent = (entry.depth * 16.0).clamp(0.0, 64.0);
    final cardColor = isGroup ? AppColors.background : Colors.white;
    final metrics = _buildMobileCatalogMetrics(item);

    return Padding(
      padding: EdgeInsets.fromLTRB(12 + indent, 0, 12, 10),
      child: Card(
        elevation: 0,
        color: cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: isGroup
              ? childCount == 0
                    ? null
                    : () => _toggleCatalogItemExpansion(item.id)
              : () => _handleEditItem(item),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _selectedItemIds.contains(item.id),
                      onChanged: (checked) => _handleSelectionChanged(
                        item,
                        checked ?? false,
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    if (isGroup)
                      IconButton(
                        onPressed: childCount == 0
                            ? null
                            : () => _toggleCatalogItemExpansion(item.id),
                        icon: Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_right,
                        ),
                        visualDensity: VisualDensity.compact,
                        tooltip: isExpanded ? 'Collapse' : 'Expand',
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              _buildMobileTypeChip(item, descendantLeafCount),
                            ],
                          ),
                          if ((item.sku ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              item.sku!,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textTertiary,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                          if ((item.description ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              item.description!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Actions',
                      onSelected: (value) async {
                        switch (value) {
                          case 'move_up':
                            await _moveItemWithinSiblings(item, -1);
                            break;
                          case 'move_down':
                            await _moveItemWithinSiblings(item, 1);
                            break;
                          case 'edit':
                            _handleEditItem(item);
                            break;
                          case 'duplicate':
                            await _handleDuplicateItem(item);
                            break;
                          case 'add_item':
                            _handleAddItem(
                              item.id,
                              item.hierarchyLevel + 1,
                              isGroup: false,
                            );
                            break;
                          case 'add_group':
                            _handleAddItem(
                              item.id,
                              item.hierarchyLevel + 1,
                              isGroup: true,
                            );
                            break;
                          case 'delete':
                            await _handleDeleteItem(item);
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'move_up',
                          enabled: canMoveUp,
                          child: ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.arrow_upward,
                              color: canMoveUp ? null : AppColors.textTertiary,
                            ),
                            title: Text(
                              'Move up',
                              style: canMoveUp
                                  ? null
                                  : TextStyle(color: AppColors.textTertiary),
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        PopupMenuItem(
                          value: 'move_down',
                          enabled: canMoveDown,
                          child: ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.arrow_downward,
                              color: canMoveDown
                                  ? null
                                  : AppColors.textTertiary,
                            ),
                            title: Text(
                              'Move down',
                              style: canMoveDown
                                  ? null
                                  : TextStyle(color: AppColors.textTertiary),
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.edit_outlined),
                            title: Text('Edit'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'duplicate',
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.copy_outlined),
                            title: Text('Duplicate'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        if (isGroup) ...[
                          const PopupMenuItem(
                            value: 'add_item',
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.add),
                              title: Text('Add Item'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'add_group',
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.create_new_folder_outlined),
                              title: Text('Add Group'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                        PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.delete_outline,
                              color: AppColors.error,
                            ),
                            title: Text(
                              'Delete',
                              style: TextStyle(color: AppColors.error),
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Primary metrics in equal-width row
                if (metrics.isNotEmpty)
                  Row(
                    children: [
                      for (var i = 0; i < metrics.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(child: _buildMobileMetricChip(metrics[i])),
                      ],
                    ],
                  ),
                // Unit shown inline for items
                if (!isGroup &&
                    item.unit != null &&
                    item.unit!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildMobileMetricChip(
                    _MobileCatalogMetric(
                      label: 'Unit',
                      value: item.unit!,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _toggleCatalogItemExpansion(String itemId) {
    setState(() {
      if (_expandedItems.contains(itemId)) {
        _expandedItems.remove(itemId);
      } else {
        _expandedItems.add(itemId);
      }
    });
  }

  Widget _buildMobileTypeChip(CatalogItem item, int descendantLeafCount) {
    final isGroup = item.itemType == CatalogItemType.group;
    final color = isGroup ? AppColors.warningDark : AppColors.infoDark;
    final background = color.withValues(alpha: 0.12);
    final label = isGroup
        ? descendantLeafCount > 0
              ? '$descendantLeafCount items'
              : 'Group'
        : 'Item';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  List<_MobileCatalogMetric> _buildMobileCatalogMetrics(CatalogItem item) {
    final isGroup = item.itemType == CatalogItemType.group;

    if (isGroup) {
      final leafItems =
          _leafDescendantsByItemId[item.id] ?? const <CatalogItem>[];
      if (leafItems.isEmpty) return const [];

      final totalCost = leafItems.fold<double>(
        0.0,
        (sum, i) => sum + i.unitCost,
      );
      final totalPrice = leafItems.fold<double>(
        0.0,
        (sum, i) => sum + i.unitPrice,
      );
      final avgMarkup = leafItems.fold<double>(
            0.0,
            (sum, i) => sum + i.markup,
          ) /
          leafItems.length;

      return [
        _MobileCatalogMetric(
          label: 'Avg Cost',
          value: _formatCurrency(totalCost / leafItems.length),
        ),
        _MobileCatalogMetric(
          label: 'Avg Price',
          value: _formatCurrency(totalPrice / leafItems.length),
          color: Theme.of(context).colorScheme.primary,
        ),
        _MobileCatalogMetric(
          label: 'Avg Markup',
          value: '${avgMarkup.toStringAsFixed(1)}%',
        ),
      ];
    }

    // Leaf item metrics
    return [
      _MobileCatalogMetric(
        label: 'Unit Cost',
        value: _formatCurrency(item.unitCost),
      ),
      _MobileCatalogMetric(
        label: 'Unit Price',
        value: _formatCurrency(item.unitPrice),
        color: Theme.of(context).colorScheme.primary,
      ),
      _MobileCatalogMetric(
        label: 'Markup',
        value: '${item.markup.toStringAsFixed(1)}%',
        color: item.markup > 0 ? AppColors.success : null,
      ),
    ];
  }

  Widget _buildMobileMetricChip(_MobileCatalogMetric metric) {
    final color = metric.color ?? AppColors.textPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            metric.label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textTertiary,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            metric.value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandCollapseToggle() {
    final chrome = ChromeColors.of(context);
    final hasExpanded = _expandedItems.isNotEmpty;
    return IconButton(
      icon: Icon(
        hasExpanded ? Icons.unfold_less : Icons.unfold_more,
        size: 20,
        color: chrome.text,
      ),
      onPressed: hasExpanded ? _collapseAll : _expandAll,
      tooltip: hasExpanded ? 'Collapse all' : 'Expand all',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }

  Widget _buildFitToScreenToggle() {
    final chrome = ChromeColors.of(context);
    return IconButton(
      icon: Icon(
        _fitToScreen ? Icons.open_in_full : Icons.close_fullscreen,
        size: 18,
        color: _fitToScreen ? chrome.text : AppColors.info,
      ),
      onPressed: () {
        final newFit = !_fitToScreen;
        setState(() => _fitToScreen = newFit);
        _saveFitToScreenPreference(newFit);
      },
      tooltip: _fitToScreen ? 'Expand table (scrollable)' : 'Fit to screen',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }

  Widget _buildCardListViewToggle() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ViewIconButton(
          icon: Icons.grid_view,
          tooltip: 'Cards',
          isSelected: _isCardLayout,
          onTap: () {
            setState(() => _isCardLayout = true);
            _saveCardLayoutPreference(true);
          },
        ),
        ViewIconButton(
          icon: Icons.table_rows,
          tooltip: 'List',
          isSelected: !_isCardLayout,
          onTap: () {
            setState(() => _isCardLayout = false);
            _saveCardLayoutPreference(false);
          },
        ),
      ],
    );
  }

  Widget _buildSavedViewsToggle() {
    final chrome = ChromeColors.of(context);
    final hasActive = _activeSavedViewId != null;
    return PopupMenuButton<String>(
      tooltip: 'Saved views',
      onSelected: (value) {
        if (value == '_save') {
          _showSaveViewDialog();
        } else if (value == '_delete') {
          _deleteActiveSavedView();
        } else {
          _applySavedViewById(value);
        }
      },
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Icon(
          hasActive ? Icons.bookmark : Icons.bookmark_border,
          size: 18,
          color: hasActive ? AppColors.secondary : chrome.text,
        ),
      ),
      itemBuilder: (context) {
        if (_savedViews.isEmpty) {
          return const [
            PopupMenuItem<String>(
              enabled: false,
              child: Text('No saved views yet'),
            ),
          ];
        }
        return [
          ..._savedViews.map((view) {
            final isActive = view.id == _activeSavedViewId;
            return PopupMenuItem<String>(
              value: view.id,
              height: 40,
              child: Row(
                children: [
                  if (isActive)
                    const Icon(Icons.check, size: 16, color: AppColors.primary)
                  else
                    const SizedBox(width: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      view.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                        color: isActive ? AppColors.primary : null,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const PopupMenuDivider(),
          const PopupMenuItem<String>(
            value: '_save',
            height: 40,
            child: Row(
              children: [
                Icon(Icons.bookmark_add_outlined, size: 18),
                SizedBox(width: 8),
                Text('Save current view'),
              ],
            ),
          ),
          if (hasActive)
            const PopupMenuItem<String>(
              value: '_delete',
              height: 40,
              child: Row(
                children: [
                  Icon(Icons.delete_outline, size: 18),
                  SizedBox(width: 8),
                  Text('Delete active view'),
                ],
              ),
            ),
        ];
      },
    );
  }

  Widget _buildCatalogActionsMenu() {
    final chrome = ChromeColors.of(context);
    return PopupMenuButton<String>(
      tooltip: 'More actions',
      onSelected: (value) {
        switch (value) {
          case 'new_item':
            _handleAddItem(null, 0, isGroup: false);
          case 'new_group':
            _handleAddItem(null, 0, isGroup: true);
          case 'csv_tools':
            _showCsvToolsMenu();
        }
      },
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Icon(
          Icons.more_horiz,
          size: 18,
          color: chrome.text,
        ),
      ),
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'new_item',
          height: 40,
          child: Row(
            children: [
              Icon(Icons.add, size: 18),
              SizedBox(width: 10),
              Text('New Item'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'new_group',
          height: 40,
          child: Row(
            children: [
              Icon(Icons.create_new_folder_outlined, size: 18),
              SizedBox(width: 10),
              Text('New Group'),
            ],
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'csv_tools',
          height: 40,
          child: Row(
            children: [
              Icon(Icons.table_view_outlined, size: 18),
              SizedBox(width: 10),
              Text('CSV Tools'),
            ],
          ),
        ),
      ],
    );
  }

  void _showCsvToolsMenu() {
    // Delegate to the existing CSV popup by showing it programmatically
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    if (workspaceId == null) return;

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Import & Export'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              showCatalogWebImportDialog(context, workspaceId: workspaceId);
            },
            child: const ListTile(
              dense: true,
              leading: Icon(Icons.travel_explore),
              title: Text('Import from Web (AI)'),
              subtitle: Text(
                'Paste a supplier product URL',
                style: TextStyle(fontSize: 11),
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _showCatalogCsvImport(workspaceId);
            },
            child: const ListTile(
              dense: true,
              leading: Icon(Icons.download_outlined),
              title: Text('Import Catalog CSV'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _exportCatalogCsv(workspaceId);
            },
            child: const ListTile(
              dense: true,
              leading: Icon(Icons.upload_outlined),
              title: Text('Export Catalog CSV'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _downloadCatalogImportTemplate();
            },
            child: const ListTile(
              dense: true,
              leading: Icon(Icons.file_download_outlined),
              title: Text('Download Import Template'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _showCatalogColumnGuide();
            },
            child: const ListTile(
              dense: true,
              leading: Icon(Icons.rule_folder_outlined),
              title: Text('CSV Column Guide'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  void _showCatalogFilterDialog(List<CatalogItem> allItems) {
    final health = _buildCatalogHealthSnapshot(allItems);
    showDialog(
      context: context,
      builder: (ctx) {
        return _CatalogFilterDialog(
          currentFilter: _quickFilter,
          health: health,
          allItems: allItems,
          onApply: (filter) {
            setState(() {
              _quickFilter = filter;
              _activeSavedViewId = null;
            });
            _expandVisibleMatches();
            Navigator.of(ctx).pop();
          },
        );
      },
    );
  }

  Widget _buildColumnPicker() {
    return TableDefaultColumnPickerButton(
      columnIds: _allColumns,
      isColumnVisible: _isColumnVisible,
      onToggleColumn: _toggleColumn,
      columnNames: _columnNames,
    );
  }

  Widget _buildAddRow(String workspaceId) {
    return TableAddItemGroupRow(
      leadingSpacing: _checkboxColumnWidth + _afterCheckboxGap,
      padding: const EdgeInsets.symmetric(
        horizontal: _tableHorizontalPadding,
        vertical: AppSpacing.md,
      ),
      borderSide: BorderSide(color: AppColors.cardBorder),
      onAddItem: () => _handleAddItem(null, 0, isGroup: false),
      onAddGroup: () => _handleAddItem(null, 0, isGroup: true),
    );
  }

  Widget _buildTableHeader(List<CatalogItem> displayedItems) {
    final isAllSelected =
        displayedItems.isNotEmpty &&
        displayedItems.every((item) => _selectedItemIds.contains(item.id));
    final isSomeSelected =
        displayedItems.any((item) => _selectedItemIds.contains(item.id)) &&
        !isAllSelected;

    final headerStyle =
        TableViewStyles.headerLabelStyle(context) ??
        const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12,
          color: AppColors.textSecondary,
        );

    final widths = {
      for (final column in _catalogHeaderColumns)
        column.id: _columnWidths[column.id] ?? column.defaultWidth,
    };

    return TableHeaderRow(
      padding: const EdgeInsets.symmetric(horizontal: _tableHorizontalPadding),
      children: [
        SizedBox(
          width: _checkboxColumnWidth,
          child: Center(
            child: Checkbox(
              value: isAllSelected,
              tristate: isSomeSelected,
              onChanged: (value) => _selectAll(value ?? false, displayedItems),
            ),
          ),
        ),
        const SizedBox(width: _afterCheckboxGap),
        Expanded(
          child: Row(
            children: [
              const SizedBox(width: _nameHeaderInset),
              _CatalogSortableLabel(
                label: 'Name',
                textStyle: headerStyle,
                isSorted: _sortState.column == 'name',
                ascending: _sortState.column == 'name' ? _sortState.ascending : true,
                onTap: () => _toggleSort('name'),
              ),
            ],
          ),
        ),
        ...buildTableHeaderCells(
          context: context,
          columns: _catalogHeaderColumns,
          widths: widths,
          isVisible: (column) => _isColumnVisible(column.id),
          onColumnResize: _handleColumnResize,
          textStyle: headerStyle,
          onSortTap: (column) => _toggleSort(column.id),
          sortedColumnId: _sortState.column,
          sortAscending: _sortState.ascending,
        ),
      ],
    );
  }

  Widget _buildSummaryFooter(List<CatalogItem> allItems) {
    final health = _buildCatalogHealthSnapshot(allItems);
    final leafItems = allItems
        .where((item) => item.itemType == CatalogItemType.item)
        .toList();
    final groupCount = allItems
        .where((item) => item.itemType == CatalogItemType.group)
        .length;
    final taxableCount = leafItems.where((item) => item.isTaxable).length;
    final avgMarkup = leafItems.isEmpty
        ? 0.0
        : leafItems.fold<double>(0, (sum, item) => sum + item.markup) /
              leafItems.length;
    final avgMargin = leafItems.isEmpty
        ? 0.0
        : leafItems.fold<double>(0, (sum, item) => sum + item.margin) /
              leafItems.length;
    final skuCount = leafItems
        .where((item) => (item.sku ?? '').trim().isNotEmpty)
        .length;
    final units = leafItems
        .map((item) => item.unit?.trim())
        .whereType<String>()
        .where((unit) => unit.isNotEmpty)
        .toSet();

    return TableSummaryFooter(
      padding: const EdgeInsets.symmetric(horizontal: _tableHorizontalPadding),
      children: [
        const SizedBox(width: _checkboxColumnWidth),
        const SizedBox(width: _afterCheckboxGap),
        TableSummaryLabel(
          text:
              '${leafItems.length} items • $groupCount groups • ${health.readyCount} ready',
          inset: _nameHeaderInset,
        ),
        if (_isColumnVisible('unit'))
          TableSummaryCell(
            width: 80,
            text: units.isEmpty
                ? null
                : units.length == 1
                ? units.first
                : '${units.length} types',
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            isBold: true,
          ),
        if (_isColumnVisible('unitCost')) const TableSummaryCell(width: 120),
        if (_isColumnVisible('unitPrice')) const TableSummaryCell(width: 120),
        if (_isColumnVisible('markup'))
          TableSummaryCell(
            width: 100,
            text: '${avgMarkup.toStringAsFixed(1)}%',
            isBold: true,
          ),
        if (_isColumnVisible('margin'))
          Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            padding: const EdgeInsets.only(left: 8),
            child: TableSummaryCell(
              width: 100,
              text: '${avgMargin.toStringAsFixed(1)}%',
              isBold: true,
            ),
          ),
        if (_isColumnVisible('taxable'))
          TableSummaryCell(
            width: 80,
            text: '$taxableCount/${leafItems.length}',
            isBold: true,
          ),
        if (_isColumnVisible('sku'))
          TableSummaryCell(
            width: 140,
            text: '$skuCount/${leafItems.length} filled',
            isBold: true,
          ),
        if (_isColumnVisible('category'))
          TableSummaryCell(
            width: 160,
            text:
                '${leafItems.length - health.missingCategoryCount}/${leafItems.length} filled',
            isBold: true,
          ),
      ],
    );
  }

  bool _isLeafCatalogItem(CatalogItem item) =>
      item.itemType == CatalogItemType.item;

  bool _hasCatalogText(String? value) => (value ?? '').trim().isNotEmpty;

  bool _isMissingSku(CatalogItem item) =>
      _isLeafCatalogItem(item) && !_hasCatalogText(item.sku);

  bool _isMissingCategory(CatalogItem item) =>
      _isLeafCatalogItem(item) && !_hasCatalogText(item.category);

  bool _isMissingUnit(CatalogItem item) =>
      _isLeafCatalogItem(item) && !_hasCatalogText(item.unit);

  bool _isMissingPricing(CatalogItem item) =>
      _isLeafCatalogItem(item) && (item.unitCost <= 0 || item.unitPrice <= 0);

  bool _isMissingCostType(CatalogItem item) =>
      _isLeafCatalogItem(item) && !_hasCatalogText(item.costTypeName);

  bool _isCatalogItemReady(CatalogItem item) =>
      _isLeafCatalogItem(item) &&
      !_isMissingSku(item) &&
      !_isMissingCategory(item) &&
      !_isMissingUnit(item) &&
      !_isMissingPricing(item) &&
      !_isMissingCostType(item);

  _CatalogHealthSnapshot _buildCatalogHealthSnapshot(List<CatalogItem> items) {
    var leafCount = 0;
    var readyCount = 0;
    var missingSkuCount = 0;
    var missingCategoryCount = 0;
    var missingUnitCount = 0;
    var missingPricingCount = 0;
    var missingCostTypeCount = 0;

    for (final item in items) {
      if (!_isLeafCatalogItem(item)) continue;
      leafCount++;
      if (_isCatalogItemReady(item)) {
        readyCount++;
      }
      if (_isMissingSku(item)) missingSkuCount++;
      if (_isMissingCategory(item)) missingCategoryCount++;
      if (_isMissingUnit(item)) missingUnitCount++;
      if (_isMissingPricing(item)) missingPricingCount++;
      if (_isMissingCostType(item)) missingCostTypeCount++;
    }

    return _CatalogHealthSnapshot(
      leafCount: leafCount,
      readyCount: readyCount,
      missingSkuCount: missingSkuCount,
      missingCategoryCount: missingCategoryCount,
      missingUnitCount: missingUnitCount,
      missingPricingCount: missingPricingCount,
      missingCostTypeCount: missingCostTypeCount,
    );
  }

  GlobalKey _rowKeyForItem(String itemId) {
    return _rowKeysByItemId.putIfAbsent(itemId, GlobalKey.new);
  }

  List<Widget> _buildFlattenedCatalogRows(
    List<CatalogItem> allItems,
    String workspaceId, {
    List<HierarchyFlatEntry<CatalogItem>>? visibleEntries,
  }) {
    final entries = visibleEntries ?? _visibleCatalogEntries(allItems);

    final rows = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final item = entry.item;
      final siblings =
          _childrenByParentId[item.parentId ?? ''] ?? const <CatalogItem>[];
      final siblingIndex = siblings.indexWhere(
        (sibling) => sibling.id == item.id,
      );
      final canMoveUp = siblingIndex > 0;
      final canMoveDown =
          siblingIndex >= 0 && siblingIndex < siblings.length - 1;

      rows.add(
        KeyedSubtree(
          key: _rowKeyForItem(item.id),
          child: CatalogViewRow(
            key: ValueKey('catalog-row-${item.id}'),
            item: item,
            allItems: allItems,
            itemsById: _catalogItemsById,
            hasChildren: entry.hasChildren,
            indentLevel: entry.depth,
            isExpanded: _expandedItems.contains(item.id),
            isSelected: _selectedItemIds.contains(item.id),
            treeGuides: entry.treeGuides,
            isLastChild: entry.isLastChild,
            searchQuery: _searchQuery,
            visibleColumns: _colVis.toSet(),
            columnWidths: _columnWidths,
            onExpandToggle: entry.hasChildren
                ? () {
                    setState(() {
                      if (_expandedItems.contains(item.id)) {
                        _expandedItems.remove(item.id);
                      } else {
                        _expandedItems.add(item.id);
                      }
                    });
                  }
                : null,
            onSelectionChanged: _handleSelectionChanged,
            onItemChanged: _handleItemChanged,
            onAddItem: (parentId, level, {required isGroup}) =>
                _handleAddItem(parentId, level, isGroup: isGroup),
            onEditItem: _handleEditItem,
            onDuplicateItem: _handleDuplicateItem,
            onDeleteItem: _handleDeleteItem,
            onItemParentChanged: _handleItemParentChanged,
            onItemDropped: _handleItemDropped,
            canMoveUp: canMoveUp,
            canMoveDown: canMoveDown,
            onMoveUp: canMoveUp
                ? () => _moveItemWithinSiblings(item, -1)
                : null,
            onMoveDown: canMoveDown
                ? () => _moveItemWithinSiblings(item, 1)
                : null,
          ),
        ),
      );

      if (_addingToParentId != null &&
          _addingHierarchyLevel != null &&
          _isLastVisibleRowInParentSubtree(
            entries,
            rowIndex: i,
            parentId: _addingToParentId!,
          )) {
        rows.add(
          KeyedSubtree(
            key: ValueKey('catalog-inline-add-${_addingToParentId!}'),
            child: _buildInlineCatalogAddRow(
              workspaceId: workspaceId,
              parentId: _addingToParentId!,
              hierarchyLevel: _addingHierarchyLevel!,
              indentLevel: (entry.depth + 1).clamp(0, 4),
            ),
          ),
        );
      }
    }

    if (_addingToParentId == null && _addingHierarchyLevel == 0) {
      rows.add(
        KeyedSubtree(
          key: const ValueKey('catalog-inline-add-root'),
          child: _buildInlineCatalogAddRow(
            workspaceId: workspaceId,
            parentId: null,
            hierarchyLevel: 0,
            indentLevel: 0,
          ),
        ),
      );
    }

    rows.add(
      KeyedSubtree(
        key: const ValueKey('add-row'),
        child: _buildAddRow(workspaceId),
      ),
    );

    return rows;
  }

  List<HierarchyFlatEntry<CatalogItem>> _visibleCatalogEntries(
    List<CatalogItem> allItems,
  ) {
    final sortComparator = _catalogSortComparator;
    final entries = flattenHierarchy<CatalogItem>(
      items: allItems,
      idOf: (item) => item.id,
      parentIdOf: (item) => item.parentId,
      isExpandedOf: (item) => _expandedItems.contains(item.id),
      sortSiblings:
          sortComparator ?? (a, b) => a.sortOrder.compareTo(b.sortOrder),
    );
    return entries
        .where((entry) => _isItemVisibleInSearch(entry.item))
        .toList(growable: false);
  }

  int Function(CatalogItem a, CatalogItem b)? get _catalogSortComparator {
    if (_sortState.column == null) return null;

    return (a, b) {
      final groupCompare = _catalogTypeSortRank(
        a,
      ).compareTo(_catalogTypeSortRank(b));
      if (groupCompare != 0) return groupCompare;

      final direction = _sortState.ascending ? 1 : -1;
      var compare = 0;
      switch (_sortState.column) {
        case 'name':
          compare = _compareStrings(a.name, b.name);
          break;
        case 'unit':
          compare = _compareStrings(a.unit, b.unit);
          break;
        case 'unitCost':
          compare = a.unitCost.compareTo(b.unitCost);
          break;
        case 'unitPrice':
          compare = a.unitPrice.compareTo(b.unitPrice);
          break;
        case 'markup':
          compare = a.markup.compareTo(b.markup);
          break;
        case 'margin':
          compare = a.margin.compareTo(b.margin);
          break;
        case 'taxable':
          compare = a.isTaxable == b.isTaxable ? 0 : (a.isTaxable ? 1 : -1);
          break;
        case 'sku':
          compare = _compareStrings(a.sku, b.sku);
          break;
        case 'category':
          compare = _compareStrings(a.category, b.category);
          break;
        case 'updatedAt':
          compare = a.updatedAt.compareTo(b.updatedAt);
          break;
      }

      if (compare == 0) {
        compare = _compareStrings(a.name, b.name);
      }
      if (compare == 0) {
        compare = a.sortOrder.compareTo(b.sortOrder);
      }
      return compare * direction;
    };
  }

  int _catalogTypeSortRank(CatalogItem item) {
    return item.itemType == CatalogItemType.group ? 0 : 1;
  }

  int _compareStrings(String? a, String? b) {
    return (a ?? '').trim().toLowerCase().compareTo(
      (b ?? '').trim().toLowerCase(),
    );
  }

  List<_CatalogSavedView> _decodeSavedViews(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (entry) =>
                _CatalogSavedView.fromMap(Map<String, dynamic>.from(entry)),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _showSaveViewDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Save current view'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'e.g. Missing SKU Cleanup',
              border: OutlineInputBorder(),
            ),
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
        );
      },
    );

    if (name == null || name.isEmpty) return;

    final view = _CatalogSavedView(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      searchQuery: _searchQuery,
      quickFilter: _quickFilter.name,
      sortColumn: _sortState.column,
      sortAscending: _sortState.ascending,
      visibleColumns: _colVis.toList(),
      createdAt: DateTime.now(),
    );

    setState(() {
      _savedViews = [..._savedViews, view];
      _activeSavedViewId = view.id;
    });
    await _saveSavedViews();
  }

  void _applySavedViewById(String viewId) {
    _CatalogSavedView? selectedView;
    for (final view in _savedViews) {
      if (view.id == viewId) {
        selectedView = view;
        break;
      }
    }
    if (selectedView == null) return;

    final quickFilter = _catalogQuickFilterFromName(selectedView.quickFilter);
    setState(() {
      _searchQuery = selectedView!.searchQuery;
      _quickFilter = quickFilter;
      _sortState = TableSortState(
        column: selectedView.sortColumn,
        ascending: selectedView.sortAscending,
      );
      _colVis = TableColumnVisibility(selectedView.visibleColumns);
      _activeSavedViewId = selectedView.id;
    });
    _saveColumnPreferences();
    _expandVisibleMatches();
  }

  Future<void> _deleteActiveSavedView() async {
    final activeId = _activeSavedViewId;
    if (activeId == null) return;

    setState(() {
      _savedViews = _savedViews
          .where((view) => view.id != activeId)
          .toList(growable: false);
      _activeSavedViewId = null;
    });
    await _saveSavedViews();
  }

  _CatalogQuickFilter _catalogQuickFilterFromName(String raw) {
    for (final value in _CatalogQuickFilter.values) {
      if (value.name == raw) return value;
    }
    return _CatalogQuickFilter.all;
  }

  bool _isLastVisibleRowInParentSubtree(
    List<HierarchyFlatEntry<CatalogItem>> entries, {
    required int rowIndex,
    required String parentId,
  }) {
    final current = entries[rowIndex].item;
    if (!_isSelfOrDescendantOf(current, parentId)) return false;
    if (rowIndex >= entries.length - 1) return true;
    final next = entries[rowIndex + 1].item;
    return !_isSelfOrDescendantOf(next, parentId);
  }

  bool _isSelfOrDescendantOf(CatalogItem item, String ancestorId) {
    if (item.id == ancestorId) return true;
    var parentId = item.parentId;
    var iterations = 0;
    while (parentId != null && iterations < 100) {
      iterations++;
      if (parentId == ancestorId) return true;
      parentId = _catalogItemsById[parentId]?.parentId;
    }
    return false;
  }

  void _selectAll(bool selected, List<CatalogItem> displayedItems) {
    setState(() {
      if (selected) {
        _selectedItemIds
          ..clear()
          ..addAll(displayedItems.map((item) => item.id));
      } else {
        _selectedItemIds.clear();
      }
    });
  }

  void _clearSelection() {
    setState(() => _selectedItemIds.clear());
  }

  List<CatalogItem> _selectedLeafItems() {
    return _allCatalogItems
        .where(
          (item) =>
              _selectedItemIds.contains(item.id) &&
              item.itemType == CatalogItemType.item,
        )
        .toList(growable: false);
  }

  Set<String> _selectedDescendantIds() {
    final ids = <String>{};
    for (final selectedId in _selectedItemIds) {
      for (final descendant
          in _descendantsByItemId[selectedId] ?? const <CatalogItem>[]) {
        ids.add(descendant.id);
      }
    }
    ids.removeAll(_selectedItemIds);
    return ids;
  }

  void _handleSelectionChanged(CatalogItem item, bool selected) {
    final descendants = _descendantsByItemId[item.id] ?? const <CatalogItem>[];
    setState(() {
      if (selected) {
        _selectedItemIds.add(item.id);
        _selectedItemIds.addAll(descendants.map((descendant) => descendant.id));
      } else {
        _selectedItemIds.remove(item.id);
        _selectedItemIds.removeAll(
          descendants.map((descendant) => descendant.id),
        );
      }
    });
  }

  Future<void> _handleItemChanged(CatalogItem item) async {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    if (workspaceId == null) return;

    await _catalogService.updateCatalogItem(workspaceId, item);
  }

  void _handleAddItem(
    String? parentId,
    int hierarchyLevel, {
    required bool isGroup,
  }) {
    // Items open in a small in-app dialog popup. Groups still use the
    // lightweight inline add row.
    if (!isGroup) {
      showCatalogItemFormPopup(context);
      return;
    }

    if (parentId != null) {
      setState(() {
        _expandedItems.add(parentId);
        _addingToParentId = parentId;
        _addingHierarchyLevel = hierarchyLevel;
        _addingAsGroup = isGroup;
      });
      return;
    }

    setState(() {
      _addingToParentId = null;
      _addingHierarchyLevel = 0;
      _addingAsGroup = isGroup;
    });
  }

  Widget _buildInlineCatalogAddRow({
    required String workspaceId,
    required String? parentId,
    required int hierarchyLevel,
    required int indentLevel,
  }) {
    return CatalogInlineAddRow(
      workspaceId: workspaceId,
      parentId: parentId,
      hierarchyLevel: hierarchyLevel,
      indentLevel: indentLevel,
      isGroup: _addingAsGroup,
      onCancel: () => setState(() {
        _addingToParentId = null;
        _addingHierarchyLevel = null;
      }),
      onSave: (newItem) async {
        final sortOrder = await _catalogService.getNextSortOrder(
          workspaceId,
          parentId,
        );
        await _catalogService.createCatalogItem(
          newItem.copyWith(sortOrder: sortOrder),
        );
        if (!mounted) return;
        setState(() {
          _addingToParentId = null;
          _addingHierarchyLevel = null;
        });
      },
    );
  }

  void _handleEditItem(CatalogItem item) {
    showCatalogItemFormPopup(context, item: item);
  }

  Future<void> _handleDuplicateItem(CatalogItem item) async {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    if (workspaceId == null) return;

    try {
      final sortOrder = await _catalogService.getNextSortOrder(
        workspaceId,
        item.parentId,
      );
      await _duplicateCatalogBranch(
        source: item,
        workspaceId: workspaceId,
        targetParentId: item.parentId,
        targetHierarchyLevel: item.hierarchyLevel,
        sortOrder: sortOrder,
        renameRoot: true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Duplicated "${item.name.trim().isEmpty ? 'item' : item.name}"',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to duplicate item: $e')));
    }
  }

  Future<void> _duplicateCatalogBranch({
    required CatalogItem source,
    required String workspaceId,
    required String? targetParentId,
    required int targetHierarchyLevel,
    required int sortOrder,
    bool renameRoot = false,
  }) async {
    final now = DateTime.now();
    final duplicatedItem = source.copyWith(
      id: '',
      name: renameRoot ? _duplicatedCatalogItemName(source.name) : source.name,
      parentId: targetParentId,
      hierarchyLevel: targetHierarchyLevel,
      sortOrder: sortOrder,
      createdAt: now,
      updatedAt: now,
    );

    final insertedItem = await _catalogService.addCatalogItem(
      workspaceId,
      duplicatedItem,
    );
    final childItems = _childrenByParentId[source.id] ?? const <CatalogItem>[];
    for (var index = 0; index < childItems.length; index++) {
      await _duplicateCatalogBranch(
        source: childItems[index],
        workspaceId: workspaceId,
        targetParentId: insertedItem.id,
        targetHierarchyLevel: targetHierarchyLevel + 1,
        sortOrder: index,
      );
    }
  }

  String _duplicatedCatalogItemName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Untitled Copy';
    if (trimmed.endsWith(' Copy')) return '$trimmed 2';
    return '$trimmed Copy';
  }

  Future<void> _handleDeleteItem(CatalogItem item) async {
    final descendantCount = _descendantsByItemId[item.id]?.length ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text(
          'Are you sure you want to delete "${item.name}"?${descendantCount > 0 ? ' This will also delete $descendantCount nested item${descendantCount == 1 ? '' : 's'}.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      final authProvider = context.read<AuthProvider>();
      final workspaceId = authProvider.appUser?.currentWorkspaceId;
      if (workspaceId != null) {
        await _catalogService.deleteCatalogItem(workspaceId, item.id);
        setState(() {
          _selectedItemIds.remove(item.id);
          _selectedItemIds.removeAll(
            (_descendantsByItemId[item.id] ?? const <CatalogItem>[]).map(
              (descendant) => descendant.id,
            ),
          );
        });
      }
    }
  }

  Future<void> _moveCatalogBranch(
    CatalogItem item,
    String? newParentId, {
    int? newSortOrder,
  }) async {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    if (workspaceId == null) return;

    final newLevel = newParentId == null
        ? 0
        : (_catalogItemsById[newParentId]?.hierarchyLevel ?? -1) + 1;
    final levelDelta = newLevel - item.hierarchyLevel;
    final sortOrder =
        newSortOrder ??
        await _catalogService.getNextSortOrder(workspaceId, newParentId);
    final now = DateTime.now();

    final descendants = _descendantsByItemId[item.id] ?? const <CatalogItem>[];
    final updates = <CatalogItem>[
      item.copyWith(
        parentId: newParentId,
        hierarchyLevel: newLevel,
        sortOrder: sortOrder,
        updatedAt: now,
      ),
      ...descendants.map(
        (descendant) => descendant.copyWith(
          hierarchyLevel: descendant.hierarchyLevel + levelDelta,
          updatedAt: now,
        ),
      ),
    ];

    await _catalogService.updateCatalogItems(workspaceId, updates);

    if (newParentId != null && mounted) {
      setState(() => _expandedItems.add(newParentId));
    }
  }

  Future<void> _handleItemParentChanged(
    CatalogItem item,
    String? newParentId,
  ) async {
    await _moveCatalogBranch(item, newParentId);
  }

  Future<void> _moveItemWithinSiblings(CatalogItem item, int direction) async {
    final siblings = List<CatalogItem>.from(
      _childrenByParentId[item.parentId ?? ''] ?? const <CatalogItem>[],
    );
    final index = siblings.indexWhere((sibling) => sibling.id == item.id);
    if (index < 0) return;

    final swapIndex = index + direction;
    if (swapIndex < 0 || swapIndex >= siblings.length) return;

    final moved = siblings.removeAt(index);
    siblings.insert(swapIndex, moved);
    await _catalogService.reorderItems(
      siblings.map((sibling) => sibling.id).toList(),
    );
  }

  Future<void> _handleItemDropped(
    CatalogItem dragged,
    CatalogItem target,
    DropZone zone,
  ) async {
    switch (zone) {
      case DropZone.child:
        if (target.itemType == CatalogItemType.group) {
          await _moveCatalogBranch(dragged, target.id);
        }
        break;
      case DropZone.above:
      case DropZone.below:
        final targetParentId = target.parentId;
        final siblings = List<CatalogItem>.from(
          _childrenByParentId[targetParentId ?? ''] ?? const <CatalogItem>[],
        );
        siblings.removeWhere((sibling) => sibling.id == dragged.id);
        final targetIndex = siblings.indexWhere(
          (sibling) => sibling.id == target.id,
        );
        if (targetIndex < 0) {
          await _moveCatalogBranch(dragged, targetParentId);
          return;
        }
        final insertIndex = zone == DropZone.above
            ? targetIndex
            : targetIndex + 1;
        siblings.insert(insertIndex, dragged);

        if (dragged.parentId != targetParentId) {
          await _moveCatalogBranch(
            dragged,
            targetParentId,
            newSortOrder: insertIndex,
          );
        }

        await _catalogService.reorderItems(
          siblings.map((sibling) => sibling.id).toList(),
        );
        break;
      case DropZone.unparent:
        await _moveCatalogBranch(dragged, null);
        break;
      case DropZone.none:
        break;
    }
  }

  Future<void> _handleMassDelete() async {
    final descendantCount = _selectedDescendantIds().length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Selected Items'),
        content: Text(
          'Delete ${_selectedItemIds.length} selected item(s)?${descendantCount > 0 ? ' This also removes $descendantCount nested item${descendantCount == 1 ? '' : 's'}.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      final authProvider = context.read<AuthProvider>();
      final workspaceId = authProvider.appUser?.currentWorkspaceId;
      if (workspaceId != null) {
        await _catalogService.deleteCatalogItems(
          workspaceId,
          _selectedItemIds.toList(),
        );
        setState(() => _selectedItemIds.clear());
      }
    }
  }

  Future<void> _handleMassEdit({CatalogMassEditPreset? preset}) async {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    if (workspaceId == null) return;

    final selectedItems = _allCatalogItems
        .where((item) => _selectedItemIds.contains(item.id))
        .toList(growable: false);
    if (selectedItems.isEmpty) return;

    showCatalogMassEditDialog(
      context,
      items: selectedItems,
      preset: preset,
      onItemsUpdated: (updatedItems) async {
        await _catalogService.updateCatalogItems(workspaceId, updatedItems);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Updated ${updatedItems.length} catalog item${updatedItems.length == 1 ? '' : 's'}',
            ),
          ),
        );
      },
      onCascadeToOpenJobs: (catalogIds, fieldOverrides) async {
        final result = await _catalogService.cascadeUpdatesToOpenJobs(
          workspaceId: workspaceId,
          catalogItemIds: catalogIds,
          fieldOverrides: fieldOverrides,
        );
        return CatalogMassEditCascadeSummary(
          matchedBudgetItems: result.matchedCount,
          touchedOpenProjects: result.projectCount,
        );
      },
    );
  }

  Future<void> _showMoveToGroupDialog() async {
    final selectedLeafs = _selectedLeafItems();
    if (selectedLeafs.isEmpty) return;

    final groups = _allCatalogItems
        .where((item) => item.itemType == CatalogItemType.group)
        .toList()
      ..sort((a, b) {
        final levelDiff = a.hierarchyLevel.compareTo(b.hierarchyLevel);
        if (levelDiff != 0) return levelDiff;
        return a.sortOrder.compareTo(b.sortOrder);
      });

    final targetId = await showDialog<Object?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Move ${selectedLeafs.length} item${selectedLeafs.length == 1 ? '' : 's'} to',
        ),
        contentPadding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.folder_open_outlined, size: 18),
                title: const Text(
                  'Root (no group)',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
                onTap: () => Navigator.of(context).pop('__root__'),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: groups.length,
                  itemBuilder: (_, i) {
                    final group = groups[i];
                    return ListTile(
                      contentPadding: EdgeInsets.only(
                        left: 16.0 + group.hierarchyLevel * 16,
                        right: 16,
                      ),
                      leading: const Icon(Icons.folder_outlined, size: 18),
                      title: Text(
                        group.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.of(context).pop(group.id),
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
        ],
      ),
    );

    if (targetId == null || !mounted) return;
    final targetGroupId = targetId == '__root__' ? null : targetId as String;
    await _handleMassMove(targetGroupId);
  }

  Future<void> _handleMassMove(String? targetGroupId) async {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    if (workspaceId == null) return;

    final selectedLeafs = _selectedLeafItems();
    if (selectedLeafs.isEmpty) return;

    final targetGroup =
        targetGroupId != null ? _catalogItemsById[targetGroupId] : null;
    final newLevel =
        targetGroupId == null ? 0 : (targetGroup?.hierarchyLevel ?? -1) + 1;
    final startSortOrder =
        await _catalogService.getNextSortOrder(workspaceId, targetGroupId);
    final now = DateTime.now();

    final updates = <CatalogItem>[
      for (var i = 0; i < selectedLeafs.length; i++)
        selectedLeafs[i].copyWith(
          parentId: targetGroupId,
          hierarchyLevel: newLevel,
          sortOrder: startSortOrder + i,
          updatedAt: now,
        ),
    ];

    await _catalogService.updateCatalogItems(workspaceId, updates);

    if (!mounted) return;

    if (targetGroupId != null) {
      setState(() => _expandedItems.add(targetGroupId));
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Moved ${updates.length} item${updates.length == 1 ? '' : 's'} to '
          '${targetGroup?.name ?? 'root'}',
        ),
      ),
    );
    _clearSelection();
  }

  Future<void> _exportCatalogCsv(String workspaceId) async {
    if (_isExportingCatalogCsv) return;
    setState(() {
      _isExportingCatalogCsv = true;
    });

    try {
      await _rawDataExportService.exportType(
        type: RawDataExportType.catalog,
        workspaceId: workspaceId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Catalog CSV export started')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to export catalog CSV: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExportingCatalogCsv = false;
        });
      }
    }
  }

  Future<void> _showCatalogCsvImport(String workspaceId) async {
    await showCatalogCsvImportDialog(context, workspaceId: workspaceId);
  }

  Future<void> _downloadCatalogImportTemplate() async {
    if (_isExportingCatalogCsv) return;
    setState(() {
      _isExportingCatalogCsv = true;
    });

    try {
      await _rawDataExportService.exportTemplateType(RawDataExportType.catalog);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Catalog import template download started'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to download catalog template: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExportingCatalogCsv = false;
        });
      }
    }
  }

  Future<void> _showCatalogColumnGuide() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        final columnGuide = _rawDataExportService.getColumnGuide(
          RawDataExportType.catalog,
        );
        return AlertDialog(
          title: const Text('Catalog CSV Column Guide'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'These are the columns included in the catalog export and template files.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final guide in columnGuide)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 180,
                            child: SelectableText(
                              guide.column,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              guide.description,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

class _CatalogSortableLabel extends StatefulWidget {
  final String label;
  final TextStyle? textStyle;
  final bool isSorted;
  final bool ascending;
  final VoidCallback onTap;

  const _CatalogSortableLabel({
    required this.label,
    this.textStyle,
    required this.isSorted,
    required this.ascending,
    required this.onTap,
  });

  @override
  State<_CatalogSortableLabel> createState() => _CatalogSortableLabelState();
}

class _CatalogSortableLabelState extends State<_CatalogSortableLabel> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final sortIcon = widget.isSorted
        ? (widget.ascending ? Icons.arrow_upward : Icons.arrow_downward)
        : Icons.unfold_more;
    final showIcon = widget.isSorted || _isHovered;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.label,
              style: widget.isSorted
                  ? widget.textStyle?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : widget.textStyle,
            ),
            if (showIcon) ...[
              const SizedBox(width: 2),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: widget.isSorted ? 1.0 : 0.5,
                child: Icon(
                  sortIcon,
                  size: 14,
                  color: widget.isSorted
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).hintColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CatalogHealthSnapshot {
  final int leafCount;
  final int readyCount;
  final int missingSkuCount;
  final int missingCategoryCount;
  final int missingUnitCount;
  final int missingPricingCount;
  final int missingCostTypeCount;

  const _CatalogHealthSnapshot({
    required this.leafCount,
    required this.readyCount,
    required this.missingSkuCount,
    required this.missingCategoryCount,
    required this.missingUnitCount,
    required this.missingPricingCount,
    required this.missingCostTypeCount,
  });

  String get readyPercentLabel {
    if (leafCount == 0) return '0%';
    final percent = (readyCount / leafCount) * 100;
    return '${percent.toStringAsFixed(percent >= 10 ? 0 : 1)}%';
  }
}

class _CatalogSavedView {
  final String id;
  final String name;
  final String searchQuery;
  final String quickFilter;
  final String? sortColumn;
  final bool sortAscending;
  final List<String> visibleColumns;
  final DateTime createdAt;

  const _CatalogSavedView({
    required this.id,
    required this.name,
    required this.searchQuery,
    required this.quickFilter,
    required this.sortColumn,
    required this.sortAscending,
    required this.visibleColumns,
    required this.createdAt,
  });

  factory _CatalogSavedView.fromMap(Map<String, dynamic> map) {
    return _CatalogSavedView(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Saved View',
      searchQuery: map['searchQuery'] as String? ?? '',
      quickFilter:
          map['quickFilter'] as String? ?? _CatalogQuickFilter.all.name,
      sortColumn: map['sortColumn'] as String?,
      sortAscending: map['sortAscending'] as bool? ?? true,
      visibleColumns: ((map['visibleColumns'] as List?) ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'searchQuery': searchQuery,
      'quickFilter': quickFilter,
      'sortColumn': sortColumn,
      'sortAscending': sortAscending,
      'visibleColumns': visibleColumns,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

class _MobileCatalogMetric {
  final String label;
  final String value;
  final Color? color;

  const _MobileCatalogMetric({
    required this.label,
    required this.value,
    this.color,
  });
}

class _CatalogFilterDialog extends StatefulWidget {
  final _CatalogQuickFilter currentFilter;
  final _CatalogHealthSnapshot health;
  final List<CatalogItem> allItems;
  final ValueChanged<_CatalogQuickFilter> onApply;

  const _CatalogFilterDialog({
    required this.currentFilter,
    required this.health,
    required this.allItems,
    required this.onApply,
  });

  @override
  State<_CatalogFilterDialog> createState() => _CatalogFilterDialogState();
}

class _CatalogFilterDialogState extends State<_CatalogFilterDialog> {
  late _CatalogQuickFilter _filter;

  @override
  void initState() {
    super.initState();
    _filter = widget.currentFilter;
  }

  static const _filterLabels = <_CatalogQuickFilter, String>{
    _CatalogQuickFilter.all: 'All',
    _CatalogQuickFilter.items: 'Items only',
    _CatalogQuickFilter.groups: 'Groups only',
    _CatalogQuickFilter.ready: 'Ready',
    _CatalogQuickFilter.missingSku: 'Missing SKU',
    _CatalogQuickFilter.missingCategory: 'Missing Category',
    _CatalogQuickFilter.missingUnit: 'Missing Unit',
    _CatalogQuickFilter.missingPricing: 'Pricing Gaps',
    _CatalogQuickFilter.missingCostType: 'Missing Cost Type',
    _CatalogQuickFilter.taxable: 'Taxable',
    _CatalogQuickFilter.recentlyUpdated: 'Updated 30d',
  };

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  const Text('Filters',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (_filter != _CatalogQuickFilter.all)
                    TextButton(
                      onPressed: () =>
                          setState(() => _filter = _CatalogQuickFilter.all),
                      child: const Text('Clear all'),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.base),
                shrinkWrap: true,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: _filter != _CatalogQuickFilter.all
                          ? AppColors.primary.withValues(alpha: 0.04)
                          : AppColors.surfaceAlt.withValues(alpha: 0.5),
                      border: Border.all(
                        color: _filter != _CatalogQuickFilter.all
                            ? AppColors.primary.withValues(alpha: 0.3)
                            : AppColors.cardBorder,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.r12),
                    ),
                    child: Theme(
                      data: Theme.of(context)
                          .copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        leading: Icon(Icons.filter_list, size: 20,
                            color: _filter != _CatalogQuickFilter.all
                                ? AppColors.primary
                                : AppColors.textSecondary),
                        title: const Text('Quick Filter',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text(
                          _filterLabels[_filter] ?? 'All',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                        initiallyExpanded: true,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: SearchableFilterChips(
                              items: _CatalogQuickFilter.values
                                  .where((f) => f != _CatalogQuickFilter.all)
                                  .map((f) => (
                                        id: f.name,
                                        label: _filterLabels[f] ?? f.name,
                                      ))
                                  .toList(),
                              selectedId: _filter == _CatalogQuickFilter.all
                                  ? null
                                  : _filter.name,
                              allLabel: 'All',
                              onAllSelected: () => setState(
                                  () => _filter = _CatalogQuickFilter.all),
                              onItemSelected: (id) => setState(() =>
                                  _filter = _CatalogQuickFilter.values
                                      .firstWhere((f) => f.name == id)),
                              searchHint: 'Search filters...',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => widget.onApply(_filter),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
