import 'dart:async';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import '../../models/time_entry.dart';
import '../../models/time_entry_status.dart';
import '../../models/user.dart';
import '../../models/workspace_member.dart';
import '../../providers/auth_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/budget_export_io.dart'
    if (dart.library.html) '../../utils/budget_export_web.dart'
    as platform_export;
import '../../utils/user_facing_error.dart';
import '../../widgets/table/table_column_schema.dart';
import '../../widgets/common/list_skeleton.dart';
import '../../widgets/table/table_header_cells_builder.dart';
import '../../widgets/table/table_header_row.dart';
import '../../widgets/table/table_layout_shell.dart';
import '../../widgets/table/table_view_styles.dart';
import 'widgets/employee_time_table_row.dart';
import 'widgets/time_tracking_view_bar.dart';

/// Date range presets for time tracking.
enum _DateRangePreset {
  thisWeek('This Week'),
  lastWeek('Last Week'),
  thisMonth('This Month'),
  lastMonth('Last Month'),
  custom('Custom');

  final String label;
  const _DateRangePreset(this.label);
}

/// Quick-filter tabs for the employee list.
enum _EmployeeStatusTab {
  all('All'),
  pending('Pending'),
  clockedIn('Clocked In'),
  approved('Approved'),
  noEntries('No Entries');

  final String label;
  const _EmployeeStatusTab(this.label);
}

class EmployeeTimeTableScreen extends StatefulWidget {
  final String? projectId;
  final ValueChanged<TimeTrackingView>? onViewChanged;

  final bool showViewBar;

  const EmployeeTimeTableScreen({
    super.key,
    this.projectId,
    this.onViewChanged,
    this.showViewBar = true,
  });

  @override
  State<EmployeeTimeTableScreen> createState() =>
      _EmployeeTimeTableScreenState();
}

class _EmployeeTimeTableScreenState extends State<EmployeeTimeTableScreen> {
  static final _exportFileDateFormat = DateFormat('yyyy-MM-dd');
  static final _exportDisplayDateFormat = DateFormat('MMM d, yyyy');
  static final _exportGeneratedDateFormat = DateFormat('MMM d, yyyy h:mm a');

  dynamic get _timeEntryService => ServiceLocator.timeEntryService;
  dynamic get _memberService => ServiceLocator.workspaceMemberService;
  dynamic get _userService => ServiceLocator.userService;

  bool _isLoading = true;
  bool _isExporting = false;
  bool _isApprovingEntries = false;
  Object? _error;
  List<WorkspaceMember> _members = [];
  Map<String, AppUser> _usersMap = {};
  Map<String, EmployeeTimeSummary> _summariesMap = {};
  Map<String, List<TimeEntry>> _entriesByWorker = {};
  Set<String> _selectedUserIds = {};
  StreamSubscription? _membersSub;
  String? _subscribedWorkspaceId;

  bool get _isSelectionMode => _selectedUserIds.isNotEmpty;

  _DateRangePreset _selectedPreset = _DateRangePreset.thisWeek;
  late DateTime _startDate;
  late DateTime _endDate;

  String? _tableSortColumn;
  bool _tableSortAscending = true;
  String _searchQuery = '';
  _EmployeeStatusTab _selectedStatusTab = _EmployeeStatusTab.all;
  Set<String> _roleFilters = {};
  bool _filterHasOvertime = false;
  bool _filterHasPending = false;
  final Map<String, double> _columnWidths = {};

  int get _activeFilterCount =>
      _roleFilters.length +
      (_filterHasOvertime ? 1 : 0) +
      (_filterHasPending ? 1 : 0);

  void _handleColumnResize(TableColumnResize resize) {
    setState(() {
      _columnWidths[resize.columnId] = resize.width;
    });
  }

  @override
  void initState() {
    super.initState();
    _setDateRange(_selectedPreset);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Provider.of (listen: true) rather than read() so this re-runs once
    // appUser hydrates. On a cold load/refresh appUser is briefly null; with
    // read() the subscription was skipped and never retried, leaving the screen
    // stuck on the loading spinner.
    final workspaceId =
        Provider.of<AuthProvider>(context).appUser?.currentWorkspaceId;
    if (workspaceId != null && workspaceId != _subscribedWorkspaceId) {
      _subscribeToMembers(workspaceId);
    }
  }

  @override
  void dispose() {
    _membersSub?.cancel();
    super.dispose();
  }

  void _setDateRange(_DateRangePreset preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (preset) {
      case _DateRangePreset.thisWeek:
        final weekday = today.weekday; // Monday = 1
        _startDate = today.subtract(Duration(days: weekday - 1));
        _endDate = _startDate.add(const Duration(days: 6));
      case _DateRangePreset.lastWeek:
        final weekday = today.weekday;
        _startDate = today.subtract(Duration(days: weekday + 6));
        _endDate = _startDate.add(const Duration(days: 6));
      case _DateRangePreset.thisMonth:
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = DateTime(now.year, now.month + 1, 0);
      case _DateRangePreset.lastMonth:
        _startDate = DateTime(now.year, now.month - 1, 1);
        _endDate = DateTime(now.year, now.month, 0);
      case _DateRangePreset.custom:
        return; // Don't change dates for custom
    }
    _selectedPreset = preset;
  }

