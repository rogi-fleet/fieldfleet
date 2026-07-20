import 'package:flutter/material.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/task.dart';
import '../../models/project.dart';
import '../../models/property.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../utils/project_terminology.dart';
import '../../theme/theme.dart';
import '../../utils/hierarchy_utils.dart';
import '../../utils/task_export.dart';
import '../../utils/task_filter_engine.dart';
import '../common/app_search_bar.dart';
import '../mass_edit_dialog.dart';
import '../task_form_popup.dart';
import '../common/view_icon_button.dart';
import '../table/table_column_schema.dart';
import '../table/table_dropdown_control.dart';
import '../table/table_header_cells_builder.dart';
import '../table/table_header_row.dart';
import '../table/table_view_styles.dart';
import 'task_list_toolbar.dart';
import 'task_group.dart';
import 'task_group_header.dart';
import 'task_row.dart' show TaskRow, DropZone;
import 'quick_add_row.dart';
import '../table/table_add_item_group_row.dart';
import '../table/table_summary_footer.dart';
import '../table/table_layout_shell.dart';
import 'mobile_task_card.dart';
import 'mobile_task_row.dart';
import '../common/zero_items_action_empty_state.dart';

enum TaskMetricFilter { open, overdue, dueToday }

/// Main orchestrator widget for the grouped task list view.
/// Used by both the project-level tasks tab and the workspace-wide All Tasks screen.
class GroupedTaskListView extends StatefulWidget {
  final String? projectId;
  final Project? externalProject;
  final String workspaceId;
  final GroupBy initialGroupBy;
  final TaskMetricFilter? initialMetricFilter;
  final bool showProjectColumn;

  const GroupedTaskListView({
    super.key,
    this.projectId,
    this.externalProject,
    required this.workspaceId,
    this.initialGroupBy = GroupBy.phase,
    this.initialMetricFilter,
    this.showProjectColumn = false,
    this.externalSearchQuery,
    this.externalPropertyFilterId,
    this.externalProjectFilterId,
    this.externalMyTasksOnly,
    this.externalHideDone,
    this.externalOverdueOnly,
    this.externalCustomerFilterId,
    this.externalPriorityFilter,
    this.externalAssigneeFilterId,
    this.externalDueDateStart,
    this.externalDueDateEnd,
    this.hideToolbarSearch = false,
    this.hideToolbarMyTasksFilter = false,
    this.hideToolbarHideDone = false,
    this.toolbarTrailingControl,
    this.forceCardView = false,
    this.externalAllExpanded,
  });

  final String? externalSearchQuery;
  final String? externalPropertyFilterId;
  final String? externalProjectFilterId;
  final bool? externalMyTasksOnly;
  final bool? externalHideDone;
  final bool? externalOverdueOnly;
  final String? externalCustomerFilterId;
  final String? externalPriorityFilter;
  final String? externalAssigneeFilterId;
  final DateTime? externalDueDateStart;
  final DateTime? externalDueDateEnd;
  final bool hideToolbarSearch;
  final bool hideToolbarMyTasksFilter;
  final bool hideToolbarHideDone;
  final Widget? toolbarTrailingControl;
  final bool forceCardView;

  /// When non-null, overrides the internal expand/collapse state and hides
  /// the expand/collapse button from [TaskListToolbar].
  final bool? externalAllExpanded;

  @override
  State<GroupedTaskListView> createState() => _GroupedTaskListViewState();
}

class _GroupedTaskListViewState extends State<GroupedTaskListView> {
  static const double _columnGap = 8;
  List<TableColumnSchema> _taskHeaderColumns(String projectLabel) => [
    TableColumnSchema(
      id: 'project',
      label: projectLabel,
      tooltip: projectLabel,
      defaultWidth: 200,
      minWidth: 120,
      maxWidth: 420,
    ),
    const TableColumnSchema(
      id: 'customer_name',
      label: 'Customer',
      tooltip: 'Customer Name',
      defaultWidth: 140,
      minWidth: 80,
      maxWidth: 300,
    ),
    const TableColumnSchema(
      id: 'job_number',
      label: 'Job #',
      tooltip: 'Job Number',
      defaultWidth: 90,
      minWidth: 60,
      maxWidth: 160,
    ),
    const TableColumnSchema(
      id: 'job_address',
      label: 'Address',
      tooltip: 'Job Address',
      defaultWidth: 160,
      minWidth: 80,
      maxWidth: 360,
    ),
    const TableColumnSchema(
      id: 'status',
      label: 'Status',
      defaultWidth: 116,
      minWidth: 90,
      maxWidth: 220,
    ),
    const TableColumnSchema(
      id: 'due_date',
      label: 'Due date',
      defaultWidth: 96,
      minWidth: 80,
      maxWidth: 180,
    ),
    const TableColumnSchema(
      id: 'assignee',
      label: 'Assignee',
      defaultWidth: 62,
      minWidth: 56,
      maxWidth: 180,
    ),
    const TableColumnSchema(
      id: 'notes',
      icon: Icons.sticky_note_2_outlined,
      tooltip: 'Notes',
      defaultWidth: 34,
      minWidth: 30,
      maxWidth: 120,
      align: TextAlign.center,
    ),
    const TableColumnSchema(
      id: 'progress',
      label: '%',
      defaultWidth: 52,
      minWidth: 40,
      maxWidth: 140,
      align: TextAlign.center,
    ),
  ];
  late GroupBy _groupBy;
  TaskMetricFilter? _metricFilter;
  String _searchQuery = '';
  bool _searchExpanded = false;
  bool _hideDoneInternal = true;
  bool get _hideDone => widget.externalHideDone ?? _hideDoneInternal;
  bool? _myTasksManualOverride; // null = follow externalMyTasksOnly
  bool get _showMyTasks =>
      _myTasksManualOverride ?? widget.externalMyTasksOnly ?? false;
  bool _allExpandedInternal = true;
  bool get _allExpanded => widget.externalAllExpanded ?? _allExpandedInternal;
  bool _fitToScreen = true;
  static const _expandedPrefsKey = 'task_list_expanded';
  static const _fitToScreenPrefsKey = 'task_list_fit_to_screen';
  bool _isTaskDragging = false;
  final Map<String, bool> _groupExpansionStates = {};
  final Map<String, bool> _taskExpansionStates = {};
  double _projectColumnWidth = 200;
  double _customerNameColumnWidth = 140;
  double _jobNumberColumnWidth = 90;
  double _jobAddressColumnWidth = 160;
  double _statusColumnWidth = 116;
  double _dueDateColumnWidth = 96;
  double _assigneeColumnWidth = 62;
  double _notesColumnWidth = 34;
  double _progressColumnWidth = 52;
  Set<String> _hiddenColumnIds = {'customer_name', 'job_number', 'job_address'};
  static const _hiddenColumnsPrefsKey = 'task_list_hidden_columns';
  String? _sortColumn;
  bool _sortAscending = true;
  Map<String, Project> _projectMap = {};
  Map<String, Property> _propertyMap = {};
  List<Task> _lastAllTasks = const [];
  // Property filter for the project task list (internal to this widget)
  String? _internalPropertyFilterId;
  Stream<List<Property>>? _projectPropertiesStream;
  final Set<String> _selectedTaskIds = {};
  List<AppUser> _lastAllWorkspaceUsers = const [];
  Map<String, int> _commentCounts = const {};
  int _commentCountRequestToken = 0;
  bool _isNarrowScreen = false;
  bool _useCardLayout = false;
  late Stream<List<AppUser>> _usersStream;
  Stream<List<Project>>? _projectsStream;
  Stream<List<Property>>? _propertiesStream;
  Stream<List<Task>>? _projectTasksStream;
  Stream<List<Task>>? _workspaceTasksStream;

  Map<String, String> get _projectNames => {
    for (final entry in _projectMap.entries) entry.key: entry.value.name,
  };

  bool get _isSearchActive =>
      (widget.externalSearchQuery ?? _searchQuery).trim().isNotEmpty;

  Map<String, double> get _taskHeaderWidths => {
    'project': _projectColumnWidth,
    'customer_name': _customerNameColumnWidth,
    'job_number': _jobNumberColumnWidth,
    'job_address': _jobAddressColumnWidth,
    'status': _statusColumnWidth,
    'due_date': _dueDateColumnWidth,
    'assignee': _assigneeColumnWidth,
    'notes': _notesColumnWidth,
    'progress': _progressColumnWidth,
  };

  bool _isColumnVisible(String id) {
    if (id == 'project') return widget.showProjectColumn;
    return !_hiddenColumnIds.contains(id);
  }

  double _visibleColumnWidth(String id, double width) {
    return _isColumnVisible(id) ? width + _columnGap : 0.0;
  }

  /// Minimum table width in scroll mode: fixed columns + a comfortable title width.
  double get _scrollModeMinWidth {
    const overhead = 64.0; // checkbox + gaps + tree toggle area
    const titleMin = 240.0;
    final rightCols =
        _visibleColumnWidth('customer_name', _customerNameColumnWidth) +
        _visibleColumnWidth('job_number', _jobNumberColumnWidth) +
        _visibleColumnWidth('job_address', _jobAddressColumnWidth) +
        _statusColumnWidth +
        _columnGap +
        _dueDateColumnWidth +
        _columnGap +
        _assigneeColumnWidth +
        _columnGap +
        _notesColumnWidth +
        _columnGap +
        _progressColumnWidth;
    final projectCol = widget.showProjectColumn
        ? _projectColumnWidth + _columnGap
        : 0.0;
    return overhead + titleMin + rightCols + projectCol;
  }

  @override
  void initState() {
    super.initState();
    _groupBy = widget.initialGroupBy;
    _metricFilter = widget.initialMetricFilter;
    _initializeStreams();
    _loadExpandedPreference();
  }

