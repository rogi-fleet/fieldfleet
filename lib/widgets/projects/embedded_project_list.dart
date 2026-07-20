import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/customer.dart';
import '../../models/project.dart';
import '../../models/project_financial_summary.dart';
import '../../models/project_status_theme.dart';
import '../../models/project_task_metrics.dart';
import '../../models/task.dart';
import '../../models/user.dart';
import 'package:go_router/go_router.dart';
import '../../providers/workspace_provider.dart';
import '../../screens/projects/widgets/active_alerts_widget.dart';
import '../../screens/projects/widgets/project_card.dart';
import '../../screens/projects/widgets/project_filters.dart';
import '../../screens/projects/widgets/project_table_row.dart';
import '../../screens/projects/widgets/view_toggle_button.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/project_customer_name.dart';
import '../../utils/project_terminology.dart';
import '../common/zero_items_action_empty_state.dart';
import '../common/entity_card_grid.dart';
import '../common/view_icon_button.dart';
import '../common/view_toolbar.dart';
import '../project_form_popup.dart';
import '../timeline/project_calendar_widget.dart';
import 'kanban_project_board_view.dart';
import '../table/table_column_schema.dart';
import '../table/table_header_cells_builder.dart';
import '../table/table_header_row.dart';
import '../table/table_layout_shell.dart';
import '../table/table_view_styles.dart';

/// A reusable project list widget that can be embedded in tabs (e.g. customer
/// or vendor detail screens). Provides the same card/table view toggle, search,
/// and sort as the top-level projects screen, but without workspace-level
/// features like saved views, bulk selection, or favorites.
class EmbeddedProjectList extends StatefulWidget {
  /// Supply exactly one of [projectStream] or [projectFuture].
  final Stream<List<Project>>? projectStream;
  final Future<List<Project>>? projectFuture;

  /// When set, the "Create Project" CTA pre-selects this customer.
  final String? createProjectCustomerId;

  /// When set, the "Create Project" CTA pre-selects this vendor.
  final String? createProjectVendorId;

  /// Label for the empty-state CTA (e.g. "Create Project for Acme").
  final String? createProjectLabel;

  /// Whether to show a "Create Project" button in the empty state.
  final bool showCreateButton;

  /// When true, uses the animated empty-state CTA style.
  final bool animatedCreateButton;

  const EmbeddedProjectList({
    super.key,
    this.projectStream,
    this.projectFuture,
    this.createProjectCustomerId,
    this.createProjectVendorId,
    this.createProjectLabel,
    this.showCreateButton = true,
    this.animatedCreateButton = false,
  }) : assert(
         projectStream != null || projectFuture != null,
         'Provide projectStream or projectFuture',
       );

  @override
  State<EmbeddedProjectList> createState() => _EmbeddedProjectListState();
}

class _EmbeddedProjectListState extends State<EmbeddedProjectList> {
  ProjectViewType _currentView = ProjectViewType.card;
  bool _isLoading = true;
  String _searchQuery = '';
  ProjectSortOption _selectedSort = ProjectSortOption.recent;
  ProjectStatus? _selectedStatus;
  String? _tableSortColumn;
  bool _tableSortAscending = true;
  final Map<String, double> _columnWidths = {};

  void _handleColumnResize(TableColumnResize resize) {
    setState(() {
      _columnWidths[resize.columnId] = resize.width;
    });
  }

  List<Project> _allProjects = [];
  StreamSubscription<List<Project>>? _streamSub;

  // Cached futures keyed by project id — pruned when the project list changes.
  final Map<String, Future<ProjectFinancialSummary>> _financialsFutures = {};
  final Map<String, Future<List<Task>>> _tasksFutures = {};
  final Map<String, Future<List<ProjectAlert>>> _alertsFutures = {};
  final Map<String, Future<Customer?>> _customerFutures = {};
  Map<String, ProjectTaskMetrics> _taskMetricsByProject = {};
  bool _isLoadingTaskMetrics = false;
  Future<Map<String, AppUser>>? _workspaceUsersFuture;

  @override
  void initState() {
    super.initState();
    _initViewPreference();
    _subscribe();
  }

  @override
  void didUpdateWidget(EmbeddedProjectList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-subscribe when the data source identity changes.
    if (widget.projectStream != oldWidget.projectStream ||
        widget.projectFuture != oldWidget.projectFuture) {
      _streamSub?.cancel();
      _streamSub = null;
      _subscribe();
    }
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    super.dispose();
  }

  Future<void> _initViewPreference() async {
    final saved = await ViewToggleButton.loadPreference();
    if (mounted) setState(() => _currentView = saved);
  }

