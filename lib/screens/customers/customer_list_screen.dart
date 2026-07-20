import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../widgets/common/list_skeleton.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/theme.dart';
import '../../models/customer.dart';
import '../../models/customer_status.dart';
import '../../models/customer_source.dart';
import '../../models/user.dart';
import '../../services/service_locator.dart';
import '../../services/supabase/customer_service.dart' show CustomerStats;
import '../../utils/currency_utils.dart';
import '../../providers/workspace_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/customers/customer_card.dart';
import '../../widgets/customers/customer_type_badge.dart';
import '../../widgets/customer_form_popup.dart';
import '../../widgets/common/entity_card_grid.dart';
import '../../widgets/common/module_header.dart';
import '../../widgets/common/view_icon_button.dart';
import '../../widgets/common/entity_create_card.dart';
import '../../widgets/common/entity_archive_actions.dart';
import '../../widgets/common/entity_record_empty_state.dart';
import '../../widgets/common/searchable_filter_chips.dart';
import '../../widgets/common/view_toolbar.dart';
import '../../utils/app_logger.dart';
import '../../utils/user_facing_error.dart';
import '../../widgets/table/table_layout_shell.dart';
import '../../widgets/table/table_header_row.dart';
import '../../widgets/table/table_column_schema.dart';
import '../../widgets/table/table_header_cells_builder.dart';
import '../../widgets/table/table_view_styles.dart';
import '../../widgets/table/hover_action_row.dart';

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

enum CustomerViewType { table, card }

enum CustomerRecordFilter { active, archived }

