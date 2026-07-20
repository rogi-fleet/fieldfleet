import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../utils/user_facing_error.dart';
import '../../widgets/common/list_skeleton.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../models/maintenance_log.dart';
import '../../models/user.dart';
import '../../models/vehicle.dart';
import '../../services/supabase/vehicle_service.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/vehicle_form_popup.dart';
import '../../widgets/animated_empty_state_cta.dart';
import '../../widgets/common/entity_card_grid.dart';
import '../../widgets/common/entity_create_card.dart';
import '../../widgets/common/module_header.dart';
import '../../widgets/common/view_icon_button.dart';
import '../../widgets/common/searchable_filter_chips.dart';
import '../../widgets/common/view_toolbar.dart';
import '../../theme/theme.dart';
import 'widgets/vehicle_card.dart';
import '../../services/service_locator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';
import '../../widgets/table/table_layout_shell.dart';
import '../../widgets/table/table_header_row.dart';
import '../../widgets/table/table_column_schema.dart';
import '../../widgets/table/table_header_cells_builder.dart';
import '../../widgets/table/table_view_styles.dart';
import '../../widgets/table/hover_action_row.dart';

enum VehicleViewType { table, card }

class VehicleListScreen extends StatefulWidget {
  const VehicleListScreen({super.key});

  @override
  State<VehicleListScreen> createState() => _VehicleListScreenState();
}