  void _subscribe() {
    if (widget.projectStream != null) {
      _streamSub = widget.projectStream!.listen(
        (projects) {
          if (!mounted) return;
          _onProjectsLoaded(projects);
        },
        onError: (_) {
          if (mounted) setState(() => _isLoading = false);
        },
      );
    } else if (widget.projectFuture != null) {
      widget.projectFuture!
          .then((projects) {
            if (!mounted) return;
            _onProjectsLoaded(projects);
          })
          .catchError((_) {
            if (mounted) setState(() => _isLoading = false);
          });
    }
  }

  void _onProjectsLoaded(List<Project> projects) {
    _pruneStaleCache(projects);
    setState(() {
      _allProjects = projects;
      _isLoading = false;
    });
    _loadTaskMetrics(projects);
    _ensureWorkspaceUsers(projects);
  }

  /// Remove cached futures for projects no longer in the list.
  void _pruneStaleCache(List<Project> projects) {
    final currentIds = projects.map((p) => p.id).toSet();
    _financialsFutures.removeWhere((k, _) => !currentIds.contains(k));
    _tasksFutures.removeWhere((k, _) => !currentIds.contains(k));
    _alertsFutures.removeWhere((k, _) => !currentIds.contains(k));
    // Customer futures are keyed by customerId, not projectId — leave them.
  }