  Future<void> _loadExpandedPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_expandedPrefsKey);
    final savedFit = prefs.getBool(_fitToScreenPrefsKey);
    final savedHidden = prefs.getStringList(_hiddenColumnsPrefsKey);
    if (mounted) {
      setState(() {
        if (saved != null) _allExpandedInternal = saved;
        if (savedFit != null) _fitToScreen = savedFit;
        if (savedHidden != null) _hiddenColumnIds = savedHidden.toSet();
      });
    }
  }

  Future<void> _saveExpandedPreference(bool expanded) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_expandedPrefsKey, expanded);
  }

  Future<void> _saveFitToScreenPreference(bool fit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_fitToScreenPrefsKey, fit);
  }

  Future<void> _saveHiddenColumnsPreference() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _hiddenColumnsPrefsKey,
      _hiddenColumnIds.toList(),
    );
  }

  void _toggleColumnVisibility(String columnId) {
    setState(() {
      if (_hiddenColumnIds.contains(columnId)) {
        _hiddenColumnIds.remove(columnId);
      } else {
        _hiddenColumnIds.add(columnId);
      }
    });
    _saveHiddenColumnsPreference();
  }

  @override
  void didUpdateWidget(covariant GroupedTaskListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialMetricFilter != widget.initialMetricFilter) {
      _metricFilter = widget.initialMetricFilter;
    }
    if (oldWidget.workspaceId != widget.workspaceId ||
        oldWidget.projectId != widget.projectId) {
      _initializeStreams();
    }
    // Clear per-group overrides when external expand/collapse changes
    if (oldWidget.externalAllExpanded != widget.externalAllExpanded) {
      _groupExpansionStates.clear();
    }
  }

  void _initializeStreams() {
    _usersStream = ServiceLocator.userService.getUsersByWorkspace(
      widget.workspaceId,
    );

    if (widget.projectId == null) {
      _projectsStream = ServiceLocator.projectService.getProjects(
        widget.workspaceId,
      );
      _propertiesStream = ServiceLocator.propertyService
          .getPropertiesByWorkspace(widget.workspaceId);
      _workspaceTasksStream = ServiceLocator.taskService.getAllWorkspaceTasks(
        widget.workspaceId,
      );
      _projectTasksStream = null;
      _projectPropertiesStream = null;
    } else {
      _projectTasksStream = ServiceLocator.taskService.getTasks(
        widget.projectId!,
        workspaceId: widget.workspaceId,
      );
      _projectPropertiesStream = ServiceLocator.propertyService.getProperties(
        widget.projectId!,
        workspaceId: widget.workspaceId,
      );
      _workspaceTasksStream = null;
      _projectsStream = null;
      _propertiesStream = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUserId = authProvider.appUser?.id;
    _isNarrowScreen = MediaQuery.sizeOf(context).width < AppBreakpoints.mobile;
    _useCardLayout = widget.forceCardView;

    if (_isNarrowScreen) {
      return Column(
        children: [
          _buildMobileToolbar(currentUserId),
          Expanded(child: _buildTaskStream(currentUserId)),
        ],
      );
    }

    return Column(
      children: [
        TaskListToolbar(
          groupBy: _groupBy,
          searchQuery: _searchQuery,
          showMyTasks: _showMyTasks,
          hideMyTasksFilter: widget.hideToolbarMyTasksFilter,
          allExpanded: _allExpanded,
          hideSearch: widget.hideToolbarSearch,
          hideHideDoneFilter: widget.hideToolbarHideDone,

          onGroupByChanged: (g) => setState(() {
            _groupBy = g;
            _groupExpansionStates.clear();
            _sortColumn = null;
            _sortAscending = true;
          }),
          onSearchChanged: (q) => setState(() => _searchQuery = q),
          onMyTasksToggled: (v) => setState(() => _myTasksManualOverride = v),
          hideDone: _hideDone,
          onHideDoneToggled: (v) => setState(() => _hideDoneInternal = v),
          hideExpandCollapse: widget.externalAllExpanded != null,
          onToggleAllExpanded: () {
            setState(() {
              _allExpandedInternal = !_allExpandedInternal;
              _groupExpansionStates.clear();
            });
            _saveExpandedPreference(_allExpandedInternal);
          },
          onAddGroup: widget.projectId != null
              ? () => _createPhaseGroup()
              : null,
          selectedCount: _selectedTaskIds.length,
          onMassEdit: _selectedTaskIds.isNotEmpty ? _handleMassEdit : null,
          onMassDelete: _selectedTaskIds.isNotEmpty ? _handleMassDelete : null,
          onClearSelection: _selectedTaskIds.isNotEmpty
              ? () => setState(() => _selectedTaskIds.clear())
              : null,
          trailingControl: widget.toolbarTrailingControl,
          fitToScreen: _fitToScreen,
          onFitToScreenToggle: () {
            final newFit = !_fitToScreen;
            setState(() => _fitToScreen = newFit);
            _saveFitToScreenPreference(newFit);
          },
          hiddenColumnIds: _hiddenColumnIds,
          toggleableColumns: [
            if (widget.showProjectColumn)
              (
                id: 'project',
                label: context.watch<WorkspaceProvider>().projectTerminology,
              ),
            (id: 'customer_name', label: 'Customer Name'),
            (id: 'job_number', label: 'Job #'),
            (id: 'job_address', label: 'Job Address'),
            (id: 'status', label: 'Status'),
            (id: 'due_date', label: 'Due Date'),
            (id: 'assignee', label: 'Assignee'),
            (id: 'notes', label: 'Notes'),
            (id: 'progress', label: 'Progress'),
          ],
          onToggleColumn: _toggleColumnVisibility,
          onExport: _handleExport,
          showBottomBorder:
              !(widget.projectId != null && _projectPropertiesStream != null),
        ),
        // Property filter row for project task list
        if (widget.projectId != null && _projectPropertiesStream != null)
          StreamBuilder<List<Property>>(
            stream: _projectPropertiesStream,
            builder: (context, snap) {
              final props = snap.data ?? [];
              _propertyMap = {
                for (final property in props) property.id: property,
              };
              if (props.isEmpty) return const SizedBox.shrink();
              return _buildProjectPropertyFilterRow(props);
            },
          ),
        Expanded(child: _buildTaskStream(currentUserId)),
      ],
    );
  }

  // ── Mobile toolbar ──────────────────────────────────────────────────────────

  Widget _buildMobileToolbar(String? currentUserId) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Group by dropdown
          SizedBox(
            width: 170,
            child: TableDropdownControl<GroupBy>(
              value: _groupBy,
              height: 36,
              items: const [
                DropdownMenuItem(
                  value: GroupBy.phase,
                  child: Text('Group by Phase'),
                ),
                DropdownMenuItem(
                  value: GroupBy.status,
                  child: Text('Group by Status'),
                ),
                DropdownMenuItem(
                  value: GroupBy.priority,
                  child: Text('Group by Priority'),
                ),
                DropdownMenuItem(
                  value: GroupBy.assignee,
                  child: Text('Group by Assignee'),
                ),
                DropdownMenuItem(
                  value: GroupBy.property,
                  child: Text('Group by Property'),
                ),
                DropdownMenuItem(
                  value: GroupBy.none,
                  child: Text('No Grouping'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _groupBy = value;
                    _groupExpansionStates.clear();
                    _sortColumn = null;
                    _sortAscending = true;
                  });
                }
              },
            ),
          ),
          // Expand/Collapse all
          if (widget.externalAllExpanded == null)
            ViewIconButton(
              icon: _allExpanded ? Icons.unfold_less : Icons.unfold_more,
              tooltip: _allExpanded ? 'Collapse all' : 'Expand all',
              isSelected: false,
              onTap: () {
                setState(() {
                  _allExpandedInternal = !_allExpandedInternal;
                  _groupExpansionStates.clear();
                });
                _saveExpandedPreference(_allExpandedInternal);
              },
            ),
          if (!widget.hideToolbarSearch)
            _searchExpanded
                ? SizedBox(
                    width: 200,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Expanded(
                          child: AppSearchBar(
                            hintText: 'Search tasks…',
                            height: 36,
                            onChanged: (q) => setState(() => _searchQuery = q),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          tooltip: 'Close search',
                          onPressed: () => setState(() {
                            _searchExpanded = false;
                            _searchQuery = '';
                          }),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  )
                : ViewIconButton(
                    icon: Icons.search,
                    tooltip: 'Search tasks',
                    isSelected: false,
                    onTap: () => setState(() => _searchExpanded = true),
                  ),
          if (!widget.hideToolbarMyTasksFilter)
            ChoiceChip(
              label: Text(_showMyTasks ? 'My Tasks' : 'All Tasks'),
              selected: _showMyTasks,
              onSelected: (v) => setState(() => _myTasksManualOverride = v),
              visualDensity: VisualDensity.compact,
              showCheckmark: false,
              avatar: Icon(
                _showMyTasks ? Icons.assignment_ind : Icons.assignment,
                size: 18,
              ),
            ),
          if (!widget.hideToolbarHideDone)
            Tooltip(
              message: _hideDone ? 'Done tasks hidden' : 'Showing done tasks',
              child: InkWell(
                onTap: () => setState(() => _hideDoneInternal = !_hideDone),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _hideDone
                        ? AppColors.secondary.withValues(alpha: 0.10)
                        : Colors.transparent,
                    border: Border.all(
                      color: _hideDone
                          ? AppColors.secondary
                          : AppColors.cardBorder,
                    ),
                  ),
                  child: Icon(
                    _hideDone ? Icons.visibility_off : Icons.visibility,
                    size: 18,
                    color: _hideDone
                        ? AppColors.secondary
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          if (_selectedTaskIds.isNotEmpty) _buildInlineMobileSelectionBar(),
        ],
      ),
    );
  }

  Widget _buildInlineMobileSelectionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.4)),
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
              '${_selectedTaskIds.length} selected',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 26,
            child: FilledButton.icon(
              onPressed: _handleMassEdit,
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
              onPressed: () => setState(() => _selectedTaskIds.clear()),
              icon: const Icon(Icons.close, size: 14),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Clear selection',
              color: AppColors.secondary,
            ),
          ),
        ],
      ),
    );
  }

  // ── Project-mode property filter row ─────────────────────────────────────────

  Widget _buildProjectPropertyFilterRow(List<Property> properties) {
    final chrome = ChromeColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      decoration: BoxDecoration(
        color: chrome.background,
        border: Border(bottom: BorderSide(color: chrome.divider)),
      ),
      child: Row(
        children: [
          Text(
            'Location:',
            style: TextStyle(
              fontSize: 13,
              color: chrome.text,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              borderRadius: AppRadius.cardRadius,
              value: _internalPropertyFilterId,
              isDense: true,
              style: TextStyle(
                fontSize: 13,
                color: chrome.textActive,
                fontWeight: FontWeight.w500,
              ),
              dropdownColor: chrome.background,
              iconEnabledColor: chrome.text,
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All'),
                ),
                ...properties.map((p) {
                  final label = p.name.isNotEmpty
                      ? (p.identifier.isNotEmpty
                            ? '${p.name} (${p.identifier})'
                            : p.name)
                      : p.identifier;
                  return DropdownMenuItem<String?>(
                    value: p.id,
                    child: Text(label),
                  );
                }),
              ],
              onChanged: (v) => setState(() => _internalPropertyFilterId = v),
            ),
          ),
          if (_internalPropertyFilterId != null) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(Icons.clear, size: 16, color: chrome.text),
              onPressed: () => setState(() => _internalPropertyFilterId = null),
              tooltip: 'Clear location filter',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }

  // ── Mobile task list view ────────────────────────────────────────────────────

  Widget _buildMobileFlatListView(
    List<Task> tasks,
    Map<String, AppUser> usersMap,
    List<AppUser> allWorkspaceUsers,
  ) {
    // Non-phase groupings use the generic grouped renderer so the Cards view
    // honors the toolbar's "Group by" selection instead of always showing
    // phases.
    if (_groupBy != GroupBy.phase) {
      return _buildMobileGroupedListView(tasks, usersMap, allWorkspaceUsers);
    }

    // Display map (filtered rows) vs. full map (accurate progress/done counts).
    // Phase headers stay visible even when "hide done" hides every task in a
    // completed phase — see _buildPhaseGroups for the rationale.
    final allTasks = _lastAllTasks;
    final Map<String, List<Task>> childrenMap = {};
    for (final t in tasks) {
      if (t.parentId != null) {
        childrenMap.putIfAbsent(t.parentId!, () => []).add(t);
      }
    }
    final Map<String, List<Task>> fullChildrenMap = {};
    for (final t in allTasks) {
      if (t.parentId != null) {
        fullChildrenMap.putIfAbsent(t.parentId!, () => []).add(t);
      }
    }

    // Phases: root summary tasks (from the unfiltered set)
    final phases =
        allTasks
            .where((t) => t.parentId == null && t.taskType == TaskType.summary)
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    final assignedToPhase = <String>{};
    final sections = <_MobileSection>[];

    for (final phase in phases) {
      final fullPhaseTasks = _collectDescendants(phase.id, fullChildrenMap);
      final visiblePhaseTasks = _collectDescendants(phase.id, childrenMap);
      final allHidden =
          visiblePhaseTasks.isEmpty && fullPhaseTasks.isNotEmpty;
      final phaseTasks = allHidden ? fullPhaseTasks : visiblePhaseTasks;
      assignedToPhase.add(phase.id);
      for (final t in fullPhaseTasks) {
        assignedToPhase.add(t.id);
      }

      final summary = _computePhaseSummary(phase, fullPhaseTasks);
      final doneCount = fullPhaseTasks.where((t) => t.isComplete).length;

      sections.add(
        _MobileSection(
          phase: phase,
          tasks: phaseTasks,
          doneCount: doneCount,
          progress: summary.progress,
          allHidden: allHidden,
        ),
      );
    }

    // Ungrouped tasks (not part of any phase and not summary tasks themselves)
    final ungrouped =
        tasks.where((t) => !assignedToPhase.contains(t.id)).toList()
          ..sort((a, b) {
            final aOver = a.isOverdue() && !a.isComplete;
            final bOver = b.isOverdue() && !b.isComplete;
            if (aOver != bOver) return aOver ? -1 : 1;
            if (a.dueDate != null && b.dueDate != null) {
              return a.dueDate!.compareTo(b.dueDate!);
            }
            if (a.dueDate != null) return -1;
            if (b.dueDate != null) return 1;
            return a.title.compareTo(b.title);
          });

    if (sections.isEmpty && ungrouped.isEmpty) {
      return _buildMobileEmptyState();
    }

    // Flatten sections + ungrouped into a linear list of items
    final items = <_MobileListItem>[];

    for (final section in sections) {
      final groupId = 'phase_${section.phase.id}';
      // Keep a phase with no visible rows (completed, done tasks hidden)
      // collapsed unless the user explicitly opened it.
      final isExpanded = _groupExpansionStates.containsKey(groupId)
          ? _groupExpansionStates[groupId]!
          : ((section.allHidden || section.tasks.isEmpty)
              ? false
              : _allExpanded);

      items.add(_MobileListItem.phase(section, groupId, isExpanded));

      if (isExpanded) {
        for (final t in section.tasks) {
          items.add(_MobileListItem.task(t));
        }
      }
    }

    if (ungrouped.isNotEmpty) {
      if (sections.isNotEmpty) {
        items.add(_MobileListItem.plainHeader('Other', AppColors.textTertiary));
      }
      for (final t in ungrouped) {
        items.add(_MobileListItem.task(t));
      }
    }

    final inSelectionMode = _selectedTaskIds.isNotEmpty;

    return ListView.builder(
      padding: EdgeInsets.only(
        top: 4,
        bottom: _isNarrowScreen
            ? MediaQuery.paddingOf(context).bottom + 90
            : 16,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => _buildMobileItem(
        items[index],
        usersMap,
        allWorkspaceUsers,
        inSelectionMode,
      ),
    );
  }

  /// Empty-state widget shared by the phase and grouped mobile renderers.
  Widget _buildMobileEmptyState() {
    if (_isSearchActive || _metricFilter != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            Text(
              'No tasks match your filters',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: ChromeColors.of(context).scaffoldText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Try adjusting your search or filters',
              style: TextStyle(
                fontSize: 12,
                color: ChromeColors.of(context).scaffoldTextSecondary,
              ),
            ),
          ],
        ),
      );
    }
    return ZeroItemsActionEmptyState(
      icon: Icons.task_alt_outlined,
      title: 'No tasks yet',
      subtitle: 'Create your first task to start tracking work',
      ctaLabel: 'Create Task',
      onTap: () {
        if (widget.projectId != null) {
          showTaskFormPopup(context, projectId: widget.projectId!);
        }
      },
      // null → ZeroItemsActionEmptyState derives 'Click "Create Task" to
      // begin' from ctaLabel; only override when there is no project context.
      hintText: widget.projectId != null ? null : 'Open a project to add tasks',
    );
  }

  /// Renders a single mobile list item (group header, plain header, or task).
  Widget _buildMobileItem(
    _MobileListItem item,
    Map<String, AppUser> usersMap,
    List<AppUser> allWorkspaceUsers,
    bool inSelectionMode,
  ) {
    // Phase header
    if (item.section != null) {
      final section = item.section!;
      final groupId = item.groupId!;
      final isExpanded = item.isExpanded!;
      return _MobileGroupHeader(
        title: section.phase.title,
        color: section.phase.groupColor,
        taskCount: section.tasks.length,
        doneCount: section.doneCount,
        progress: section.progress,
        isExpanded: isExpanded,
        onTap: () =>
            setState(() => _groupExpansionStates[groupId] = !isExpanded),
        isSelectionMode: inSelectionMode,
        isAllSelected: _triStateForGroup(section.tasks, inSelectionMode),
        onSelectAllChanged: (selectAll) =>
            _handleGroupSelectAll(section.tasks, selectAll),
      );
    }

    // Generic group header (status / priority / assignee / property)
    if (item.group != null) {
      final group = item.group!;
      final isExpanded = item.isExpanded!;
      return _MobileGroupHeader(
        title: group.title,
        color: group.color,
        taskCount: group.taskCount,
        doneCount: group.doneCount,
        progress: group.progress,
        isExpanded: isExpanded,
        onTap: () => setState(
          () => _groupExpansionStates[group.groupId] = !isExpanded,
        ),
        isSelectionMode: inSelectionMode,
        isAllSelected: _triStateForGroup(group.tasks, inSelectionMode),
        onSelectAllChanged: (selectAll) =>
            _handleGroupSelectAll(group.tasks, selectAll),
      );
    }

    if (item.isPlainHeader) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          item.headerTitle!,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: item.headerColor ?? AppColors.textTertiary,
            letterSpacing: 0.3,
          ),
        ),
      );
    }

    final task = item.task!;
    final pName = widget.showProjectColumn
        ? _projectMap[task.projectId]?.name
        : null;
    final proj = _projectMap[task.projectId];
    final isSel = _selectedTaskIds.contains(task.id);

    // Resolve location label from property IDs
    String? locationLabel;
    if (task.propertyIds.isNotEmpty) {
      final names = task.propertyIds
          .map((id) => _propertyMap[id])
          .where((p) => p != null)
          .map((p) => p!.name.isNotEmpty ? p.name : p.identifier)
          .where((n) => n.isNotEmpty)
          .toList();
      if (names.isNotEmpty) locationLabel = names.join(', ');
    }

    if (_useCardLayout) {
      return MobileTaskCard(
        key: ValueKey(task.id),
        task: task,
        allTasks: _lastAllTasks,
        projectName: pName,
        project: proj,
        customerName: proj?.customerName,
        locationLabel: locationLabel,
        propertyMap: _propertyMap,
        usersMap: usersMap,
        allWorkspaceUsers: allWorkspaceUsers,
        isSelectionMode: inSelectionMode,
        isSelected: isSel,
        onSelectionChanged: (selected) =>
            _handleTaskSelectionChanged(task, selected),
        onLongPress: () => _handleTaskSelectionChanged(task, true),
      );
    }
    return MobileTaskRow(
      key: ValueKey(task.id),
      task: task,
      allTasks: _lastAllTasks,
      projectName: pName,
      project: proj,
      customerName: proj?.customerName,
      locationLabel: locationLabel,
      propertyMap: _propertyMap,
      usersMap: usersMap,
      allWorkspaceUsers: allWorkspaceUsers,
      isSelectionMode: inSelectionMode,
      isSelected: isSel,
      onSelectionChanged: (selected) =>
          _handleTaskSelectionChanged(task, selected),
      onLongPress: () => _handleTaskSelectionChanged(task, true),
    );
  }

  /// Tri-state select-all value for a group: true=all, false=some, null=none.
  bool? _triStateForGroup(List<Task> groupTasks, bool inSelectionMode) {
    if (!inSelectionMode || groupTasks.isEmpty) return null;
    final selected = groupTasks
        .where((t) => _selectedTaskIds.contains(t.id))
        .length;
    if (selected == groupTasks.length) return true;
    if (selected > 0) return false;
    return null;
  }

  /// Renders the mobile/Cards view when grouped by something other than phase
  /// (status, priority, assignee, property) or not grouped at all.
  Widget _buildMobileGroupedListView(
    List<Task> tasks,
    Map<String, AppUser> usersMap,
    List<AppUser> allWorkspaceUsers,
  ) {
    final groups = _computeMobileGroups(tasks, usersMap);
    if (groups.every((g) => g.tasks.isEmpty)) {
      return _buildMobileEmptyState();
    }

    final showHeaders = _groupBy != GroupBy.none;
    final items = <_MobileListItem>[];
    for (final group in groups) {
      if (group.tasks.isEmpty) continue;
      if (showHeaders) {
        final isExpanded = _isSearchActive
            ? true
            : (_groupExpansionStates[group.groupId] ?? _allExpanded);
        items.add(_MobileListItem.group(group, isExpanded));
        if (isExpanded) {
          for (final t in group.tasks) {
            items.add(_MobileListItem.task(t));
          }
        }
      } else {
        for (final t in group.tasks) {
          items.add(_MobileListItem.task(t));
        }
      }
    }

    final inSelectionMode = _selectedTaskIds.isNotEmpty;
    return ListView.builder(
      padding: EdgeInsets.only(
        top: 4,
        bottom: _isNarrowScreen
            ? MediaQuery.paddingOf(context).bottom + 90
            : 16,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => _buildMobileItem(
        items[index],
        usersMap,
        allWorkspaceUsers,
        inSelectionMode,
      ),
    );
  }

  /// Builds grouped task data for the mobile/Cards view based on [_groupBy].
  List<_MobileGroupData> _computeMobileGroups(
    List<Task> tasks,
    Map<String, AppUser> usersMap,
  ) {
    // Exclude phase/summary container tasks — they are not leaf work items.
    final groupable = tasks
        .where((t) => t.taskType != TaskType.summary)
        .toList();

    switch (_groupBy) {
      case GroupBy.status:
        return _mobileFieldGroups(
          groupable,
          keyOf: (t) => t.status,
          labels: {
            'not_started': 'Not Started',
            'working_on_it': 'Working on it',
            'stuck': 'Stuck',
            'done': 'Done',
          },
          colors: {
            'not_started': AppColors.textTertiary,
            'working_on_it': AppColors.info,
            'stuck': AppColors.warning,
            'done': AppColors.success,
          },
          ordering: const ['not_started', 'working_on_it', 'stuck', 'done'],
          idPrefix: 'status',
        );
      case GroupBy.priority:
        return _mobileFieldGroups(
          groupable,
          keyOf: (t) => t.priority,
          labels: {
            'high': 'High Priority',
            'medium': 'Medium Priority',
            'low': 'Low Priority',
          },
          colors: {
            'high': AppColors.error,
            'medium': AppColors.warning,
            'low': AppColors.info,
          },
          ordering: const ['high', 'medium', 'low'],
          idPrefix: 'priority',
        );
      case GroupBy.assignee:
        return _mobileAssigneeGroups(groupable, usersMap);
      case GroupBy.property:
        return _mobilePropertyGroups(groupable);
      case GroupBy.none:
        return [
          _MobileGroupData(
            groupId: 'all',
            title: 'All Tasks',
            color: AppColors.textTertiary,
            tasks: _sortedMobileTasks(groupable),
          ),
        ];
      case GroupBy.phase:
        return const [];
    }
  }

  List<_MobileGroupData> _mobileFieldGroups(
    List<Task> tasks, {
    required String Function(Task) keyOf,
    required Map<String, String> labels,
    required Map<String, Color> colors,
    required List<String> ordering,
    required String idPrefix,
  }) {
    final Map<String, List<Task>> grouped = {};
    for (final t in tasks) {
      grouped.putIfAbsent(keyOf(t), () => []).add(t);
    }
    final result = <_MobileGroupData>[];
    for (final key in ordering) {
      result.add(
        _MobileGroupData(
          groupId: '${idPrefix}_$key',
          title: labels[key] ?? key,
          color: colors[key] ?? AppColors.textTertiary,
          tasks: _sortedMobileTasks(grouped[key] ?? const []),
        ),
      );
    }
    final extraTasks = <Task>[];
    for (final key in grouped.keys.where((k) => !ordering.contains(k))) {
      extraTasks.addAll(grouped[key]!);
    }
    if (extraTasks.isNotEmpty) {
      result.add(
        _MobileGroupData(
          groupId: '${idPrefix}_other',
          title: 'Other',
          color: AppColors.textTertiary,
          tasks: _sortedMobileTasks(extraTasks),
        ),
      );
    }
    return result;
  }

  List<_MobileGroupData> _mobileAssigneeGroups(
    List<Task> tasks,
    Map<String, AppUser> usersMap,
  ) {
    const unassignedKey = '_unassigned_';
    final Map<String, List<Task>> grouped = {};
    for (final t in tasks) {
      final key = t.assignedToIds.isEmpty
          ? unassignedKey
          : t.assignedToIds.first;
      grouped.putIfAbsent(key, () => []).add(t);
    }
    String nameFor(String id) =>
        usersMap[id]?.displayName ?? usersMap[id]?.email ?? id;
    final namedKeys = grouped.keys.where((k) => k != unassignedKey).toList()
      ..sort(
        (a, b) => nameFor(a).toLowerCase().compareTo(nameFor(b).toLowerCase()),
      );
    final result = <_MobileGroupData>[];
    for (final key in namedKeys) {
      result.add(
        _MobileGroupData(
          groupId: 'assignee_$key',
          title: nameFor(key),
          color: AppColors.info,
          tasks: _sortedMobileTasks(grouped[key]!),
        ),
      );
    }
    if (grouped.containsKey(unassignedKey)) {
      result.add(
        _MobileGroupData(
          groupId: 'assignee_$unassignedKey',
          title: 'Unassigned',
          color: AppColors.textTertiary,
          tasks: _sortedMobileTasks(grouped[unassignedKey]!),
        ),
      );
    }
    return result;
  }

  List<_MobileGroupData> _mobilePropertyGroups(List<Task> tasks) {
    const noPropertyKey = '_no_property_';
    final Map<String, List<Task>> grouped = {};
    for (final t in tasks) {
      final key = t.propertyIds.isEmpty ? noPropertyKey : t.propertyIds.first;
      grouped.putIfAbsent(key, () => []).add(t);
    }
    final result = <_MobileGroupData>[];
    for (final key in grouped.keys.where((k) => k != noPropertyKey)) {
      final prop = _propertyMap[key];
      final label = prop != null
          ? (prop.name.isNotEmpty ? prop.name : prop.identifier)
          : key;
      result.add(
        _MobileGroupData(
          groupId: 'property_$key',
          title: label,
          color: AppColors.financialAccent,
          tasks: _sortedMobileTasks(grouped[key]!),
        ),
      );
    }
    if (grouped.containsKey(noPropertyKey)) {
      result.add(
        _MobileGroupData(
          groupId: 'property_$noPropertyKey',
          title: 'No Property',
          color: AppColors.textTertiary,
          tasks: _sortedMobileTasks(grouped[noPropertyKey]!),
        ),
      );
    }
    return result;
  }

  /// Sorts tasks for the mobile view: overdue first, then by due date, then
  /// alphabetically — matching the existing "ungrouped" ordering.
  List<Task> _sortedMobileTasks(List<Task> tasks) {
    final sorted = [...tasks];
    sorted.sort((a, b) {
      final aOver = a.isOverdue() && !a.isComplete;
      final bOver = b.isOverdue() && !b.isComplete;
      if (aOver != bOver) return aOver ? -1 : 1;
      if (a.dueDate != null && b.dueDate != null) {
        return a.dueDate!.compareTo(b.dueDate!);
      }
      if (a.dueDate != null) return -1;
      if (b.dueDate != null) return 1;
      return a.title.compareTo(b.title);
    });
    return sorted;
  }

  Widget _buildTaskStream(String? currentUserId) {
    return StreamBuilder<List<AppUser>>(
      stream: _usersStream,
      builder: (context, usersSnapshot) {
        final allWorkspaceUsers = usersSnapshot.data ?? const <AppUser>[];
        final usersMap = {for (final u in allWorkspaceUsers) u.id: u};

        // For all-tasks view, wrap with project and property streams to get full context
        if (widget.projectId == null) {
          return StreamBuilder<List<Project>>(
            stream: _projectsStream,
            builder: (context, projectSnapshot) {
              if (projectSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final projects = projectSnapshot.data ?? [];
              _projectMap = {for (final p in projects) p.id: p};

              return StreamBuilder<List<Property>>(
                stream: _propertiesStream,
                builder: (context, propertySnapshot) {
                  if (propertySnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final properties = propertySnapshot.data ?? [];
                  _propertyMap = {for (final p in properties) p.id: p};

                  return StreamBuilder<List<Task>>(
                    stream: _workspaceTasksStream,
                    builder: (context, snapshot) => _buildFromSnapshot(
                      snapshot,
                      currentUserId,
                      usersMap,
                      allWorkspaceUsers,
                    ),
                  );
                },
              );
            },
          );
        }

        return StreamBuilder<List<Property>>(
          stream: _projectPropertiesStream,
          builder: (context, propertySnapshot) {
            if (propertySnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final properties = propertySnapshot.data ?? [];
            _propertyMap = {
              for (final property in properties) property.id: property,
            };

            return StreamBuilder<List<Task>>(
              stream: _projectTasksStream,
              builder: (context, snapshot) => _buildFromSnapshot(
                snapshot,
                currentUserId,
                usersMap,
                allWorkspaceUsers,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFromSnapshot(
    AsyncSnapshot<List<Task>> snapshot,
    String? currentUserId,
    Map<String, AppUser> usersMap,
    List<AppUser> allWorkspaceUsers,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: AppColors.errorDark,
              ),
              const SizedBox(height: 12),
              SelectableText(
                UserFacingError.uiMessage(snapshot.error, action: 'load data'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Builder(
                builder: (_) {
                  final raw = snapshot.error.toString();
                  final clipped = raw.length > 200 ? '${raw.substring(0, 200)}…' : raw;
                  return Text(
                    'Details: $clipped',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                      fontSize: 11,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );
    }

    final allTasks = snapshot.data ?? [];
    if (widget.externalProject != null) {
      _projectMap = {widget.externalProject!.id: widget.externalProject!};
    }
    _lastAllTasks = allTasks;
    _lastAllWorkspaceUsers = allWorkspaceUsers;
    _refreshCommentCountsForTasks(allTasks);

    // Prune stale expansion state entries for deleted tasks/groups
    if (_taskExpansionStates.length > allTasks.length * 2) {
      final validIds = {for (final t in allTasks) t.id};
      _taskExpansionStates.removeWhere((id, _) => !validIds.contains(id));
      _groupExpansionStates.removeWhere((id, _) => !validIds.contains(id));
    }

    // Combine external and internal search/filter
    final searchQuery = (widget.externalSearchQuery ?? _searchQuery).trim();
    // External property filter (from parent) takes precedence; internal is for project mode
    final propertyFilterId =
        widget.externalPropertyFilterId ?? _internalPropertyFilterId;
    // Project filter: from parent (workspace-wide all-tasks view)
    final projectFilterId = widget.externalProjectFilterId;

    var tasks = TaskFilterEngine.apply(
      allTasks,
      options: TaskFilterOptions(
        myTasksOnly: _showMyTasks,
        currentUserId: currentUserId,
        propertyFilterId: propertyFilterId,
        projectId: projectFilterId,
        customerId: widget.externalCustomerFilterId,
        priority: widget.externalPriorityFilter,
        assigneeId: widget.externalAssigneeFilterId,
        dueDateStart: widget.externalDueDateStart,
        dueDateEnd: widget.externalDueDateEnd,
        overdueOnly: widget.externalOverdueOnly ?? false,
        hideDone: _hideDone,
        query: '',
      ),
      context: TaskFilterContext(
        projectMap: _projectMap,
        propertyMap: _propertyMap,
      ),
    );

    Map<String, bool> effectiveExpansionStates = _taskExpansionStates;

    if (searchQuery.isNotEmpty) {
      final loweredQuery = searchQuery.toLowerCase();
      final searchContext = TaskFilterContext(
        projectMap: _projectMap,
        propertyMap: _propertyMap,
      );

      final matchedIds = tasks
          .where(
            (task) => TaskFilterEngine.matchesQuery(
              task,
              query: loweredQuery,
              context: searchContext,
            ),
          )
          .map((task) => task.id)
          .toSet();

      if (matchedIds.isEmpty) {
        tasks = const <Task>[];
      } else {
        final itemsById = {for (final task in tasks) task.id: task};
        final visibleIds = <String>{...matchedIds};

        for (final matchedId in matchedIds) {
          final matchedTask = itemsById[matchedId];
          if (matchedTask == null) continue;
          visibleIds.addAll(
            HierarchyUtils.collectAncestorIds<Task>(
              item: matchedTask,
              itemsById: itemsById,
              idOf: (task) => task.id,
              parentIdOf: (task) => task.parentId,
            ),
          );
        }
        effectiveExpansionStates = _buildSearchExpansionStates(
          matchedIds: matchedIds,
          byId: itemsById,
        );
        tasks = tasks.where((task) => visibleIds.contains(task.id)).toList();
      }
    }

    // Apply metric filter before any view (mobile or desktop)
    if (_metricFilter != null) {
      tasks = _applyMetricFilter(tasks, _metricFilter!);
    }

    // Mobile / card layout: use mobile-friendly rendering instead of the desktop table
    if (_useCardLayout || _isNarrowScreen) {
      return _buildMobileFlatListView(tasks, usersMap, allWorkspaceUsers);
    }

    if (_metricFilter != null) {
      return _buildMetricFilteredView(
        tasks,
        usersMap,
        allWorkspaceUsers,
        expansionStates: effectiveExpansionStates,
      );
    }

    if (_groupBy == GroupBy.none) {
      return _buildFlatListView(tasks, usersMap, allWorkspaceUsers);
    }

    // Build grouped view
    final groups = _buildGroups(
      tasks,
      usersMap,
      allWorkspaceUsers,
      expansionStates: effectiveExpansionStates,
    );
    final groupsToRender = groups.isNotEmpty
        ? groups
        : [
            TaskGroup(
              key: const ValueKey('ungrouped_empty'),
              groupId: 'ungrouped',
              title: 'Ungrouped',
              groupColor: AppColors.textTertiary,
              tasks: const <Task>[],
              allTasks: const <Task>[],
              isExpanded: true,
              showProjectColumn: widget.showProjectColumn,
              projectColumnWidth: _projectColumnWidth,
              customerNameColumnWidth: _customerNameColumnWidth,
              jobNumberColumnWidth: _jobNumberColumnWidth,
              jobAddressColumnWidth: _jobAddressColumnWidth,
              statusColumnWidth: _statusColumnWidth,
              dueDateColumnWidth: _dueDateColumnWidth,
              assigneeColumnWidth: _assigneeColumnWidth,
              notesColumnWidth: _notesColumnWidth,
              progressColumnWidth: _progressColumnWidth,
              hiddenColumnIds: _hiddenColumnIds,
              projectNames: _projectNames,
              projectMap: _projectMap,
              propertyMap: _propertyMap,
              usersMap: usersMap,
              allWorkspaceUsers: allWorkspaceUsers,
              expansionStates: const <String, bool>{},
              onToggle: () {},
              onQuickAdd: (title) => _createTask(title),
              onDeleteTask: (_) {},
              onUngroupTask: _handleUngroupTask,
              onTaskExpandToggle: (_, __) {},
              onTaskDroppedOnTask: _handleTaskDroppedOnTask,
              onTaskDragStarted: _onTaskDragStarted,
              onTaskDragEnded: _onTaskDragEnded,
              isAnyTaskDragging: _isTaskDragging,
              selectedTaskIds: _selectedTaskIds,
              onSelectionChanged: _handleTaskSelectionChanged,
              onGroupSelectAll: _handleGroupSelectAll,
              commentCounts: _commentCounts,
              customSortSiblings: _columnSortComparator,
            ),
          ];
    final hasAddRow = widget.projectId != null;
    final body = _buildTaskListWithUngroupTarget(
      ListView.builder(
        itemCount: groupsToRender.length + (hasAddRow ? 1 : 0),
        itemBuilder: (context, index) {
          if (index < groupsToRender.length) return groupsToRender[index];
          return TableAddItemGroupRow(
            onAddItem: () => _createTask('New Task'),
            onAddGroup: _createPhaseGroup,
          );
        },
      ),
    );
    if (_fitToScreen) {
      final chrome = ChromeColors.of(context);
      Widget table = Column(
        children: [
          _buildTaskListHeader(),
          Expanded(child: body),
          _buildTaskSummaryFooter(tasks),
        ],
      );
      if (chrome.isDark) {
        table = Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: const [
              BoxShadow(
                color: Color(0x30000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: table,
        );
      }
      return table;
    }
    return TableLayoutShell(
      minTableWidth: _scrollModeMinWidth,
      header: _buildTaskListHeader(),
      body: body,
      footer: _buildTaskSummaryFooter(tasks),
    );
  }

  Map<String, bool> _buildSearchExpansionStates({
    required Set<String> matchedIds,
    required Map<String, Task> byId,
  }) {
    final result = Map<String, bool>.from(_taskExpansionStates);
    for (final matchedId in matchedIds) {
      final matchedTask = byId[matchedId];
      if (matchedTask == null) continue;
      final ancestors = HierarchyUtils.collectAncestorIds<Task>(
        item: matchedTask,
        itemsById: byId,
        idOf: (task) => task.id,
        parentIdOf: (task) => task.parentId,
      );
      for (final ancestorId in ancestors) {
        result[ancestorId] = true;
      }
    }
    return result;
  }

  void _refreshCommentCountsForTasks(List<Task> tasks) {
    final taskIds = tasks.map((task) => task.id).toSet();
    if (taskIds.isEmpty) {
      if (_commentCounts.isNotEmpty) {
        _queueCommentCountsUpdate(const <String, int>{});
      }
      return;
    }

    final missingIds = taskIds
        .where((taskId) => !_commentCounts.containsKey(taskId))
        .toList(growable: false);
    final hasStaleIds = _commentCounts.keys.any(
      (taskId) => !taskIds.contains(taskId),
    );

    if (missingIds.isEmpty && !hasStaleIds) {
      return;
    }

    final requestToken = ++_commentCountRequestToken;
    final nextCounts = {
      for (final taskId in taskIds) taskId: _commentCounts[taskId] ?? 0,
    };

    if (hasStaleIds) {
      // Apply stale-id cleanup without calling setState during build.
      _queueCommentCountsUpdate(Map<String, int>.from(nextCounts));
    }

    if (missingIds.isEmpty) return;

    ServiceLocator.taskCommentService
        .getCommentCounts(missingIds)
        .then((fetchedCountsRaw) {
          if (!mounted || requestToken != _commentCountRequestToken) return;
          final fetchedCounts = Map<String, int>.from(
            fetchedCountsRaw as Map<dynamic, dynamic>,
          );
          final merged = <String, int>{...nextCounts, ...fetchedCounts};
          _queueCommentCountsUpdate(merged);
        })
        .catchError((_) {
          // Ignore count fetch failures; rows gracefully show empty state.
        });
  }

  void _queueCommentCountsUpdate(Map<String, int> nextCounts) {
    if (!mounted || _mapsEqual(nextCounts, _commentCounts)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _mapsEqual(nextCounts, _commentCounts)) return;
      setState(() => _commentCounts = nextCounts);
    });
  }

  bool _mapsEqual(Map<String, int> a, Map<String, int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  List<Widget> _buildGroups(
    List<Task> tasks,
    Map<String, AppUser> usersMap,
    List<AppUser> allWorkspaceUsers, {
    required Map<String, bool> expansionStates,
  }) {
    switch (_groupBy) {
      case GroupBy.phase:
        return _buildPhaseGroups(
          tasks,
          usersMap,
          allWorkspaceUsers,
          expansionStates: expansionStates,
        );
      case GroupBy.status:
        return _buildFieldGroups(
          tasks,
          usersMap: usersMap,
          allWorkspaceUsers: allWorkspaceUsers,
          expansionStates: expansionStates,
          keyExtractor: (t) => t.status,
          labels: {
            'not_started': 'Not Started',
            'working_on_it': 'Working on it',
            'stuck': 'Stuck',
            'done': 'Done',
          },
          colors: {
            'not_started': AppColors.textTertiary,
            'working_on_it': AppColors.info,
            'stuck': AppColors.warning,
            'done': AppColors.success,
          },
          ordering: ['not_started', 'working_on_it', 'stuck', 'done'],
          quickAddField: 'status',
        );
      case GroupBy.priority:
        return _buildFieldGroups(
          tasks,
          usersMap: usersMap,
          allWorkspaceUsers: allWorkspaceUsers,
          expansionStates: expansionStates,
          keyExtractor: (t) => t.priority,
          labels: {
            'high': 'High Priority',
            'medium': 'Medium Priority',
            'low': 'Low Priority',
          },
          colors: {
            'high': AppColors.error,
            'medium': AppColors.warning,
            'low': AppColors.info,
          },
          ordering: ['high', 'medium', 'low'],
          quickAddField: 'priority',
        );
      case GroupBy.assignee:
        return _buildAssigneeGroups(
          tasks,
          usersMap,
          allWorkspaceUsers,
          expansionStates: expansionStates,
        );
      case GroupBy.property:
        return _buildPropertyGroups(
          tasks,
          usersMap,
          allWorkspaceUsers,
          expansionStates: expansionStates,
        );
      case GroupBy.none:
        return const <Widget>[];
    }
  }

  List<Widget> _buildPhaseGroups(
    List<Task> tasks,
    Map<String, AppUser> usersMap,
    List<AppUser> allWorkspaceUsers, {
    required Map<String, bool> expansionStates,
  }) {
    // Phase headers represent project structure, so they stay visible even
    // when "hide done" is on: a completed phase like "Phase 1 — Demolition"
    // must not vanish from the Tasks tab while the Overview still shows it at
    // 100%. Derive the phase list and progress from the unfiltered task set,
    // but only display the child rows that survived filtering.
    final allTasks = _lastAllTasks;

    final phases = allTasks
        .where((t) => t.parentId == null && t.taskType == TaskType.summary)
        .toList();
    phases.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    // Display map (filtered rows) vs. full map (accurate progress/done counts).
    final Map<String, List<Task>> displayChildrenMap = {};
    for (final t in tasks) {
      if (t.parentId != null) {
        displayChildrenMap.putIfAbsent(t.parentId!, () => []).add(t);
      }
    }
    final Map<String, List<Task>> fullChildrenMap = {};
    for (final t in allTasks) {
      if (t.parentId != null) {
        fullChildrenMap.putIfAbsent(t.parentId!, () => []).add(t);
      }
    }

    // Collect all tasks under each phase (recursively)
    Set<String> assignedTaskIds = {};
    List<Widget> groups = [];

    for (final phase in phases) {
      final fullPhaseTasks = _collectDescendants(phase.id, fullChildrenMap);
      final visiblePhaseTasks =
          _collectDescendants(phase.id, displayChildrenMap);
      // When every task in a phase is hidden (a completed phase under "hide
      // done"), fall back to the full set so the header still shows accurate
      // counts (e.g. 2/2 rather than 2/0). The group is collapsed by default
      // so those done rows stay tucked away until the user expands to review.
      final allHidden =
          visiblePhaseTasks.isEmpty && fullPhaseTasks.isNotEmpty;
      final phaseTasks = allHidden ? fullPhaseTasks : visiblePhaseTasks;
      final phaseSummary = _computePhaseSummary(phase, fullPhaseTasks);
      final phaseAssignees = phaseSummary.assigneeIds
          .map((id) => usersMap[id])
          .whereType<AppUser>()
          .toList();
      assignedTaskIds.add(phase.id);
      for (final t in fullPhaseTasks) {
        assignedTaskIds.add(t.id);
      }

      final groupId = 'phase_${phase.id}';
      // Collapse a phase that has no visible rows unless the user explicitly
      // expanded it, so the structure stays without leaving an empty open group.
      final hasExplicitExpansion =
          _groupExpansionStates.containsKey(groupId);
      final isExpanded = _isSearchActive
          ? true
          : hasExplicitExpansion
              ? _groupExpansionStates[groupId]!
              : (allHidden ? false : _allExpanded);

      groups.add(
        TaskGroup(
          key: ValueKey(groupId),
          groupId: groupId,
          title: phase.title,
          groupColor: phase.groupColor,
          tasks: phaseTasks,
          allTasks: tasks,
          isExpanded: isExpanded,
          showProjectColumn: widget.showProjectColumn,
          projectColumnWidth: _projectColumnWidth,
          customerNameColumnWidth: _customerNameColumnWidth,
          jobNumberColumnWidth: _jobNumberColumnWidth,
          jobAddressColumnWidth: _jobAddressColumnWidth,
          statusColumnWidth: _statusColumnWidth,
          dueDateColumnWidth: _dueDateColumnWidth,
          assigneeColumnWidth: _assigneeColumnWidth,
          notesColumnWidth: _notesColumnWidth,
          progressColumnWidth: _progressColumnWidth,
          hiddenColumnIds: _hiddenColumnIds,
          projectNames: _projectNames,
          projectMap: _projectMap,
          propertyMap: _propertyMap,
          usersMap: usersMap,
          allWorkspaceUsers: allWorkspaceUsers,
          expansionStates: expansionStates,
          onToggle: () =>
              setState(() => _groupExpansionStates[groupId] = !isExpanded),
          onQuickAdd: (title) => _createTask(
            title,
            parentId: phase.id,
            projectId: phase.projectId,
          ),
          onEditGroup: () => showTaskFormPopup(
            context,
            projectId: phase.projectId,
            taskId: phase.id,
          ),
          onRenameGroup: (newTitle) => ServiceLocator.taskService.updateTask(
            taskId: phase.id,
            title: newTitle,
          ),
          showSummaryColumns: true,
          onSummaryStatusChanged: (status) =>
              ServiceLocator.taskService.updateTaskStatus(phase.id, status),
          draggableGroupTask: phase,
          summaryStatus: phase.status,
          summaryDueDate: phaseSummary.dueDate,
          summaryProgress: phaseSummary.progress,
          summaryAssignees: phaseAssignees,
          allWorkspaceUsersForSummary: allWorkspaceUsers,
          onSummaryAssigneeSelected: (userId) => _assignPhaseAssigneeToSubtasks(
            phaseTasks: phaseTasks,
            assigneeId: userId,
          ),
          onDeleteTask: (taskId) => _deleteTask(taskId),
          onUngroupTask: _handleUngroupTask,
          onTaskExpandToggle: (taskId, expanded) {
            setState(() => _taskExpansionStates[taskId] = expanded);
          },
          onTaskDroppedOnHeader: (task) {
            // Move task into this phase
            ServiceLocator.taskService.updateTask(
              taskId: task.id,
              parentId: phase.id,
            );
          },
          onTaskDroppedOnHeaderWithZone: (dragged, zone) {
            if (dragged.id == phase.id) return;
            if (dragged.taskType == TaskType.summary &&
                dragged.parentId == null &&
                (zone == GroupHeaderDropZone.above ||
                    zone == GroupHeaderDropZone.below)) {
              final sortOrder = zone == GroupHeaderDropZone.above
                  ? _computeSortOrderBefore(phase)
                  : _computeSortOrderAfter(phase);
              ServiceLocator.taskService.updateTask(
                taskId: dragged.id,
                clearParentId: true,
                sortOrder: sortOrder,
              );
              return;
            }
            // Default behavior: move dropped task into this phase.
            ServiceLocator.taskService.updateTask(
              taskId: dragged.id,
              parentId: phase.id,
            );
          },
          onTaskDroppedOnTask: _handleTaskDroppedOnTask,
          onTaskDragStarted: _onTaskDragStarted,
          onTaskDragEnded: _onTaskDragEnded,
          isAnyTaskDragging: _isTaskDragging,
          selectedTaskIds: _selectedTaskIds,
          onSelectionChanged: _handleTaskSelectionChanged,
          onGroupSelectAll: _handleGroupSelectAll,
          showPhaseHierarchyGuides: true,
          commentCounts: _commentCounts,
          customSortSiblings: _columnSortComparator,
        ),
      );
    }

    // Ungrouped section: tasks with no parent that aren't summary type
    final ungrouped = tasks
        .where((t) => !assignedTaskIds.contains(t.id))
        .toList();
    if (ungrouped.isNotEmpty) {
      const groupId = 'ungrouped';
      final isExpanded = _isSearchActive
          ? true
          : (_groupExpansionStates[groupId] ?? _allExpanded);
      groups.add(
        TaskGroup(
          key: const ValueKey(groupId),
          groupId: groupId,
          title: 'Ungrouped',
          groupColor: AppColors.textTertiary,
          tasks: ungrouped,
          allTasks: tasks,
          isExpanded: isExpanded,
          showProjectColumn: widget.showProjectColumn,
          projectColumnWidth: _projectColumnWidth,
          customerNameColumnWidth: _customerNameColumnWidth,
          jobNumberColumnWidth: _jobNumberColumnWidth,
          jobAddressColumnWidth: _jobAddressColumnWidth,
          statusColumnWidth: _statusColumnWidth,
          dueDateColumnWidth: _dueDateColumnWidth,
          assigneeColumnWidth: _assigneeColumnWidth,
          notesColumnWidth: _notesColumnWidth,
          progressColumnWidth: _progressColumnWidth,
          hiddenColumnIds: _hiddenColumnIds,
          projectNames: _projectNames,
          projectMap: _projectMap,
          propertyMap: _propertyMap,
          usersMap: usersMap,
          allWorkspaceUsers: allWorkspaceUsers,
          expansionStates: expansionStates,
          onToggle: () =>
              setState(() => _groupExpansionStates[groupId] = !isExpanded),
          onQuickAdd: (title) => _createTask(title),
          onDeleteTask: (taskId) => _deleteTask(taskId),
          onUngroupTask: _handleUngroupTask,
          onTaskExpandToggle: (taskId, expanded) {
            setState(() => _taskExpansionStates[taskId] = expanded);
          },
          onTaskDroppedOnHeader: (task) {
            // Remove from any phase (clear parent)
            _moveTaskToUngrouped(task);
          },
          onTaskDroppedOnTask: _handleTaskDroppedOnTask,
          onTaskDragStarted: _onTaskDragStarted,
          onTaskDragEnded: _onTaskDragEnded,
          isAnyTaskDragging: _isTaskDragging,
          selectedTaskIds: _selectedTaskIds,
          onSelectionChanged: _handleTaskSelectionChanged,
          onGroupSelectAll: _handleGroupSelectAll,
          showPhaseHierarchyGuides: true,
          commentCounts: _commentCounts,
          customSortSiblings: _columnSortComparator,
        ),
      );
    }

    return groups;
  }

  Widget _buildMetricFilteredView(
    List<Task> tasks,
    Map<String, AppUser> usersMap,
    List<AppUser> allWorkspaceUsers, {
    required Map<String, bool> expansionStates,
  }) {
    final metric = _metricFilter;
    if (metric == null) {
      return _buildFlatListView(tasks, usersMap, allWorkspaceUsers);
    }

    final groupId = 'metric_${metric.name}';
    final isExpanded = _isSearchActive
        ? true
        : (_groupExpansionStates[groupId] ?? _allExpanded);
    final group = TaskGroup(
      key: ValueKey(groupId),
      groupId: groupId,
      title: _metricFilterLabel(metric),
      groupColor: _metricFilterColor(metric),
      tasks: tasks,
      allTasks: tasks,
      isExpanded: isExpanded,
      showProjectColumn: widget.showProjectColumn,
      projectColumnWidth: _projectColumnWidth,
      customerNameColumnWidth: _customerNameColumnWidth,
      jobNumberColumnWidth: _jobNumberColumnWidth,
      jobAddressColumnWidth: _jobAddressColumnWidth,
      statusColumnWidth: _statusColumnWidth,
      dueDateColumnWidth: _dueDateColumnWidth,
      assigneeColumnWidth: _assigneeColumnWidth,
      notesColumnWidth: _notesColumnWidth,
      progressColumnWidth: _progressColumnWidth,
      hiddenColumnIds: _hiddenColumnIds,
      projectNames: _projectNames,
      projectMap: _projectMap,
      propertyMap: _propertyMap,
      usersMap: usersMap,
      allWorkspaceUsers: allWorkspaceUsers,
      expansionStates: expansionStates,
      onToggle: () =>
          setState(() => _groupExpansionStates[groupId] = !isExpanded),
      onQuickAdd: (title) => _createTask(title),
      onDeleteTask: (taskId) => _deleteTask(taskId),
      onUngroupTask: _handleUngroupTask,
      onTaskExpandToggle: (taskId, expanded) {
        setState(() => _taskExpansionStates[taskId] = expanded);
      },
      onTaskDroppedOnTask: _handleTaskDroppedOnTask,
      onTaskDragStarted: _onTaskDragStarted,
      onTaskDragEnded: _onTaskDragEnded,
      isAnyTaskDragging: _isTaskDragging,
      selectedTaskIds: _selectedTaskIds,
      onSelectionChanged: _handleTaskSelectionChanged,
      onGroupSelectAll: _handleGroupSelectAll,
      commentCounts: _commentCounts,
      customSortSiblings: _columnSortComparator,
    );

    return Column(
      children: [
        _buildTaskListHeader(),
        Expanded(
          child: _buildTaskListWithUngroupTarget(ListView(children: [group])),
        ),
        _buildTaskSummaryFooter(tasks),
      ],
    );
  }

  List<Task> _applyMetricFilter(List<Task> tasks, TaskMetricFilter metric) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    return tasks.where((task) {
      if (task.isComplete) {
        return false;
      }
      switch (metric) {
        case TaskMetricFilter.open:
          return true;
        case TaskMetricFilter.overdue:
          return task.isOverdue();
        case TaskMetricFilter.dueToday:
          final dueDate = task.dueDate;
          if (dueDate == null) return false;
          // Inclusive of exactly-midnight due dates (date-only tasks).
          return !dueDate.isBefore(todayStart) && dueDate.isBefore(todayEnd);
      }
    }).toList();
  }

  String _metricFilterLabel(TaskMetricFilter metric) {
    switch (metric) {
      case TaskMetricFilter.open:
        return 'Open';
      case TaskMetricFilter.overdue:
        return 'Overdue';
      case TaskMetricFilter.dueToday:
        return 'Due Today';
    }
  }

  Color _metricFilterColor(TaskMetricFilter metric) {
    switch (metric) {
      case TaskMetricFilter.open:
        return AppColors.info;
      case TaskMetricFilter.overdue:
        return AppColors.error;
      case TaskMetricFilter.dueToday:
        return AppColors.financialAccent;
    }
  }

  List<Task> _collectDescendants(
    String parentId,
    Map<String, List<Task>> childrenMap, [
    Set<String>? visited,
  ]) {
    visited ??= {};
    if (!visited.add(parentId)) return []; // Prevent circular reference loops
    final children = [...(childrenMap[parentId] ?? const <Task>[])];
    children.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final List<Task> result = [];
    for (final child in children) {
      result.add(child);
      result.addAll(_collectDescendants(child.id, childrenMap, visited));
    }
    return result;
  }

  _PhaseSummary _computePhaseSummary(Task phase, List<Task> phaseTasks) {
    final assigneeIds = <String>{...phase.assignedToIds};
    var standardTaskCount = 0;
    var standardTaskProgressTotal = 0;
    DateTime? dueDate;

    for (final task in phaseTasks) {
      if (task.taskType == TaskType.standard) {
        standardTaskCount++;
        standardTaskProgressTotal += task.progress;
      }

      assigneeIds.addAll(task.assignedToIds);

      final candidateDueDate = task.dueDate ?? task.getEffectiveDueDate();
      if (candidateDueDate != null &&
          (dueDate == null || candidateDueDate.isAfter(dueDate))) {
        dueDate = candidateDueDate;
      }
    }

    final progress = standardTaskCount == 0
        ? 0
        : (standardTaskProgressTotal / standardTaskCount).round();

    return _PhaseSummary(
      progress: progress,
      dueDate: dueDate,
      assigneeIds: assigneeIds.toList(growable: false),
    );
  }

  Future<void> _assignPhaseAssigneeToSubtasks({
    required List<Task> phaseTasks,
    required String? assigneeId,
  }) async {
    final assigneeIds = assigneeId == null ? <String>[] : <String>[assigneeId];
    if (phaseTasks.isEmpty) return;

    try {
      await Future.wait(
        phaseTasks.map(
          (task) => ServiceLocator.taskService.updateTask(
            taskId: task.id,
            assignedToIds: assigneeIds,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to assign phase tasks: $e')),
      );
    }
  }

  List<Widget> _buildFieldGroups(
    List<Task> tasks, {
    required Map<String, AppUser> usersMap,
    required List<AppUser> allWorkspaceUsers,
    required Map<String, bool> expansionStates,
    required String Function(Task) keyExtractor,
    required Map<String, String> labels,
    required Map<String, Color> colors,
    required List<String> ordering,
    required String quickAddField,
  }) {
    final Map<String, List<Task>> grouped = {};
    for (final t in tasks) {
      final key = keyExtractor(t);
      grouped.putIfAbsent(key, () => []).add(t);
    }

    final List<Widget> groups = [];
    for (final key in ordering) {
      final groupTasks = grouped[key] ?? [];
      final groupId = '${quickAddField}_$key';
      final isExpanded = _isSearchActive
          ? true
          : (_groupExpansionStates[groupId] ?? _allExpanded);

      groups.add(
        TaskGroup(
          key: ValueKey(groupId),
          groupId: groupId,
          title: labels[key] ?? key,
          groupColor: colors[key] ?? AppColors.textTertiary,
          tasks: groupTasks,
          allTasks: tasks,
          isExpanded: isExpanded,
          showProjectColumn: widget.showProjectColumn,
          projectColumnWidth: _projectColumnWidth,
          customerNameColumnWidth: _customerNameColumnWidth,
          jobNumberColumnWidth: _jobNumberColumnWidth,
          jobAddressColumnWidth: _jobAddressColumnWidth,
          statusColumnWidth: _statusColumnWidth,
          dueDateColumnWidth: _dueDateColumnWidth,
          assigneeColumnWidth: _assigneeColumnWidth,
          notesColumnWidth: _notesColumnWidth,
          progressColumnWidth: _progressColumnWidth,
          hiddenColumnIds: _hiddenColumnIds,
          projectNames: _projectNames,
          projectMap: _projectMap,
          propertyMap: _propertyMap,
          usersMap: usersMap,
          allWorkspaceUsers: allWorkspaceUsers,
          expansionStates: expansionStates,
          onToggle: () =>
              setState(() => _groupExpansionStates[groupId] = !isExpanded),
          onQuickAdd: (title) async {
            if (quickAddField == 'status') {
              await _createTask(title, status: key);
            } else if (quickAddField == 'priority') {
              await _createTask(title, priority: key);
            }
          },
          onDeleteTask: (taskId) => _deleteTask(taskId),
          onUngroupTask: _handleUngroupTask,
          onTaskExpandToggle: (taskId, expanded) {
            setState(() => _taskExpansionStates[taskId] = expanded);
          },
          onTaskDroppedOnHeader: (task) {
            // Update the field that this grouping is based on
            if (quickAddField == 'status') {
              ServiceLocator.taskService.updateTaskStatus(task.id, key);
            } else if (quickAddField == 'priority') {
              ServiceLocator.taskService.updateTaskPriority(task.id, key);
            }
          },
          onTaskDroppedOnTask: _handleTaskDroppedOnTask,
          onTaskDragStarted: _onTaskDragStarted,
          onTaskDragEnded: _onTaskDragEnded,
          isAnyTaskDragging: _isTaskDragging,
          selectedTaskIds: _selectedTaskIds,
          onSelectionChanged: _handleTaskSelectionChanged,
          onGroupSelectAll: _handleGroupSelectAll,
          commentCounts: _commentCounts,
          customSortSiblings: _columnSortComparator,
        ),
      );
    }

    // Tasks with keys not in ordering
    final otherTasks = tasks
        .where((t) => !ordering.contains(keyExtractor(t)))
        .toList();
    if (otherTasks.isNotEmpty) {
      const groupId = 'other';
      final isExpanded = _isSearchActive
          ? true
          : (_groupExpansionStates[groupId] ?? _allExpanded);
      groups.add(
        TaskGroup(
          key: const ValueKey(groupId),
          groupId: groupId,
          title: 'Other',
          groupColor: AppColors.textTertiary,
          tasks: otherTasks,
          allTasks: tasks,
          isExpanded: isExpanded,
          showProjectColumn: widget.showProjectColumn,
          projectColumnWidth: _projectColumnWidth,
          customerNameColumnWidth: _customerNameColumnWidth,
          jobNumberColumnWidth: _jobNumberColumnWidth,
          jobAddressColumnWidth: _jobAddressColumnWidth,
          statusColumnWidth: _statusColumnWidth,
          dueDateColumnWidth: _dueDateColumnWidth,
          assigneeColumnWidth: _assigneeColumnWidth,
          notesColumnWidth: _notesColumnWidth,
          progressColumnWidth: _progressColumnWidth,
          hiddenColumnIds: _hiddenColumnIds,
          projectNames: _projectNames,
          projectMap: _projectMap,
          propertyMap: _propertyMap,
          usersMap: usersMap,
          allWorkspaceUsers: allWorkspaceUsers,
          expansionStates: expansionStates,
          onToggle: () =>
              setState(() => _groupExpansionStates[groupId] = !isExpanded),
          onQuickAdd: (title) => _createTask(title),
          onDeleteTask: (taskId) => _deleteTask(taskId),
          onUngroupTask: _handleUngroupTask,
          onTaskExpandToggle: (taskId, expanded) {
            setState(() => _taskExpansionStates[taskId] = expanded);
          },
          onTaskDroppedOnTask: _handleTaskDroppedOnTask,
          onTaskDragStarted: _onTaskDragStarted,
          onTaskDragEnded: _onTaskDragEnded,
          isAnyTaskDragging: _isTaskDragging,
          selectedTaskIds: _selectedTaskIds,
          onSelectionChanged: _handleTaskSelectionChanged,
          onGroupSelectAll: _handleGroupSelectAll,
          commentCounts: _commentCounts,
          customSortSiblings: _columnSortComparator,
        ),
      );
    }

    return groups;
  }

  List<Widget> _buildAssigneeGroups(
    List<Task> tasks,
    Map<String, AppUser> usersMap,
    List<AppUser> allWorkspaceUsers, {
    required Map<String, bool> expansionStates,
  }) {
    final Map<String, List<Task>> grouped = {};
    const unassignedKey = '_unassigned_';

    for (final t in tasks) {
      if (t.assignedToIds.isEmpty) {
        grouped.putIfAbsent(unassignedKey, () => []).add(t);
      } else {
        final key = t.assignedToIds.first;
        grouped.putIfAbsent(key, () => []).add(t);
      }
    }

    final List<Widget> groups = [];

    for (final entry in grouped.entries) {
      final key = entry.key;
      final groupId = 'assignee_$key';
      final isExpanded = _isSearchActive
          ? true
          : (_groupExpansionStates[groupId] ?? _allExpanded);
      // label used for display in TaskGroup title

      groups.add(
        key == unassignedKey
            ? TaskGroup(
                key: ValueKey(groupId),
                groupId: groupId,
                title: 'Unassigned',
                groupColor: AppColors.textTertiary,
                tasks: entry.value,
                allTasks: tasks,
                isExpanded: isExpanded,
                showProjectColumn: widget.showProjectColumn,
                projectColumnWidth: _projectColumnWidth,
                customerNameColumnWidth: _customerNameColumnWidth,
                jobNumberColumnWidth: _jobNumberColumnWidth,
                jobAddressColumnWidth: _jobAddressColumnWidth,
                statusColumnWidth: _statusColumnWidth,
                dueDateColumnWidth: _dueDateColumnWidth,
                assigneeColumnWidth: _assigneeColumnWidth,
                notesColumnWidth: _notesColumnWidth,
                progressColumnWidth: _progressColumnWidth,
                hiddenColumnIds: _hiddenColumnIds,
                projectNames: _projectNames,
                projectMap: _projectMap,
                propertyMap: _propertyMap,
                usersMap: usersMap,
                allWorkspaceUsers: allWorkspaceUsers,
                expansionStates: expansionStates,
                onToggle: () => setState(
                  () => _groupExpansionStates[groupId] = !isExpanded,
                ),
                onQuickAdd: (title) => _createTask(title),
                onDeleteTask: (taskId) => _deleteTask(taskId),
                onUngroupTask: _handleUngroupTask,
                onTaskExpandToggle: (taskId, expanded) {
                  setState(() => _taskExpansionStates[taskId] = expanded);
                },
                onTaskDroppedOnHeader: (task) {
                  ServiceLocator.taskService.updateTask(
                    taskId: task.id,
                    assignedToIds: [],
                  );
                },
                onTaskDroppedOnTask: _handleTaskDroppedOnTask,
                onTaskDragStarted: _onTaskDragStarted,
                onTaskDragEnded: _onTaskDragEnded,
                isAnyTaskDragging: _isTaskDragging,
                commentCounts: _commentCounts,
                customSortSiblings: _columnSortComparator,
              )
            : TaskGroup(
                key: ValueKey(groupId),
                groupId: groupId,
                title:
                    usersMap[key]?.displayName ?? usersMap[key]?.email ?? key,
                groupColor: AppColors.info,
                tasks: entry.value,
                allTasks: tasks,
                isExpanded: isExpanded,
                showProjectColumn: widget.showProjectColumn,
                projectColumnWidth: _projectColumnWidth,
                customerNameColumnWidth: _customerNameColumnWidth,
                jobNumberColumnWidth: _jobNumberColumnWidth,
                jobAddressColumnWidth: _jobAddressColumnWidth,
                statusColumnWidth: _statusColumnWidth,
                dueDateColumnWidth: _dueDateColumnWidth,
                assigneeColumnWidth: _assigneeColumnWidth,
                notesColumnWidth: _notesColumnWidth,
                progressColumnWidth: _progressColumnWidth,
                hiddenColumnIds: _hiddenColumnIds,
                projectNames: _projectNames,
                projectMap: _projectMap,
                propertyMap: _propertyMap,
                usersMap: usersMap,
                allWorkspaceUsers: allWorkspaceUsers,
                expansionStates: expansionStates,
                onToggle: () => setState(
                  () => _groupExpansionStates[groupId] = !isExpanded,
                ),
                onQuickAdd: (title) => _createTask(title, assigneeId: key),
                onDeleteTask: (taskId) => _deleteTask(taskId),
                onUngroupTask: _handleUngroupTask,
                onTaskExpandToggle: (taskId, expanded) {
                  setState(() => _taskExpansionStates[taskId] = expanded);
                },
                onTaskDroppedOnHeader: (task) {
                  ServiceLocator.taskService.updateTask(
                    taskId: task.id,
                    assignedToIds: [key],
                  );
                },
                onTaskDroppedOnTask: _handleTaskDroppedOnTask,
                onTaskDragStarted: _onTaskDragStarted,
                onTaskDragEnded: _onTaskDragEnded,
                isAnyTaskDragging: _isTaskDragging,
                commentCounts: _commentCounts,
                customSortSiblings: _columnSortComparator,
              ),
      );
    }

    return groups;
  }

  List<Widget> _buildPropertyGroups(
    List<Task> tasks,
    Map<String, AppUser> usersMap,
    List<AppUser> allWorkspaceUsers, {
    required Map<String, bool> expansionStates,
  }) {
    final Map<String, List<Task>> grouped = {};
    const noPropertyKey = '_no_property_';

    for (final t in tasks) {
      if (t.propertyIds.isEmpty) {
        grouped.putIfAbsent(noPropertyKey, () => []).add(t);
      } else {
        final key = t.propertyIds.first;
        grouped.putIfAbsent(key, () => []).add(t);
      }
    }

    return grouped.entries.map((entry) {
      final key = entry.key;
      final groupId = 'property_$key';
      final isExpanded = _isSearchActive
          ? true
          : (_groupExpansionStates[groupId] ?? _allExpanded);
      final label = key == noPropertyKey ? 'No Property' : key;

      return TaskGroup(
        key: ValueKey(groupId),
        groupId: groupId,
        title: label,
        groupColor: key == noPropertyKey
            ? AppColors.textTertiary
            : AppColors.financialAccent,
        tasks: entry.value,
        allTasks: tasks,
        isExpanded: isExpanded,
        showProjectColumn: widget.showProjectColumn,
        projectColumnWidth: _projectColumnWidth,
        customerNameColumnWidth: _customerNameColumnWidth,
        jobNumberColumnWidth: _jobNumberColumnWidth,
        jobAddressColumnWidth: _jobAddressColumnWidth,
        statusColumnWidth: _statusColumnWidth,
        dueDateColumnWidth: _dueDateColumnWidth,
        assigneeColumnWidth: _assigneeColumnWidth,
        notesColumnWidth: _notesColumnWidth,
        progressColumnWidth: _progressColumnWidth,
        hiddenColumnIds: _hiddenColumnIds,
        projectNames: _projectNames,
        projectMap: _projectMap,
        propertyMap: _propertyMap,
        usersMap: usersMap,
        allWorkspaceUsers: allWorkspaceUsers,
        expansionStates: expansionStates,
        onToggle: () =>
            setState(() => _groupExpansionStates[groupId] = !isExpanded),
        onQuickAdd: (title) => _createTask(
          title,
          propertyIds: key == noPropertyKey ? null : [key],
        ),
        onDeleteTask: (taskId) => _deleteTask(taskId),
        onUngroupTask: _handleUngroupTask,
        onTaskExpandToggle: (taskId, expanded) {
          setState(() => _taskExpansionStates[taskId] = expanded);
        },
        onTaskDroppedOnHeader: (task) {
          ServiceLocator.taskService.updateTask(
            taskId: task.id,
            propertyIds: key == noPropertyKey ? [] : [key],
          );
        },
        onTaskDroppedOnTask: _handleTaskDroppedOnTask,
        onTaskDragStarted: _onTaskDragStarted,
        onTaskDragEnded: _onTaskDragEnded,
        isAnyTaskDragging: _isTaskDragging,
        commentCounts: _commentCounts,
        customSortSiblings: _columnSortComparator,
      );
    }).toList();
  }

  Widget _buildFlatListView(
    List<Task> tasks,
    Map<String, AppUser> usersMap,
    List<AppUser> allWorkspaceUsers,
  ) {
    // Sort: column sort takes priority, otherwise incomplete first then by due date.
    final sortedTasks = [...tasks];
    if (_sortColumn != null) {
      _applyColumnSort(sortedTasks);
    } else {
      sortedTasks.sort((a, b) {
        if (a.isComplete != b.isComplete) {
          return a.isComplete ? 1 : -1;
        }
        if (a.dueDate != null && b.dueDate != null) {
          return a.dueDate!.compareTo(b.dueDate!);
        }
        if (a.dueDate != null) {
          return -1;
        }
        if (b.dueDate != null) {
          return 1;
        }
        return a.title.compareTo(b.title);
      });
    }

    final rowCount = sortedTasks.length + 1;
    final body = _buildTaskListWithUngroupTarget(
      ListView.builder(
        itemCount: rowCount,
        itemBuilder: (context, index) {
          if (index == sortedTasks.length) {
            return QuickAddRow(
              groupColor: AppColors.textTertiary,
              onSubmit: (title) => _createTask(title),
            );
          }
          final task = sortedTasks[index];
          return TaskRow(
            key: ValueKey(task.id),
            task: task,
            allTasks: sortedTasks,
            showProjectColumn: widget.showProjectColumn,
            projectColumnWidth: _projectColumnWidth,
            customerNameColumnWidth: _customerNameColumnWidth,
            jobNumberColumnWidth: _jobNumberColumnWidth,
            jobAddressColumnWidth: _jobAddressColumnWidth,
            statusColumnWidth: _statusColumnWidth,
            dueDateColumnWidth: _dueDateColumnWidth,
            assigneeColumnWidth: _assigneeColumnWidth,
            notesColumnWidth: _notesColumnWidth,
            progressColumnWidth: _progressColumnWidth,
            hiddenColumnIds: _hiddenColumnIds,
            projectName: _projectNames[task.projectId],
            project: _projectMap[task.projectId],
            propertyMap: _propertyMap,
            usersMap: usersMap,
            allWorkspaceUsers: allWorkspaceUsers,
            onDelete: () => _deleteTask(task.id),
            onUngroup: task.taskType == TaskType.summary
                ? () => _handleUngroupTask(task)
                : null,
            onTaskDroppedOnTask: _handleTaskDroppedOnTask,
            onDragStarted: _onTaskDragStarted,
            onDragEnded: _onTaskDragEnded,
            isAnyTaskDragging: _isTaskDragging,
            isSelected: _selectedTaskIds.contains(task.id),
            onSelectionChanged: _handleTaskSelectionChanged,
            commentCount: _commentCounts[task.id],
          );
        },
      ),
    );
    if (_fitToScreen) {
      final chrome = ChromeColors.of(context);
      Widget table = Column(
        children: [
          _buildTaskListHeader(),
          Expanded(child: body),
          _buildTaskSummaryFooter(sortedTasks),
        ],
      );
      if (chrome.isDark) {
        table = Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: const [
              BoxShadow(
                color: Color(0x30000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: table,
        );
      }
      return table;
    }
    return TableLayoutShell(
      minTableWidth: _scrollModeMinWidth,
      header: _buildTaskListHeader(),
      body: body,
      footer: _buildTaskSummaryFooter(sortedTasks),
    );
  }

  /// Handle a task being dropped onto another task row with zone-based behavior.
  void _handleTaskDroppedOnTask(Task dragged, Task target, DropZone zone) {
    switch (zone) {
      case DropZone.child:
        // Make the dragged task a child of the target
        ServiceLocator.taskService.updateTask(
          taskId: dragged.id,
          parentId: target.id,
        );
      case DropZone.above:
        // Place above target: same parent, sort order just before target
        final sortOrder = _computeSortOrderBefore(target);
        if (target.parentId == null) {
          ServiceLocator.taskService.updateTask(
            taskId: dragged.id,
            clearParentId: true,
            sortOrder: sortOrder,
          );
        } else {
          ServiceLocator.taskService.updateTask(
            taskId: dragged.id,
            parentId: target.parentId,
            sortOrder: sortOrder,
          );
        }
      case DropZone.below:
        // Place below target: same parent, sort order just after target
        final sortOrder = _computeSortOrderAfter(target);
        if (target.parentId == null) {
          ServiceLocator.taskService.updateTask(
            taskId: dragged.id,
            clearParentId: true,
            sortOrder: sortOrder,
          );
        } else {
          ServiceLocator.taskService.updateTask(
            taskId: dragged.id,
            parentId: target.parentId,
            sortOrder: sortOrder,
          );
        }
      case DropZone.unparent:
        // Move up one level: set parent to grandparent (or clear if depth 1)
        final grandparentId = _findGrandparentId(target);
        if (grandparentId == null) {
          ServiceLocator.taskService.updateTask(
            taskId: dragged.id,
            clearParentId: true,
            sortOrder: target.sortOrder,
          );
        } else {
          ServiceLocator.taskService.updateTask(
            taskId: dragged.id,
            parentId: grandparentId,
            sortOrder: target.sortOrder,
          );
        }
      case DropZone.none:
        break;
    }
  }

  /// Compute a sort order value just before the target task among its siblings.
  double _computeSortOrderBefore(Task target) {
    final siblings = _getSiblings(target);
    final idx = siblings.indexWhere((t) => t.id == target.id);
    if (idx <= 0) {
      return target.sortOrder - 1000;
    }
    return (siblings[idx - 1].sortOrder + target.sortOrder) / 2;
  }

  /// Compute a sort order value just after the target task among its siblings.
  double _computeSortOrderAfter(Task target) {
    final siblings = _getSiblings(target);
    final idx = siblings.indexWhere((t) => t.id == target.id);
    if (idx < 0 || idx >= siblings.length - 1) {
      return target.sortOrder + 1000;
    }
    return (target.sortOrder + siblings[idx + 1].sortOrder) / 2;
  }

  List<double> _computeInsertedSortOrders({
    required double? before,
    required double? after,
    required int count,
  }) {
    if (count <= 0) return const [];
    if (before != null && after != null) {
      final gap = (after - before) / (count + 1);
      return List<double>.generate(
        count,
        (index) => before + gap * (index + 1),
      );
    }
    if (before != null) {
      return List<double>.generate(
        count,
        (index) => before + 1000 * (index + 1),
      );
    }
    if (after != null) {
      final start = after - 1000 * count;
      return List<double>.generate(count, (index) => start + 1000 * index);
    }
    return List<double>.generate(
      count,
      (index) => 1000 * (index + 1).toDouble(),
    );
  }

  Future<void> _handleUngroupTask(Task task) async {
    final directChildren =
        _lastAllTasks
            .where((candidate) => candidate.parentId == task.id)
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    if (task.taskType != TaskType.summary || directChildren.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This grouped task has no subtasks to ungroup'),
          ),
        );
      }
      return;
    }

    final siblings = _getSiblings(task);
    final groupIndex = siblings.indexWhere(
      (candidate) => candidate.id == task.id,
    );
    final beforeSortOrder = groupIndex > 0
        ? siblings[groupIndex - 1].sortOrder
        : null;
    final afterSortOrder = groupIndex >= 0 && groupIndex < siblings.length - 1
        ? siblings[groupIndex + 1].sortOrder
        : null;
    final insertedSortOrders = _computeInsertedSortOrders(
      before: beforeSortOrder,
      after: afterSortOrder,
      count: directChildren.length,
    );

    try {
      for (var index = 0; index < directChildren.length; index++) {
        final child = directChildren[index];
        if (task.parentId == null) {
          await ServiceLocator.taskService.updateTask(
            taskId: child.id,
            clearParentId: true,
            sortOrder: insertedSortOrders[index],
          );
        } else {
          await ServiceLocator.taskService.updateTask(
            taskId: child.id,
            parentId: task.parentId,
            sortOrder: insertedSortOrders[index],
          );
        }
      }

      await ServiceLocator.taskService.deleteTask(task.id);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ungrouped "${task.title}"')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserFacingError.uiMessage(e, action: 'ungroup task')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  /// Get sibling tasks (tasks with the same parentId), sorted by sortOrder.
  List<Task> _getSiblings(Task task) {
    final siblings = _lastAllTasks
        .where((t) => t.parentId == task.parentId)
        .toList();
    siblings.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return siblings;
  }

  /// Find the grandparent ID of a task (the parent of its parent).
  String? _findGrandparentId(Task task) {
    if (task.parentId == null) return null;
    final parent = _lastAllTasks
        .where((t) => t.id == task.parentId)
        .firstOrNull;
    return parent?.parentId;
  }

  Widget _buildTaskListWithUngroupTarget(Widget listContent) {
    return listContent;
  }

  Widget _buildTaskListHeader() {
    final labelStyle = TableViewStyles.headerLabelStyle(context);
    final isTaskSorted = _sortColumn == 'task';

    return TableHeaderRow(
      children: [
        const SizedBox(width: 24), // Selection checkbox column
        const SizedBox(width: 4),
        const SizedBox(width: 20), // Tree toggle area
        const SizedBox(width: 8),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              _TaskColumnHeader(
                label: 'Task',
                textStyle: labelStyle,
                isSorted: isTaskSorted,
                ascending: isTaskSorted ? _sortAscending : true,
                onTap: () {
                  setState(() {
                    if (_sortColumn == 'task') {
                      if (_sortAscending) {
                        _sortAscending = false;
                      } else {
                        _sortColumn = null;
                        _sortAscending = true;
                      }
                    } else {
                      _sortColumn = 'task';
                      _sortAscending = true;
                    }
                  });
                },
              ),
              Positioned(
                right: 0,
                top: 4,
                bottom: 4,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragUpdate: (details) {
                      _resizeFirstVisibleRightColumn(details.delta.dx);
                    },
                    child: SizedBox(
                      width: 8,
                      child: Center(
                        child: Container(
                          width: 1,
                          height: 16,
                          color: Theme.of(
                            context,
                          ).dividerColor.withValues(alpha: 0.65),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        ..._buildTaskHeaderCells(labelStyle),
      ],
    );
  }

  Widget _buildTaskSummaryFooter(List<Task> tasks) {
    if (tasks.isEmpty) return const SizedBox.shrink();

    final total = tasks.length;
    final completed = tasks.where((t) => t.status == 'done').length;
    final overdue = tasks.where((t) => t.isOverdue()).length;
    final avgProgress = total > 0
        ? (tasks.fold<int>(0, (sum, t) => sum + t.progress) / total).round()
        : 0;

    final colorScheme = Theme.of(context).colorScheme;
    const footerTextStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );

    return TableSummaryFooter(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      children: [
        const SizedBox(width: 24), // Checkbox column
        const SizedBox(width: 4),
        const SizedBox(width: 20), // Tree toggle area
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$total task${total == 1 ? '' : 's'}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: colorScheme.onSurface,
            ),
          ),
        ),
        if (_isColumnVisible('project')) ...[
          SizedBox(width: _projectColumnWidth),
          const SizedBox(width: _columnGap),
        ],
        if (_isColumnVisible('customer_name')) ...[
          SizedBox(width: _customerNameColumnWidth),
          const SizedBox(width: _columnGap),
        ],
        if (_isColumnVisible('job_number')) ...[
          SizedBox(width: _jobNumberColumnWidth),
          const SizedBox(width: _columnGap),
        ],
        if (_isColumnVisible('job_address')) ...[
          SizedBox(width: _jobAddressColumnWidth),
          const SizedBox(width: _columnGap),
        ],
        SizedBox(
          width: _statusColumnWidth,
          child: Text(
            '$completed done',
            style: footerTextStyle.copyWith(color: AppColors.success),
          ),
        ),
        const SizedBox(width: _columnGap),
        SizedBox(
          width: _dueDateColumnWidth,
          child: overdue > 0
              ? Text(
                  '$overdue overdue',
                  style: footerTextStyle.copyWith(color: AppColors.error),
                )
              : Text(
                  '-',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
        ),
        const SizedBox(width: _columnGap),
        SizedBox(
          width: _assigneeColumnWidth,
          child: Text(
            '-',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
          ),
        ),
        const SizedBox(width: _columnGap),
        SizedBox(
          width: _notesColumnWidth,
          child: Text(
            '-',
            textAlign: TextAlign.center,
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
          ),
        ),
        const SizedBox(width: _columnGap),
        SizedBox(
          width: _progressColumnWidth,
          child: Text(
            '$avgProgress%',
            style: footerTextStyle.copyWith(
              color: avgProgress >= 100
                  ? AppColors.success
                  : avgProgress >= 50
                  ? const Color(0xFF4A90A4)
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  void _resizeFirstVisibleRightColumn(double dx) {
    // The drag is on the right edge of the Task (Expanded) column.
    // Dragging right shrinks the first visible right column; left grows it.
    // We negate dx because increasing the task area means decreasing the
    // adjacent column width.
    const minWidth = 40.0;
    const maxWidth = 500.0;

    if (_isColumnVisible('project')) {
      setState(() {
        _projectColumnWidth = (_projectColumnWidth - dx).clamp(
          minWidth,
          maxWidth,
        );
      });
    } else if (_isColumnVisible('customer_name')) {
      setState(() {
        _customerNameColumnWidth = (_customerNameColumnWidth - dx).clamp(
          minWidth,
          maxWidth,
        );
      });
    } else if (_isColumnVisible('job_number')) {
      setState(() {
        _jobNumberColumnWidth = (_jobNumberColumnWidth - dx).clamp(
          minWidth,
          maxWidth,
        );
      });
    } else if (_isColumnVisible('job_address')) {
      setState(() {
        _jobAddressColumnWidth = (_jobAddressColumnWidth - dx).clamp(
          minWidth,
          maxWidth,
        );
      });
    } else {
      setState(() {
        _statusColumnWidth = (_statusColumnWidth - dx).clamp(
          minWidth,
          maxWidth,
        );
      });
    }
  }

  List<Widget> _buildTaskHeaderCells(TextStyle? labelStyle) {
    final projectTerminology = context
        .watch<WorkspaceProvider>()
        .projectTerminology;
    final cells = buildTableHeaderCells(
      context: context,
      columns: _taskHeaderColumns(projectTerminology),
      widths: _taskHeaderWidths,
      isVisible: (column) => _isColumnVisible(column.id),
      textStyle: labelStyle,
      iconColor: AppColors.textSecondary,
      dividerColor: Theme.of(context).dividerColor.withValues(alpha: 0.65),
      showHoverAffordances: true,
      headerMenuBuilder: (column, _) =>
          _buildHeaderMenuItems(column, projectTerminology),
      onHeaderMenuSelected: _handleHeaderMenuSelection,
      onSortTap: _onColumnSortTap,
      sortedColumnId: _sortColumn,
      sortAscending: _sortAscending,
      onColumnResize: (resize) {
        setState(() {
          switch (resize.columnId) {
            case 'project':
              _projectColumnWidth = resize.width;
              break;
            case 'customer_name':
              _customerNameColumnWidth = resize.width;
              break;
            case 'job_number':
              _jobNumberColumnWidth = resize.width;
              break;
            case 'job_address':
              _jobAddressColumnWidth = resize.width;
              break;
            case 'status':
              _statusColumnWidth = resize.width;
              break;
            case 'due_date':
              _dueDateColumnWidth = resize.width;
              break;
            case 'assignee':
              _assigneeColumnWidth = resize.width;
              break;
            case 'notes':
              _notesColumnWidth = resize.width;
              break;
            case 'progress':
              _progressColumnWidth = resize.width;
              break;
          }
        });
      },
    );

    final withGaps = <Widget>[];
    for (var i = 0; i < cells.length; i++) {
      if (i > 0) withGaps.add(const SizedBox(width: _columnGap));
      withGaps.add(cells[i]);
    }
    return withGaps;
  }

  List<PopupMenuEntry<String>> _buildHeaderMenuItems(
    TableColumnSchema column,
    String projectLabel,
  ) {
    final groupBy = _groupByForColumn(column.id);
    final columnLabel =
        column.label ?? column.tooltip ?? _columnLabel(column.id, projectLabel);
    return [
      PopupMenuItem<String>(
        value: 'group_by',
        enabled: groupBy != null,
        child: Text(
          groupBy != null
              ? 'Group by $columnLabel'
              : 'Grouping unavailable for $columnLabel',
        ),
      ),
    ];
  }

  void _handleHeaderMenuSelection(TableColumnSchema column, String value) {
    if (value != 'group_by') return;
    final groupBy = _groupByForColumn(column.id);
    if (groupBy == null) return;
    setState(() {
      _groupBy = groupBy;
    });
  }

  void _onColumnSortTap(TableColumnSchema column) {
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

  /// Returns a comparator for the active column sort, or null if no sort is active.
  Comparator<Task>? get _columnSortComparator {
    if (_sortColumn == null) return null;
    final asc = _sortAscending;
    return (a, b) {
      int cmp;
      switch (_sortColumn) {
        case 'status':
          const order = {
            'not_started': 0,
            'working_on_it': 1,
            'stuck': 2,
            'done': 3,
          };
          cmp = (order[a.status] ?? 0).compareTo(order[b.status] ?? 0);
          break;
        case 'due_date':
          final ad = a.dueDate;
          final bd = b.dueDate;
          if (ad == null && bd == null) {
            cmp = 0;
          } else if (ad == null) {
            cmp = 1;
          } else if (bd == null) {
            cmp = -1;
          } else {
            cmp = ad.compareTo(bd);
          }
          break;
        case 'assignee':
          final usersById = {for (final u in _lastAllWorkspaceUsers) u.id: u};
          String nameFor(Task t) {
            if (t.assignedToIds.isEmpty) {
              return '\uffff'; // sort unassigned last
            }
            final user = usersById[t.assignedToIds.first];
            return user?.displayName?.toLowerCase() ?? t.assignedToIds.first;
          }
          cmp = nameFor(a).compareTo(nameFor(b));
          break;
        case 'progress':
          cmp = a.progress.compareTo(b.progress);
          break;
        case 'project':
          final aProject = _projectNames[a.projectId] ?? '';
          final bProject = _projectNames[b.projectId] ?? '';
          cmp = aProject.toLowerCase().compareTo(bProject.toLowerCase());
          break;
        case 'task':
          cmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          break;
        default:
          cmp = 0;
      }
      return asc ? cmp : -cmp;
    };
  }

  /// Apply the active column sort to a list of tasks (in-place).
  void _applyColumnSort(List<Task> tasks) {
    final comparator = _columnSortComparator;
    if (comparator == null) return;
    tasks.sort(comparator);
  }

  GroupBy? _groupByForColumn(String columnId) {
    return switch (columnId) {
      'project' => GroupBy.phase,
      'status' => GroupBy.status,
      'assignee' => GroupBy.assignee,
      _ => null,
    };
  }

  String _columnLabel(String columnId, String projectLabel) {
    return switch (columnId) {
      'project' => projectLabel,
      'due_date' => 'Due date',
      'notes' => 'Notes',
      'progress' => 'Progress',
      _ => columnId,
    };
  }

  // ── Selection handling ──

  void _handleTaskSelectionChanged(Task task, bool isSelected) {
    setState(() {
      if (isSelected) {
        _selectedTaskIds.add(task.id);
      } else {
        _selectedTaskIds.remove(task.id);
      }
    });
  }

  void _handleGroupSelectAll(List<Task> groupTasks, bool selectAll) {
    setState(() {
      if (selectAll) {
        _selectedTaskIds.addAll(groupTasks.map((t) => t.id));
      } else {
        _selectedTaskIds.removeAll(groupTasks.map((t) => t.id).toSet());
      }
    });
  }

  Future<void> _handleMassDelete() async {
    final count = _selectedTaskIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Tasks'),
        content: Text(
          'Are you sure you want to delete $count task${count > 1 ? 's' : ''}? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final idsToDelete = _selectedTaskIds.toList();
    setState(() => _selectedTaskIds.clear());

    try {
      await Future.wait(
        idsToDelete.map((id) => ServiceLocator.taskService.deleteTask(id)),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted $count task${count > 1 ? 's' : ''}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleExport() async {
    final usersMap = {for (final u in _lastAllWorkspaceUsers) u.id: u};
    try {
      await TaskExport().exportTasksToCsv(
        tasks: _lastAllTasks,
        projectMap: _projectMap,
        usersMap: usersMap,
        fileLabel: 'tasks',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.uiMessage(e, action: 'export tasks')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _handleMassEdit() {
    final selectedTasks = _lastAllTasks
        .where((task) => _selectedTaskIds.contains(task.id))
        .toList();
    if (selectedTasks.isEmpty) return;

    showMassEditDialog(
      context,
      tasks: selectedTasks,
      allTasks: _lastAllTasks,
      allWorkspaceUsers: _lastAllWorkspaceUsers,
      onTasksUpdated: (updatedTasks) {
        for (final updatedTask in updatedTasks) {
          ServiceLocator.taskService.updateTask(
            taskId: updatedTask.id,
            status: updatedTask.status,
            progress: updatedTask.progress,
            startDate: updatedTask.startDate,
            dueDate: updatedTask.dueDate,
            assignedToIds: updatedTask.assignedToIds,
            estimatedDuration: updatedTask.estimatedDuration,
            isComplete: updatedTask.isComplete,
          );
        }
        setState(() => _selectedTaskIds.clear());
      },
      onClone: () => _handleMassClone(selectedTasks),
    );
  }

  Future<void> _handleMassClone(List<Task> selectedTasks) async {
    try {
      await ServiceLocator.taskService.cloneMultipleTasks(
        selectedTasks: selectedTasks,
        allTasks: _lastAllTasks,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Cloned ${selectedTasks.length} item${selectedTasks.length > 1 ? 's' : ''}',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        setState(() => _selectedTaskIds.clear());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to clone: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _onTaskDragStarted() {
    if (!_isTaskDragging) {
      setState(() => _isTaskDragging = true);
    }
  }

  void _onTaskDragEnded() {
    if (_isTaskDragging) {
      setState(() => _isTaskDragging = false);
    }
  }

  void _moveTaskToUngrouped(Task task) {
    ServiceLocator.taskService.updateTask(taskId: task.id, clearParentId: true);
  }

  Future<void> _createTask(
    String title, {
    String? parentId,
    String? projectId,
    String? status,
    String? priority,
    String? assigneeId,
    List<String>? propertyIds,
  }) async {
    // Determine which project to create the task in
    final pid = projectId ?? widget.projectId;
    final assigneeIds = assigneeId != null ? <String>[assigneeId] : <String>[];
    final linkedPropertyIds = propertyIds ?? <String>[];

    if (pid == null) {
      // For all-tasks view, need to pick a project
      final projects = await ServiceLocator.projectService.getProjectsOnce(
        widget.workspaceId,
      );
      if (projects.isEmpty || !mounted) return;
      if (projects.length == 1) {
        await ServiceLocator.taskService.createTask(
          workspaceId: widget.workspaceId,
          projectId: projects.first.id,
          title: title,
          parentId: parentId,
          status: status ?? 'not_started',
          priority: priority ?? 'medium',
          assignedToIds: assigneeIds,
          propertyIds: linkedPropertyIds,
        );
        return;
      }
      // Show picker
      if (!mounted) return;
      final selected = await showDialog<Project>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            'Select ${singularProjectTerminology(context.read<WorkspaceProvider>().projectTerminology)}',
          ),
          content: SizedBox(
            width: 300,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: projects.length,
              itemBuilder: (_, i) => ListTile(
                title: Text(projects[i].name),
                onTap: () => Navigator.pop(ctx, projects[i]),
              ),
            ),
          ),
        ),
      );
      if (selected == null) return;
      await ServiceLocator.taskService.createTask(
        workspaceId: widget.workspaceId,
        projectId: selected.id,
        title: title,
        parentId: parentId,
        status: status ?? 'not_started',
        priority: priority ?? 'medium',
        assignedToIds: assigneeIds,
        propertyIds: linkedPropertyIds,
      );
      return;
    }

    await ServiceLocator.taskService.createTask(
      workspaceId: widget.workspaceId,
      projectId: pid,
      title: title,
      parentId: parentId,
      status: status ?? 'not_started',
      priority: priority ?? 'medium',
      assignedToIds: assigneeIds,
      propertyIds: linkedPropertyIds,
    );
  }

  Future<void> _createPhaseGroup() async {
    if (widget.projectId == null) return;
    await ServiceLocator.taskService.createTask(
      workspaceId: widget.workspaceId,
      projectId: widget.projectId!,
      title: 'New Phase',
      taskType: TaskType.summary,
    );
  }

  Future<void> _deleteTask(String taskId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Task'),
        content: const Text('Are you sure you want to delete this task?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ServiceLocator.taskService.deleteTask(taskId);
    }
  }
}

class _PhaseSummary {
  final int progress;
  final DateTime? dueDate;
  final List<String> assigneeIds;

  const _PhaseSummary({
    required this.progress,
    required this.dueDate,
    required this.assigneeIds,
  });
}

/// Data holder for a phase section in the mobile list.
class _MobileSection {
  final Task phase;
  final List<Task> tasks;
  final int doneCount;
  final int progress;
  // True when every task is hidden (completed phase under "hide done"); the
  // section falls back to showing the full set but stays collapsed by default.
  final bool allHidden;
  const _MobileSection({
    required this.phase,
    required this.tasks,
    required this.doneCount,
    required this.progress,
    this.allHidden = false,
  });
}

/// Data holder for a generic (status / priority / assignee / property) group
/// in the mobile/Cards list.
class _MobileGroupData {
  final String groupId;
  final String title;
  final Color color;
  final List<Task> tasks;
  const _MobileGroupData({
    required this.groupId,
    required this.title,
    required this.color,
    required this.tasks,
  });

  int get taskCount => tasks.length;
  int get doneCount => tasks.where((t) => t.isComplete).length;
  int get progress {
    if (tasks.isEmpty) return 0;
    final sum = tasks.fold<int>(0, (acc, t) => acc + t.progress);
    return (sum / tasks.length).round();
  }
}

/// Lightweight list-item discriminated union for the mobile flat list.
class _MobileListItem {
  final Task? task;
  final _MobileSection? section;
  final _MobileGroupData? group;
  final String? groupId;
  final bool? isExpanded;
  final String? headerTitle;
  final Color? headerColor;
  final bool isPlainHeader;

  const _MobileListItem._({
    this.task,
    this.section,
    this.group,
    this.groupId,
    this.isExpanded,
    this.headerTitle,
    this.headerColor,
    this.isPlainHeader = false,
  });

  factory _MobileListItem.task(Task t) => _MobileListItem._(task: t);

  factory _MobileListItem.phase(
    _MobileSection s,
    String groupId,
    bool expanded,
  ) => _MobileListItem._(section: s, groupId: groupId, isExpanded: expanded);

  factory _MobileListItem.group(_MobileGroupData g, bool expanded) =>
      _MobileListItem._(group: g, isExpanded: expanded);

  factory _MobileListItem.plainHeader(String title, [Color? color]) =>
      _MobileListItem._(
        headerTitle: title,
        headerColor: color,
        isPlainHeader: true,
      );
}

/// Collapsible group header for the mobile task list. Used for phase, status,
/// priority, assignee and property groupings.
class _MobileGroupHeader extends StatelessWidget {
  final String title;
  final Color color;
  final int taskCount;
  final int doneCount;
  final int progress;
  final bool isExpanded;
  final VoidCallback onTap;
  final bool isSelectionMode;

  /// null = none, false = some, true = all
  final bool? isAllSelected;
  final ValueChanged<bool>? onSelectAllChanged;

  const _MobileGroupHeader({
    required this.title,
    required this.color,
    required this.taskCount,
    required this.doneCount,
    required this.progress,
    required this.isExpanded,
    required this.onTap,
    this.isSelectionMode = false,
    this.isAllSelected,
    this.onSelectAllChanged,
  });

  @override
  Widget build(BuildContext context) {
    final allDone = taskCount > 0 && doneCount == taskCount;

    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 2),
        decoration: BoxDecoration(
          color: Color.alphaBlend(color.withValues(alpha: 0.08), Colors.white),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
              child: Row(
                children: [
                  // Select-all checkbox (in selection mode)
                  if (isSelectionMode) ...[
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: Checkbox(
                        value: isAllSelected,
                        tristate: true,
                        onChanged: (_) =>
                            onSelectAllChanged?.call(isAllSelected != true),
                        activeColor: AppColors.secondary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Color dot
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Group name
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: allDone
                            ? AppColors.textTertiary
                            : AppColors.textPrimary,
                        decoration: allDone ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                  // Task count
                  Text(
                    '$doneCount/$taskCount',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Chevron
                  AnimatedRotation(
                    turns: isExpanded ? 0 : -0.25,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(Icons.expand_more, size: 20, color: color),
                  ),
                ],
              ),
            ),
            // Progress bar
            if (taskCount > 0)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(9),
                ),
                child: LinearProgressIndicator(
                  value: progress / 100,
                  minHeight: 3,
                  backgroundColor: color.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    allDone ? AppColors.success : color,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Sortable header cell for the expanded "Task" column in the task list.
class _TaskColumnHeader extends StatefulWidget {
  final String label;
  final TextStyle? textStyle;
  final bool isSorted;
  final bool ascending;
  final VoidCallback onTap;

  const _TaskColumnHeader({
    required this.label,
    this.textStyle,
    required this.isSorted,
    required this.ascending,
    required this.onTap,
  });

  @override
  State<_TaskColumnHeader> createState() => _TaskColumnHeaderState();
}

class _TaskColumnHeaderState extends State<_TaskColumnHeader> {
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
