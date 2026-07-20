import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../models/project.dart';
import '../../../models/property.dart';
import '../../../models/property_status.dart';
import '../../../models/property_task_metrics.dart';
import '../../../providers/workspace_provider.dart';
import '../../../services/service_locator.dart';
import '../../../widgets/properties/property_form_popup.dart';
import '../../../widgets/properties/property_status_badge.dart';
import '../../../widgets/properties/property_detail_view.dart';
import '../../../widgets/properties/building_elevation_view.dart';
import '../../../widgets/table/inline_dropdown_cell.dart';
import '../../../widgets/table/inline_edit_cell.dart';
import '../../../widgets/table/table_column_schema.dart';
import '../../../widgets/table/table_header_cells_builder.dart';
import '../../../widgets/table/table_header_row.dart';
import '../../../widgets/table/table_layout_shell.dart';
import '../../../widgets/common/view_icon_button.dart';
import '../../../widgets/common/view_toolbar.dart';
import '../../../widgets/table/table_summary_footer.dart';
import '../../../widgets/table/table_view_styles.dart';
import '../../../widgets/table/tree_row_container.dart';
import '../../../theme/theme.dart';
import '../../../utils/project_terminology.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/common/zero_items_action_empty_state.dart';
import '../../../widgets/common/entity_card_grid.dart';
import '../../../widgets/common/entity_create_card.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

const List<String> _propertyStructureSuggestions = [
  'Dwelling',
  'Unit',
  'Suite',
  'Apartment',
  'Condo',
  'Townhome',
  'Office',
  'Retail',
  'Warehouse',
];

Iterable<String> _buildAutocompleteOptions(String query, List<String> source) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    return source;
  }
  return source.where((value) => value.toLowerCase().contains(normalized));
}

/// Properties tab showing all properties for a project.
class ProjectPropertiesTab extends StatefulWidget {
  final Project project;
  final void Function(String propertyId)? onOpenTasksForProperty;

  const ProjectPropertiesTab({
    super.key,
    required this.project,
    this.onOpenTasksForProperty,
  });

  @override
  State<ProjectPropertiesTab> createState() => _ProjectPropertiesTabState();
}

class _ProjectPropertiesTabState extends State<ProjectPropertiesTab> {
  // Shared inline editor mode for add/edit to avoid duplicate row logic.
  static const String _inlineModeAdd = 'add';
  static const String _inlineModeEdit = 'edit';
  static const List<TableColumnSchema> _propertyTableColumns = [
    TableColumnSchema(
      id: 'name',
      label: 'Structure',
      defaultWidth: 120,
      minWidth: 100,
      maxWidth: 320,
    ),
    TableColumnSchema(
      id: 'identifier',
      label: 'Number',
      defaultWidth: 100,
      minWidth: 80,
      maxWidth: 240,
    ),
    TableColumnSchema(
      id: 'level',
      label: 'Level',
      defaultWidth: 70,
      minWidth: 56,
      maxWidth: 180,
    ),
    TableColumnSchema(
      id: 'occupancy',
      label: 'Occupancy',
      defaultWidth: 120,
      minWidth: 90,
      maxWidth: 300,
    ),
    TableColumnSchema(
      id: 'status',
      label: 'Status',
      defaultWidth: 120,
      minWidth: 100,
      maxWidth: 200,
    ),
    TableColumnSchema(
      id: 'areas',
      label: 'Areas',
      defaultWidth: 64,
      minWidth: 56,
      maxWidth: 140,
      align: TextAlign.center,
    ),
    TableColumnSchema(
      id: 'drying',
      label: 'Drying',
      defaultWidth: 68,
      minWidth: 56,
      maxWidth: 140,
      align: TextAlign.center,
    ),
    TableColumnSchema(
      id: 'contents',
      label: 'Contents',
      defaultWidth: 80,
      minWidth: 68,
      maxWidth: 180,
      align: TextAlign.center,
    ),
    TableColumnSchema(
      id: 'tasks',
      label: 'Tasks',
      defaultWidth: 72,
      minWidth: 60,
      maxWidth: 140,
      align: TextAlign.center,
    ),
    TableColumnSchema(
      id: 'updated',
      label: 'Updated',
      defaultWidth: 110,
      minWidth: 90,
      maxWidth: 220,
      align: TextAlign.center,
    ),
    TableColumnSchema(
      id: 'actions',
      label: '',
      defaultWidth: 44,
      minWidth: 44,
      maxWidth: 44,
      align: TextAlign.center,
      resizable: false,
    ),
  ];

  late Stream<List<Property>> _propertiesStream;
  StreamSubscription<Map<String, PropertyTaskMetrics>>? _taskMetricsSub;
  Map<String, PropertyTaskMetrics> _taskMetrics = {};
  String _searchQuery = '';
  final TextEditingController _inlineIdentifierController =
      TextEditingController();
  final TextEditingController _inlineNameController = TextEditingController();
  final TextEditingController _inlineLevelController = TextEditingController();
  final TextEditingController _inlineOccupancyController =
      TextEditingController();
  final Map<String, double> _propertyColumnWidths = {
    for (final column in _propertyTableColumns) column.id: column.defaultWidth,
  };
  final Set<String> _selectedPropertyIds = {};
  final Map<String, Property> _latestPropertiesById = {};
  PropertyStatus? _statusFilter;
  String? _sortColumn;
  bool _sortAscending = true;
  bool _isCardView = true;
  bool _isElevationView = false;
  String? _selectedPropertyId;
  String? _inlineMode;
  String? _inlineEditingPropertyId;
  bool _isInlineSavingProperty = false;
  bool _isBulkUpdatingProperties = false;
  PropertyStatus _inlineStatus = PropertyStatus.pending;
  final Object _inlineEditorTapRegionGroup = Object();

  bool get _isInlineAddingProperty => _inlineMode == _inlineModeAdd;

  @override
  void initState() {
    super.initState();
    _propertiesStream = ServiceLocator.propertyService.getProperties(
      widget.project.id,
      workspaceId: widget.project.workspaceId,
    );
    _subscribeToTaskMetrics();
  }