  void _subscribeToMembers(String workspaceId) {
    setState(() {
      _subscribedWorkspaceId = workspaceId;
      _isLoading = true;
      _error = null;
    });

    _membersSub?.cancel();
    _membersSub =
        (_memberService.getWorkspaceMembers(workspaceId)
                as Stream<List<WorkspaceMember>>)
            .listen(
              (members) async {
                if (!mounted || _subscribedWorkspaceId != workspaceId) return;
                setState(() {
                  _members = members;
                });
                await _loadUsersAndTimeData(workspaceId);
              },
              onError: (error) {
                if (!mounted) return;
                setState(() {
                  _error = error;
                  _isLoading = false;
                });
              },
            );
  }

  Future<void> _loadUsersAndTimeData(String workspaceId) async {
    try {
      final usersMap =
          await (_userService.getWorkspaceUsersMap(workspaceId)
              as Future<Map<String, AppUser>>);

      if (!mounted) return;

      final allEntries =
          await (_timeEntryService.getWorkspaceTimeEntries(
                workspaceId,
                _startDate,
                _endDate,
              )
              as Future<List<TimeEntry>>);

      if (!mounted) return;

      final entries = widget.projectId == null
          ? allEntries
          : allEntries
                .where((e) => e.projectId == widget.projectId)
                .toList();

      // Group entries by worker
      final entriesByWorker = <String, List<TimeEntry>>{};
      for (final entry in entries) {
        entriesByWorker.putIfAbsent(entry.workerId, () => []).add(entry);
      }

      // Build summaries
      final summaries = <String, EmployeeTimeSummary>{};
      for (final member in _members) {
        final workerEntries = entriesByWorker[member.userId] ?? [];
        summaries[member.userId] = EmployeeTimeSummary.fromEntries(
          member.userId,
          workerEntries,
        );
      }

      setState(() {
        _usersMap = usersMap;
        _summariesMap = summaries;
        _entriesByWorker = entriesByWorker;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _isLoading = false;
      });
    }
  }

  void _refreshData() {
    if (_subscribedWorkspaceId != null) {
      setState(() => _isLoading = true);
      _loadUsersAndTimeData(_subscribedWorkspaceId!);
    }
  }

