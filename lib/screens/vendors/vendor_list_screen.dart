import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../utils/user_facing_error.dart';
import '../../widgets/common/list_skeleton.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/vendor.dart';
import '../../models/customer_type_config.dart';
import '../../theme/theme.dart';
import '../../services/service_locator.dart';
import '../../providers/auth_provider.dart' as app_auth;
import '../../widgets/vendor_form_popup.dart';
import '../../widgets/common/entity_card_grid.dart';
import '../../widgets/common/module_header.dart';
import '../../widgets/common/view_icon_button.dart';
import '../../widgets/common/entity_create_card.dart';
import '../../widgets/common/entity_archive_actions.dart';
import '../../widgets/common/entity_record_empty_state.dart';
import '../../widgets/common/searchable_filter_chips.dart';
import '../../widgets/common/view_toolbar.dart';
import '../../widgets/vendors/vendor_card.dart';
import '../../widgets/table/table_layout_shell.dart';
import '../../widgets/table/table_header_row.dart';
import '../../widgets/table/table_column_schema.dart';
import '../../widgets/table/table_header_cells_builder.dart';
import '../../widgets/table/table_view_styles.dart';
import '../../widgets/table/hover_action_row.dart';

enum VendorViewType { table, card }

enum VendorRecordFilter { active, archived }

class VendorListScreen extends StatefulWidget {
  const VendorListScreen({super.key});

  @override
  State<VendorListScreen> createState() => _VendorListScreenState();
}