  Future<void> _loadTaskMetrics(List<Project> projects) async {
    if (projects.isEmpty) return;
    final workspaceId = projects.first.workspaceId;
    setState(() => _isLoadingTaskMetrics = true);
    try {
      final metrics =
          await ServiceLocator.taskService.getProjectListMetrics(workspaceId)
              as Map<String, ProjectTaskMetrics>;
      if (!mounted) return;
      setState(() {
        _taskMetricsByProject = metrics;
        _isLoadingTaskMetrics = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _taskMetricsByProject = {};
          _isLoadingTaskMetrics = false;
        });
      }
    }
  }

  void _ensureWorkspaceUsers(List<Project> projects) {
    if (projects.isEmpty || _workspaceUsersFuture != null) return;
    _workspaceUsersFuture = ServiceLocator.userService.getWorkspaceUsersMap(
      projects.first.workspaceId,
    );
  }

  Future<ProjectFinancialSummary> _financialsFutureFor(Project project) {
    return _financialsFutures.putIfAbsent(
      project.id,
      () =>
          ServiceLocator.projectService.getProjectFinancials(
                project.id,
                project,
              )
              as Future<ProjectFinancialSummary>,
    );
  }

  Future<List<Task>> _tasksFutureFor(Project project) {
    return _tasksFutures.putIfAbsent(
      project.id,
      () => ServiceLocator.taskService
          .getTasks(project.id, workspaceId: project.workspaceId)
          .first,
    );
  }

  Future<List<ProjectAlert>> _alertsFutureFor(Project project) {
    return _alertsFutures.putIfAbsent(project.id, () async {
      try {
        final financials = await _financialsFutureFor(project);
        return ProjectAlertsEngine.generateAlerts(
          project,
          financialSummary: financials,
        );
      } catch (_) {
        return ProjectAlertsEngine.generateAlerts(project);
      }
    });
  }

  Future<Customer?>? _customerFutureFor(Project project) {
    final customerId = project.clientId;
    if (customerId == null ||
        customerId.isEmpty ||
        !projectCustomerNeedsRefresh(project)) {
      return null;
    }
    return _customerFutures.putIfAbsent(
      customerId,
      () => ServiceLocator.customerService.getCustomer(customerId),
    );
  }

  List<Project> _filterAndSort(List<Project> projects) {
    var filtered = projects.where((project) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matches =
            project.name.toLowerCase().contains(q) ||
            project.address.toLowerCase().contains(q) ||
            (project.description?.toLowerCase().contains(q) ?? false) ||
            (project.customerName?.toLowerCase().contains(q) ?? false) ||
            (project.primaryContactName?.toLowerCase().contains(q) ?? false) ||
            (project.purchaseOrderNumber?.toLowerCase().contains(q) ?? false) ||
            (project.serialNumber?.toLowerCase().contains(q) ?? false);
        if (!matches) return false;
      }
      if (_selectedStatus != null && project.status != _selectedStatus) {
        return false;
      }
      return true;
    }).toList();

    if (_tableSortColumn != null && _currentView == ProjectViewType.table) {
      final asc = _tableSortAscending;
      filtered.sort((a, b) {
        int cmp;
        switch (_tableSortColumn) {
          case 'id':
            cmp = compareProjectTableIds(a, b);
          case 'project':
            cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          case 'customer':
            cmp = (a.customerName ?? '').toLowerCase().compareTo(
              (b.customerName ?? '').toLowerCase(),
            );
          case 'status':
            cmp = a.status.displayName.toLowerCase().compareTo(
              b.status.displayName.toLowerCase(),
            );
          case 'budget':
            cmp = (a.estimatedBudget ?? 0).compareTo(b.estimatedBudget ?? 0);
          case 'tasks':
            final aM = _taskMetricsByProject[a.id];
            final bM = _taskMetricsByProject[b.id];
            cmp = (aM?.totalCount ?? 0).compareTo(bM?.totalCount ?? 0);
          case 'timeline':
            final aD = a.startDate ?? a.createdAt;
            final bD = b.startDate ?? b.createdAt;
            cmp = aD.compareTo(bD);
          case 'progress':
            final aM = _taskMetricsByProject[a.id];
            final bM = _taskMetricsByProject[b.id];
            cmp = (aM?.progressPercent ?? 0).compareTo(
              bM?.progressPercent ?? 0,
            );
          default:
            cmp = 0;
        }
        return asc ? cmp : -cmp;
      });
    } else {
      switch (_selectedSort) {
        case ProjectSortOption.recent:
          filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        case ProjectSortOption.nameAsc:
          filtered.sort((a, b) => a.name.compareTo(b.name));
        case ProjectSortOption.nameDesc:
          filtered.sort((a, b) => b.name.compareTo(a.name));
        case ProjectSortOption.budgetHigh:
          filtered.sort(
            (a, b) =>
                (b.estimatedBudget ?? 0).compareTo(a.estimatedBudget ?? 0),
          );
        case ProjectSortOption.budgetLow:
          filtered.sort(
            (a, b) =>
                (a.estimatedBudget ?? 0).compareTo(b.estimatedBudget ?? 0),
          );
      }
    }

    return filtered;
  }

  int get _activeFilterCount => _selectedStatus != null ? 1 : 0;

  @override
  Widget build(BuildContext context) {
    final pluralTerminology = context
        .watch<WorkspaceProvider>()
        .projectTerminology;
    final singularTerminology = singularProjectTerminology(pluralTerminology);

    return Column(
      children: [
        _buildToolbar(pluralTerminology),
        const Divider(height: 1),
        Expanded(child: _buildBody(pluralTerminology, singularTerminology)),
      ],
    );
  }

  Widget _buildToolbar(String pluralTerminology) {
    return ViewToolbar(
      searchHint: 'Search ${pluralTerminology.toLowerCase()}...',
      searchQuery: _searchQuery,
      onSearch: (query) => setState(() => _searchQuery = query),
      centerSlot: _buildViewToggle(),
      quickToggles: [_buildSortToggle()],
      filterCount: _activeFilterCount,
      onFilterTap: _showStatusFilterDialog,
    );
  }

  Widget _buildViewToggle() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ViewIconButton(
          icon: Icons.grid_view,
          tooltip: 'Cards',
          isSelected: _currentView == ProjectViewType.card,
          onTap: () => setState(() => _currentView = ProjectViewType.card),
        ),
        ViewIconButton(
          icon: Icons.view_list,
          tooltip: 'Table',
          isSelected: _currentView == ProjectViewType.table,
          onTap: () => setState(() => _currentView = ProjectViewType.table),
        ),
        ViewIconButton(
          icon: Icons.view_kanban,
          tooltip: 'Board',
          isSelected: _currentView == ProjectViewType.board,
          onTap: () => setState(() => _currentView = ProjectViewType.board),
        ),
        ViewIconButton(
          icon: Icons.calendar_month,
          tooltip: 'Calendar',
          isSelected: _currentView == ProjectViewType.calendar,
          onTap: () => setState(() => _currentView = ProjectViewType.calendar),
        ),
      ],
    );
  }

  Widget _buildSortToggle() {
    return PopupMenuButton<ProjectSortOption>(
      onSelected: (sort) => setState(() => _selectedSort = sort),
      tooltip: 'Sort',
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 180),
      child: Builder(
        builder: (context) {
          final chrome = ChromeColors.of(context);
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: chrome.subtleBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sort, size: 16, color: chrome.text),
                const SizedBox(width: 6),
                Text(
                  _selectedSort.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: chrome.textActive,
                  ),
                ),
                Icon(Icons.arrow_drop_down, size: 18, color: chrome.text),
              ],
            ),
          );
        },
      ),
      itemBuilder: (context) => [
        for (final option in ProjectSortOption.values)
          PopupMenuItem<ProjectSortOption>(
            value: option,
            height: 40,
            child: Row(
              children: [
                Text(
                  option.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: option == _selectedSort
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: option == _selectedSort ? AppColors.primary : null,
                  ),
                ),
                const Spacer(),
                if (option == _selectedSort)
                  const Icon(Icons.check, size: 18, color: AppColors.primary),
              ],
            ),
          ),
      ],
    );
  }

  void _showStatusFilterDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return _StatusFilterDialog(
          selectedStatus: _selectedStatus,
          onApply: (status) {
            setState(() => _selectedStatus = status);
            Navigator.of(ctx).pop();
          },
        );
      },
    );
  }

  Widget _buildBody(String pluralTerminology, String singularTerminology) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final projects = _filterAndSort(_allProjects);

    if (projects.isEmpty) {
      return _buildEmptyState(pluralTerminology, singularTerminology);
    }

    switch (_currentView) {
      case ProjectViewType.table:
        return _buildTableView(projects, singularTerminology);
      case ProjectViewType.board:
        return _buildBoardView(projects);
      case ProjectViewType.calendar:
        return _buildCalendarView(projects);
      case ProjectViewType.card:
      case ProjectViewType.gantt:
        return _buildCardView(projects);
    }
  }

  Widget _buildEmptyState(
    String pluralTerminology,
    String singularTerminology,
  ) {
    final hasFilters = _searchQuery.isNotEmpty || _selectedStatus != null;
    final createLabel =
        widget.createProjectLabel ?? 'Create $singularTerminology';
    void createAction() {
      showProjectFormPopup(
        context,
        initialCustomerId: widget.createProjectCustomerId,
        initialVendorId: widget.createProjectVendorId,
      );
    }

    if (!hasFilters && widget.showCreateButton && widget.animatedCreateButton) {
      return ZeroItemsActionEmptyState(
        icon: Icons.work_outline,
        title: 'No ${pluralTerminology.toLowerCase()} yet',
        subtitle:
            'Create a ${singularTerminology.toLowerCase()} to get started.',
        ctaLabel: createLabel,
        onTap: createAction,
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasFilters ? Icons.search_off : Icons.work_outline,
            size: 64,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            hasFilters
                ? 'No ${pluralTerminology.toLowerCase()} match your filters'
                : 'No ${pluralTerminology.toLowerCase()} yet',
          ),
          if (hasFilters) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _searchQuery = '';
                  _selectedStatus = null;
                });
              },
              icon: const Icon(Icons.clear_all),
              label: const Text('Clear Filters'),
            ),
          ] else if (widget.showCreateButton) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: createAction,
              icon: const Icon(Icons.add),
              label: Text(createLabel),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBoardView(List<Project> projects) {
    return KanbanProjectBoardView(
      projects: projects,
      taskMetricsByProject: _taskMetricsByProject,
      onProjectStatusChanged: (project, newStatus) async {
        if (project.status == newStatus) return;
        try {
          await ServiceLocator.projectService.updateProject(
            projectId: project.id,
            status: newStatus,
          );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(
                content: Text('Failed to update status: $e'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      },
    );
  }

  Widget _buildCalendarView(List<Project> projects) {
    return ProjectCalendarWidget(
      projects: projects,
      taskMetricsByProject: _taskMetricsByProject,
      onProjectTap: (project) => context.go('/projects/${project.id}'),
      onAddProjectForDate: widget.showCreateButton
          ? (date) => showProjectFormPopup(
              context,
              initialCustomerId: widget.createProjectCustomerId,
              initialVendorId: widget.createProjectVendorId,
              initialStartDate: date,
            )
          : null,
    );
  }

  Widget _buildCardView(List<Project> projects) {
    return EntityCardGrid(
      mobileColumns: 1,
      itemCount: projects.length,
      itemBuilder: (context, index, _) {
        final project = projects[index];
        return ProjectCard(
          project: project,
          forceCompactLayout: true,
          taskMetrics: _isLoadingTaskMetrics
              ? null
              : (_taskMetricsByProject[project.id] ??
                    ProjectTaskMetrics.empty(project.id)),
          customerFuture: _customerFutureFor(project),
          financialsFuture: _financialsFutureFor(project),
          tasksFuture: _tasksFutureFor(project),
          alertsFuture: _alertsFutureFor(project),
          workspaceUsersFuture: _workspaceUsersFuture,
        );
      },
    );
  }

  List<TableColumnSchema> _tableColumns(String singularTerminology) => [
    const TableColumnSchema(
      id: 'id',
      label: '#',
      defaultWidth: kProjectTableColId,
      resizable: false,
    ),
    TableColumnSchema(
      id: 'project',
      label: singularTerminology,
      defaultWidth: kProjectTableColProject,
      minWidth: 120,
      maxWidth: 500,
    ),
    const TableColumnSchema(
      id: 'customer',
      label: 'Customer',
      defaultWidth: kProjectTableColCustomer,
      minWidth: 100,
      maxWidth: 400,
    ),
    const TableColumnSchema(
      id: 'status',
      label: 'Status',
      defaultWidth: kProjectTableColStatus,
      minWidth: 80,
      maxWidth: 200,
    ),
    const TableColumnSchema(
      id: 'budget',
      label: 'Budget',
      defaultWidth: kProjectTableColBudget,
      minWidth: 80,
      maxWidth: 200,
    ),
    const TableColumnSchema(
      id: 'margin',
      label: 'Margin',
      defaultWidth: kProjectTableColMargin,
      minWidth: 80,
      maxWidth: 200,
    ),
    const TableColumnSchema(
      id: 'profit',
      label: 'Profit',
      defaultWidth: kProjectTableColProfit,
      minWidth: 80,
      maxWidth: 200,
    ),
    const TableColumnSchema(
      id: 'tasks',
      label: 'Tasks',
      defaultWidth: kProjectTableColTasks,
      minWidth: 80,
      maxWidth: 200,
    ),
    const TableColumnSchema(
      id: 'timeline',
      label: 'Dates',
      defaultWidth: kProjectTableColTimeline,
      minWidth: 100,
      maxWidth: 300,
    ),
    const TableColumnSchema(
      id: 'progress',
      label: 'Progress',
      defaultWidth: kProjectTableColProgress,
      minWidth: 80,
      maxWidth: 250,
    ),
  ];

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
    });
  }

  Widget _buildTableView(List<Project> projects, String singularTerminology) {
    final headerStyle = TableViewStyles.headerLabelStyle(context);

    final columns = _tableColumns(singularTerminology);
    final headerCells = buildTableHeaderCells(
      context: context,
      columns: columns,
      widths: {
        for (final c in columns)
          c.id: _columnWidths[c.id] ?? c.defaultWidth,
      },
      onColumnResize: _handleColumnResize,
      textStyle: headerStyle,
      onSortTap: (column) => _onColumnSortTap(column.id),
      sortedColumnId: _tableSortColumn,
      sortAscending: _tableSortAscending,
    );

    final headerChildren = <Widget>[];
    for (int i = 0; i < headerCells.length; i++) {
      if (i > 0) headerChildren.add(const SizedBox(width: kProjectTableColGap));
      headerChildren.add(headerCells[i]);
    }

    return TableLayoutShell(
      minTableWidth: 1450,
      header: TableHeaderRow(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
        children: headerChildren,
      ),
      body: ListView.builder(
        itemCount: projects.length,
        itemBuilder: (context, index) {
          final project = projects[index];
          return ProjectTableRow(
            project: project,
            columnWidths: _columnWidths,
            taskMetrics: _isLoadingTaskMetrics
                ? null
                : (_taskMetricsByProject[project.id] ??
                      ProjectTaskMetrics.empty(project.id)),
            financialsFuture: _financialsFutureFor(project),
            customerFuture: _customerFutureFor(project),
          );
        },
      ),
    );
  }
}

/// Simple status-only filter dialog for the embedded list.
class _StatusFilterDialog extends StatefulWidget {
  final ProjectStatus? selectedStatus;
  final void Function(ProjectStatus?) onApply;

  const _StatusFilterDialog({
    required this.selectedStatus,
    required this.onApply,
  });

  @override
  State<_StatusFilterDialog> createState() => _StatusFilterDialogState();
}

class _StatusFilterDialogState extends State<_StatusFilterDialog> {
  late ProjectStatus? _status;

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
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  const Text(
                    'Filter by Status',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (_status != null)
                    TextButton(
                      onPressed: () => setState(() => _status = null),
                      child: const Text('Clear'),
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
            Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _status == null,
                    onSelected: (_) => setState(() => _status = null),
                  ),
                  ...ProjectStatus.values.map((status) {
                    return ChoiceChip(
                      label: Text(status.displayName),
                      avatar: Icon(
                        Icons.circle,
                        size: 8,
                        color: ProjectStatusTheme.color(status),
                      ),
                      selected: _status == status,
                      onSelected: (_) => setState(() => _status = status),
                    );
                  }),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
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