class _CustomerListScreenState extends State<CustomerListScreen>
    with SingleTickerProviderStateMixin {
  static const _savedViewsPrefKey = 'saved_customer_views';
  dynamic get _customerService => ServiceLocator.customerService;
  String _searchQuery = '';
  CustomerViewType _viewType = CustomerViewType.card;
  CustomerRecordFilter _recordFilter = CustomerRecordFilter.active;

  // Phase 1 filters
  CustomerStatus? _statusFilter;
  CustomerSource? _sourceFilter;
  String? _ownerFilter;
  String? _sortColumn;
  bool _sortAscending = true;
  final Map<String, double> _columnWidths = {};
  Stream<List<Customer>>? _customersStream;
  String? _cachedWorkspaceId;
  CustomerRecordFilter? _cachedRecordFilter;

  void _maybeRebuildStream(String workspaceId) {
    if (_customersStream == null ||
        _cachedWorkspaceId != workspaceId ||
        _cachedRecordFilter != _recordFilter) {
      _cachedWorkspaceId = workspaceId;
      _cachedRecordFilter = _recordFilter;
      _customersStream = _recordFilter == CustomerRecordFilter.archived
          ? _customerService.getArchivedCustomers(workspaceId)
          : _customerService.getCustomers(workspaceId);
    }
  }

  void _handleColumnResize(TableColumnResize resize) {
    setState(() {
      _columnWidths[resize.columnId] = resize.width;
    });
  }

  double _colW(String id, double defaultWidth) =>
      _columnWidths[id] ?? defaultWidth;
  List<_CustomerSavedView> _savedViews = [];
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
    _loadCustomerTypeColors();
  }

  dynamic _typeColorSub;

  void _loadCustomerTypeColors() {
    final workspaceId = Provider.of<AuthProvider>(
      context,
      listen: false,
    ).appUser?.currentWorkspaceId;
    if (workspaceId == null) return;
    _typeColorSub = ServiceLocator.customerTypeService
        .getCustomerTypes(workspaceId)
        .listen((types) => CustomerTypeBadge.updateColorCache(types));
  }

  @override
  void dispose() {
    _typeColorSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadViewPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('customers_view_type');
    if (!mounted) return;
    setState(() {
      _viewType = saved == 'list' || saved == 'table'
          ? CustomerViewType.table
          : CustomerViewType.card;
    });
  }

  Future<void> _saveViewPreference(CustomerViewType viewType) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('customers_view_type', viewType.name);
  }

  Future<void> _loadSavedViews() async {
    final raw = await ServiceLocator.userPreferencesService.getSavedViews(
      _savedViewsPrefKey,
    );
    if (!mounted) return;
    setState(() {
      _savedViews = raw.map(_CustomerSavedView.fromMap).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final AppUser? currentUser = authProvider.appUser;

    if (currentUser == null) {
      return const ListSkeleton();
    }

    _maybeRebuildStream(currentUser.currentWorkspaceId);

    return Scaffold(
      backgroundColor: AppColors.surfaceAlt,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: StreamBuilder<List<Customer>>(
              stream: _customersStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const ListSkeleton();
                }

                if (snapshot.hasError) {
                  AppLogger.error(
                    'Customer list error',
                    error: snapshot.error,
                    stackTrace: snapshot.stackTrace,
                    metadata: {
                      'workspaceId': authProvider.appUser?.currentWorkspaceId,
                    },
                  );
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 48,
                          color: AppColors.error,
                        ),
                        const SizedBox(height: 16),
                        const Text('Error loading customers'),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.base),
                          child: Text(
                            UserFacingError.uiMessage(
                              snapshot.error,
                              action: 'load customers',
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              // Force rebuild to retry
                            });
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                final allCustomers = snapshot.data ?? [];

                return FutureBuilder<List<Customer>>(
                  future: _filterCustomers(allCustomers),
                  builder: (context, filterSnapshot) {
                    if (filterSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const ListSkeleton();
                    }

                    final customers = filterSnapshot.data ?? [];

                    if (customers.isEmpty) {
                      final bool hasFilters =
                          _searchQuery.isNotEmpty ||
                          _statusFilter != null ||
                          _sourceFilter != null ||
                          _ownerFilter != null ||
                          _recordFilter == CustomerRecordFilter.archived;
                      return EntityRecordEmptyState(
                        hasFilters: hasFilters,
                        isArchivedView:
                            _recordFilter == CustomerRecordFilter.archived,
                        animation: _pulseAnimation,
                        defaultIcon: Icons.people_outline,
                        entityPluralLabel: 'customers',
                        entitySingularLabel: 'customer',
                        onClearFilters: () {
                          setState(() {
                            _searchQuery = '';
                            _statusFilter = null;
                            _sourceFilter = null;
                            _ownerFilter = null;
                            _recordFilter = CustomerRecordFilter.active;
                            _sortColumn = null;
                            _sortAscending = true;
                            _activeSavedViewId = null;
                          });
                        },
                        onCreate: () => showCustomerFormPopup(context),
                        onShowActive: () {
                          setState(() {
                            _recordFilter = CustomerRecordFilter.active;
                          });
                        },
                      );
                    }

                    if (_viewType == CustomerViewType.table) {
                      return _buildTableView(customers);
                    }

                    return EntityCardGrid(
                      itemCount: customers.length,
                      padding: EdgeInsets.fromLTRB(
                        16,
                        16,
                        16,
                        MediaQuery.paddingOf(context).bottom + 90,
                      ),
                      itemBuilder: (context, index, cardWidth) {
                        final customer = customers[index];
                        return FutureBuilder<CustomerStats>(
                          future: _getCustomerStats(customer.id),
                          builder: (context, statsSnapshot) {
                            final stats = statsSnapshot.data ??
                                const CustomerStats.empty();

                            return CustomerCard(
                              customer: customer,
                              margin: EdgeInsets.zero,
                              minHeight: _getCreateCardHeight(cardWidth),
                              projectCount: stats.totalProjects,
                              openJobs: stats.openJobs,
                              closedJobs: stats.closedJobs,
                              collectedRevenue: stats.collectedRevenue,
                              lastActivityDate: stats.lastActivity,
                              onEdit: () => showCustomerFormPopup(
                                context,
                                customerId: customer.id,
                              ),
                              onViewDetails: () =>
                                  context.push('/customers/${customer.id}'),
                              onToggleArchive: () =>
                                  _toggleCustomerArchive(customer),
                              onTap: () {
                                context.push('/customers/${customer.id}');
                              },
                            );
                          },
                        );
                      },
                      trailingBuilder:
                          _recordFilter == CustomerRecordFilter.archived
                          ? null
                          : (context, cardWidth) => EntityCreateCard(
                              title: 'Create New Customer',
                              subtitle: kIsWeb ? 'Click to add a new customer' : 'Tap to add a new customer',
                              size: EntityCreateCardSize.compact,
                              minHeight: _getCreateCardHeight(cardWidth),
                              onTap: () => showCustomerFormPopup(context),
                            ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  int get _activeFilterCount =>
      (_statusFilter != null ? 1 : 0) +
      (_sourceFilter != null ? 1 : 0) +
      (_ownerFilter != null ? 1 : 0);

  Widget _buildHeader() {
    return Container(
      color: ChromeColors.of(context).background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ModuleHeader(
            icon: Icons.people_outline,
            title: 'Customers',
            description: 'Manage clients, contacts and customer relationships.',
          ),
          ViewToolbar(
            searchHint: 'Search customers...',
            searchQuery: _searchQuery,
            onSearch: (query) => setState(() {
              _searchQuery = query;
              _activeSavedViewId = null;
            }),
            centerSlot: _buildViewIcons(),
            quickToggles: [
              _buildPipelineButton(),
              _buildRecordToggle(),
              _buildTypesButton(),
            ],
            filterCount: _activeFilterCount,
            onFilterTap: _showCustomerFilterDialog,
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
          isSelected: _viewType == CustomerViewType.card,
          onTap: () {
            setState(() {
              _viewType = CustomerViewType.card;
              _activeSavedViewId = null;
            });
            _saveViewPreference(CustomerViewType.card);
          },
        ),
        ViewIconButton(
          icon: Icons.view_list,
          tooltip: 'Table',
          isSelected: _viewType == CustomerViewType.table,
          onTap: () {
            setState(() {
              _viewType = CustomerViewType.table;
              _activeSavedViewId = null;
            });
            _saveViewPreference(CustomerViewType.table);
          },
        ),
      ],
    );
  }

  Widget _buildRecordToggle() {
    final isArchived = _recordFilter == CustomerRecordFilter.archived;
    return _ToggleIconButton(
      icon: Icons.inventory_2_outlined,
      tooltip: isArchived ? 'Showing Archived' : 'Show Archived',
      isActive: isArchived,
      onTap: () {
        setState(() {
          _recordFilter = isArchived
              ? CustomerRecordFilter.active
              : CustomerRecordFilter.archived;
          _activeSavedViewId = null;
        });
      },
    );
  }

  Widget _buildTypesButton() {
    return _ToggleIconButton(
      icon: Icons.settings_outlined,
      tooltip: 'Customer Types',
      isActive: false,
      onTap: () => context.go('/settings/customer-types'),
    );
  }

  Widget _buildPipelineButton() {
    return _ToggleIconButton(
      icon: Icons.trending_up,
      tooltip: 'Opportunity Pipeline',
      isActive: false,
      onTap: () => context.go('/opportunities'),
    );
  }

  void _showCustomerFilterDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return _CustomerFilterDialog(
          selectedStatus: _statusFilter,
          selectedSource: _sourceFilter,
          recordFilter: _recordFilter,
          savedViews: _savedViews,
          activeSavedViewId: _activeSavedViewId,
          onApply: (status, source, recordFilter) {
            setState(() {
              _statusFilter = status;
              _sourceFilter = source;
              _recordFilter = recordFilter;
              _activeSavedViewId = null;
            });
            Navigator.of(ctx).pop();
          },
          onApplySavedView: (viewId) {
            Navigator.of(ctx).pop();
            _applySavedViewById(viewId);
          },
          onSaveView: (status, source, recordFilter) {
            Navigator.of(ctx).pop();
            _showSaveViewDialog(
              status: status,
              source: source,
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
    _CustomerSavedView? view;
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
      _statusFilter = selectedView.status;
      _sourceFilter = selectedView.source;
      _sortColumn = selectedView.sortColumn;
      _sortAscending = selectedView.sortAscending;
      _activeSavedViewId = selectedView.id;
    });
    _saveViewPreference(selectedView.viewType);
  }

  Future<void> _showSaveViewDialog({
    required CustomerStatus? status,
    required CustomerSource? source,
    required CustomerRecordFilter recordFilter,
  }) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save current view'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Archived leads'),
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

    final view = _CustomerSavedView(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      searchQuery: _searchQuery,
      viewType: _viewType,
      recordFilter: recordFilter,
      status: status,
      source: source,
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

  Future<List<Customer>> _filterCustomers(List<Customer> customers) async {
    var filtered = customers;

    if (_searchQuery.isNotEmpty) {
      final lowerQuery = _searchQuery.toLowerCase();
      filtered = filtered.where((customer) {
        return customer.name.toLowerCase().contains(lowerQuery) ||
            (customer.companyName?.toLowerCase().contains(lowerQuery) ??
                false) ||
            (customer.email?.toLowerCase().contains(lowerQuery) ?? false) ||
            (customer.phone?.toLowerCase().contains(lowerQuery) ?? false);
      }).toList();
    }

    // Apply Phase 1 filters
    if (_statusFilter != null) {
      filtered = filtered.where((c) => c.status == _statusFilter).toList();
    }

    if (_sourceFilter != null) {
      filtered = filtered.where((c) => c.source == _sourceFilter).toList();
    }

    if (_ownerFilter != null) {
      filtered = filtered
          .where((c) => c.accountOwnerId == _ownerFilter)
          .toList();
    }

    return filtered;
  }

  Future<CustomerStats> _getCustomerStats(String customerId) async {
    return await _customerService.getCustomerStats(customerId) as CustomerStats;
  }

  Future<void> _toggleCustomerArchive(Customer customer) async {
    return EntityArchiveActions.toggle(
      context: context,
      entityLabel: 'customer',
      isActive: customer.isActive,
      archive: () => _customerService.archiveCustomer(customer.id),
      restore: () => _customerService.restoreCustomer(customer.id),
    );
  }

  static const double _colName = 200;
  static const double _colContact = 180;
  static const double _colPhone = 140;
  static const double _colStatus = 120;
  static const double _colSource = 130;
  static const double _colCity = 140;
  static const double _colUpdated = 120;
  static const double _colJobsCount = 90;
  static const double _colCollected = 130;
  static const double _colGap = 12;

  static const _tableColumns = [
    TableColumnSchema(
      id: 'name',
      label: 'Name',
      defaultWidth: _colName,
      minWidth: 100,
      maxWidth: 400,
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
      id: 'status',
      label: 'Status',
      defaultWidth: _colStatus,
      minWidth: 80,
      maxWidth: 200,
    ),
    TableColumnSchema(
      id: 'source',
      label: 'Source',
      defaultWidth: _colSource,
      minWidth: 80,
      maxWidth: 200,
    ),
    TableColumnSchema(
      id: 'city',
      label: 'City',
      defaultWidth: _colCity,
      minWidth: 80,
      maxWidth: 250,
    ),
    TableColumnSchema(
      id: 'openJobs',
      label: 'Open Jobs',
      defaultWidth: _colJobsCount,
      minWidth: 60,
      maxWidth: 140,
    ),
    TableColumnSchema(
      id: 'closedJobs',
      label: 'Closed Jobs',
      defaultWidth: _colJobsCount,
      minWidth: 60,
      maxWidth: 140,
    ),
    TableColumnSchema(
      id: 'collected',
      label: 'Collected Invoices',
      defaultWidth: _colCollected,
      minWidth: 100,
      maxWidth: 220,
    ),
    TableColumnSchema(
      id: 'updated',
      label: 'Updated',
      defaultWidth: _colUpdated,
      minWidth: 80,
      maxWidth: 200,
    ),
  ];

  static const _unsortableColumns = {'openJobs', 'closedJobs', 'collected'};

  void _onColumnSortTap(String columnId) {
    if (_unsortableColumns.contains(columnId)) return;
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

  List<Customer> _applySorting(List<Customer> customers) {
    if (_sortColumn == null) return customers;
    final sorted = List<Customer>.from(customers);
    final ascending = _sortAscending;
    sorted.sort((a, b) {
      int result;
      switch (_sortColumn) {
        case 'name':
          result = (a.companyName ?? a.name).toLowerCase().compareTo(
            (b.companyName ?? b.name).toLowerCase(),
          );
        case 'phone':
          final aPhone = a.businessPhone ?? '';
          final bPhone = b.businessPhone ?? '';
          result = aPhone.compareTo(bPhone);
        case 'email':
          final aEmail = a.businessEmail ?? '';
          final bEmail = b.businessEmail ?? '';
          result = aEmail.toLowerCase().compareTo(bEmail.toLowerCase());
        case 'status':
          result = a.status.displayName.compareTo(b.status.displayName);
        case 'source':
          final aSource = a.source?.displayName ?? '';
          final bSource = b.source?.displayName ?? '';
          result = aSource.compareTo(bSource);
        case 'city':
          result = (a.city ?? '').toLowerCase().compareTo(
            (b.city ?? '').toLowerCase(),
          );
        case 'updated':
          result = a.updatedAt.compareTo(b.updatedAt);
        default:
          result = 0;
      }
      return ascending ? result : -result;
    });
    return sorted;
  }

  Widget _buildTableView(List<Customer> customers) {
    final sorted = _applySorting(customers);
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
      minTableWidth: 1410,
      header: TableHeaderRow(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
        children: headerChildren,
      ),
      body: ListView.builder(
        itemCount: sorted.length,
        itemBuilder: (context, index) {
          final customer = sorted[index];
          return _buildCustomerRow(context, customer);
        },
      ),
    );
  }

  Widget _buildCustomerRow(BuildContext context, Customer customer) {
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
              child: Text(customer.isActive ? 'Archive' : 'Restore'),
            ),
          ],
          onSelected: (value) {
            switch (value) {
              case 'details':
                context.push('/customers/${customer.id}');
              case 'edit':
                showCustomerFormPopup(context, customerId: customer.id);
              case 'archive':
                _toggleCustomerArchive(customer);
            }
          },
        ),
      ],
      builder: (isHovered) => InkWell(
        onTap: () => context.push('/customers/${customer.id}'),
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
                  width: _colW('name', _colName),
                  child: Text(
                    customer.companyName ?? customer.name,
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
                  width: _colW('phone', _colContact),
                  child: Text(
                    customer.businessPhone ?? '\u2014',
                    style: const TextStyle(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: _colGap),
                SizedBox(
                  width: _colW('email', _colPhone),
                  child: Text(
                    customer.businessEmail ?? '\u2014',
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
                  width: _colW('status', _colStatus),
                  child: Text(
                    customer.status.displayName,
                    style: const TextStyle(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: _colGap),
                SizedBox(
                  width: _colW('source', _colSource),
                  child: Text(
                    customer.source?.displayName ?? '\u2014',
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
                  width: _colW('city', _colCity),
                  child: Text(
                    customer.city ?? '\u2014',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: _colGap),
                _buildStatsCells(customer.id),
                const SizedBox(width: _colGap),
                SizedBox(
                  width: _colW('updated', _colUpdated),
                  child: Text(
                    _formatDate(customer.updatedAt),
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

  Widget _buildStatsCells(String customerId) {
    final currencyCode = context.read<WorkspaceProvider>().currencyCode;
    return FutureBuilder<CustomerStats>(
      future: _getCustomerStats(customerId),
      builder: (context, snapshot) {
        final stats = snapshot.data;
        return Row(
          children: [
            SizedBox(
              width: _colW('openJobs', _colJobsCount),
              child: Text(
                stats == null ? '\u2014' : '${stats.openJobs}',
                style: const TextStyle(fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: _colGap),
            SizedBox(
              width: _colW('closedJobs', _colJobsCount),
              child: Text(
                stats == null ? '\u2014' : '${stats.closedJobs}',
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
              width: _colW('collected', _colCollected),
              child: Text(
                stats == null
                    ? '\u2014'
                    : CurrencyUtils.formatCurrency(
                        stats.collectedRevenue,
                        currencyCode,
                      ),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      },
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

  double _getCreateCardHeight(double cardWidth) {
    if (cardWidth < 280) return 292;
    if (cardWidth < 340) return 276;
    return 260;
  }
}

class _CustomerSavedView {
  final String id;
  final String name;
  final String searchQuery;
  final CustomerViewType viewType;
  final CustomerRecordFilter recordFilter;
  final CustomerStatus? status;
  final CustomerSource? source;
  final String? sortColumn;
  final bool sortAscending;
  final DateTime createdAt;

  const _CustomerSavedView({
    required this.id,
    required this.name,
    required this.searchQuery,
    required this.viewType,
    required this.recordFilter,
    required this.status,
    required this.source,
    required this.sortColumn,
    required this.sortAscending,
    required this.createdAt,
  });

  factory _CustomerSavedView.fromMap(Map<String, dynamic> map) {
    CustomerStatus? parsedStatus;
    final statusName = map['status'] as String?;
    if (statusName != null) {
      for (final value in CustomerStatus.values) {
        if (value.name == statusName) {
          parsedStatus = value;
          break;
        }
      }
    }

    CustomerSource? parsedSource;
    final sourceName = map['source'] as String?;
    if (sourceName != null) {
      for (final value in CustomerSource.values) {
        if (value.name == sourceName) {
          parsedSource = value;
          break;
        }
      }
    }

    final rawViewType = map['view_type'] as String?;
    final viewType = rawViewType == CustomerViewType.table.name
        ? CustomerViewType.table
        : CustomerViewType.card;

    final rawRecordFilter = map['record_filter'] as String?;
    final recordFilter = rawRecordFilter == CustomerRecordFilter.archived.name
        ? CustomerRecordFilter.archived
        : CustomerRecordFilter.active;

    return _CustomerSavedView(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Saved view',
      searchQuery: map['search_query'] as String? ?? '',
      viewType: viewType,
      recordFilter: recordFilter,
      status: parsedStatus,
      source: parsedSource,
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
      'status': status?.name,
      'source': source?.name,
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

/// Centered filter dialog for customers.
class _CustomerFilterDialog extends StatefulWidget {
  final CustomerStatus? selectedStatus;
  final CustomerSource? selectedSource;
  final CustomerRecordFilter recordFilter;
  final List<_CustomerSavedView> savedViews;
  final String? activeSavedViewId;
  final void Function(
    CustomerStatus? status,
    CustomerSource? source,
    CustomerRecordFilter recordFilter,
  )
  onApply;
  final void Function(
    CustomerStatus? status,
    CustomerSource? source,
    CustomerRecordFilter recordFilter,
  )
  onSaveView;
  final ValueChanged<String> onApplySavedView;
  final ValueChanged<String> onDeleteSavedView;

  const _CustomerFilterDialog({
    required this.selectedStatus,
    required this.selectedSource,
    required this.recordFilter,
    required this.savedViews,
    required this.activeSavedViewId,
    required this.onApply,
    required this.onSaveView,
    required this.onApplySavedView,
    required this.onDeleteSavedView,
  });

  @override
  State<_CustomerFilterDialog> createState() => _CustomerFilterDialogState();
}

class _CustomerFilterDialogState extends State<_CustomerFilterDialog> {
  late CustomerStatus? _status;
  late CustomerSource? _source;
  late CustomerRecordFilter _recordFilter;

  bool get _hasAnyFilter => _status != null || _source != null;

  @override
  void initState() {
    super.initState();
    _status = widget.selectedStatus;
    _source = widget.selectedSource;
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
                          _status = null;
                          _source = null;
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
                  // ── Status ──
                  _buildSection(
                    icon: Icons.flag_outlined,
                    title: 'Status',
                    subtitle: _status?.displayName ?? 'Any',
                    isActive: _status != null,
                    child: SearchableFilterChips(
                      items: CustomerStatus.values
                          .map((s) => (id: s.name, label: s.displayName))
                          .toList(),
                      selectedId: _status?.name,
                      allLabel: 'Any',
                      onAllSelected: () => setState(() => _status = null),
                      onItemSelected: (id) => setState(
                        () => _status = CustomerStatus.values.firstWhere(
                          (s) => s.name == id,
                        ),
                      ),
                      searchHint: 'Search statuses...',
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Source ──
                  _buildSection(
                    icon: Icons.source_outlined,
                    title: 'Source',
                    subtitle: _source?.displayName ?? 'Any',
                    isActive: _source != null,
                    child: SearchableFilterChips(
                      items: CustomerSource.values
                          .map((s) => (id: s.name, label: s.displayName))
                          .toList(),
                      selectedId: _source?.name,
                      allLabel: 'Any',
                      onAllSelected: () => setState(() => _source = null),
                      onItemSelected: (id) => setState(
                        () => _source = CustomerSource.values.firstWhere(
                          (s) => s.name == id,
                        ),
                      ),
                      searchHint: 'Search sources...',
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Record type ──
                  _buildSection(
                    icon: Icons.inventory_outlined,
                    title: 'Record Type',
                    subtitle: _recordFilter == CustomerRecordFilter.active
                        ? 'Active'
                        : 'Archived',
                    isActive: _recordFilter == CustomerRecordFilter.archived,
                    child: SegmentedButton<CustomerRecordFilter>(
                      segments: const [
                        ButtonSegment(
                          value: CustomerRecordFilter.active,
                          label: Text('Active'),
                        ),
                        ButtonSegment(
                          value: CustomerRecordFilter.archived,
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
                    onPressed: () =>
                        widget.onSaveView(_status, _source, _recordFilter),
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
                    onPressed: () =>
                        widget.onApply(_status, _source, _recordFilter),
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