  void _toggleSelection(String userId) {
    setState(() {
      if (_selectedUserIds.contains(userId)) {
        _selectedUserIds.remove(userId);
      } else {
        _selectedUserIds.add(userId);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedUserIds = _filteredMembers.map((m) => m.userId).toSet();
    });
  }

  void _clearSelection() {
    setState(() => _selectedUserIds.clear());
  }

  Future<void> _bulkApproveSelected() async {
    final pendingEntryIds = <String>[];
    for (final userId in _selectedUserIds) {
      final entries = _entriesByWorker[userId] ?? [];
      for (final entry in entries) {
        if (entry.status == TimeEntryStatus.submitted) {
          pendingEntryIds.add(entry.id);
        }
      }
    }

    if (pendingEntryIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pending entries to approve')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Pending Entries'),
        content: Text(
          'Approve ${pendingEntryIds.length} pending entr${pendingEntryIds.length == 1 ? 'y' : 'ies'} '
          'for ${_selectedUserIds.length} employee${_selectedUserIds.length == 1 ? '' : 's'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final managerId = context.read<AuthProvider>().appUser?.id;
    if (managerId == null) return;

    setState(() => _isApprovingEntries = true);
    try {
      await (_timeEntryService.bulkApprove(pendingEntryIds, managerId)
          as Future);
      if (mounted) {
        _clearSelection();
        _refreshData();
        _showExportSnackBar(
          '${pendingEntryIds.length} entr${pendingEntryIds.length == 1 ? 'y' : 'ies'} approved',
        );
      }
    } catch (e) {
      if (mounted) _showExportError(e, 'approve time entries');
    } finally {
      if (mounted) setState(() => _isApprovingEntries = false);
    }
  }

  List<String> get _availableRoles {
    final roles = _members.map((m) => m.displayRoleName).toSet().toList()
      ..sort();
    return roles;
  }

  void _showFilterSheet() {
    Set<String> draftRoles = Set.of(_roleFilters);
    bool draftHasOvertime = _filterHasOvertime;
    bool draftHasPending = _filterHasPending;

    final roles = _availableRoles;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          builder: (_, scrollController) {
            return StatefulBuilder(
              builder: (builderContext, setSheetState) {
                int draftCount =
                    draftRoles.length +
                    (draftHasOvertime ? 1 : 0) +
                    (draftHasPending ? 1 : 0);
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: draftCount == 0
                                ? null
                                : () => setSheetState(() {
                                    draftRoles.clear();
                                    draftHasOvertime = false;
                                    draftHasPending = false;
                                  }),
                            child: const Text('Clear all'),
                          ),
                          const Text(
                            'Filters',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          FilledButton(
                            onPressed: () {
                              setState(() {
                                _roleFilters = draftRoles;
                                _filterHasOvertime = draftHasOvertime;
                                _filterHasPending = draftHasPending;
                                _selectedUserIds.clear();
                              });
                              Navigator.pop(builderContext);
                            },
                            child: const Text('Apply'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.base,
                          vertical: AppSpacing.md,
                        ),
                        children: [
                          _buildFilterSection(
                            context: builderContext,
                            icon: Icons.badge_outlined,
                            title: 'Role',
                            subtitle: draftRoles.isEmpty
                                ? 'All roles'
                                : '${draftRoles.length} selected',
                            active: draftRoles.isNotEmpty,
                            child: roles.isEmpty
                                ? const Padding(
                                    padding: EdgeInsets.all(AppSpacing.md),
                                    child: Text(
                                      'No roles available',
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  )
                                : Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final role in roles)
                                        FilterChip(
                                          label: Text(role),
                                          selected: draftRoles.contains(role),
                                          onSelected: (selected) =>
                                              setSheetState(() {
                                                if (selected) {
                                                  draftRoles.add(role);
                                                } else {
                                                  draftRoles.remove(role);
                                                }
                                              }),
                                        ),
                                    ],
                                  ),
                          ),
                          const SizedBox(height: 12),
                          _buildFilterToggleTile(
                            icon: Icons.trending_up,
                            title: 'Has overtime',
                            subtitle: 'Employees with any OT or DT hours',
                            value: draftHasOvertime,
                            onChanged: (v) =>
                                setSheetState(() => draftHasOvertime = v),
                          ),
                          const SizedBox(height: 8),
                          _buildFilterToggleTile(
                            icon: Icons.pending_actions,
                            title: 'Has pending entries',
                            subtitle: 'Employees with entries awaiting approval',
                            value: draftHasPending,
                            onChanged: (v) =>
                                setSheetState(() => draftHasPending = v),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildFilterSection({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool active,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: active
            ? AppColors.primary.withValues(alpha: 0.04)
            : AppColors.surfaceAlt.withValues(alpha: 0.5),
        border: Border.all(
          color: active
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
            color: active ? AppColors.primary : AppColors.textSecondary,
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
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

  Widget _buildFilterToggleTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: value
            ? AppColors.primary.withValues(alpha: 0.04)
            : AppColors.surfaceAlt.withValues(alpha: 0.5),
        border: Border.all(
          color: value
              ? AppColors.primary.withValues(alpha: 0.3)
              : AppColors.cardBorder,
        ),
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: SwitchListTile(
        secondary: Icon(
          icon,
          size: 20,
          color: value ? AppColors.primary : AppColors.textSecondary,
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
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  List<WorkspaceMember> get _filteredMembers {
    var filtered = List<WorkspaceMember>.from(_members);

    // Search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((member) {
        final user = _usersMap[member.userId];
        if (user == null) return false;
        final name = (user.displayName ?? '').toLowerCase();
        final email = user.email.toLowerCase();
        final job = (user.jobTitle ?? '').toLowerCase();
        return name.contains(query) ||
            email.contains(query) ||
            job.contains(query);
      }).toList();
    }

    // Role filter
    if (_roleFilters.isNotEmpty) {
      filtered = filtered
          .where((member) => _roleFilters.contains(member.displayRoleName))
          .toList();
    }

    // Overtime / pending toggles
    if (_filterHasOvertime || _filterHasPending) {
      filtered = filtered.where((member) {
        final summary =
            _summariesMap[member.userId] ??
            const EmployeeTimeSummary(workerId: '');
        if (_filterHasOvertime &&
            (summary.overtimeHours + summary.doubleTimeHours) <= 0) {
          return false;
        }
        if (_filterHasPending && summary.pendingEntries <= 0) return false;
        return true;
      }).toList();
    }

    // Status tab filter
    if (_selectedStatusTab != _EmployeeStatusTab.all) {
      filtered = filtered.where((member) {
        final summary =
            _summariesMap[member.userId] ??
            const EmployeeTimeSummary(workerId: '');
        return switch (_selectedStatusTab) {
          _EmployeeStatusTab.pending => summary.pendingEntries > 0,
          _EmployeeStatusTab.clockedIn => summary.isClockedIn,
          _EmployeeStatusTab.approved =>
            summary.totalEntries > 0 &&
                summary.pendingEntries == 0 &&
                summary.approvedEntries > 0,
          _EmployeeStatusTab.noEntries => summary.totalEntries == 0,
          _EmployeeStatusTab.all => true,
        };
      }).toList();
    }

    // Sort
    if (_tableSortColumn != null) {
      filtered.sort((a, b) {
        final summaryA =
            _summariesMap[a.userId] ?? const EmployeeTimeSummary(workerId: '');
        final summaryB =
            _summariesMap[b.userId] ?? const EmployeeTimeSummary(workerId: '');
        final userA = _usersMap[a.userId];
        final userB = _usersMap[b.userId];

        int result;
        switch (_tableSortColumn) {
          case 'employee':
            final nameA = (userA?.displayName ?? userA?.email ?? '')
                .toLowerCase();
            final nameB = (userB?.displayName ?? userB?.email ?? '')
                .toLowerCase();
            result = nameA.compareTo(nameB);
          case 'role':
            result = a.displayRoleName.compareTo(b.displayRoleName);
          case 'rate':
            result = (a.hourlyRate ?? 0).compareTo(b.hourlyRate ?? 0);
          case 'total_hours':
            result = summaryA.totalHours.compareTo(summaryB.totalHours);
          case 'regular_hours':
            result = summaryA.regularHours.compareTo(summaryB.regularHours);
          case 'overtime_hours':
            final otA = summaryA.overtimeHours + summaryA.doubleTimeHours;
            final otB = summaryB.overtimeHours + summaryB.doubleTimeHours;
            result = otA.compareTo(otB);
          case 'total_cost':
            result = summaryA.totalCost.compareTo(summaryB.totalCost);
          case 'pending':
            result = summaryA.pendingEntries.compareTo(summaryB.pendingEntries);
          case 'approved':
            result = summaryA.approvedEntries.compareTo(
              summaryB.approvedEntries,
            );
          default:
            result = 0;
        }
        return _tableSortAscending ? result : -result;
      });
    }

    return filtered;
  }

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

  Widget _buildStatusTabs(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: 6),
        itemCount: _EmployeeStatusTab.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = _EmployeeStatusTab.values[index];
          final isActive = _selectedStatusTab == tab;
          return ChoiceChip(
            label: Text(
              tab.label,
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
              color: isActive ? AppColors.primary : AppColors.cardBorder,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.xl),
            ),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onSelected: (_) => setState(() {
              _selectedStatusTab = tab;
              _selectedUserIds.clear();
            }),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AppBreakpoints.isMobileContext(context);
    return Scaffold(
      body: Column(
        children: [
          if (widget.showViewBar)
            TimeTrackingViewBar(
              currentView: TimeTrackingView.employees,
              onViewChanged: widget.onViewChanged,
              onSearch: (value) => setState(() {
              _searchQuery = value;
              _selectedUserIds.clear();
            }),
            searchQuery: _searchQuery,
            searchHint: 'Search employees...',
            filterCount: _activeFilterCount,
            onFilterTap: _showFilterSheet,
            quickToggles: [
              _buildDateRangeSelector(context),
              if (!_isLoading && !isMobile) ..._buildSummaryChips(context),
              IconButton(
                onPressed: _isLoading || _isExporting
                    ? null
                    : () => _showExportDialog(),
                icon: _isExporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.file_upload_outlined, size: 20),
                tooltip: 'Export Employees',
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: _refreshData,
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: 'Refresh',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if (_isSelectionMode)
            _EmployeeSelectionBar(
              selectedCount: _selectedUserIds.length,
              totalCount: _filteredMembers.length,
              pendingCount: _selectedUserIds.fold(0, (sum, uid) {
                return sum + (_summariesMap[uid]?.pendingEntries ?? 0);
              }),
              onSelectAll: _selectAll,
              onClearSelection: _clearSelection,
              onApprove: _isApprovingEntries ? null : _bulkApproveSelected,
              onExport: _isExporting
                  ? null
                  : () => _showExportDialog(selectedOnly: true),
            ),
          if (!_isLoading) _buildStatusTabs(context),
          Expanded(
            child: _isLoading
                ? const ListSkeleton()
                : _error != null
                ? Center(
                    child: SelectableText(
                      UserFacingError.uiMessage(
                        _error,
                        action: 'load employee time data',
                      ),
                    ),
                  )
                : _buildContent(context),
          ),
        ],
      ),
    );
  }

  Widget _buildDateRangeSelector(BuildContext context) {
    if (AppBreakpoints.isMobileContext(context)) {
      return _buildDateRangeDropdown(context);
    }
    return SegmentedButton<_DateRangePreset>(
      segments: [
        for (final preset in _DateRangePreset.values)
          if (preset != _DateRangePreset.custom)
            ButtonSegment(
              value: preset,
              label: Text(preset.label, style: const TextStyle(fontSize: 12)),
            ),
      ],
      selected: {_selectedPreset},
      onSelectionChanged: (selected) {
        setState(() {
          _setDateRange(selected.first);
          _selectedUserIds.clear();
          _selectedStatusTab = _EmployeeStatusTab.all;
        });
        _refreshData();
      },
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll(
          Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }

  Widget _buildDateRangeDropdown(BuildContext context) {
    final effectivePreset = _selectedPreset == _DateRangePreset.custom
        ? _DateRangePreset.thisWeek
        : _selectedPreset;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.cardBorder),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: DropdownButton<_DateRangePreset>(
        value: effectivePreset,
        items: _DateRangePreset.values
            .where((p) => p != _DateRangePreset.custom)
            .map(
              (preset) => DropdownMenuItem(
                value: preset,
                child: Text(preset.label, style: const TextStyle(fontSize: 13)),
              ),
            )
            .toList(),
        onChanged: (preset) {
          if (preset != null) {
            setState(() {
              _setDateRange(preset);
              _selectedUserIds.clear();
              _selectedStatusTab = _EmployeeStatusTab.all;
            });
            _refreshData();
          }
        },
        underline: const SizedBox(),
        isDense: true,
        icon: const Icon(Icons.keyboard_arrow_down, size: 18),
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  List<Widget> _buildSummaryChips(BuildContext context) {
    double totalHours = 0;
    double totalCost = 0;
    int totalPending = 0;
    int activelyClockedIn = 0;

    for (final summary in _summariesMap.values) {
      totalHours += summary.totalHours;
      totalCost += summary.totalCost;
      totalPending += summary.pendingEntries;
      if (summary.isClockedIn) activelyClockedIn++;
    }

    return [
      _SummaryChip(
        label: '${totalHours.toStringAsFixed(1)}h',
        subtitle: 'Total',
        icon: Icons.schedule,
      ),
      const SizedBox(width: 8),
      _SummaryChip(
        label: '\$${totalCost.toStringAsFixed(0)}',
        subtitle: 'Cost',
        icon: Icons.payments_outlined,
      ),
      if (totalPending > 0) ...[
        const SizedBox(width: 8),
        _SummaryChip(
          label: '$totalPending',
          subtitle: 'Pending',
          icon: Icons.pending_actions,
          color: AppColors.warningDark,
        ),
      ],
      if (activelyClockedIn > 0) ...[
        const SizedBox(width: 8),
        _SummaryChip(
          label: '$activelyClockedIn',
          subtitle: 'Active',
          icon: Icons.circle,
          color: AppColors.success,
        ),
      ],
    ];
  }

  Widget _buildContent(BuildContext context) {
    final members = _filteredMembers;

    if (_members.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 48, color: AppColors.textTertiary),
            SizedBox(height: 12),
            Text(
              'No team members found',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    if (members.isEmpty) {
      final message = _searchQuery.isNotEmpty
          ? 'No employees match your search'
          : 'No employees match the "${_selectedStatusTab.label}" filter';
      return Center(
        child: Text(
          message,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return _buildTableView(context, members);
  }

  Future<void> _showExportDialog({
    bool selectedOnly = false,
    List<WorkspaceMember>? membersOverride,
  }) async {
    final format = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Employee Time'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Choose export format:'),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.table_chart),
              title: const Text('CSV'),
              subtitle: const Text('Visible employees and time totals'),
              onTap: () => Navigator.pop(context, 'csv'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('PDF'),
              subtitle: const Text('Printable employee time report'),
              onTap: () => Navigator.pop(context, 'pdf'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (format == null || !mounted) return;

    final members =
        membersOverride ??
        (selectedOnly
            ? _filteredMembers
                  .where(
                    (m) =>
                        _selectedUserIds.contains(m.userId) &&
                        _usersMap.containsKey(m.userId),
                  )
                  .toList()
            : _exportableMembers());

    if (format == 'csv') {
      await _exportToCsv(members: members);
    } else if (format == 'pdf') {
      await _exportToPdf(members: members);
    }
  }

  Future<void> _approvePendingForMember(String userId) async {
    final pendingEntryIds = (_entriesByWorker[userId] ?? [])
        .where((e) => e.status == TimeEntryStatus.submitted)
        .map((e) => e.id)
        .toList();

    if (pendingEntryIds.isEmpty || !mounted) return;

    final user = _usersMap[userId];
    final name = user?.displayName?.isNotEmpty == true
        ? user!.displayName!
        : user?.email ?? 'this employee';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Pending Entries'),
        content: Text(
          'Approve ${pendingEntryIds.length} pending entr${pendingEntryIds.length == 1 ? 'y' : 'ies'} for $name?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final managerId = context.read<AuthProvider>().appUser?.id;
    if (managerId == null) return;

    setState(() => _isApprovingEntries = true);
    try {
      await (_timeEntryService.bulkApprove(pendingEntryIds, managerId)
          as Future);
      if (mounted) {
        _refreshData();
        _showExportSnackBar(
          '${pendingEntryIds.length} entr${pendingEntryIds.length == 1 ? 'y' : 'ies'} approved',
        );
      }
    } catch (e) {
      if (mounted) _showExportError(e, 'approve time entries');
    } finally {
      if (mounted) setState(() => _isApprovingEntries = false);
    }
  }

  List<WorkspaceMember> _exportableMembers() {
    return _filteredMembers
        .where((member) => _usersMap.containsKey(member.userId))
        .toList();
  }

  String get _exportDateRangeLabel =>
      '${_exportDisplayDateFormat.format(_startDate)} - '
      '${_exportDisplayDateFormat.format(_endDate)}';

  String get _exportFileDateRangeLabel =>
      '${_exportFileDateFormat.format(_startDate)}_'
      '${_exportFileDateFormat.format(_endDate)}';

  Future<void> _exportToCsv({List<WorkspaceMember>? members}) async {
    final exportMembers = members ?? _exportableMembers();
    if (exportMembers.isEmpty) {
      _showExportSnackBar('No employees to export');
      return;
    }

    setState(() => _isExporting = true);
    try {
      final rows = <List<dynamic>>[
        [
          'Employee',
          'Email',
          'Job Title',
          'Role',
          'Hourly Rate',
          'Total Hours',
          'Regular Hours',
          'Overtime Hours',
          'Double Time Hours',
          'Labor Cost',
          'Total Entries',
          'Pending',
          'Approved',
          'Rejected',
          'Draft',
          'Status',
        ],
      ];

      for (final member in exportMembers) {
        final user = _usersMap[member.userId]!;
        final summary =
            _summariesMap[member.userId] ??
            EmployeeTimeSummary(workerId: member.userId);
        rows.add([
          user.displayName?.isNotEmpty == true ? user.displayName! : user.email,
          user.email,
          user.jobTitle ?? '',
          member.displayRoleName,
          member.hourlyRate?.toStringAsFixed(2) ?? '',
          summary.totalHours.toStringAsFixed(2),
          summary.regularHours.toStringAsFixed(2),
          summary.overtimeHours.toStringAsFixed(2),
          summary.doubleTimeHours.toStringAsFixed(2),
          summary.totalCost.toStringAsFixed(2),
          summary.totalEntries,
          summary.pendingEntries,
          summary.approvedEntries,
          summary.rejectedEntries,
          summary.draftEntries,
          _employeeStatus(summary),
        ]);
      }

      final csv = const ListToCsvConverter().convert(rows);
      final fileName =
          'employee_time_${_exportFileDateRangeLabel}_${DateTime.now().millisecondsSinceEpoch}.csv';

      await platform_export.exportCsv(
        csv,
        fileName,
        'Employee Time Export - $_exportDateRangeLabel',
      );

      if (mounted) {
        _showExportSnackBar('Employee time exported to CSV');
      }
    } catch (e) {
      if (mounted) {
        _showExportError(e, 'export employee time to CSV');
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _exportToPdf({List<WorkspaceMember>? members}) async {
    final exportMembers = members ?? _exportableMembers();
    if (exportMembers.isEmpty) {
      _showExportSnackBar('No employees to export');
      return;
    }

    setState(() => _isExporting = true);
    try {
      final totals = _calculateExportTotals(exportMembers);
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.letter.landscape,
          margin: const pw.EdgeInsets.all(AppSpacing.xxl),
          build: (pdfContext) => [
            pw.Header(
              level: 0,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Employee Time Report',
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    _exportDateRangeLabel,
                    style: const pw.TextStyle(fontSize: 14),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Generated: ${_exportGeneratedDateFormat.format(DateTime.now())}',
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey600,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Container(
              padding: const pw.EdgeInsets.all(AppSpacing.md),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _buildPdfSummaryColumn([
                    'Employees: ${exportMembers.length}',
                    'Total Hours: ${totals.totalHours.toStringAsFixed(2)}',
                    'Regular: ${totals.regularHours.toStringAsFixed(2)}h',
                    'Overtime: ${(totals.overtimeHours + totals.doubleTimeHours).toStringAsFixed(2)}h',
                  ]),
                  _buildPdfSummaryColumn([
                    'Labor Cost: \$${totals.totalCost.toStringAsFixed(2)}',
                    'Entries: ${totals.totalEntries}',
                    'Pending: ${totals.pendingEntries}',
                    'Approved: ${totals.approvedEntries}',
                  ], alignEnd: true),
                ],
              ),
            ),
            pw.SizedBox(height: 18),
            pw.Text(
              'Employees',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400),
              columnWidths: const {
                0: pw.FlexColumnWidth(2.1),
                1: pw.FlexColumnWidth(1.1),
                2: pw.FlexColumnWidth(0.8),
                3: pw.FlexColumnWidth(0.8),
                4: pw.FlexColumnWidth(0.8),
                5: pw.FlexColumnWidth(0.8),
                6: pw.FlexColumnWidth(0.9),
                7: pw.FlexColumnWidth(0.7),
                8: pw.FlexColumnWidth(0.7),
                9: pw.FlexColumnWidth(1.0),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    _buildPdfTableCell('Employee', isHeader: true),
                    _buildPdfTableCell('Role', isHeader: true),
                    _buildPdfTableCell('Rate', isHeader: true),
                    _buildPdfTableCell('Total', isHeader: true),
                    _buildPdfTableCell('Regular', isHeader: true),
                    _buildPdfTableCell('OT', isHeader: true),
                    _buildPdfTableCell('Cost', isHeader: true),
                    _buildPdfTableCell('Pending', isHeader: true),
                    _buildPdfTableCell('Approved', isHeader: true),
                    _buildPdfTableCell('Status', isHeader: true),
                  ],
                ),
                ...exportMembers.map((member) {
                  final user = _usersMap[member.userId]!;
                  final summary =
                      _summariesMap[member.userId] ??
                      EmployeeTimeSummary(workerId: member.userId);
                  final name = user.displayName?.isNotEmpty == true
                      ? user.displayName!
                      : user.email;
                  final overtime =
                      summary.overtimeHours + summary.doubleTimeHours;

                  return pw.TableRow(
                    children: [
                      _buildPdfTableCell(name),
                      _buildPdfTableCell(member.displayRoleName),
                      _buildPdfTableCell(
                        member.hourlyRate == null
                            ? '-'
                            : '\$${member.hourlyRate!.toStringAsFixed(2)}/hr',
                      ),
                      _buildPdfTableCell(
                        '${summary.totalHours.toStringAsFixed(1)}h',
                      ),
                      _buildPdfTableCell(
                        '${summary.regularHours.toStringAsFixed(1)}h',
                      ),
                      _buildPdfTableCell('${overtime.toStringAsFixed(1)}h'),
                      _buildPdfTableCell(
                        '\$${summary.totalCost.toStringAsFixed(2)}',
                      ),
                      _buildPdfTableCell('${summary.pendingEntries}'),
                      _buildPdfTableCell('${summary.approvedEntries}'),
                      _buildPdfTableCell(_employeeStatus(summary)),
                    ],
                  );
                }),
              ],
            ),
          ],
        ),
      );

      await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
        name: 'employee_time_$_exportFileDateRangeLabel.pdf',
      );

      if (mounted) {
        _showExportSnackBar('Employee time exported to PDF');
      }
    } catch (e) {
      if (mounted) {
        _showExportError(e, 'export employee time to PDF');
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  ({
    double totalHours,
    double regularHours,
    double overtimeHours,
    double doubleTimeHours,
    double totalCost,
    int totalEntries,
    int pendingEntries,
    int approvedEntries,
  })
  _calculateExportTotals(List<WorkspaceMember> members) {
    double totalHours = 0;
    double regularHours = 0;
    double overtimeHours = 0;
    double doubleTimeHours = 0;
    double totalCost = 0;
    int totalEntries = 0;
    int pendingEntries = 0;
    int approvedEntries = 0;

    for (final member in members) {
      final summary = _summariesMap[member.userId];
      if (summary == null) continue;
      totalHours += summary.totalHours;
      regularHours += summary.regularHours;
      overtimeHours += summary.overtimeHours;
      doubleTimeHours += summary.doubleTimeHours;
      totalCost += summary.totalCost;
      totalEntries += summary.totalEntries;
      pendingEntries += summary.pendingEntries;
      approvedEntries += summary.approvedEntries;
    }

    return (
      totalHours: totalHours,
      regularHours: regularHours,
      overtimeHours: overtimeHours,
      doubleTimeHours: doubleTimeHours,
      totalCost: totalCost,
      totalEntries: totalEntries,
      pendingEntries: pendingEntries,
      approvedEntries: approvedEntries,
    );
  }

  String _employeeStatus(EmployeeTimeSummary summary) {
    if (summary.isClockedIn) return 'Clocked In';
    if (summary.totalEntries == 0) return 'No entries';
    return 'Clocked Out';
  }

  pw.Widget _buildPdfSummaryColumn(
    List<String> lines, {
    bool alignEnd = false,
  }) {
    return pw.Column(
      crossAxisAlignment: alignEnd
          ? pw.CrossAxisAlignment.end
          : pw.CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          pw.Text(line, style: const pw.TextStyle(fontSize: 11)),
      ],
    );
  }

  pw.Widget _buildPdfTableCell(String text, {bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 8 : 7,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  void _showExportSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showExportError(Object error, String action) {
    final errorMsg = UserFacingError.uiMessage(error, action: action);
    debugPrint(errorMsg);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: SelectableText(errorMsg),
        backgroundColor: AppColors.error,
      ),
    );
  }

  static const _tableColumns = [
    TableColumnSchema(
      id: 'employee',
      label: 'Employee',
      defaultWidth: kEmployeeTimeColEmployee,
      minWidth: 120,
      maxWidth: 400,
    ),
    TableColumnSchema(
      id: 'role',
      label: 'Role',
      defaultWidth: kEmployeeTimeColRole,
      minWidth: 70,
      maxWidth: 200,
    ),
    TableColumnSchema(
      id: 'rate',
      label: 'Rate',
      defaultWidth: kEmployeeTimeColRate,
      minWidth: 70,
      maxWidth: 180,
    ),
    TableColumnSchema(
      id: 'total_hours',
      label: 'Total Hours',
      defaultWidth: kEmployeeTimeColTotalHours,
      minWidth: 70,
      maxWidth: 180,
    ),
    TableColumnSchema(
      id: 'regular_hours',
      label: 'Regular',
      defaultWidth: kEmployeeTimeColRegularHours,
      minWidth: 70,
      maxWidth: 180,
    ),
    TableColumnSchema(
      id: 'overtime_hours',
      label: 'Overtime',
      defaultWidth: kEmployeeTimeColOvertimeHours,
      minWidth: 70,
      maxWidth: 180,
    ),
    TableColumnSchema(
      id: 'total_cost',
      label: 'Labor Cost',
      defaultWidth: kEmployeeTimeColTotalCost,
      minWidth: 80,
      maxWidth: 200,
    ),
    TableColumnSchema(
      id: 'pending',
      label: 'Pending',
      defaultWidth: kEmployeeTimeColPending,
      minWidth: 60,
      maxWidth: 140,
    ),
    TableColumnSchema(
      id: 'approved',
      label: 'Approved',
      defaultWidth: kEmployeeTimeColApproved,
      minWidth: 60,
      maxWidth: 140,
    ),
    TableColumnSchema(
      id: 'status',
      label: 'Status',
      defaultWidth: kEmployeeTimeColStatus,
      minWidth: 80,
      maxWidth: 200,
    ),
  ];

  Widget _buildTableView(BuildContext context, List<WorkspaceMember> members) {
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
      onSortTap: (column) {
        if (column.id == 'status') return;
        _onColumnSortTap(column.id);
      },
      sortedColumnId: _tableSortColumn,
      sortAscending: _tableSortAscending,
    );

    final allSelected =
        members.isNotEmpty &&
        members.every((m) => _selectedUserIds.contains(m.userId));
    final someSelected =
        !allSelected && members.any((m) => _selectedUserIds.contains(m.userId));

    final headerChildren = <Widget>[
      SizedBox(
        width: kEmployeeTimeColCheckbox,
        child: Checkbox(
          value: allSelected ? true : (someSelected ? null : false),
          tristate: true,
          onChanged: (_) {
            if (allSelected) {
              _clearSelection();
            } else {
              _selectAll();
            }
          },
          activeColor: AppColors.info,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xs)),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
      ),
      const SizedBox(width: kEmployeeTimeColGap),
    ];
    for (int i = 0; i < headerCells.length; i++) {
      if (i > 0) headerChildren.add(const SizedBox(width: kEmployeeTimeColGap));
      headerChildren.add(headerCells[i]);
    }

    return TableLayoutShell(
      minTableWidth: 1248,
      header: TableHeaderRow(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
        children: headerChildren,
      ),
      body: ListView.builder(
        itemCount: members.length,
        itemBuilder: (context, index) {
          final member = members[index];
          final user = _usersMap[member.userId];
          final summary =
              _summariesMap[member.userId] ??
              EmployeeTimeSummary(workerId: member.userId);

          if (user == null) return const SizedBox.shrink();

          return EmployeeTimeTableRow(
            user: user,
            member: member,
            summary: summary,
            columnWidths: _columnWidths,
            isSelected: _selectedUserIds.contains(member.userId),
            onToggleSelect: () => _toggleSelection(member.userId),
            onExport: () => _showExportDialog(membersOverride: [member]),
            onApprovePending: summary.pendingEntries > 0
                ? () => _approvePendingForMember(member.userId)
                : null,
          );
        },
      ),
      footer: _buildFooter(context, members),
    );
  }

  double _colW(String id, double defaultWidth) =>
      _columnWidths[id] ?? defaultWidth;

  Widget _buildFooter(BuildContext context, List<WorkspaceMember> members) {
    double totalHours = 0;
    double regularHours = 0;
    double overtimeHours = 0;
    double totalCost = 0;
    int totalPending = 0;
    int totalApproved = 0;

    for (final member in members) {
      final summary = _summariesMap[member.userId];
      if (summary == null) continue;
      totalHours += summary.totalHours;
      regularHours += summary.regularHours;
      overtimeHours += summary.overtimeHours + summary.doubleTimeHours;
      totalCost += summary.totalCost;
      totalPending += summary.pendingEntries;
      totalApproved += summary.approvedEntries;
    }

    final footerStyle = const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
    );

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: 10),
      child: Row(
        children: [
          const SizedBox(width: kEmployeeTimeColCheckbox + kEmployeeTimeColGap),
          SizedBox(
            width: _colW('employee', kEmployeeTimeColEmployee),
            child: Text('${members.length} employees', style: footerStyle),
          ),
          SizedBox(
            width:
                kEmployeeTimeColGap +
                _colW('role', kEmployeeTimeColRole) +
                kEmployeeTimeColGap +
                _colW('rate', kEmployeeTimeColRate) +
                kEmployeeTimeColGap,
          ),
          SizedBox(
            width: _colW('total_hours', kEmployeeTimeColTotalHours),
            child: Text(
              '${totalHours.toStringAsFixed(1)}h',
              style: footerStyle,
            ),
          ),
          const SizedBox(width: kEmployeeTimeColGap),
          SizedBox(
            width: _colW('regular_hours', kEmployeeTimeColRegularHours),
            child: Text(
              '${regularHours.toStringAsFixed(1)}h',
              style: footerStyle,
            ),
          ),
          const SizedBox(width: kEmployeeTimeColGap),
          SizedBox(
            width: _colW('overtime_hours', kEmployeeTimeColOvertimeHours),
            child: Text(
              '${overtimeHours.toStringAsFixed(1)}h',
              style: footerStyle.copyWith(
                color: overtimeHours > 0 ? AppColors.warningDark : null,
              ),
            ),
          ),
          const SizedBox(width: kEmployeeTimeColGap),
          SizedBox(
            width: _colW('total_cost', kEmployeeTimeColTotalCost),
            child: Text(
              '\$${totalCost.toStringAsFixed(2)}',
              style: footerStyle,
            ),
          ),
          const SizedBox(width: kEmployeeTimeColGap),
          SizedBox(
            width: _colW('pending', kEmployeeTimeColPending),
            child: Text(
              '$totalPending',
              style: footerStyle.copyWith(
                color: totalPending > 0 ? AppColors.warningDark : null,
              ),
            ),
          ),
          const SizedBox(width: kEmployeeTimeColGap),
          SizedBox(
            width: _colW('approved', kEmployeeTimeColApproved),
            child: Text(
              '$totalApproved',
              style: footerStyle.copyWith(
                color: totalApproved > 0 ? AppColors.success : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Selection bar shown when one or more employees are selected
// ---------------------------------------------------------------------------

class _EmployeeSelectionBar extends StatelessWidget {
  final int selectedCount;
  final int totalCount;
  final int pendingCount;
  final VoidCallback onSelectAll;
  final VoidCallback onClearSelection;
  final VoidCallback? onApprove;
  final VoidCallback? onExport;

  const _EmployeeSelectionBar({
    required this.selectedCount,
    required this.totalCount,
    required this.pendingCount,
    required this.onSelectAll,
    required this.onClearSelection,
    this.onApprove,
    this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final allSelected = selectedCount == totalCount && totalCount > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.08),
        border: Border(
          bottom: BorderSide(color: AppColors.info.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: allSelected,
              tristate: !allSelected && selectedCount > 0,
              onChanged: (_) {
                if (allSelected) {
                  onClearSelection();
                } else {
                  onSelectAll();
                }
              },
              activeColor: AppColors.info,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: AppColors.info,
              borderRadius: BorderRadius.circular(AppRadius.r12),
            ),
            child: Text(
              '$selectedCount selected',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          const Spacer(),
          if (pendingCount > 0)
            IconButton(
              icon: onApprove == null
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_outlined),
              tooltip:
                  'Approve $pendingCount pending entr${pendingCount == 1 ? 'y' : 'ies'}',
              onPressed: onApprove,
              iconSize: 20,
              visualDensity: VisualDensity.compact,
              color: AppColors.financialAccent,
            ),
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: 'Export selected',
            onPressed: onExport,
            iconSize: 20,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Clear selection',
            onPressed: onClearSelection,
            iconSize: 20,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary chip used in toolbar
// ---------------------------------------------------------------------------

class _SummaryChip extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color? color;

  const _SummaryChip({
    required this.label,
    required this.subtitle,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: (color ?? AppColors.textSecondary).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color ?? AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color ?? AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