class _VendorListScreenState extends State<VendorListScreen>
    with SingleTickerProviderStateMixin {
  static const _savedViewsPrefKey = 'saved_vendor_views';
  final _vendorService = ServiceLocator.vendorService;
  String _searchQuery = '';
  VendorViewType _viewType = VendorViewType.card;
  VendorRecordFilter _recordFilter = VendorRecordFilter.active;
  String? _categoryFilter;
  String? _typeFilter;
  List<CustomerTypeConfig> _vendorCategories = [];
  List<CustomerTypeConfig> _vendorTypes = [];
  bool _preferredOnly = false;
  String? _sortColumn;
  bool _sortAscending = true;
  final Map<String, double> _columnWidths = {};
  Stream<List<Vendor>>? _vendorsStream;
  String? _cachedWorkspaceId;
  VendorRecordFilter? _cachedRecordFilter;

  void _maybeRebuildStream(String workspaceId) {
    if (_vendorsStream == null ||
        _cachedWorkspaceId != workspaceId ||
        _cachedRecordFilter != _recordFilter) {
      _cachedWorkspaceId = workspaceId;
      _cachedRecordFilter = _recordFilter;
      _vendorsStream = _recordFilter == VendorRecordFilter.archived
          ? _vendorService.getArchivedVendors(workspaceId)
          : _vendorService.getVendors(workspaceId);
    }
  }

  void _handleColumnResize(TableColumnResize resize) {
    setState(() {
      _columnWidths[resize.columnId] = resize.width;
    });
  }

  double _colW(String id, double defaultWidth) =>
      _columnWidths[id] ?? defaultWidth;
  List<_VendorSavedView> _savedViews = [];
  String? _activeSavedViewId;

  // Pulse animation for the empty state button
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    // Pulse animation for the + button to draw attention
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
    _loadVendorTypeConfigs();
  }

  @override
  void dispose() {
    _vendorTypeSub?.cancel();
    _vendorCatSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  dynamic _vendorTypeSub;
  dynamic _vendorCatSub;

  void _loadVendorTypeConfigs() {
    final authProvider = Provider.of<app_auth.AuthProvider>(
      context,
      listen: false,
    );
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    if (workspaceId == null) return;

    final service = ServiceLocator.vendorTypeService;
    _vendorTypeSub = service.getVendorTypes(workspaceId).listen((types) {
      if (mounted) setState(() => _vendorTypes = types);
    });
    _vendorCatSub = service.getVendorCategories(workspaceId).listen((cats) {
      if (mounted) setState(() => _vendorCategories = cats);
    });
  }

  Future<void> _loadViewPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('vendors_view_type');
    if (!mounted) return;
    setState(() {
      _viewType = saved == 'list' || saved == 'table'
          ? VendorViewType.table
          : VendorViewType.card;
    });
  }

  Future<void> _saveViewPreference(VendorViewType viewType) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vendors_view_type', viewType.name);
  }

  Future<void> _loadSavedViews() async {
    final raw = await ServiceLocator.userPreferencesService.getSavedViews(
      _savedViewsPrefKey,
    );
    if (!mounted) return;
    setState(() {
      _savedViews = raw.map(_VendorSavedView.fromMap).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<app_auth.AuthProvider>(context);
    final workspaceId = authProvider.appUser?.currentWorkspaceId ?? '';

    if (workspaceId.isEmpty) {
      return const Center(child: Text('No workspace selected'));
    }

    _maybeRebuildStream(workspaceId);

    return Scaffold(
      backgroundColor: AppColors.surfaceAlt,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: StreamBuilder<List<Vendor>>(
              stream: _vendorsStream,
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

                final vendors = snapshot.data ?? [];
                final filteredVendors = _filterVendors(vendors);

                if (filteredVendors.isEmpty) {
                  return _buildEmptyState();
                }

                return _viewType == VendorViewType.table
                    ? _buildTableView(filteredVendors)
                    : EntityCardGrid(
                        itemCount: filteredVendors.length,
                        padding: EdgeInsets.fromLTRB(
                          16,
                          16,
                          16,
                          MediaQuery.paddingOf(context).bottom + 90,
                        ),
                        itemBuilder: (context, index, cardWidth) {
                          final vendor = filteredVendors[index];
                          return VendorCard(
                            vendor: vendor,
                            margin: EdgeInsets.zero,
                            minHeight: _getGridCardMinHeight(cardWidth),
                            onTap: () => context.go('/vendors/${vendor.id}'),
                            onViewDetails: () =>
                                context.go('/vendors/${vendor.id}'),
                            onEdit: () => showVendorFormPopup(
                              context,
                              vendorId: vendor.id,
                            ),
                            onToggleArchive: () => _toggleVendorArchive(vendor),
                          );
                        },
                        trailingBuilder:
                            _recordFilter == VendorRecordFilter.archived
                            ? null
                            : (context, cardWidth) => EntityCreateCard(
                                title: 'Create New Vendor',
                                subtitle: kIsWeb ? 'Click to add a new vendor' : 'Tap to add a new vendor',
                                size: EntityCreateCardSize.regular,
                                minHeight: _getGridCardMinHeight(cardWidth),
                                onTap: () => showVendorFormPopup(context),
                              ),
                      );
              },
            ),
          ),
        ],
      ),
    );
  }

  int get _activeFilterCount =>
      (_categoryFilter != null ? 1 : 0) +
      (_typeFilter != null ? 1 : 0) +
      (_preferredOnly ? 1 : 0);

  Widget _buildHeader() {
    return Container(
      color: ChromeColors.of(context).background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ModuleHeader(
            icon: Icons.store_outlined,
            title: 'Vendors',
            description: 'Manage suppliers, subcontractors and service providers.',
          ),
          ViewToolbar(
            searchHint: 'Search vendors...',
            searchQuery: _searchQuery,
            onSearch: (query) => setState(() {
              _searchQuery = query;
              _activeSavedViewId = null;
            }),
            centerSlot: _buildViewIcons(),
            quickToggles: [_buildRecordToggle(), _buildTypesButton()],
            filterCount: _activeFilterCount,
            onFilterTap: _showVendorFilterDialog,
          ),
        ],
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
          isSelected: _viewType == VendorViewType.card,
          onTap: () {
            setState(() {
              _viewType = VendorViewType.card;
              _activeSavedViewId = null;
            });
            _saveViewPreference(VendorViewType.card);
          },
        ),
        ViewIconButton(
          icon: Icons.view_list,
          tooltip: 'Table',
          isSelected: _viewType == VendorViewType.table,
          onTap: () {
            setState(() {
              _viewType = VendorViewType.table;
              _activeSavedViewId = null;
            });
            _saveViewPreference(VendorViewType.table);
          },
        ),
      ],
    );
  }

  Widget _buildRecordToggle() {
    final isArchived = _recordFilter == VendorRecordFilter.archived;
    return _ToggleIconButton(
      icon: Icons.inventory_2_outlined,
      tooltip: isArchived ? 'Showing Archived' : 'Show Archived',
      isActive: isArchived,
      onTap: () {
        setState(() {
          _recordFilter = isArchived
              ? VendorRecordFilter.active
              : VendorRecordFilter.archived;
          _activeSavedViewId = null;
        });
      },
    );
  }

  Widget _buildTypesButton() {
    return _ToggleIconButton(
      icon: Icons.settings_outlined,
      tooltip: 'Vendor Types & Categories',
      isActive: false,
      onTap: () => context.go('/settings/vendor-types'),
    );
  }

  void _showVendorFilterDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return _VendorFilterDialog(
          selectedCategory: _categoryFilter,
          selectedType: _typeFilter,
          preferredOnly: _preferredOnly,
          recordFilter: _recordFilter,
          vendorCategories: _vendorCategories,
          vendorTypes: _vendorTypes,
          savedViews: _savedViews,
          activeSavedViewId: _activeSavedViewId,
          onApply: (category, type, preferred, recordFilter) {
            setState(() {
              _categoryFilter = category;
              _typeFilter = type;
              _preferredOnly = preferred;
              _recordFilter = recordFilter;
              _activeSavedViewId = null;
            });
            Navigator.of(ctx).pop();
          },
          onApplySavedView: (viewId) {
            Navigator.of(ctx).pop();
            _applySavedViewById(viewId);
          },
          onSaveView: (category, type, preferred, recordFilter) {
            Navigator.of(ctx).pop();
            _showSaveViewDialog(
              category: category,
              type: type,
              preferredOnly: preferred,
              recordFilter: recordFilter,
            );
          },
          onDeleteSavedView: (viewId) {
            _deleteSavedViewById(viewId);
          },
        );
      },
    );
  }

  void _applySavedViewById(String viewId) {
    _VendorSavedView? view;
    for (final candidate in _savedViews) {
      if (candidate.id == viewId) {
        view = candidate;
        break;
      }
    }
    if (view == null) return;
    final selectedView = view;
    setState(() {
      _searchQuery = selectedView.searchQuery;
      _viewType = selectedView.viewType;
      _recordFilter = selectedView.recordFilter;
      _categoryFilter = selectedView.category;
      _typeFilter = selectedView.type;
      _preferredOnly = selectedView.preferredOnly;
      _sortColumn = selectedView.sortColumn;
      _sortAscending = selectedView.sortAscending;
      _activeSavedViewId = selectedView.id;
    });
    _saveViewPreference(selectedView.viewType);
  }

  Future<void> _showSaveViewDialog({
    required String? category,
    required String? type,
    required bool preferredOnly,
    required VendorRecordFilter recordFilter,
  }) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save current view'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. Preferred archived vendors',
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
      ),
    );
    if (name == null || name.isEmpty) return;

    final view = _VendorSavedView(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      searchQuery: _searchQuery,
      viewType: _viewType,
      recordFilter: recordFilter,
      category: category,
      type: type,
      preferredOnly: preferredOnly,
      sortColumn: _sortColumn,
      sortAscending: _sortAscending,
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

  List<Vendor> _filterVendors(List<Vendor> vendors) {
    var filtered = vendors;

    if (_categoryFilter != null) {
      filtered = filtered
          .where((vendor) => vendor.category == _categoryFilter)
          .toList();
    }

    if (_typeFilter != null) {
      filtered = filtered
          .where((vendor) => vendor.vendorType == _typeFilter)
          .toList();
    }

    if (_preferredOnly) {
      filtered = filtered.where((vendor) => vendor.isPreferred).toList();
    }

    if (_searchQuery.isEmpty) {
      return filtered;
    }

    final lowerQuery = _searchQuery.toLowerCase();

    return filtered.where((vendor) {
      final companyName = vendor.companyName.toLowerCase();
      final dba = vendor.dba?.toLowerCase() ?? '';
      final primaryContact = vendor.getPrimaryContact();
      final contactName = primaryContact?.name.toLowerCase() ?? '';

      return companyName.contains(lowerQuery) ||
          dba.contains(lowerQuery) ||
          contactName.contains(lowerQuery);
    }).toList();
  }

  Widget _buildEmptyState() {
    final bool hasFilters =
        _searchQuery.isNotEmpty ||
        _categoryFilter != null ||
        _typeFilter != null ||
        _preferredOnly ||
        _recordFilter == VendorRecordFilter.archived;

    return EntityRecordEmptyState(
      hasFilters: hasFilters,
      isArchivedView: _recordFilter == VendorRecordFilter.archived,
      animation: _pulseAnimation,
      defaultIcon: Icons.store_mall_directory,
      entityPluralLabel: 'vendors',
      entitySingularLabel: 'vendor',
      onClearFilters: () {
        setState(() {
          _searchQuery = '';
          _categoryFilter = null;
          _typeFilter = null;
          _preferredOnly = false;
          _recordFilter = VendorRecordFilter.active;
          _sortColumn = null;
          _sortAscending = true;
          _activeSavedViewId = null;
        });
      },
      onCreate: () => showVendorFormPopup(context),
      onShowActive: () {
        setState(() {
          _recordFilter = VendorRecordFilter.active;
        });
      },
    );
  }

  static const double _colCompany = 200;
  static const double _colCategory = 150;
  static const double _colType = 130;
  static const double _colContact = 170;
  static const double _colPhone = 140;
  static const double _colPreferred = 90;
  static const double _colUpdated = 120;
  static const double _colGap = 12;

  static const _tableColumns = [
    TableColumnSchema(
      id: 'company',
      label: 'Company',
      defaultWidth: _colCompany,
      minWidth: 100,
      maxWidth: 400,
    ),
    TableColumnSchema(
      id: 'category',
      label: 'Category',
      defaultWidth: _colCategory,
      minWidth: 80,
      maxWidth: 300,
    ),
    TableColumnSchema(
      id: 'type',
      label: 'Type',
      defaultWidth: _colType,
      minWidth: 80,
      maxWidth: 250,
    ),
    TableColumnSchema(
      id: 'phone',
      label: 'Phone',
      defaultWidth: _colContact,
      minWidth: 100,
      maxWidth: 300,
    ),
    TableColumnSchema(
      id: 'email',
      label: 'Email',
      defaultWidth: _colPhone,
      minWidth: 100,
      maxWidth: 300,
    ),
    TableColumnSchema(
      id: 'preferred',
      label: 'Preferred',
      defaultWidth: _colPreferred,
      minWidth: 60,
      maxWidth: 150,
    ),
    TableColumnSchema(
      id: 'updated',
      label: 'Updated',
      defaultWidth: _colUpdated,
      minWidth: 80,
      maxWidth: 200,
    ),
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

  List<Vendor> _applySorting(List<Vendor> vendors) {
    if (_sortColumn == null) return vendors;
    final sorted = List<Vendor>.from(vendors);
    final ascending = _sortAscending;
    sorted.sort((a, b) {
      int result;
      switch (_sortColumn) {
        case 'company':
          result = a.companyName.toLowerCase().compareTo(
            b.companyName.toLowerCase(),
          );
        case 'category':
          result = a.category.compareTo(b.category);
        case 'type':
          result = a.vendorType.compareTo(b.vendorType);
        case 'phone':
          final aP = a.businessPhone ?? '';
          final bP = b.businessPhone ?? '';
          result = aP.compareTo(bP);
        case 'email':
          final aE = a.businessEmail ?? '';
          final bE = b.businessEmail ?? '';
          result = aE.toLowerCase().compareTo(bE.toLowerCase());
        case 'preferred':
          result = (a.isPreferred ? 1 : 0).compareTo(b.isPreferred ? 1 : 0);
        case 'updated':
          result = a.updatedAt.compareTo(b.updatedAt);
        default:
          result = 0;
      }
      return ascending ? result : -result;
    });
    return sorted;
  }

  Widget _buildTableView(List<Vendor> vendors) {
    final sorted = _applySorting(vendors);
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
      sortedColumnId: _sortColumn,
      sortAscending: _sortAscending,
    );

    final headerChildren = <Widget>[];
    for (int i = 0; i < headerCells.length; i++) {
      if (i > 0) headerChildren.add(const SizedBox(width: _colGap));
      headerChildren.add(headerCells[i]);
    }

    return TableLayoutShell(
      minTableWidth: 1100,
      header: TableHeaderRow(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
        children: headerChildren,
      ),
      body: ListView.builder(
        itemCount: sorted.length,
        itemBuilder: (context, index) {
          final vendor = sorted[index];
          return _buildVendorRow(context, vendor);
        },
      ),
    );
  }

  Widget _buildVendorRow(BuildContext context, Vendor vendor) {
    return HoverActionRow(
      actionWidth: 40,
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 20),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'details', child: Text('View details')),
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(
              value: 'archive',
              child: Text(vendor.isActive ? 'Archive' : 'Restore'),
            ),
          ],
          onSelected: (value) {
            switch (value) {
              case 'details':
                context.go('/vendors/${vendor.id}');
              case 'edit':
                showVendorFormPopup(context, vendorId: vendor.id);
              case 'archive':
                _toggleVendorArchive(vendor);
            }
          },
        ),
      ],
      builder: (isHovered) => InkWell(
        onTap: () => context.go('/vendors/${vendor.id}'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          decoration: BoxDecoration(
            color: isHovered
                ? Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                : Colors.transparent,
            border: Border(bottom: TableViewStyles.rowDivider(context)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: _colW('company', _colCompany),
                  child: Text(
                    vendor.companyName,
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
                  width: _colW('category', _colCategory),
                  child: Text(
                    vendor.category,
                    style: const TextStyle(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: _colGap),
                SizedBox(
                  width: _colW('type', _colType),
                  child: Text(
                    vendor.vendorType,
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
                  width: _colW('phone', _colContact),
                  child: Text(
                    vendor.businessPhone ?? '\u2014',
                    style: const TextStyle(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: _colGap),
                SizedBox(
                  width: _colW('email', _colPhone),
                  child: Text(
                    vendor.businessEmail ?? '\u2014',
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
                  width: _colW('preferred', _colPreferred),
                  child: vendor.isPreferred
                      ? Icon(Icons.star, size: 16, color: Colors.amber.shade700)
                      : const Text(
                          '\u2014',
                          style: TextStyle(color: AppColors.textTertiary),
                        ),
                ),
                const SizedBox(width: _colGap),
                SizedBox(
                  width: _colW('updated', _colUpdated),
                  child: Text(
                    _formatDate(vendor.updatedAt),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
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

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Future<void> _toggleVendorArchive(Vendor vendor) async {
    return EntityArchiveActions.toggle(
      context: context,
      entityLabel: 'vendor',
      isActive: vendor.isActive,
      archive: () => _vendorService.archiveVendor(vendor.id),
      restore: () => _vendorService.restoreVendor(vendor.id),
    );
  }

  double _getGridCardMinHeight(double cardWidth) {
    if (cardWidth < 260) return 292;
    if (cardWidth < 340) return 276;
    return 260;
  }
}

class _VendorSavedView {
  final String id;
  final String name;
  final String searchQuery;
  final VendorViewType viewType;
  final VendorRecordFilter recordFilter;
  final String? category;
  final String? type;
  final bool preferredOnly;
  final String? sortColumn;
  final bool sortAscending;
  final DateTime createdAt;

  const _VendorSavedView({
    required this.id,
    required this.name,
    required this.searchQuery,
    required this.viewType,
    required this.recordFilter,
    required this.category,
    required this.type,
    required this.preferredOnly,
    required this.sortColumn,
    required this.sortAscending,
    required this.createdAt,
  });

  factory _VendorSavedView.fromMap(Map<String, dynamic> map) {
    final rawViewType = map['view_type'] as String?;
    final viewType = rawViewType == VendorViewType.table.name
        ? VendorViewType.table
        : VendorViewType.card;

    final rawRecordFilter = map['record_filter'] as String?;
    final recordFilter = rawRecordFilter == VendorRecordFilter.archived.name
        ? VendorRecordFilter.archived
        : VendorRecordFilter.active;

    return _VendorSavedView(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Saved view',
      searchQuery: map['search_query'] as String? ?? '',
      viewType: viewType,
      recordFilter: recordFilter,
      category: map['category'] as String?,
      type: map['type'] as String?,
      preferredOnly: map['preferred_only'] as bool? ?? false,
      sortColumn: map['sort_column'] as String?,
      sortAscending: map['sort_ascending'] as bool? ?? true,
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
      'record_filter': recordFilter.name,
      'category': category,
      'type': type,
      'preferred_only': preferredOnly,
      'sort_column': sortColumn,
      'sort_ascending': sortAscending,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// Circular toggle icon button for quick toggles.
class _ToggleIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback onTap;

  const _ToggleIconButton({
    required this.icon,
    required this.tooltip,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeColors.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.transparent,
            border: Border.all(
              color: isActive ? AppColors.secondary : chrome.divider,
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: isActive ? AppColors.secondary : chrome.text,
          ),
        ),
      ),
    );
  }
}

/// Centered filter dialog for vendors.
class _VendorFilterDialog extends StatefulWidget {
  final String? selectedCategory;
  final String? selectedType;
  final bool preferredOnly;
  final VendorRecordFilter recordFilter;
  final List<CustomerTypeConfig> vendorCategories;
  final List<CustomerTypeConfig> vendorTypes;
  final List<_VendorSavedView> savedViews;
  final String? activeSavedViewId;
  final void Function(
    String? category,
    String? type,
    bool preferredOnly,
    VendorRecordFilter recordFilter,
  )
  onApply;
  final void Function(
    String? category,
    String? type,
    bool preferredOnly,
    VendorRecordFilter recordFilter,
  )
  onSaveView;
  final ValueChanged<String> onApplySavedView;
  final ValueChanged<String> onDeleteSavedView;

  const _VendorFilterDialog({
    required this.selectedCategory,
    required this.selectedType,
    required this.preferredOnly,
    required this.recordFilter,
    required this.vendorCategories,
    required this.vendorTypes,
    required this.savedViews,
    required this.activeSavedViewId,
    required this.onApply,
    required this.onSaveView,
    required this.onApplySavedView,
    required this.onDeleteSavedView,
  });

  @override
  State<_VendorFilterDialog> createState() => _VendorFilterDialogState();
}

class _VendorFilterDialogState extends State<_VendorFilterDialog> {
  late String? _category;
  late String? _type;
  late bool _preferred;
  late VendorRecordFilter _recordFilter;

  bool get _hasAnyFilter => _category != null || _type != null || _preferred;

  @override
  void initState() {
    super.initState();
    _category = widget.selectedCategory;
    _type = widget.selectedType;
    _preferred = widget.preferredOnly;
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
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  const Text(
                    'Filters',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (_hasAnyFilter)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _category = null;
                          _type = null;
                          _preferred = false;
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

            // ── Content ──
            Flexible(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.base),
                shrinkWrap: true,
                children: [
                  // ── Category ──
                  _buildSection(
                    icon: Icons.category_outlined,
                    title: 'Category',
                    subtitle: _category ?? 'Any',
                    isActive: _category != null,
                    child: SearchableFilterChips(
                      items: widget.vendorCategories
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

                  // ── Type ──
                  _buildSection(
                    icon: Icons.type_specimen_outlined,
                    title: 'Vendor Type',
                    subtitle: _type ?? 'Any',
                    isActive: _type != null,
                    child: SearchableFilterChips(
                      items: widget.vendorTypes
                          .map((t) => (id: t.name, label: t.name))
                          .toList(),
                      selectedId: _type,
                      allLabel: 'Any',
                      onAllSelected: () => setState(() => _type = null),
                      onItemSelected: (id) => setState(() => _type = id),
                      searchHint: 'Search vendor types...',
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Preferred ──
                  _buildSection(
                    icon: Icons.star_outline,
                    title: 'Preferred',
                    subtitle: _preferred ? 'Preferred only' : 'All vendors',
                    isActive: _preferred,
                    child: SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Preferred vendors only',
                        style: TextStyle(fontSize: 14),
                      ),
                      value: _preferred,
                      onChanged: (v) => setState(() => _preferred = v),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Record type ──
                  _buildSection(
                    icon: Icons.inventory_outlined,
                    title: 'Record Type',
                    subtitle: _recordFilter == VendorRecordFilter.active
                        ? 'Active'
                        : 'Archived',
                    isActive: _recordFilter == VendorRecordFilter.archived,
                    child: SegmentedButton<VendorRecordFilter>(
                      segments: const [
                        ButtonSegment(
                          value: VendorRecordFilter.active,
                          label: Text('Active'),
                        ),
                        ButtonSegment(
                          value: VendorRecordFilter.archived,
                          label: Text('Archived'),
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
                    Row(
                      children: [
                        const Icon(
                          Icons.bookmark_border,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        const Text(
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

            // ── Footer ──
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => widget.onSaveView(
                      _category,
                      _type,
                      _preferred,
                      _recordFilter,
                    ),
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
                      _category,
                      _type,
                      _preferred,
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

  Widget _buildSection({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isActive,
    required Widget child,
  }) {
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
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
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
