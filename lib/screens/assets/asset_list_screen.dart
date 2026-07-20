import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../utils/user_facing_error.dart';
import '../../widgets/common/list_skeleton.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/asset.dart';
import '../../models/asset_category.dart';
import '../../models/asset_category_config.dart';
import '../../services/service_locator.dart';
import '../../services/supabase/asset_category_service.dart';
import '../../services/supabase/asset_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../services/supabase/user_service.dart';
import '../../utils/asset_export.dart';
import '../../utils/currency_utils.dart';
import '../../widgets/asset_form_popup.dart';
import '../../models/project.dart';
import '../../widgets/animated_empty_state_cta.dart';
import '../../widgets/common/entity_card_grid.dart';
import '../../widgets/common/entity_create_card.dart';
import '../../widgets/common/module_header.dart';
import '../../widgets/common/saved_views_menu.dart';
import '../../widgets/common/searchable_filter_chips.dart';
import '../../widgets/common/view_icon_button.dart';
import '../../widgets/common/view_toolbar.dart';
import '../../widgets/project_selector_dialog.dart';
import '../../theme/theme.dart';
import '../../widgets/table/table_layout_shell.dart';
import '../../widgets/table/table_header_row.dart';
import '../../widgets/table/table_column_schema.dart';
import '../../widgets/table/table_header_cells_builder.dart';
import '../../widgets/table/table_view_styles.dart';
import '../../widgets/table/hover_action_row.dart';
import 'widgets/asset_card.dart';

enum AssetViewType { table, card }

enum AssetRecordFilter { active, retired }

class AssetListScreen extends StatefulWidget {
  /// Whether to show the ModuleHeader at the top. Pass false when embedded
  /// inside another module (e.g. the Assets tab of Inventory) to avoid a
  /// duplicate title block.
  final bool showModuleHeader;

  const AssetListScreen({super.key, this.showModuleHeader = true});

  @override
  State<AssetListScreen> createState() => _AssetListScreenState();
}