class _VehicleListScreenState extends State<VehicleListScreen>
    with SingleTickerProviderStateMixin {
  static const _savedViewsPrefKey = 'saved_vehicle_views';
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  String _searchQuery = '';
  String _statusFilter = 'all';
  VehicleViewType _viewType = VehicleViewType.card;
  String? _sortColumn;
  bool _sortAscending = true;
  final Map<String, double> _columnWidths = {};
  List<_VehicleSavedView> _savedViews = [];

  void _handleColumnResize(TableColumnResize resize) {
    setState(() {
      _columnWidths[resize.columnId] = resize.width;
    });
  }
  String? _activeSavedViewId;

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

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadViewPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('vehicles_view_type');
    if (!mounted) return;
    setState(() {
      _viewType = saved == 'list' || saved == 'table'
          ? VehicleViewType.table
          : VehicleViewType.card;
    });
  }

  Future<void> _saveViewPreference(VehicleViewType viewType) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vehicles_view_type', viewType.name);
  }

  Future<void> _loadSavedViews() async {
    final raw = await ServiceLocator.userPreferencesService.getSavedViews(
      _savedViewsPrefKey,
    );
    if (!mounted) return;
    setState(() {
      _savedViews = raw.map(_VehicleSavedView.fromMap).toList();
    });
  }

  int get _activeFilterCount => _statusFilter != 'all' ? 1 : 0;

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final appUser = authProvider.appUser;
    final workspaceId =
        appUser?.activeWorkspaceId ?? appUser?.workspaceId ?? '';
    final vehicleService = SupabaseVehicleService(workspaceId: workspaceId);

    return Scaffold(
      body: Column(
        children: [
          const ModuleHeader(
            icon: Icons.directions_car_outlined,
            title: 'Vehicles',
            description:
                'Fleet, fuel, maintenance and operator assignment.',
          ),
          Expanded(
            child: StreamBuilder<List<Vehicle>>(
              stream: vehicleService.getVehicles(),
              builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: SelectableText(
                UserFacingError.uiMessage(snapshot.error, action: 'load data'),
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const ListSkeleton();
          }

          final vehicles = snapshot.data ?? [];

          if (vehicles.isEmpty) {
            return _buildEmptyState();
          }

          final filteredVehicles = _filterVehicles(vehicles);

          return FutureBuilder<Map<String, AppUser>>(
            future: ServiceLocator.userService.getWorkspaceUsersMap(
              workspaceId,
            ),
            builder: (context, usersSnapshot) {
              final usersMap = usersSnapshot.data ?? <String, AppUser>{};

              return Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: filteredVehicles.isEmpty
                        ? _buildNoResultsState()
                        : _viewType == VehicleViewType.table
                        ? _buildTableView(
                            context,
                            filteredVehicles,
                            usersMap,
                            vehicleService,
                            workspaceId,
                          )
                        : _buildCardView(
                            context,
                            filteredVehicles,
                            usersMap,
                            vehicleService,
                            workspaceId,
                          ),
                  ),
                ],
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

  List<Vehicle> _filterVehicles(List<Vehicle> vehicles) {
    return vehicles.where((vehicle) {
      final matchesStatus =
          _statusFilter == 'all' || vehicle.status == _statusFilter;
      if (!matchesStatus) return false;

      if (_searchQuery.trim().isEmpty) return true;
      final query = _searchQuery.toLowerCase();
      final haystack = [
        vehicle.name,
        vehicle.make,
        vehicle.model,
        vehicle.licensePlate,
        vehicle.year.toString(),
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  Widget _buildHeader() {
    return ViewToolbar(
      searchHint: 'Search vehicles...',
      searchQuery: _searchQuery,
      onSearch: (query) => setState(() {
        _searchQuery = query;
        _activeSavedViewId = null;
      }),
      centerSlot: _buildViewIcons(),
      filterCount: _activeFilterCount,
      onFilterTap: _showVehicleFilterDialog,
    );
  }

  Widget _buildViewIcons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ViewIconButton(
          icon: Icons.grid_view,
          tooltip: 'Cards',
          isSelected: _viewType == VehicleViewType.card,
          onTap: () {
            setState(() {
              _viewType = VehicleViewType.card;
              _activeSavedViewId = null;
            });
            _saveViewPreference(VehicleViewType.card);
          },
        ),
        ViewIconButton(
          icon: Icons.view_list,
          tooltip: 'Table',
          isSelected: _viewType == VehicleViewType.table,
          onTap: () {
            setState(() {
              _viewType = VehicleViewType.table;
              _activeSavedViewId = null;
            });
            _saveViewPreference(VehicleViewType.table);
          },
        ),
      ],
    );
  }

  void _showVehicleFilterDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return _VehicleFilterDialog(
          selectedStatus: _statusFilter,
          savedViews: _savedViews,
          activeSavedViewId: _activeSavedViewId,
          onApply: (status) {
            setState(() {
              _statusFilter = status;
              _activeSavedViewId = null;
            });
            Navigator.of(ctx).pop();
          },
          onApplySavedView: (viewId) {
            Navigator.of(ctx).pop();
            _applySavedViewById(viewId);
          },
          onSaveView: (status) {
            Navigator.of(ctx).pop();
            _showSaveViewDialog(status);
          },
          onDeleteSavedView: (viewId) {
            _deleteSavedViewById(viewId);
          },
        );
      },
    );
  }

  void _applySavedViewById(String viewId) {
    _VehicleSavedView? view;
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
      _statusFilter = selectedView.statusFilter;
      _viewType = selectedView.viewType;
      _sortColumn = selectedView.sortColumn;
      _sortAscending = selectedView.sortAscending;
      _activeSavedViewId = selectedView.id;
    });
    _saveViewPreference(selectedView.viewType);
  }

  Future<void> _showSaveViewDialog(String status) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save current view'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Active fleet'),
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

    final view = _VehicleSavedView(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      searchQuery: _searchQuery,
      statusFilter: status,
      viewType: _viewType,
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

  Widget _buildNoResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off, size: 48, color: AppColors.textTertiary),
          const SizedBox(height: 16),
          const Text(
            'No vehicles match your filters',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try adjusting your search or status filter',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildCardView(
    BuildContext context,
    List<Vehicle> vehicles,
    Map<String, AppUser> usersMap,
    SupabaseVehicleService vehicleService,
    String workspaceId,
  ) {
    return EntityCardGrid(
      itemCount: vehicles.length,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screenPaddingMobile,
        0,
        AppSpacing.screenPaddingMobile,
        MediaQuery.paddingOf(context).bottom + 90,
      ),
      itemBuilder: (context, index, cardWidth) {
        final vehicle = vehicles[index];
        final assignedUser = vehicle.assignedToUserId == null
            ? null
            : usersMap[vehicle.assignedToUserId];

        return FutureBuilder<List<MaintenanceLog>>(
          future: vehicleService.getMaintenanceLogsOnce(vehicle.id),
          builder: (context, logSnapshot) {
            final logs = logSnapshot.data ?? const <MaintenanceLog>[];
            final latestLog = logs.isNotEmpty ? logs.first : null;

            return VehicleCard(
              vehicle: vehicle,
              assignedUser: assignedUser,
              latestLog: latestLog,
              recentLogs: logs,
              onQuickLog: () => _showQuickLogDialog(
                context,
                vehicleService,
                vehicle.id,
                workspaceId,
              ),
              onToggleStatus: () =>
                  _toggleVehicleStatus(context, vehicleService, vehicle),
            );
          },
        );
      },
      trailingBuilder: (context, cardWidth) => EntityCreateCard(
        title: 'Create New Vehicle',
        subtitle: kIsWeb ? 'Click to add a new vehicle' : 'Tap to add a new vehicle',
        size: EntityCreateCardSize.tall,
        minHeight: _getCreateCardHeight(cardWidth),
        onTap: () => showVehicleFormPopup(context),
      ),
    );
  }

  static const double _colName = 180;
  static const double _colMakeModel = 180;
  static const double _colYear = 70;
  static const double _colPlate = 130;
  static const double _colMileage = 110;
  static const double _colStatus = 110;
  static const double _colGap = 12;

  static const _tableColumns = [
    TableColumnSchema(id: 'name', label: 'Name', defaultWidth: _colName, minWidth: 100, maxWidth: 350),
    TableColumnSchema(id: 'makeModel', label: 'Make / Model', defaultWidth: _colMakeModel, minWidth: 100, maxWidth: 350),
    TableColumnSchema(id: 'year', label: 'Year', defaultWidth: _colYear, minWidth: 56, maxWidth: 120),
    TableColumnSchema(id: 'plate', label: 'License Plate', defaultWidth: _colPlate, minWidth: 80, maxWidth: 220),
    TableColumnSchema(id: 'mileage', label: 'Mileage', defaultWidth: _colMileage, minWidth: 80, maxWidth: 200),
    TableColumnSchema(id: 'status', label: 'Status', defaultWidth: _colStatus, minWidth: 80, maxWidth: 200),
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

  List<Vehicle> _applySorting(List<Vehicle> vehicles) {
    if (_sortColumn == null) return vehicles;
    final sorted = List<Vehicle>.from(vehicles);
    final ascending = _sortAscending;
    sorted.sort((a, b) {
      int result;
      switch (_sortColumn) {
        case 'name':
          result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case 'makeModel':
          result = '${a.make} ${a.model}'.toLowerCase().compareTo(
            '${b.make} ${b.model}'.toLowerCase(),
          );
        case 'year':
          result = a.year.compareTo(b.year);
        case 'plate':
          result = a.licensePlate.compareTo(b.licensePlate);
        case 'mileage':
          result = a.currentMileage.compareTo(b.currentMileage);
        case 'status':
          result = a.status.compareTo(b.status);
        default:
          result = 0;
      }
      return ascending ? result : -result;
    });
    return sorted;
  }

  Widget _buildTableView(
    BuildContext context,
    List<Vehicle> vehicles,
    Map<String, AppUser> usersMap,
    SupabaseVehicleService vehicleService,
    String workspaceId,
  ) {
    final sorted = _applySorting(vehicles);
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
      minTableWidth: 850,
      header: TableHeaderRow(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
        children: headerChildren,
      ),
      body: ListView.builder(
        itemCount: sorted.length,
        itemBuilder: (context, index) {
          final vehicle = sorted[index];
          return _buildVehicleRow(context, vehicle, vehicleService);
        },
      ),
    );
  }

  double _colW(String id, double defaultWidth) =>
      _columnWidths[id] ?? defaultWidth;

  Widget _buildVehicleRow(
    BuildContext context,
    Vehicle vehicle,
    SupabaseVehicleService vehicleService,
  ) {
    return HoverActionRow(
      actionWidth: 40,
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 20),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'details', child: Text('View details')),
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(
              value: 'toggle',
              child: Text(
                vehicle.status == 'retired' ? 'Mark Active' : 'Mark Retired',
              ),
            ),
          ],
          onSelected: (value) {
            switch (value) {
              case 'details':
                context.push('/vehicles/${vehicle.id}');
              case 'edit':
                showVehicleFormPopup(context, vehicleId: vehicle.id);
              case 'toggle':
                _toggleVehicleStatus(context, vehicleService, vehicle);
            }
          },
        ),
      ],
      builder: (isHovered) => InkWell(
        onTap: () => context.push('/vehicles/${vehicle.id}'),
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
                    vehicle.name,
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
                  width: _colW('makeModel', _colMakeModel),
                  child: Text(
                    '${vehicle.make} ${vehicle.model}',
                    style: const TextStyle(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: _colGap),
                SizedBox(
                  width: _colW('year', _colYear),
                  child: Text(
                    vehicle.year.toString(),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: _colGap),
                SizedBox(
                  width: _colW('plate', _colPlate),
                  child: Text(
                    vehicle.licensePlate,
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: _colGap),
                SizedBox(
                  width: _colW('mileage', _colMileage),
                  child: Text(
                    '${vehicle.currentMileage} mi',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: _colGap),
                SizedBox(
                  width: _colW('status', _colStatus),
                  child: Text(
                    vehicle.status[0].toUpperCase() +
                        vehicle.status.substring(1),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showQuickLogDialog(
    BuildContext context,
    SupabaseVehicleService vehicleService,
    String vehicleId,
    String workspaceId,
  ) async {
    final descriptionController = TextEditingController();
    final costController = TextEditingController();
    final performedByController = TextEditingController();
    final nextMileageController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    DateTime? nextMaintenanceDate;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Quick Maintenance Log'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StackedField(
                      label: 'Description *',
                      child: TextField(
                        controller: descriptionController,
                        decoration: const InputDecoration(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      title: const Text('Date'),
                      subtitle: Text(
                        '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );
                        if (date != null) {
                          setState(() => selectedDate = date);
                        }
                      },
                    ),
                    StackedField(
                      label: 'Cost',
                      child: TextField(
                        controller: costController,
                        decoration: const InputDecoration(prefixText: '\$ '),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(height: 16),
                    StackedField(
                      label: 'Performed By',
                      child: TextField(
                        controller: performedByController,
                        decoration: const InputDecoration(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    StackedField(
                      label: 'Next Maintenance Mileage',
                      child: TextField(
                        controller: nextMileageController,
                        decoration: const InputDecoration(),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      title: const Text('Next Maintenance Date'),
                      subtitle: Text(
                        nextMaintenanceDate == null
                            ? 'Not set'
                            : '${nextMaintenanceDate!.year}-${nextMaintenanceDate!.month.toString().padLeft(2, '0')}-${nextMaintenanceDate!.day.toString().padLeft(2, '0')}',
                      ),
                      trailing: const Icon(Icons.event),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: nextMaintenanceDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now().add(
                            const Duration(days: 3650),
                          ),
                        );
                        if (date != null) {
                          setState(() => nextMaintenanceDate = date);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (descriptionController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Description is required'),
                        ),
                      );
                      return;
                    }

                    final log = MaintenanceLog(
                      id: '',
                      workspaceId: workspaceId,
                      entityId: vehicleId,
                      entityType: 'vehicle',
                      date: selectedDate,
                      type: 'other',
                      description: descriptionController.text.trim(),
                      cost: double.tryParse(costController.text.trim()) ?? 0.0,
                      performedBy: performedByController.text.trim().isEmpty
                          ? null
                          : performedByController.text.trim(),
                      nextMaintenanceDate: nextMaintenanceDate,
                      nextMaintenanceMileage: int.tryParse(
                        nextMileageController.text.trim(),
                      ),
                    );

                    await vehicleService.addMaintenanceLog(log);
                    if (context.mounted) {
                      Navigator.pop(context, true);
                    }
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Maintenance log added')));
    }

    descriptionController.dispose();
    costController.dispose();
    performedByController.dispose();
    nextMileageController.dispose();
  }

  Future<void> _toggleVehicleStatus(
    BuildContext context,
    SupabaseVehicleService vehicleService,
    Vehicle vehicle,
  ) async {
    final nextStatus = vehicle.status == 'retired' ? 'active' : 'retired';
    try {
      await vehicleService.updateVehicle(vehicle.copyWith(status: nextStatus));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextStatus == 'retired'
                ? 'Vehicle marked retired'
                : 'Vehicle marked active',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.uiMessage(error, action: 'update vehicle'),
          ),
        ),
      );
    }
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
                    Icons.directions_car,
                    size: 40,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          const Text(
            'No vehicles yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Add your first vehicle to get started',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 18),
          AnimatedEmptyStateCta(
            animation: _pulseAnimation,
            label: 'Create Your First Vehicle',
            onTap: () {
              showVehicleFormPopup(context);
            },
          ),
          const SizedBox(height: 10),
          Text(
            kIsWeb
                ? 'Click "Create Your First Vehicle" to begin'
                : 'Tap "Create Your First Vehicle" to begin',
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

  double _getCreateCardHeight(double cardWidth) {
    if (cardWidth < 280) return 320;
    if (cardWidth < 340) return 410;
    return 500;
  }
}

class _VehicleSavedView {
  final String id;
  final String name;
  final String searchQuery;
  final String statusFilter;
  final VehicleViewType viewType;
  final String? sortColumn;
  final bool sortAscending;
  final DateTime createdAt;

  const _VehicleSavedView({
    required this.id,
    required this.name,
    required this.searchQuery,
    required this.statusFilter,
    required this.viewType,
    required this.sortColumn,
    required this.sortAscending,
    required this.createdAt,
  });

  factory _VehicleSavedView.fromMap(Map<String, dynamic> map) {
    final rawViewType = map['view_type'] as String?;
    final viewType = rawViewType == VehicleViewType.table.name
        ? VehicleViewType.table
        : VehicleViewType.card;

    return _VehicleSavedView(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Saved view',
      searchQuery: map['search_query'] as String? ?? '',
      statusFilter: map['status_filter'] as String? ?? 'all',
      viewType: viewType,
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
      'status_filter': statusFilter,
      'view_type': viewType.name,
      'sort_column': sortColumn,
      'sort_ascending': sortAscending,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class _VehicleFilterDialog extends StatefulWidget {
  final String selectedStatus;
  final ValueChanged<String> onApply;
  final ValueChanged<String> onSaveView;
  final ValueChanged<String> onApplySavedView;
  final ValueChanged<String> onDeleteSavedView;
  final List<_VehicleSavedView> savedViews;
  final String? activeSavedViewId;

  const _VehicleFilterDialog({
    required this.selectedStatus,
    required this.onApply,
    required this.onSaveView,
    required this.onApplySavedView,
    required this.onDeleteSavedView,
    required this.savedViews,
    required this.activeSavedViewId,
  });

  @override
  State<_VehicleFilterDialog> createState() => _VehicleFilterDialogState();
}

class _VehicleFilterDialogState extends State<_VehicleFilterDialog> {
  late String _status;

  static const _statusOptions = <String, String>{
    'all': 'All',
    'active': 'Active',
    'maintenance': 'Maintenance',
    'retired': 'Retired',
    'available': 'Available',
  };

  @override
  void initState() {
    super.initState();
    _status = widget.selectedStatus;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  const Text(
                    'Filters',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (_status != 'all')
                    TextButton(
                      onPressed: () => setState(() => _status = 'all'),
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
                      color: _status != 'all'
                          ? AppColors.primary.withValues(alpha: 0.04)
                          : AppColors.surfaceAlt.withValues(alpha: 0.5),
                      border: Border.all(
                        color: _status != 'all'
                            ? AppColors.primary.withValues(alpha: 0.3)
                            : AppColors.cardBorder,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.r12),
                    ),
                    child: Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        leading: Icon(
                          Icons.flag_outlined,
                          size: 20,
                          color: _status != 'all'
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                        title: const Text(
                          'Status',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          _statusOptions[_status] ?? 'All',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        initiallyExpanded: true,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: SearchableFilterChips(
                              items: _statusOptions.entries
                                  .where((e) => e.key != 'all')
                                  .map((e) => (id: e.key, label: e.value))
                                  .toList(),
                              selectedId: _status == 'all' ? null : _status,
                              allLabel: 'All',
                              onAllSelected: () =>
                                  setState(() => _status = 'all'),
                              onItemSelected: (id) =>
                                  setState(() => _status = id),
                              searchHint: 'Search statuses...',
                            ),
                          ),
                        ],
                      ),
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
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => widget.onSaveView(_status),
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
                    onPressed: () => widget.onApply(_status),
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