  void _subscribeToTaskMetrics() {
    _taskMetricsSub?.cancel();
    _taskMetricsSub = ServiceLocator.taskService
        .getPropertyTaskMetrics(
          widget.project.id,
          workspaceId: widget.project.workspaceId,
        )
        .listen((metrics) {
      if (mounted) setState(() => _taskMetrics = metrics);
    });
  }

  @override
  void didUpdateWidget(ProjectPropertiesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project.id != widget.project.id ||
        oldWidget.project.workspaceId != widget.project.workspaceId) {
      _propertiesStream = ServiceLocator.propertyService.getProperties(
        widget.project.id,
        workspaceId: widget.project.workspaceId,
      );
      _subscribeToTaskMetrics();
    }
  }

  @override
  void dispose() {
    _taskMetricsSub?.cancel();
    _inlineIdentifierController.dispose();
    _inlineNameController.dispose();
    _inlineLevelController.dispose();
    _inlineOccupancyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedPropertyId != null) {
      return PropertyDetailView(
        project: widget.project,
        propertyId: _selectedPropertyId!,
        onBack: () => setState(() => _selectedPropertyId = null),
        onPropertySelected: (propertyId) {
          setState(() => _selectedPropertyId = propertyId);
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header with search, filters, and add button
        _buildHeader(context),
        // Properties list
        Expanded(
          child: StreamBuilder<List<Property>>(
            stream: _propertiesStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    UserFacingError.uiMessage(
                      snapshot.error,
                      action: 'load properties',
                    ),
                  ),
                );
              }

              final properties = snapshot.data ?? [];
              _latestPropertiesById
                ..clear()
                ..addEntries(properties.map((p) => MapEntry(p.id, p)));

              // Apply filters
              final filteredProperties = _filterProperties(properties);

              final canShowInlineEmptyList =
                  _isInlineAddingProperty &&
                  !_isElevationView &&
                  !_isCardView &&
                  _searchQuery.trim().isEmpty &&
                  _statusFilter == null;
              final shouldShowEmptyState =
                  filteredProperties.isEmpty && !canShowInlineEmptyList;
              if (shouldShowEmptyState) {
                return _buildEmptyState(context, properties.isEmpty);
              }

              if (_isElevationView) {
                return BuildingElevationView(
                  properties: filteredProperties,
                  project: widget.project,
                  onPropertyTap: (property) =>
                      _openPropertyDetail(context, property),
                  onPropertyEdit: (property) =>
                      _showPropertyForm(context, property),
                  taskMetrics: _taskMetrics,
                );
              }

              return _isCardView
                  ? _buildCardView(context, filteredProperties)
                  : _buildTableView(context, filteredProperties);
            },
          ),
        ),
      ],
    );
  }

  int get _activeFilterCount => _statusFilter != null ? 1 : 0;

  Widget _buildHeader(BuildContext context) {
    return Column(
      children: [
        ViewToolbar(
          searchHint: 'Search properties...',
          searchQuery: _searchQuery,
          onSearch: (query) => setState(() => _searchQuery = query),
          centerSlot: _buildPropertyViewIcons(),
          filterCount: _activeFilterCount,
          onFilterTap: _showPropertyFilterDialog,
        ),
        if (_selectedPropertyIds.isNotEmpty) _buildSelectionBanner(),
      ],
    );
  }

  Widget _buildPropertyViewIcons() {
    final currentView = _isElevationView
        ? 'elevation'
        : (_isCardView ? 'cards' : 'list');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ViewIconButton(
          icon: Icons.grid_view,
          tooltip: 'Cards',
          isSelected: currentView == 'cards',
          onTap: () => setState(() {
            _isCardView = true;
            _isElevationView = false;
          }),
        ),
        ViewIconButton(
          icon: Icons.table_rows,
          tooltip: 'List',
          isSelected: currentView == 'list',
          onTap: () => setState(() {
            _isCardView = false;
            _isElevationView = false;
          }),
        ),
        ViewIconButton(
          icon: Icons.apartment,
          tooltip: 'Elevation',
          isSelected: currentView == 'elevation',
          onTap: () => setState(() {
            _isCardView = false;
            _isElevationView = true;
          }),
        ),
      ],
    );
  }

  void _showPropertyFilterDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return _PropertyFilterDialog(
          selectedStatus: _statusFilter,
          onApply: (status) {
            setState(() => _statusFilter = status);
            Navigator.of(ctx).pop();
          },
        );
      },
    );
  }

  Widget _buildSelectionBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.xs),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: AppColors.info.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.info.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_selectedPropertyIds.length} selected',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.info,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 26,
              child: FilledButton.icon(
                onPressed: _isBulkUpdatingProperties
                    ? null
                    : () => _showPropertyMassEditDialog(context),
                icon: const Icon(Icons.edit_outlined, size: 14),
                label: const Text('Edit', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 26,
              height: 26,
              child: IconButton(
                onPressed: _isBulkUpdatingProperties
                    ? null
                    : _clearPropertySelection,
                icon: const Icon(Icons.close, size: 14),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Clear selection',
                color: AppColors.info,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Property> _filterProperties(List<Property> properties) {
    var filtered = properties;

    // Apply search filter
    final searchTerm = _searchQuery.toLowerCase();
    if (searchTerm.isNotEmpty) {
      filtered = filtered.where((p) {
        return p.name.toLowerCase().contains(searchTerm) ||
            p.identifier.toLowerCase().contains(searchTerm) ||
            (p.occupant?.toLowerCase().contains(searchTerm) ?? false);
      }).toList();
    }

    // Apply status filter
    if (_statusFilter != null) {
      filtered = filtered.where((p) => p.status == _statusFilter).toList();
    }

    // Apply column sort
    if (_sortColumn != null) {
      final asc = _sortAscending;
      filtered = List.of(filtered)
        ..sort((a, b) {
          int cmp;
          switch (_sortColumn) {
            case 'name':
              cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
              break;
            case 'identifier':
              cmp = a.identifier.toLowerCase().compareTo(
                b.identifier.toLowerCase(),
              );
              break;
            case 'level':
              cmp = (a.floor ?? '').compareTo(b.floor ?? '');
              break;
            case 'occupancy':
              cmp = (a.occupant ?? '').toLowerCase().compareTo(
                (b.occupant ?? '').toLowerCase(),
              );
              break;
            case 'status':
              cmp = a.status.index.compareTo(b.status.index);
              break;
            case 'areas':
              cmp = a.areaCount.compareTo(b.areaCount);
              break;
            case 'drying':
              cmp = a.dryAreaCount.compareTo(b.dryAreaCount);
              break;
            case 'contents':
              cmp = a.contentsCount.compareTo(b.contentsCount);
              break;
            case 'updated':
              cmp = a.updatedAt.compareTo(b.updatedAt);
              break;
            default:
              cmp = 0;
          }
          return asc ? cmp : -cmp;
        });
    }

    return filtered;
  }

  void _onPropertyColumnSortTap(TableColumnSchema column) {
    setState(() {
      if (_sortColumn == column.id) {
        if (_sortAscending) {
          _sortAscending = false;
        } else {
          _sortColumn = null;
          _sortAscending = true;
        }
      } else {
        _sortColumn = column.id;
        _sortAscending = true;
      }
    });
  }

  Widget _buildHeaderFact({
    required IconData icon,
    required Color iconColor,
    required String text,
    String? label,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 4),
        if (label != null) ...[
          Text(
            '$label ',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
            ),
          ),
        ],
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: label != null ? FontWeight.w600 : FontWeight.w400,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, bool noProperties) {
    if (noProperties) {
      final pluralTerminology = context
          .watch<WorkspaceProvider>()
          .projectTerminology;
      return ZeroItemsActionEmptyState(
        icon: Icons.home_work_outlined,
        title:
            'No property for this ${singularProjectTerminology(pluralTerminology).toLowerCase()} yet',
        subtitle:
            'Add property to track multi-unit restoration ${pluralTerminology.toLowerCase()}',
        ctaLabel: 'Add Structure',
        onTap: _isInlineSavingProperty
            ? null
            : () => _startAddProperty(context),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.home_work_outlined,
              size: 64,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'No property match your search',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your search or filters',
              style: TextStyle(color: AppColors.textTertiary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableView(BuildContext context, List<Property> properties) {
    final dateFormat = DateFormat('MMM d, yyyy');
    final headerStyle = TableViewStyles.headerLabelStyle(context);
    const selectionColumnWidth = 40.0;

    final showInlineEditorRow = _isInlineAddingProperty || properties.isEmpty;
    final showInlineAddTriggerRow = !showInlineEditorRow;
    const tableHorizontalPadding =
        32.0; // header/body use 16px left + 16px right
    final tableContentMinWidth =
        _propertyTableColumns.fold<double>(
          0,
          (sum, column) =>
              sum + (_propertyColumnWidths[column.id] ?? column.defaultWidth),
        ) +
        selectionColumnWidth +
        tableHorizontalPadding;

    final rowCount =
        properties.length +
        (showInlineEditorRow ? 1 : 0) +
        (showInlineAddTriggerRow ? 1 : 0);

    return TableLayoutShell(
      minTableWidth: tableContentMinWidth,
      showHeaderDivider: false,
      header: _buildTableHeader(
        context,
        headerStyle,
        visibleProperties: properties,
      ),
      footer: _buildPropertySummaryFooter(properties),
      body: ListView.builder(
        itemCount: rowCount,
        itemBuilder: (context, index) {
          if (index < properties.length) {
            final property = properties[index];
            if (_inlineEditingPropertyId == property.id) {
              return _buildInlineEditablePropertyRow(
                context: context,
                existingProperty: property,
              );
            }
            return _buildPropertyListRow(
              context: context,
              property: property,
              dateFormat: dateFormat,
              isAlternate: index.isOdd,
            );
          }
          if (showInlineEditorRow && index == properties.length) {
            return _buildInlineEditablePropertyRow(context: context);
          }
          return _buildInlineAddTriggerRow(context: context);
        },
      ),
    );
  }

  Widget _buildPropertySummaryFooter(List<Property> properties) {
    if (properties.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final totalAreas = properties.fold<int>(0, (sum, p) => sum + p.areaCount);

    // Count by status
    final statusCounts = <PropertyStatus, int>{};
    for (final property in properties) {
      statusCounts[property.status] = (statusCounts[property.status] ?? 0) + 1;
    }

    // Task totals across visible properties
    int totalTasks = 0;
    int completedTasks = 0;
    for (final p in properties) {
      final m = _taskMetrics[p.id];
      if (m != null) {
        totalTasks += m.totalCount;
        completedTasks += m.completedCount;
      }
    }

    return TableSummaryFooter(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      children: [
        const SizedBox(width: 40), // Selection checkbox
        SizedBox(
          width: _propertyColumnWidths['name'] ?? 120,
          child: Text(
            '${properties.length} ${properties.length == 1 ? 'property' : 'properties'}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: colorScheme.onSurface,
            ),
          ),
        ),
        SizedBox(width: _propertyColumnWidths['identifier'] ?? 100),
        SizedBox(width: _propertyColumnWidths['level'] ?? 70),
        SizedBox(width: _propertyColumnWidths['occupancy'] ?? 120),
        // Status column — show breakdown
        SizedBox(
          width: _propertyColumnWidths['status'] ?? 120,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in statusCounts.entries)
                if (entry.value > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      '${entry.value}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: entry.key.color,
                      ),
                    ),
                  ),
            ],
          ),
        ),
        // Areas total
        SizedBox(
          width: _propertyColumnWidths['areas'] ?? 64,
          child: Text(
            '$totalAreas',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: colorScheme.onSurface,
            ),
          ),
        ),
        // Remaining columns — dashes
        SizedBox(
          width: _propertyColumnWidths['drying'] ?? 68,
          child: Text(
            '-',
            textAlign: TextAlign.center,
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
          ),
        ),
        SizedBox(
          width: _propertyColumnWidths['contents'] ?? 80,
          child: Text(
            '-',
            textAlign: TextAlign.center,
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
          ),
        ),
        TableSummaryCell(
          width: _propertyColumnWidths['tasks'] ?? 72,
          text: totalTasks == 0 ? null : '$completedTasks/$totalTasks',
          placeholder: '—',
          isBold: totalTasks > 0,
          color: totalTasks > 0 && completedTasks == totalTasks
              ? AppColors.success
              : null,
        ),
        SizedBox(
          width: _propertyColumnWidths['updated'] ?? 110,
          child: Text(
            '-',
            textAlign: TextAlign.center,
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
          ),
        ),
        SizedBox(width: _propertyColumnWidths['actions'] ?? 44),
      ],
    );
  }

  Widget _buildTableHeader(
    BuildContext context,
    TextStyle? headerStyle, {
    required List<Property> visibleProperties,
  }) {
    final isAllSelected =
        visibleProperties.isNotEmpty &&
        visibleProperties.every((p) => _selectedPropertyIds.contains(p.id));
    final isSomeSelected =
        visibleProperties.any((p) => _selectedPropertyIds.contains(p.id)) &&
        !isAllSelected;

    return TableHeaderRow(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      children: [
        SizedBox(
          width: 40,
          child: Center(
            child: Checkbox(
              value: isAllSelected,
              tristate: isSomeSelected,
              onChanged: (checked) =>
                  _toggleSelectAllVisible(visibleProperties, checked ?? false),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
        ...buildTableHeaderCells(
          context: context,
          columns: _propertyTableColumns,
          widths: _propertyColumnWidths,
          textStyle: headerStyle,
          dividerColor: Theme.of(context).dividerColor.withValues(alpha: 0.65),
          showHoverAffordances: true,
          onSortTap: _onPropertyColumnSortTap,
          sortedColumnId: _sortColumn,
          sortAscending: _sortAscending,
          onColumnResize: (resize) {
            setState(() {
              _propertyColumnWidths[resize.columnId] = resize.width;
            });
          },
        ),
      ],
    );
  }

  Widget _buildInlineEditablePropertyRow({
    required BuildContext context,
    Property? existingProperty,
  }) {
    final rowColor = Theme.of(
      context,
    ).colorScheme.primaryContainer.withValues(alpha: 0.22);
    final isEditing = existingProperty != null;
    final inputDecoration = InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.zero,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
    );
    return _buildPropertyRowContainer(
      context: context,
      color: rowColor,
      isAutoHeight: true,
      child: TextFieldTapRegion(
        groupId: _inlineEditorTapRegionGroup,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              const SizedBox(width: 40),
              _buildListCell(
                'name',
                _buildInlineEditorFrame(
                  child: _buildInlineAutocompleteField(
                    controller: _inlineNameController,
                    enabled: !_isInlineSavingProperty,
                    autofocus: true,
                    suggestionValues: _propertyStructureSuggestions,
                    decoration: inputDecoration.copyWith(
                      hintText: 'e.g., Dwelling, Unit, Suite',
                    ),
                  ),
                ),
              ),
              _buildListCell(
                'identifier',
                _buildInlineEditorFrame(
                  child: _buildInlineAutocompleteField(
                    controller: _inlineIdentifierController,
                    enabled: !_isInlineSavingProperty,
                    suggestionValues: _propertyStructureSuggestions,
                    decoration: inputDecoration.copyWith(
                      hintText: 'e.g., A, 101',
                    ),
                  ),
                ),
              ),
              _buildListCell(
                'level',
                _buildInlineEditorFrame(
                  child: TextField(
                    controller: _inlineLevelController,
                    enabled: !_isInlineSavingProperty,
                    decoration: inputDecoration.copyWith(
                      hintText: 'e.g., 1st, Ground, Basement',
                    ),
                    onTapOutside: (_) => _cancelInlineEditIfAllowed(),
                  ),
                ),
              ),
              _buildListCell(
                'occupancy',
                _buildInlineEditorFrame(
                  child: TextField(
                    controller: _inlineOccupancyController,
                    enabled: !_isInlineSavingProperty,
                    decoration: inputDecoration.copyWith(hintText: 'Occupant'),
                    onTapOutside: (_) => _cancelInlineEditIfAllowed(),
                  ),
                ),
              ),
              _buildListCell(
                'status',
                _buildInlineEditorFrame(
                  child: DropdownButtonFormField<PropertyStatus>(
                    borderRadius: AppRadius.cardRadius,
                    initialValue: _inlineStatus,
                    isExpanded: true,
                    decoration: inputDecoration,
                    items: PropertyStatus.values
                        .where((status) => status != PropertyStatus.archived)
                        .map(
                          (status) => DropdownMenuItem(
                            value: status,
                            child: Text(status.displayName),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: _isInlineSavingProperty
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _inlineStatus = value);
                          },
                  ),
                ),
              ),
              _buildListCell('areas', const Text('0')),
              _buildListCell('drying', const Text('0/0')),
              _buildListCell('contents', const Text('0')),
              _buildListCell('updated', const Text('-')),
              _buildListCell(
                'actions',
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: isEditing ? 'Save changes' : 'Save',
                      onPressed: _isInlineSavingProperty
                          ? null
                          : _saveInlineProperty,
                      icon: _isInlineSavingProperty
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                    ),
                    IconButton(
                      tooltip: 'Cancel',
                      onPressed: _isInlineSavingProperty
                          ? null
                          : _cancelInlineEdit,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInlineAutocompleteField({
    required TextEditingController controller,
    required bool enabled,
    required InputDecoration decoration,
    required List<String> suggestionValues,
    bool autofocus = false,
  }) {
    return RawAutocomplete<String>(
      textEditingController: controller,
      optionsBuilder: (textEditingValue) {
        if (!enabled) return const Iterable<String>.empty();
        return _buildAutocompleteOptions(
          textEditingValue.text,
          suggestionValues,
        );
      },
      fieldViewBuilder:
          (context, textController, focusNode, onFieldSubmitted) => TextField(
            controller: textController,
            focusNode: focusNode,
            enabled: enabled,
            autofocus: autofocus,
            decoration: decoration,
            onSubmitted: (_) => onFieldSubmitted(),
            onTapOutside: (_) => _cancelInlineEditIfAllowed(),
          ),
      onSelected: (selection) {
        controller
          ..text = selection
          ..selection = TextSelection.collapsed(offset: selection.length);
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: TextFieldTapRegion(
            groupId: _inlineEditorTapRegionGroup,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 220,
                  maxWidth: 240,
                ),
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: options
                      .map(
                        (option) => ListTile(
                          dense: true,
                          title: Text(option),
                          onTap: () => onSelected(option),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInlineEditorFrame({required Widget child}) {
    return InlineEditFrame(borderColor: AppColors.info, child: child);
  }

  Widget _buildInlineAddTriggerRow({required BuildContext context}) {
    final addLabelStyle = TableViewStyles.headerLabelStyle(context)?.copyWith(
      color: _isInlineSavingProperty
          ? AppColors.textTertiary
          : AppColors.textSecondary,
    );

    return _buildPropertyRowContainer(
      context: context,
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          const SizedBox(width: 40),
          _buildListCell(
            'name',
            TextButton(
              onPressed: _isInlineSavingProperty
                  ? null
                  : () => _startAddProperty(context),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                alignment: Alignment.centerLeft,
                foregroundColor: addLabelStyle?.color,
                textStyle: addLabelStyle,
              ),
              child: const Text('Add Structure'),
            ),
          ),
          for (final columnId in const [
            'identifier',
            'level',
            'occupancy',
            'status',
            'areas',
            'drying',
            'contents',
            'updated',
            'actions',
          ])
            _buildListCell(columnId, const SizedBox.shrink()),
        ],
      ),
    );
  }

  Widget _buildPropertyListRow({
    required BuildContext context,
    required Property property,
    required DateFormat dateFormat,
    required bool isAlternate,
  }) {
    final rowColor = isAlternate
        ? Theme.of(context).colorScheme.surfaceContainerLowest
        : Theme.of(context).colorScheme.surface;
    return InkWell(
      onTap: _inlineMode == null
          ? () => _openPropertyDetail(context, property)
          : null,
      child: _buildPropertyRowContainer(
        context: context,
        color: rowColor,
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Center(
                child: Checkbox(
                  value: _selectedPropertyIds.contains(property.id),
                  onChanged: (checked) =>
                      _togglePropertySelection(property, checked ?? false),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
            _buildListCell(
              'name',
              InlineEditCell(
                value: property.name,
                placeholder: 'e.g., Dwelling, Unit, Suite',
                required: true,
                suggestions: _propertyStructureSuggestions,
                onSave: (value) => _updatePropertyInline(property, name: value),
              ),
            ),
            _buildListCell(
              'identifier',
              InlineEditCell(
                value: property.identifier,
                displayStyle: const TextStyle(fontWeight: FontWeight.w600),
                placeholder: 'e.g., A, 101',
                required: true,
                suggestions: _propertyStructureSuggestions,
                onSave: (value) =>
                    _updatePropertyInline(property, identifier: value),
              ),
            ),
            _buildListCell(
              'level',
              InlineEditCell(
                value: property.floor ?? '',
                placeholder: 'e.g., 1st, Ground, Basement',
                onSave: (value) =>
                    _updatePropertyInline(property, floor: value),
              ),
            ),
            _buildListCell(
              'occupancy',
              InlineEditCell(
                value: property.occupant ?? '',
                placeholder: 'Occupancy',
                onSave: (value) =>
                    _updatePropertyInline(property, occupant: value),
              ),
            ),
            _buildListCell(
              'status',
              InlineDropdownCell<PropertyStatus>(
                value: property.status,
                items: PropertyStatus.values
                    .where((v) => v != PropertyStatus.archived)
                    .toList(),
                labelBuilder: (v) => v.displayName,
                itemBuilder: (v) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(v.icon, size: 14, color: v.color),
                    const SizedBox(width: 6),
                    Text(v.displayName),
                  ],
                ),
                onChanged: (status) {
                  if (status != null) {
                    _updatePropertyInline(property, status: status);
                  }
                },
              ),
            ),
            _buildListCell(
              'areas',
              Text(
                '${property.areaCount}',
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _buildListCell(
              'drying',
              Text(
                '${property.dryAreaCount}/${property.areaCount}',
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: property.isDryingComplete
                      ? AppColors.success
                      : AppColors.warning,
                ),
              ),
            ),
            _buildListCell(
              'contents',
              Text(
                '${property.contentsCount}',
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _buildListCell(
              'tasks',
              _buildTasksCell(property.id),
            ),
            _buildListCell(
              'updated',
              Text(dateFormat.format(property.updatedAt)),
            ),
            _buildListCell('actions', _buildRowActions(context, property)),
          ],
        ),
      ),
    );
  }

  Widget _buildPropertyRowContainer({
    required BuildContext context,
    required Color color,
    required Widget child,
    bool isAutoHeight = false,
  }) {
    final divider = TableViewStyles.rowDivider(context);
    return TreeRowContainer(
      color: color,
      rightBorder: divider,
      bottomBorder: divider,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      height: isAutoHeight ? null : 48,
      child: child,
    );
  }

  void _togglePropertySelection(Property property, bool selected) {
    setState(() {
      if (selected) {
        _selectedPropertyIds.add(property.id);
      } else {
        _selectedPropertyIds.remove(property.id);
      }
    });
  }

  void _toggleSelectAllVisible(List<Property> properties, bool selected) {
    setState(() {
      if (selected) {
        _selectedPropertyIds.addAll(properties.map((p) => p.id));
      } else {
        for (final property in properties) {
          _selectedPropertyIds.remove(property.id);
        }
      }
    });
  }

  void _clearPropertySelection() {
    setState(() => _selectedPropertyIds.clear());
  }

  Future<void> _showPropertyMassEditDialog(BuildContext context) async {
    final selectedProperties = _selectedPropertyIds
        .map((id) => _latestPropertiesById[id])
        .whereType<Property>()
        .toList(growable: false);
    if (selectedProperties.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No selected properties found')),
      );
      return;
    }

    var applyStatus = false;
    var applyLevel = false;
    var applyOccupancy = false;
    var selectedStatus = PropertyStatus.pending;
    final levelController = TextEditingController();
    final occupancyController = TextEditingController();

    final shouldApply = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: Text(
                'Mass Edit ${selectedProperties.length} Propert${selectedProperties.length == 1 ? 'y' : 'ies'}',
              ),
              content: SizedBox(
                width: (MediaQuery.of(dialogContext).size.width - 48)
                    .clamp(0.0, 460.0),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CheckboxListTile(
                        value: applyStatus,
                        onChanged: (value) =>
                            setDialogState(() => applyStatus = value ?? false),
                        title: const Text('Status'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      if (applyStatus)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: DropdownButtonFormField<PropertyStatus>(
                            borderRadius: AppRadius.cardRadius,
                            initialValue: selectedStatus,
                            isExpanded: true,
                            items: PropertyStatus.values
                                .where(
                                  (status) => status != PropertyStatus.archived,
                                )
                                .map(
                                  (status) => DropdownMenuItem(
                                    value: status,
                                    child: Text(status.displayName),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: (value) {
                              if (value == null) return;
                              setDialogState(() => selectedStatus = value);
                            },
                          ),
                        ),
                      CheckboxListTile(
                        value: applyLevel,
                        onChanged: (value) =>
                            setDialogState(() => applyLevel = value ?? false),
                        title: const Text('Level'),
                        subtitle: const Text('Leave blank to clear level'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      if (applyLevel)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TextField(
                            controller: levelController,
                            decoration: const InputDecoration(
                              labelText: 'Level',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      CheckboxListTile(
                        value: applyOccupancy,
                        onChanged: (value) => setDialogState(
                          () => applyOccupancy = value ?? false,
                        ),
                        title: const Text('Occupancy'),
                        subtitle: const Text('Leave blank to clear occupancy'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      if (applyOccupancy)
                        TextField(
                          controller: occupancyController,
                          decoration: const InputDecoration(
                            labelText: 'Occupancy',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final hasChanges =
                        applyStatus || applyLevel || applyOccupancy;
                    if (!hasChanges) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Select at least one field to edit'),
                        ),
                      );
                      return;
                    }
                    Navigator.of(dialogContext).pop(true);
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );

    if (shouldApply != true) {
      levelController.dispose();
      occupancyController.dispose();
      return;
    }

    setState(() => _isBulkUpdatingProperties = true);
    try {
      final levelValue = levelController.text.trim();
      final occupancyValue = occupancyController.text.trim();
      final now = DateTime.now();
      final updates = <Future<void>>[
        for (final property in selectedProperties)
          ServiceLocator.propertyService.updateProperty(
            property.copyWith(
              status: applyStatus ? selectedStatus : property.status,
              floor: applyLevel
                  ? (levelValue.isEmpty ? null : levelValue)
                  : property.floor,
              occupant: applyOccupancy
                  ? (occupancyValue.isEmpty ? null : occupancyValue)
                  : property.occupant,
              updatedAt: now,
            ),
          ),
      ];

      await Future.wait(updates);

      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
          content: Text(
            'Updated ${selectedProperties.length} propert${selectedProperties.length == 1 ? 'y' : 'ies'}',
          ),
        ),
      );
      _clearPropertySelection();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
          content: Text('Failed to apply mass edit: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      levelController.dispose();
      occupancyController.dispose();
      if (mounted) setState(() => _isBulkUpdatingProperties = false);
    }
  }

  Future<void> _updatePropertyInline(
    Property original, {
    String? identifier,
    String? name,
    String? floor,
    String? occupant,
    PropertyStatus? status,
  }) async {
    final nextIdentifier = identifier?.trim() ?? original.identifier;
    final nextName = name?.trim() ?? original.name;
    final nextFloor = floor != null ? floor.trim() : (original.floor ?? '');
    final nextOccupant = occupant != null
        ? occupant.trim()
        : (original.occupant ?? '');
    final nextStatus = status ?? original.status;

    if (nextIdentifier.isEmpty || nextName.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Identifier and name are required')),
      );
      return;
    }

    final changed =
        nextIdentifier != original.identifier ||
        nextName != original.name ||
        nextFloor != (original.floor ?? '') ||
        nextOccupant != (original.occupant ?? '') ||
        nextStatus != original.status;
    if (!changed) return;

    if (nextIdentifier != original.identifier) {
      final isUnique = await ServiceLocator.propertyService.isIdentifierUnique(
        widget.project.id,
        nextIdentifier,
        original.id,
        workspaceId: widget.project.workspaceId,
      );
      if (!isUnique) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Identifier already exists')),
        );
        return;
      }
    }

    try {
      await ServiceLocator.propertyService.updateProperty(
        original.copyWith(
          identifier: nextIdentifier,
          name: nextName,
          floor: nextFloor.isEmpty ? null : nextFloor,
          occupant: nextOccupant.isEmpty ? null : nextOccupant,
          status: nextStatus,
          updatedAt: DateTime.now(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update property: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Widget _buildListCell(String columnId, Widget child) {
    final column = _propertyTableColumns.firstWhere((c) => c.id == columnId);
    return SizedBox(
      width: _propertyColumnWidths[columnId] ?? column.defaultWidth,
      child: Align(
        alignment: switch (column.align) {
          TextAlign.center => Alignment.center,
          TextAlign.right => Alignment.centerRight,
          _ => Alignment.centerLeft,
        },
        child: child,
      ),
    );
  }

  Widget _buildCardView(BuildContext context, List<Property> properties) {
    return EntityCardGrid(
      padding: const EdgeInsets.all(AppSpacing.xl),
      maxCardWidth: 350,
      spacing: 16,
      itemCount: properties.length,
      itemBuilder: (context, index, _) =>
          _buildPropertyCard(context, properties[index]),
      trailingBuilder: (context, cardWidth) => EntityCreateCard(
        title: 'Add Property',
        subtitle: kIsWeb ? 'Click to add a new property' : 'Tap to add a new property',
        size: EntityCreateCardSize.compact,
        minHeight: _getCreateCardHeight(cardWidth),
        onTap: () => _startAddProperty(context),
      ),
    );
  }

  Widget _buildPropertyCard(BuildContext context, Property property) {
    final dateFormat = DateFormat('MMM d');

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r12)),
      child: InkWell(
        onTap: () => _openPropertyDetail(context, property),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              color: property.status.color.withAlpha(25),
              child: Row(
                children: [
                  Icon(Icons.home_work, color: property.status.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          property.identifier,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          property.name,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  _buildRowActions(context, property),
                ],
              ),
            ),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PropertyStatusBadge(status: property.status),
                    const Spacer(),
                    // Stats row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildStatItem(
                          Icons.room,
                          '${property.areaCount}',
                          'Areas',
                        ),
                        _buildStatItem(
                          Icons.air,
                          '${property.dryAreaCount}/${property.areaCount}',
                          'Drying',
                          color: property.isDryingComplete
                              ? AppColors.success
                              : AppColors.warning,
                        ),
                        _buildStatItem(
                          Icons.inventory_2,
                          '${property.contentsCount}',
                          'Items',
                        ),
                      ],
                    ),
                    // Task progress row
                    if (_taskMetrics[property.id] case final m
                        when m != null && m.totalCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Tooltip(
                          message: widget.onOpenTasksForProperty != null
                              ? 'View tasks for this property'
                              : '',
                          child: InkWell(
                            onTap: widget.onOpenTasksForProperty == null
                                ? null
                                : () => widget.onOpenTasksForProperty!(
                                      property.id,
                                    ),
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.task_alt,
                                          size: 12, color: m.taskColor),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${m.completedCount}/${m.totalCount} tasks',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: m.taskColor,
                                          fontWeight: m.isFullyComplete
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                        ),
                                      ),
                                      if (m.hasOverdue) ...[
                                        const SizedBox(width: 8),
                                        Text(
                                          '${m.overdueCount} overdue',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: AppColors.error),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  LinearProgressIndicator(
                                    value: m.progressPercent / 100,
                                    minHeight: 3,
                                    backgroundColor:
                                        m.taskColor.withValues(alpha: 0.15),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        m.taskColor),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    const Spacer(),
                    // Footer
                    if (property.occupant != null)
                      Text(
                        property.occupant!,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Updated ${dateFormat.format(property.updatedAt)}',
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
    IconData icon,
    String value,
    String label, {
    Color? color,
  }) {
    return Column(
      children: [
        Icon(icon, size: 16, color: color ?? AppColors.textSecondary),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: AppColors.textTertiary),
        ),
      ],
    );
  }

  Widget _buildTasksCell(String propertyId) {
    final m = _taskMetrics[propertyId];
    if (m == null || m.totalCount == 0) {
      return Text(
        '—',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
      );
    }
    final canTap = widget.onOpenTasksForProperty != null;
    final text = Text(
      '${m.completedCount}/${m.totalCount}',
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13,
        color: m.isFullyComplete ? m.taskColor : null,
        fontWeight: m.isFullyComplete ? FontWeight.w600 : FontWeight.normal,
        decoration: canTap ? TextDecoration.underline : null,
        decorationColor: AppColors.textTertiary,
      ),
    );
    if (!canTap) return text;
    return Tooltip(
      message: 'View tasks for this property',
      child: InkWell(
        onTap: () => widget.onOpenTasksForProperty!(propertyId),
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: Center(child: text),
      ),
    );
  }

  Widget _buildRowActions(BuildContext context, Property property) {
    return PopupMenuButton<String>(
      icon: const Icon(
        Icons.more_horiz,
        size: 18,
        color: AppColors.textTertiary,
      ),
      padding: EdgeInsets.zero,
      iconSize: 18,
      offset: const Offset(0, 32),
      onSelected: (action) async {
        switch (action) {
          case 'view':
            _openPropertyDetail(context, property);
            break;
          case 'inline_edit':
            _startInlineEdit(property);
            break;
          case 'edit':
            _showPropertyForm(context, property);
            break;
          case 'plans':
            context.push(
              '/projects/${property.projectId}/plans?property=${property.id}',
            );
            break;
          case 'duplicate':
            await _duplicateProperty(context, property);
            break;
          case 'archive':
            await _archiveProperty(context, property);
            break;
          case 'delete':
            await _deleteProperty(context, property);
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'view',
          child: Row(
            children: [
              Icon(Icons.visibility_outlined, size: 16),
              SizedBox(width: 8),
              Text('View Details'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'inline_edit',
          child: Row(
            children: [
              Icon(Icons.edit_note, size: 16),
              SizedBox(width: 8),
              Text('Inline Edit'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 16),
              SizedBox(width: 8),
              Text('Edit Full Details'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'plans',
          child: Row(
            children: [
              Icon(Icons.architecture, size: 16),
              SizedBox(width: 8),
              Text('View Plans'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'duplicate',
          child: Row(
            children: [
              Icon(Icons.copy_outlined, size: 16),
              SizedBox(width: 8),
              Text('Duplicate'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'archive',
          enabled: property.status != PropertyStatus.archived,
          child: Row(
            children: [
              Icon(Icons.archive_outlined, size: 16),
              const SizedBox(width: 8),
              Text('Archive'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 16, color: AppColors.error),
              const SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: AppColors.error)),
            ],
          ),
        ),
      ],
    );
  }

  void _startInlineAdd() {
    setState(() {
      _isCardView = false;
      _isElevationView = false;
      _inlineMode = _inlineModeAdd;
      _inlineEditingPropertyId = null;
      _inlineStatus = PropertyStatus.pending;
      _inlineIdentifierController.clear();
      _inlineNameController.clear();
      _inlineLevelController.clear();
      _inlineOccupancyController.clear();
    });
  }

  void _startAddProperty(BuildContext context) {
    if (AppBreakpoints.isMobileContext(context)) {
      if (_inlineMode != null) {
        _cancelInlineEdit();
      }
      _showPropertyForm(context, null);
      return;
    }
    _startInlineAdd();
  }

  void _startInlineEdit(Property property) {
    setState(() {
      _isCardView = false;
      _isElevationView = false;
      _inlineMode = _inlineModeEdit;
      _inlineEditingPropertyId = property.id;
      _inlineStatus = property.status;
      _inlineIdentifierController.text = property.identifier;
      _inlineNameController.text = property.name;
      _inlineLevelController.text = property.floor ?? '';
      _inlineOccupancyController.text = property.occupant ?? '';
    });
  }

  void _cancelInlineEdit() {
    setState(() {
      _inlineMode = null;
      _inlineEditingPropertyId = null;
      _isInlineSavingProperty = false;
    });
  }

  void _cancelInlineEditIfAllowed() {
    if (_isInlineSavingProperty || _inlineMode == null) return;
    // Don't cancel if a popup/dropdown overlay is currently open on top of this route.
    if (ModalRoute.of(context)?.isCurrent == false) return;
    _cancelInlineEdit();
  }

  Future<void> _saveInlineProperty() async {
    if (_isInlineSavingProperty) return;

    final providedIdentifier = _inlineIdentifierController.text.trim();
    final providedName = _inlineNameController.text.trim();
    if (providedIdentifier.isEmpty && providedName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a structure name or number')),
      );
      return;
    }
    // Number is optional: derive whichever of name/identifier is blank from the
    // other so a name-only (or number-only) entry saves from the checkmark.
    final name = providedName.isEmpty ? providedIdentifier : providedName;
    final identifier = providedIdentifier.isEmpty
        ? providedName
        : providedIdentifier;
    final floor = _inlineLevelController.text.trim();
    final occupant = _inlineOccupancyController.text.trim();

    setState(() => _isInlineSavingProperty = true);
    try {
      final isEditing = _inlineMode == _inlineModeEdit;
      final isUnique = await ServiceLocator.propertyService.isIdentifierUnique(
        widget.project.id,
        identifier,
        isEditing ? _inlineEditingPropertyId : null,
        workspaceId: widget.project.workspaceId,
      );
      if (!isUnique) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Identifier already exists')),
          );
        }
        return;
      }

      final now = DateTime.now();
      if (isEditing) {
        final editingId = _inlineEditingPropertyId;
        if (editingId == null) {
          throw StateError('Missing property id for inline edit');
        }
        final existingProperty = await ServiceLocator.propertyService
            .getProperty(editingId);
        if (existingProperty == null) {
          throw StateError('Property no longer exists');
        }
        await ServiceLocator.propertyService.updateProperty(
          existingProperty.copyWith(
            name: name,
            identifier: identifier,
            floor: floor.isEmpty ? null : floor,
            occupant: occupant.isEmpty ? null : occupant,
            status: _inlineStatus,
            updatedAt: now,
          ),
        );
      } else {
        await ServiceLocator.propertyService.createProperty(
          Property(
            id: '',
            workspaceId: widget.project.workspaceId,
            projectId: widget.project.id,
            name: name,
            identifier: identifier,
            floor: floor.isEmpty ? null : floor,
            occupant: occupant.isEmpty ? null : occupant,
            status: _inlineStatus,
            areaCount: 0,
            dryAreaCount: 0,
            contentsCount: 0,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isEditing ? 'Structure updated' : 'Structure created'),
        ),
      );
      setState(() {
        _inlineMode = null;
        _inlineEditingPropertyId = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create property: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isInlineSavingProperty = false);
      }
    }
  }

  void _showPropertyForm(BuildContext context, Property? property) {
    showPropertyFormPopup(
      context,
      project: widget.project,
      existingProperty: property,
    );
  }

  void _openPropertyDetail(BuildContext context, Property property) {
    setState(() {
      _selectedPropertyId = property.id;
    });
  }

  Future<void> _duplicateProperty(
    BuildContext context,
    Property property,
  ) async {
    // Show dialog to get new identifier
    final identifierController = TextEditingController(
      text: '${property.identifier}-copy',
    );

    final newIdentifier = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Duplicate Property'),
        content: StackedField(
          label: 'New Identifier',
          child: TextField(
            controller: identifierController,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, identifierController.text),
            child: const Text('Duplicate'),
          ),
        ],
      ),
    );

    if (newIdentifier != null && newIdentifier.isNotEmpty && context.mounted) {
      try {
        await ServiceLocator.propertyService.duplicateProperty(
          property.id,
          newIdentifier,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Property duplicated')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                UserFacingError.uiMessage(e, action: 'complete this action'),
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _archiveProperty(BuildContext context, Property property) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive Property'),
        content: Text(
          'Are you sure you want to archive "${property.displayLabel}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.warning),
            child: const Text('Archive'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await ServiceLocator.propertyService.archiveProperty(property.id);
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Property archived')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                UserFacingError.uiMessage(e, action: 'complete this action'),
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteProperty(BuildContext context, Property property) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Property'),
        content: Text(
          'Are you sure you want to delete "${property.displayLabel}"? This action cannot be undone.',
        ),
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

    if (confirmed == true && context.mounted) {
      try {
        await ServiceLocator.propertyService.deleteProperty(property.id);
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Property deleted')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                UserFacingError.uiMessage(e, action: 'complete this action'),
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  double _getCreateCardHeight(double cardWidth) {
    if (cardWidth < 280) return 200;
    if (cardWidth < 340) return 220;
    return 240;
  }
}

class _PropertyFilterDialog extends StatefulWidget {
  final PropertyStatus? selectedStatus;
  final ValueChanged<PropertyStatus?> onApply;

  const _PropertyFilterDialog({
    required this.selectedStatus,
    required this.onApply,
  });

  @override
  State<_PropertyFilterDialog> createState() => _PropertyFilterDialogState();
}

class _PropertyFilterDialogState extends State<_PropertyFilterDialog> {
  late PropertyStatus? _status;

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
                  if (_status != null)
                    TextButton(
                      onPressed: () => setState(() => _status = null),
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
                      color: _status != null
                          ? AppColors.primary.withValues(alpha: 0.04)
                          : AppColors.surfaceAlt.withValues(alpha: 0.5),
                      border: Border.all(
                        color: _status != null
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
                          color: _status != null
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
                          _status?.displayName ?? 'All',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        initiallyExpanded: true,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                ChoiceChip(
                                  label: const Text('All'),
                                  selected: _status == null,
                                  onSelected: (_) =>
                                      setState(() => _status = null),
                                ),
                                ...PropertyStatus.values.map(
                                  (s) => ChoiceChip(
                                    label: Text(s.displayName),
                                    avatar: Icon(
                                      s.icon,
                                      size: 14,
                                      color: s.color,
                                    ),
                                    selected: _status == s,
                                    onSelected: (_) =>
                                        setState(() => _status = s),
                                  ),
                                ),
                              ],
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
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
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