class _AssetListScreenState extends State<AssetListScreen>
    with SingleTickerProviderStateMixin {
  static const String _savedViewsPrefKey = 'saved_asset_views';

  static const _statusOptions = <({String id, String label})>[
    (id: 'available', label: 'Available'),
    (id: 'assigned', label: 'Assigned'),
    (id: 'maintenance', label: 'Maintenance'),
  ];

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  AssetViewType _viewType = AssetViewType.card;
  AssetRecordFilter _recordFilter = AssetRecordFilter.active;
  String? _filterStatus;
  String? _filterCategory;
  Set<String> _filterTags = const {};
  List<String> _workspaceTags = const [];
  List<AssetCategoryConfig> _workspaceCategories = const [];
  String? _sortColumn;
  bool _sortAscending = true;
  String _searchQuery = '';
  final Map<String, double> _columnWidths = {};

  Set<String> _selectedIds = {};
  bool _selectionMode = false;

  SupabaseAssetService? _assetService;
  Stream<List<Asset>>? _assetsStream;
  String? _cachedWorkspaceId;

  List<_AssetSavedView> _savedViews = const [];
  String? _activeSavedViewId;

  void _maybeRebuildStream(String workspaceId) {
    if (_assetsStream == null || _cachedWorkspaceId != workspaceId) {
      _cachedWorkspaceId = workspaceId;
      _assetService = SupabaseAssetService(workspaceId: workspaceId);
      _assetsStream = _assetService!.getAssets();
      _refreshWorkspaceTags();
      _refreshWorkspaceCategories(workspaceId);
    }
  }

  void _handleColumnResize(TableColumnResize resize) {
    setState(() {
      _columnWidths[resize.columnId] = resize.width;
    });
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
    _loadViewPreference();
    _loadSavedViews();
  }

  Future<void> _refreshWorkspaceTags() async {
    if (_assetService == null) return;
    try {
      final tags = await _assetService!.getDistinctTags();
      if (!mounted) return;
      setState(() => _workspaceTags = tags);
    } catch (_) {
      // Suggestions are decorative — failure shouldn't break the screen.
    }
  }

  Future<void> _refreshWorkspaceCategories(String workspaceId) async {
    if (workspaceId.isEmpty) return;
    try {
      final categories =
          await SupabaseAssetCategoryService().getCategories(workspaceId);
      if (!mounted) return;
      setState(() => _workspaceCategories = categories);
    } catch (_) {
      // Falls back to the hardcoded enum — list still renders.
    }
  }

  Future<void> _loadSavedViews() async {
    final raw = await ServiceLocator.userPreferencesService
        .getSavedViews(_savedViewsPrefKey);
    if (!mounted) return;
    setState(() {
      _savedViews = raw.map(_AssetSavedView.fromMap).toList();
    });
  }

  void _applySavedViewById(String viewId) {
    final view = _savedViews.where((v) => v.id == viewId).firstOrNull;
    if (view == null) return;
    setState(() {
      _searchQuery = view.searchQuery;
      _viewType = view.viewType;
      _sortColumn = view.sortColumn;
      _sortAscending = view.sortAscending;
      _filterStatus = view.filterStatus;
      _filterCategory = view.filterCategory;
      _filterTags = view.filterTags.toSet();
      _recordFilter = view.recordFilter;
      _activeSavedViewId = view.id;
    });
    _saveViewPreference(view.viewType);
  }

  Future<void> _saveCurrentView() async {
    final name = await promptSavedViewName(
      context,
      hintText: 'e.g. Active equipment by name',
    );
    if (name == null || name.isEmpty) return;
    final view = _AssetSavedView(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      searchQuery: _searchQuery,
      viewType: _viewType,
      sortColumn: _sortColumn,
      sortAscending: _sortAscending,
      filterStatus: _filterStatus,
      filterCategory: _filterCategory,
      filterTags: _filterTags.toList()..sort(),
      recordFilter: _recordFilter,
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

  Future<void> _deleteSavedView(String viewId) async {
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

  bool get _hasNonDefaultState =>
      _searchQuery.trim().isNotEmpty ||
      _sortColumn != null ||
      _filterStatus != null ||
      _filterCategory != null ||
      _filterTags.isNotEmpty ||
      _recordFilter != AssetRecordFilter.active;

  int get _activeFilterCount {
    var count = 0;
    if (_filterStatus != null) count++;
    if (_filterCategory != null) count++;
    if (_filterTags.isNotEmpty) count++;
    if (_recordFilter != AssetRecordFilter.active) count++;
    return count;
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadViewPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('assets_view_type');
    if (!mounted) return;
    setState(() {
      _viewType = saved == 'list' || saved == 'table'
          ? AssetViewType.table
          : AssetViewType.card;
    });
  }

  Future<void> _saveViewPreference(AssetViewType viewType) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('assets_view_type', viewType.name);
  }

  void _showAssetFilterDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => _AssetFilterDialog(
        selectedStatus: _filterStatus,
        selectedCategory: _filterCategory,
        availableCategories: _workspaceCategories,
        selectedTags: _filterTags,
        availableTags: _workspaceTags,
        recordFilter: _recordFilter,
        savedViews: _savedViews,
        activeSavedViewId: _activeSavedViewId,
        onApply: (status, category, tags, record) {
          setState(() {
            _filterStatus = status;
            _filterCategory = category;
            _filterTags = tags;
            _recordFilter = record;
            _activeSavedViewId = null;
          });
          Navigator.of(ctx).pop();
        },
        onApplySavedView: (viewId) {
          Navigator.of(ctx).pop();
          _applySavedViewById(viewId);
        },
        onSaveCurrentView: () {
          Navigator.of(ctx).pop();
          _saveCurrentView();
        },
        onDeleteSavedView: _deleteSavedView,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final appUser = authProvider.appUser;
    final workspaceId =
        appUser?.activeWorkspaceId ?? appUser?.workspaceId ?? '';
    _maybeRebuildStream(workspaceId);
    final assetService = _assetService!;

    return Scaffold(
      body: Column(
        children: [
          if (widget.showModuleHeader)
            const ModuleHeader(
              icon: Icons.inventory_2_outlined,
              title: 'Equipment',
              description:
                  'Owned equipment register — tools, machinery and tracked gear.',
            ),
          _buildHeader(context),
          if (_selectionMode && _selectedIds.isNotEmpty)
            _buildBulkActionBar(context, assetService),
          Expanded(
            child: StreamBuilder<List<Asset>>(
              stream: _assetsStream,
              builder: (context, snapshot) {
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
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const ListSkeleton();
                }

                final allAssets = snapshot.data ?? [];

                if (allAssets.isEmpty) {
                  return _buildEmptyState();
                }

                final assets = _filterAssets(allAssets);

                if (assets.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.search_off,
                          size: 48,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No equipment matches these filters',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Try clearing the search or status filter',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        TextButton.icon(
                          onPressed: () => setState(() {
                            _searchQuery = '';
                            _filterStatus = null;
                            _filterCategory = null;
                            _filterTags = const {};
                            _recordFilter = AssetRecordFilter.active;
                            _activeSavedViewId = null;
                          }),
                          icon: const Icon(Icons.clear),
                          label: const Text('Clear filters'),
                        ),
                      ],
                    ),
                  );
                }

                if (_viewType == AssetViewType.table) {
                  return _buildTableView(assets);
                }

                return EntityCardGrid(
                  itemCount: assets.length,
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.screenPaddingMobile,
                    AppSpacing.screenPaddingMobile,
                    AppSpacing.screenPaddingMobile,
                    MediaQuery.paddingOf(context).bottom + 90,
                  ),
                  itemBuilder: (context, index, cardWidth) {
                    final asset = assets[index];
                    final categoryConfig = _workspaceCategories
                        .where((c) => c.name == asset.category)
                        .firstOrNull;
                    return AssetCard(
                      asset: asset,
                      categoryConfig: categoryConfig,
                      onRetire: () =>
                          _retireAsset(context, assetService, asset),
                      selectionMode: _selectionMode,
                      isSelected: _selectedIds.contains(asset.id),
                      onLongPress: () => _enterSelectionMode(asset.id),
                      onSelectionChanged: (selected) =>
                          _toggleSelection(asset.id, selected),
                    );
                  },
                  trailingBuilder: (context, cardWidth) => EntityCreateCard(
                    title: 'New Equipment',
                    subtitle: kIsWeb ? 'Click to add new equipment' : 'Tap to add new equipment',
                    size: EntityCreateCardSize.regular,
                    minHeight: _getCreateCardHeight(cardWidth),
                    onTap: () => showAssetFormPopup(context),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return ViewToolbar(
      searchHint: 'Search equipment...',
      searchQuery: _searchQuery,
      onSearch: (query) => setState(() {
        _searchQuery = query;
        _activeSavedViewId = null;
      }),
      centerSlot: _buildViewIcons(),
      quickToggles: [
        SavedViewsMenu(
          savedViews: _savedViews
              .map((v) => SavedViewEntry(id: v.id, name: v.name))
              .toList(growable: false),
          activeSavedViewId: _activeSavedViewId,
          canSaveCurrent: _hasNonDefaultState,
          onApplyView: _applySavedViewById,
          onDeleteView: _deleteSavedView,
          onSaveCurrentView: _saveCurrentView,
        ),
        _buildRecordToggle(),
        _buildExportButton(),
        _buildScanButton(),
      ],
      filterCount: _activeFilterCount,
      onFilterTap: _showAssetFilterDialog,
    );
  }

  Widget _buildRecordToggle() {
    final isRetired = _recordFilter == AssetRecordFilter.retired;
    return Tooltip(
      message: isRetired ? 'Showing retired' : 'Show retired',
      child: InkWell(
        onTap: () {
          setState(() {
            _recordFilter = isRetired
                ? AssetRecordFilter.active
                : AssetRecordFilter.retired;
            _activeSavedViewId = null;
          });
        },
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isRetired
                ? AppColors.primary.withValues(alpha: 0.12)
                : null,
            border: Border.all(
              color: isRetired ? AppColors.primary : AppColors.cardBorder,
            ),
          ),
          child: Icon(
            Icons.archive_outlined,
            size: 18,
            color: isRetired
                ? AppColors.primary
                : ChromeColors.of(context).text,
          ),
        ),
      ),
    );
  }

  Widget _buildExportButton() {
    return Tooltip(
      message: 'Export CSV',
      child: InkWell(
        onTap: () => _exportFilteredToCsv(context),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Icon(
            Icons.file_download_outlined,
            size: 18,
            color: ChromeColors.of(context).text,
          ),
        ),
      ),
    );
  }

  Widget _buildScanButton() {
    return Tooltip(
      message: 'Scan QR Code',
      child: InkWell(
        onTap: () => context.push('/qr-scanner'),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Icon(
            Icons.qr_code_scanner,
            size: 18,
            color: ChromeColors.of(context).text,
          ),
        ),
      ),
    );
  }

  Widget _buildViewIcons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ViewIconButton(
          icon: Icons.grid_view,
          tooltip: 'Cards',
          isSelected: _viewType == AssetViewType.card,
          onTap: () {
            setState(() {
              _viewType = AssetViewType.card;
              _activeSavedViewId = null;
            });
            _saveViewPreference(AssetViewType.card);
          },
        ),
        ViewIconButton(
          icon: Icons.view_list,
          tooltip: 'Table',
          isSelected: _viewType == AssetViewType.table,
          onTap: () {
            setState(() {
              _viewType = AssetViewType.table;
              _activeSavedViewId = null;
            });
            _saveViewPreference(AssetViewType.table);
          },
        ),
      ],
    );
  }

  List<Asset> _filterAssets(List<Asset> assets) {
    Iterable<Asset> filtered = assets;

    if (_recordFilter == AssetRecordFilter.retired) {
      filtered = filtered.where((a) => a.status == 'retired');
    } else {
      filtered = filtered.where((a) => a.status != 'retired');
    }

    if (_filterStatus != null) {
      filtered = filtered.where((a) => a.status == _filterStatus);
    }

    if (_filterCategory != null) {
      filtered = filtered.where((a) => a.category == _filterCategory);
    }

    if (_filterTags.isNotEmpty) {
      filtered = filtered.where(
        (a) => a.tags.any(_filterTags.contains),
      );
    }

    final query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      filtered = filtered.where((a) {
        return a.name.toLowerCase().contains(query) ||
            (a.serialNumber?.toLowerCase().contains(query) ?? false) ||
            (a.description?.toLowerCase().contains(query) ?? false) ||
            a.status.toLowerCase().contains(query);
      });
    }
    return filtered.toList();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.1),
                        Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.2),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.2),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.inventory_2,
                    size: 40,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          const Text(
            'No equipment yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Add your first equipment to get started',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 18),
          AnimatedEmptyStateCta(
            animation: _pulseAnimation,
            label: 'Add Your First Equipment',
            onTap: () {
              showAssetFormPopup(context);
            },
          ),
          const SizedBox(height: 10),
          Text(
            kIsWeb
                ? 'Click "Add Your First Equipment" to begin'
                : 'Tap "Add Your First Equipment" to begin',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  static const double _colName = 200;
  static const double _colSerial = 160;
  static const double _colStatus = 120;
  static const double _colDescription = 220;
  static const double _colPrice = 120;
  static const double _colGap = 12;

  static const _tableColumns = [
    TableColumnSchema(id: 'name', label: 'Name', defaultWidth: _colName, minWidth: 100, maxWidth: 400),
    TableColumnSchema(id: 'serial', label: 'Serial #', defaultWidth: _colSerial, minWidth: 80, maxWidth: 280),
    TableColumnSchema(id: 'status', label: 'Status', defaultWidth: _colStatus, minWidth: 80, maxWidth: 200),
    TableColumnSchema(id: 'description', label: 'Description', defaultWidth: _colDescription, minWidth: 100, maxWidth: 400),
    TableColumnSchema(id: 'price', label: 'Purchase Price', defaultWidth: _colPrice, minWidth: 80, maxWidth: 200),
  ];

  void _onColumnSortTap(String columnId) {
    setState(() {
      if (_sortColumn == columnId) {
        if (_sortAscending) {
          _sortAscending = false;
        } else {
          _sortColumn = null;
          _sortAscending = true;
        }
      } else {
        _sortColumn = columnId;
        _sortAscending = true;
      }
      _activeSavedViewId = null;
    });
  }

  List<Asset> _applySorting(List<Asset> assets) {
    if (_sortColumn == null) return assets;
    final sorted = List<Asset>.from(assets);
    final ascending = _sortAscending;
    sorted.sort((a, b) {
      int result;
      switch (_sortColumn) {
        case 'name':
          result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case 'serial':
          result = (a.serialNumber ?? '').compareTo(b.serialNumber ?? '');
        case 'status':
          result = a.status.compareTo(b.status);
        case 'description':
          result = (a.description ?? '').toLowerCase().compareTo((b.description ?? '').toLowerCase());
        case 'price':
          result = (a.purchasePrice ?? 0).compareTo(b.purchasePrice ?? 0);
        default:
          result = 0;
      }
      return ascending ? result : -result;
    });
    return sorted;
  }

  Widget _buildTableView(List<Asset> assets) {
    final sorted = _applySorting(assets);
    final headerStyle = TableViewStyles.headerLabelStyle(context);
    final allSelected = sorted.isNotEmpty &&
        sorted.every((a) => _selectedIds.contains(a.id));

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
      sortedColumnId: _sortColumn,
      sortAscending: _sortAscending,
    );

    final headerChildren = <Widget>[
      if (_selectionMode) ...[
        SizedBox(
          width: 40,
          child: Checkbox(
            value: allSelected,
            tristate: true,
            onChanged: (value) {
              setState(() {
                if (value == true) {
                  _selectedIds = sorted.map((a) => a.id).toSet();
                } else {
                  _selectedIds.clear();
                  _selectionMode = false;
                }
              });
            },
          ),
        ),
        const SizedBox(width: 4),
      ],
    ];
    for (int i = 0; i < headerCells.length; i++) {
      if (i > 0) headerChildren.add(const SizedBox(width: _colGap));
      headerChildren.add(headerCells[i]);
    }

    return TableLayoutShell(
      minTableWidth: 900,
      header: TableHeaderRow(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
        children: headerChildren,
      ),
      body: ListView.builder(
        itemCount: sorted.length,
        itemBuilder: (context, index) {
          final asset = sorted[index];
          return _buildAssetRow(context, asset);
        },
      ),
    );
  }

  double _colW(String id, double defaultWidth) =>
      _columnWidths[id] ?? defaultWidth;

  Widget _buildAssetRow(BuildContext context, Asset asset) {
    final isSelected = _selectedIds.contains(asset.id);
    return HoverActionRow(
      actionWidth: 40,
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 20),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'details', child: Text('View details')),
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
          ],
          onSelected: (value) {
            switch (value) {
              case 'details':
                context.push('/equipment/${asset.id}');
              case 'edit':
                showAssetFormPopup(context, assetId: asset.id);
            }
          },
        ),
      ],
      builder: (isHovered) => InkWell(
        onTap: () {
          if (_selectionMode) {
            _toggleSelection(asset.id, !isSelected);
          } else {
            context.push('/equipment/${asset.id}');
          }
        },
        onLongPress: () => _enterSelectionMode(asset.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.10)
                : isHovered
                    ? Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.5)
                    : Colors.transparent,
            border: Border(bottom: TableViewStyles.rowDivider(context)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: 10),
            child: Row(
              children: [
                if (_selectionMode) ...[
                  SizedBox(
                    width: 40,
                    child: Checkbox(
                      value: isSelected,
                      onChanged: (value) =>
                          _toggleSelection(asset.id, value ?? false),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                SizedBox(
                  width: _colW('name', _colName),
                  child: Text(
                    asset.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: _colGap),
                SizedBox(
                  width: _colW('serial', _colSerial),
                  child: Text(
                    asset.serialNumber ?? '—',
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: _colGap),
                SizedBox(
                  width: _colW('status', _colStatus),
                  child: Text(
                    asset.status,
                    style: const TextStyle(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: _colGap),
                SizedBox(
                  width: _colW('description', _colDescription),
                  child: Text(
                    asset.description ?? '—',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: _colGap),
                SizedBox(
                  width: _colW('price', _colPrice),
                  child: Text(
                    asset.purchasePrice != null
                        ? CurrencyUtils.formatCurrency(
                            asset.purchasePrice!,
                            context.read<WorkspaceProvider>().currencyCode,
                          )
                        : '—',
                    style: const TextStyle(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _getCreateCardHeight(double cardWidth) {
    if (cardWidth < 280) return 300;
    if (cardWidth < 340) return 360;
    return 420;
  }

  Future<void> _exportFilteredToCsv(BuildContext context) async {
    if (_assetService == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final currencyCode = context.read<WorkspaceProvider>().currencyCode;
    try {
      final allAssets = await _assetService!.getAssets().first;
      final filtered = _applySorting(_filterAssets(allAssets));
      if (filtered.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No equipment to export')),
        );
        return;
      }

      final projectIds = filtered
          .map((a) => a.assignedToProjectId)
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet();
      final userIds = filtered
          .map((a) => a.assignedToUserId)
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet();

      final projectsList = await Future.wait(
        projectIds.map(
          (id) => ServiceLocator.projectService.getProject(id),
        ),
      );
      final users =
          await SupabaseUserService().getUsersByIds(userIds.toList());

      final projectMap = <String, Project>{
        for (final p in projectsList.whereType<Project>()) p.id: p,
      };
      final userMap = {for (final u in users) u.id: u};

      await AssetExport().exportAssetsToCsv(
        assets: filtered,
        projectMap: projectMap,
        usersMap: userMap,
        currencyCode: currencyCode,
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(UserFacingError.uiMessage(e, action: 'export equipment')),
        ),
      );
    }
  }

  void _enterSelectionMode(String assetId) {
    setState(() {
      _selectionMode = true;
      _selectedIds = {assetId};
    });
  }

  void _toggleSelection(String assetId, bool selected) {
    setState(() {
      if (selected) {
        _selectedIds.add(assetId);
      } else {
        _selectedIds.remove(assetId);
        if (_selectedIds.isEmpty) _selectionMode = false;
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _runBulkAction(
    Future<void> Function() action,
    String successMessage,
  ) async {
    try {
      await action();
      if (!mounted) return;
      _exitSelectionMode();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.uiMessage(error, action: 'complete this action'),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _bulkAssignToProject(
    BuildContext context,
    SupabaseAssetService assetService,
    String workspaceId,
  ) async {
    final project = await showDialog<Project>(
      context: context,
      builder: (_) => ProjectSelectorDialog(
        workspaceId: workspaceId,
        currentProjectId: null,
      ),
    );
    if (project == null) return;
    final ids = _selectedIds.toList();
    await _runBulkAction(
      () => assetService.bulkAssignToProject(ids, project.id),
      'Assigned ${ids.length} equipment item${ids.length == 1 ? '' : 's'} to ${project.name}',
    );
  }

  Future<void> _confirmBulkDelete(
    BuildContext context,
    SupabaseAssetService assetService,
  ) async {
    final ids = _selectedIds.toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete equipment?'),
        content: Text(
          'Permanently delete ${ids.length} equipment item${ids.length == 1 ? '' : 's'}? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runBulkAction(
      () => assetService.bulkDelete(ids),
      'Deleted ${ids.length} equipment item${ids.length == 1 ? '' : 's'}',
    );
  }

  Widget _buildBulkActionBar(
    BuildContext context,
    SupabaseAssetService assetService,
  ) {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.activeWorkspaceId ??
        authProvider.appUser?.workspaceId ??
        '';
    final count = _selectedIds.length;
    final inRetiredView = _recordFilter == AssetRecordFilter.retired;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
        border: const Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Row(
        children: [
          Text(
            '$count selected',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: _exitSelectionMode,
            child: const Text('Clear'),
          ),
          const Spacer(),
          if (inRetiredView)
            ActionChip(
              avatar: const Icon(Icons.restart_alt, size: 16),
              label: const Text('Mark active'),
              visualDensity: VisualDensity.compact,
              onPressed: () => _runBulkAction(
                () => assetService.bulkUpdateStatus(
                  _selectedIds.toList(),
                  'available',
                ),
                'Marked $count equipment item${count == 1 ? '' : 's'} active',
              ),
            )
          else
            ActionChip(
              avatar: const Icon(Icons.archive_outlined, size: 16),
              label: const Text('Retire'),
              visualDensity: VisualDensity.compact,
              onPressed: () => _runBulkAction(
                () => assetService.bulkUpdateStatus(
                  _selectedIds.toList(),
                  'retired',
                ),
                'Retired $count equipment item${count == 1 ? '' : 's'}',
              ),
            ),
          const SizedBox(width: 8),
          ActionChip(
            avatar: const Icon(Icons.assignment_ind_outlined, size: 16),
            label: const Text('Assign'),
            visualDensity: VisualDensity.compact,
            onPressed: () =>
                _bulkAssignToProject(context, assetService, workspaceId),
          ),
          const SizedBox(width: 8),
          ActionChip(
            avatar: const Icon(Icons.link_off, size: 16),
            label: const Text('Unassign'),
            visualDensity: VisualDensity.compact,
            onPressed: () => _runBulkAction(
              () => assetService.bulkUnassign(_selectedIds.toList()),
              'Unassigned $count equipment item${count == 1 ? '' : 's'}',
            ),
          ),
          const SizedBox(width: 8),
          ActionChip(
            avatar: const Icon(
              Icons.delete_outline,
              size: 16,
              color: AppColors.error,
            ),
            label: const Text(
              'Delete',
              style: TextStyle(color: AppColors.error),
            ),
            visualDensity: VisualDensity.compact,
            onPressed: () => _confirmBulkDelete(context, assetService),
          ),
        ],
      ),
    );
  }

  Future<void> _retireAsset(
    BuildContext context,
    SupabaseAssetService assetService,
    Asset asset,
  ) async {
    try {
      await assetService.updateAsset(asset.copyWith(status: 'retired'));
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Equipment marked retired')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.uiMessage(error, action: 'update equipment'),
          ),
        ),
      );
    }
  }
}

class _AssetSavedView {
  final String id;
  final String name;
  final String searchQuery;
  final AssetViewType viewType;
  final String? sortColumn;
  final bool sortAscending;
  final String? filterStatus;
  final String? filterCategory;
  final List<String> filterTags;
  final AssetRecordFilter recordFilter;
  final DateTime createdAt;

  const _AssetSavedView({
    required this.id,
    required this.name,
    required this.searchQuery,
    required this.viewType,
    required this.sortColumn,
    required this.sortAscending,
    required this.filterStatus,
    required this.filterCategory,
    required this.filterTags,
    required this.recordFilter,
    required this.createdAt,
  });

  factory _AssetSavedView.fromMap(Map<String, dynamic> map) {
    final rawViewType = map['view_type'] as String?;
    final viewType = rawViewType == AssetViewType.table.name
        ? AssetViewType.table
        : AssetViewType.card;
    final rawRecord = map['record_filter'] as String?;
    final recordFilter = rawRecord == AssetRecordFilter.retired.name
        ? AssetRecordFilter.retired
        : AssetRecordFilter.active;
    return _AssetSavedView(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Saved view',
      searchQuery: map['search_query'] as String? ?? '',
      viewType: viewType,
      sortColumn: map['sort_column'] as String?,
      sortAscending: map['sort_ascending'] as bool? ?? true,
      filterStatus: map['filter_status'] as String?,
      filterCategory: map['filter_category'] as String?,
      filterTags:
          (map['filter_tags'] as List<dynamic>?)?.cast<String>() ?? const [],
      recordFilter: recordFilter,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'search_query': searchQuery,
      'view_type': viewType.name,
      'sort_column': sortColumn,
      'sort_ascending': sortAscending,
      'filter_status': filterStatus,
      'filter_category': filterCategory,
      'filter_tags': filterTags,
      'record_filter': recordFilter.name,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class _AssetFilterDialog extends StatefulWidget {
  final String? selectedStatus;
  final String? selectedCategory;
  final List<AssetCategoryConfig> availableCategories;
  final Set<String> selectedTags;
  final List<String> availableTags;
  final AssetRecordFilter recordFilter;
  final List<_AssetSavedView> savedViews;
  final String? activeSavedViewId;
  final void Function(
    String? status,
    String? category,
    Set<String> tags,
    AssetRecordFilter recordFilter,
  ) onApply;
  final ValueChanged<String> onApplySavedView;
  final VoidCallback onSaveCurrentView;
  final ValueChanged<String> onDeleteSavedView;

  const _AssetFilterDialog({
    required this.selectedStatus,
    required this.selectedCategory,
    required this.availableCategories,
    required this.selectedTags,
    required this.availableTags,
    required this.recordFilter,
    required this.savedViews,
    required this.activeSavedViewId,
    required this.onApply,
    required this.onApplySavedView,
    required this.onSaveCurrentView,
    required this.onDeleteSavedView,
  });

  @override
  State<_AssetFilterDialog> createState() => _AssetFilterDialogState();
}

class _AssetFilterDialogState extends State<_AssetFilterDialog> {
  late String? _status;
  late String? _category;
  late Set<String> _tags;
  late AssetRecordFilter _recordFilter;

  bool get _hasAnyFilter =>
      _status != null ||
      _category != null ||
      _tags.isNotEmpty ||
      _recordFilter != AssetRecordFilter.active;

  @override
  void initState() {
    super.initState();
    _status = widget.selectedStatus;
    _category = widget.selectedCategory;
    _tags = {...widget.selectedTags};
    _recordFilter = widget.recordFilter;
  }

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
                  const Text(
                    'Filters',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (_hasAnyFilter)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _status = null;
                          _category = null;
                          _tags = {};
                          _recordFilter = AssetRecordFilter.active;
                        });
                      },
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
                  _FilterSection(
                    icon: Icons.flag_outlined,
                    title: 'Status',
                    subtitle: _statusLabel(_status),
                    isActive: _status != null,
                    child: SearchableFilterChips(
                      items: _State._statusOptions
                          .map((o) => (id: o.id, label: o.label))
                          .toList(),
                      selectedId: _status,
                      allLabel: 'Any',
                      onAllSelected: () => setState(() => _status = null),
                      onItemSelected: (id) => setState(() => _status = id),
                      searchHint: 'Search statuses...',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FilterSection(
                    icon: Icons.category_outlined,
                    title: 'Category',
                    subtitle: _category ?? 'Any',
                    isActive: _category != null,
                    child: SearchableFilterChips(
                      items: widget.availableCategories.isEmpty
                          ? AssetCategory.values
                              .map((c) => (id: c.label, label: c.label))
                              .toList()
                          : widget.availableCategories
                              .map((c) => (id: c.name, label: c.name))
                              .toList(),
                      selectedId: _category,
                      allLabel: 'Any',
                      onAllSelected: () => setState(() => _category = null),
                      onItemSelected: (id) => setState(() => _category = id),
                      searchHint: 'Search categories...',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FilterSection(
                    icon: Icons.local_offer_outlined,
                    title: 'Tags',
                    subtitle: _tags.isEmpty
                        ? 'Any'
                        : '${_tags.length} selected',
                    isActive: _tags.isNotEmpty,
                    child: widget.availableTags.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                            child: Text(
                              'No tags in this workspace yet.',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          )
                        : Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              for (final tag in widget.availableTags)
                                FilterChip(
                                  label: Text(tag),
                                  selected: _tags.contains(tag),
                                  onSelected: (selected) {
                                    setState(() {
                                      if (selected) {
                                        _tags.add(tag);
                                      } else {
                                        _tags.remove(tag);
                                      }
                                    });
                                  },
                                ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 12),
                  _FilterSection(
                    icon: Icons.archive_outlined,
                    title: 'Record',
                    subtitle: _recordFilter == AssetRecordFilter.active
                        ? 'Active'
                        : 'Retired',
                    isActive: _recordFilter != AssetRecordFilter.active,
                    child: SegmentedButton<AssetRecordFilter>(
                      segments: const [
                        ButtonSegment(
                          value: AssetRecordFilter.active,
                          label: Text('Active'),
                        ),
                        ButtonSegment(
                          value: AssetRecordFilter.retired,
                          label: Text('Retired'),
                        ),
                      ],
                      selected: {_recordFilter},
                      onSelectionChanged: (selected) {
                        setState(() => _recordFilter = selected.first);
                      },
                    ),
                  ),
                  if (widget.savedViews.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    const Row(
                      children: [
                        Icon(
                          Icons.bookmark_border,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Saved Views',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...widget.savedViews.map((view) {
                      final isActive = view.id == widget.activeSavedViewId;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          isActive ? Icons.bookmark : Icons.bookmark_border,
                          size: 18,
                          color: isActive
                              ? AppColors.primary
                              : AppColors.textTertiary,
                        ),
                        title: Text(
                          view.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isActive
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: isActive ? AppColors.primary : null,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 16),
                          onPressed: () => widget.onDeleteSavedView(view.id),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          color: AppColors.textTertiary,
                        ),
                        onTap: () => widget.onApplySavedView(view.id),
                      );
                    }),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: widget.onSaveCurrentView,
                    icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                    label: const Text('Save View'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => widget.onApply(
                      _status,
                      _category,
                      _tags,
                      _recordFilter,
                    ),
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

  static String _statusLabel(String? id) {
    if (id == null) return 'Any';
    final option = _State._statusOptions
        .where((o) => o.id == id)
        .firstOrNull;
    return option?.label ?? id;
  }
}

/// Bridge to expose static fields on `_AssetListScreenState` to the dialog.
typedef _State = _AssetListScreenState;

class _FilterSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isActive;
  final Widget child;

  const _FilterSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isActive,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.primary.withValues(alpha: 0.04)
            : AppColors.surfaceAlt.withValues(alpha: 0.5),
        border: Border.all(
          color: isActive
              ? AppColors.primary.withValues(alpha: 0.3)
              : AppColors.cardBorder,
        ),
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(
            icon,
            size: 20,
            color: isActive ? AppColors.primary : AppColors.textSecondary,
          ),
          title: Text(
            title,
            style:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          initiallyExpanded: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}
