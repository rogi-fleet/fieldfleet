import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/project.dart';
import '../../../models/project_status_theme.dart';
import '../../../models/customer.dart';
import '../../../models/user.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/workspace_provider.dart';
import '../../../services/service_locator.dart';
import '../../../theme/theme.dart';
import '../../../utils/project_terminology.dart';
import '../../../widgets/common/searchable_filter_chips.dart';

enum ProjectSortOption {
  recent,
  nameAsc,
  nameDesc,
  budgetHigh,
  budgetLow,
}

extension ProjectSortOptionLabel on ProjectSortOption {
  String get label {
    switch (this) {
      case ProjectSortOption.recent:
        return 'Recent';
      case ProjectSortOption.nameAsc:
        return 'Name (A-Z)';
      case ProjectSortOption.nameDesc:
        return 'Name (Z-A)';
      case ProjectSortOption.budgetHigh:
        return 'Budget (High-Low)';
      case ProjectSortOption.budgetLow:
        return 'Budget (Low-High)';
    }
  }
}

class ProjectFilters extends StatefulWidget {
  final ProjectStatus? selectedStatus;
  final String? selectedCustomerId;
  final String? selectedProjectManagerId;
  final String? selectedSupervisorId;
  final String? selectedSalespersonId;
  final ProjectSortOption selectedSort;
  final ValueChanged<ProjectStatus?> onStatusChanged;
  final ValueChanged<String?> onCustomerChanged;
  final ValueChanged<String?> onProjectManagerChanged;
  final ValueChanged<String?> onSupervisorChanged;
  final ValueChanged<String?> onSalespersonChanged;
  final ValueChanged<ProjectSortOption> onSortChanged;
  final bool statusOnly;
  final Set<String>? projectManagerIds;
  final Set<String>? supervisorIds;

  const ProjectFilters({
    super.key,
    this.selectedStatus,
    this.selectedCustomerId,
    this.selectedProjectManagerId,
    this.selectedSupervisorId,
    this.selectedSalespersonId,
    required this.selectedSort,
    required this.onStatusChanged,
    required this.onCustomerChanged,
    required this.onProjectManagerChanged,
    required this.onSupervisorChanged,
    required this.onSalespersonChanged,
    required this.onSortChanged,
    this.statusOnly = false,
    this.projectManagerIds,
    this.supervisorIds,
  });

  @override
  State<ProjectFilters> createState() => _ProjectFiltersState();
}

class _ProjectFiltersState extends State<ProjectFilters> {
  bool _isLoadingUsers = false;
  String? _loadedWorkspaceId;
  List<AppUser> _workspaceUsers = [];

  bool get _hasActiveFilters =>
      widget.selectedStatus != null ||
      widget.selectedCustomerId != null ||
      widget.selectedProjectManagerId != null ||
      widget.selectedSupervisorId != null ||
      widget.selectedSalespersonId != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final workspaceId =
        context.read<AuthProvider>().appUser?.currentWorkspaceId;
    if (workspaceId != null && workspaceId != _loadedWorkspaceId) {
      _loadWorkspaceUsers(workspaceId);
    }
  }

  Future<void> _loadWorkspaceUsers(String workspaceId) async {
    setState(() {
      _isLoadingUsers = true;
      _loadedWorkspaceId = workspaceId;
    });

    try {
      final members = await ServiceLocator.workspaceMemberService
          .getWorkspaceMembers(workspaceId)
          .first;

      final userFutures = members.map(
        (member) => ServiceLocator.userService.getUserById(member.userId),
      );
      final users = await Future.wait(userFutures);

      final existingIds = <String>{};
      final loadedUsers = <AppUser>[];
      for (final user in users) {
        if (user != null && existingIds.add(user.id)) {
          loadedUsers.add(user);
        }
      }

      loadedUsers.sort((a, b) {
        final aName = (a.displayName ?? a.email).toLowerCase();
        final bName = (b.displayName ?? b.email).toLowerCase();
        return aName.compareTo(bName);
      });

      if (!mounted) return;
      setState(() {
        _workspaceUsers = loadedUsers;
        _isLoadingUsers = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _workspaceUsers = [];
        _isLoadingUsers = false;
      });
    }
  }

  String? _userDisplayName(String userId) {
    final user = _workspaceUsers.where((u) => u.id == userId).firstOrNull;
    if (user == null) return null;
    return user.displayName ?? user.email;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.statusOnly) {
      return _buildStatusOnlyDropdown();
    }

    return Row(
      children: [
        // Filter icon button
        _buildFilterIconButton(context),
        const SizedBox(width: 8),
        // Active filter chips
        ..._buildActiveFilterChips(),
        // Sort control (kept inline, separate from filters)
        _buildSortDropdown(),
      ],
    );
  }

  Widget _buildStatusOnlyDropdown() {
    return _buildInlineDropdown<ProjectStatus?>(
      label: 'Status',
      value: widget.selectedStatus,
      items: [
        const DropdownMenuItem(value: null, child: Text('All')),
        ...ProjectStatus.values.map((status) {
          return DropdownMenuItem(
            value: status,
            child: Row(
              children: [
                Icon(Icons.circle, size: 8, color: _getStatusColor(status)),
                const SizedBox(width: 8),
                Text(status.displayName),
              ],
            ),
          );
        }),
      ],
      onChanged: widget.onStatusChanged,
    );
  }

  int get _activeFilterCount =>
      (widget.selectedStatus != null ? 1 : 0) +
      (widget.selectedCustomerId != null ? 1 : 0) +
      (widget.selectedProjectManagerId != null ? 1 : 0) +
      (widget.selectedSupervisorId != null ? 1 : 0) +
      (widget.selectedSalespersonId != null ? 1 : 0);

  Widget _buildFilterIconButton(BuildContext context) {
    return Stack(
      children: [
        IconButton(
          icon: Icon(
            _hasActiveFilters ? Icons.filter_alt : Icons.filter_alt_outlined,
            color: _hasActiveFilters
                ? Theme.of(context).colorScheme.primary
                : AppColors.textSecondary,
          ),
          tooltip: 'Filters',
          onPressed: () => _showFilterBottomSheet(context),
          visualDensity: VisualDensity.compact,
        ),
        if (_activeFilterCount > 0)
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xs),
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(
                minWidth: 18,
                minHeight: 18,
              ),
              child: Text(
                '$_activeFilterCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildActiveFilterChips() {
    final chips = <Widget>[];

    if (widget.selectedStatus != null) {
      chips.add(Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InputChip(
          label: Text(widget.selectedStatus!.displayName),
          avatar: Icon(
            Icons.circle,
            size: 8,
            color: _getStatusColor(widget.selectedStatus!),
          ),
          onDeleted: () => widget.onStatusChanged(null),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ));
    }

    if (widget.selectedCustomerId != null) {
      final workspaceId =
          context.read<AuthProvider>().appUser?.currentWorkspaceId;
      chips.add(Padding(
        padding: const EdgeInsets.only(right: 6),
        child: StreamBuilder<List<Customer>>(
          stream: workspaceId != null
              ? ServiceLocator.customerService.getCustomers(workspaceId)
              : const Stream.empty(),
          builder: (context, snapshot) {
            final customers = snapshot.data ?? [];
            final customer = customers
                .where((c) => c.id == widget.selectedCustomerId)
                .firstOrNull;
            final name = customer?.name ?? 'Customer';
            return InputChip(
              label: Text(
                name.length > 20 ? '${name.substring(0, 20)}...' : name,
              ),
              onDeleted: () => widget.onCustomerChanged(null),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            );
          },
        ),
      ));
    }

    if (widget.selectedProjectManagerId != null) {
      final name =
          _userDisplayName(widget.selectedProjectManagerId!) ?? 'PM';
      chips.add(Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InputChip(
          label: Text(name),
          onDeleted: () => widget.onProjectManagerChanged(null),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ));
    }

    if (widget.selectedSupervisorId != null) {
      final name =
          _userDisplayName(widget.selectedSupervisorId!) ?? 'Supervisor';
      chips.add(Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InputChip(
          label: Text(name),
          onDeleted: () => widget.onSupervisorChanged(null),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ));
    }

    if (widget.selectedSalespersonId != null) {
      final name =
          _userDisplayName(widget.selectedSalespersonId!) ?? 'Sales';
      chips.add(Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InputChip(
          label: Text(name),
          onDeleted: () => widget.onSalespersonChanged(null),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ));
    }

    return chips;
  }

  Widget _buildSortDropdown() {
    return _buildInlineDropdown<ProjectSortOption>(
      label: 'Sort',
      value: widget.selectedSort,
      items: ProjectSortOption.values.map((option) {
        return DropdownMenuItem(value: option, child: Text(option.label));
      }).toList(),
      onChanged: (value) {
        if (value != null) {
          widget.onSortChanged(value);
        }
      },
    );
  }

  void _showFilterBottomSheet(BuildContext context) {
    final projectTerminology = context.read<WorkspaceProvider>().projectTerminology;
    final singular = singularProjectTerminology(projectTerminology);
    final workspaceId =
        context.read<AuthProvider>().appUser?.currentWorkspaceId;

    // Local draft state for the bottom sheet
    ProjectStatus? draftStatus = widget.selectedStatus;
    String? draftCustomerId = widget.selectedCustomerId;
    String? draftPMId = widget.selectedProjectManagerId;
    String? draftSupervisorId = widget.selectedSupervisorId;
    String? draftSalespersonId = widget.selectedSalespersonId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          builder: (_, scrollController) {
            return StatefulBuilder(
              builder: (builderContext, setSheetState) {
                return Column(
                  children: [
                    // Drag handle
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 4),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // Header with Clear all & Apply
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.base, vertical: AppSpacing.sm),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: () {
                              setSheetState(() {
                                draftStatus = null;
                                draftCustomerId = null;
                                draftPMId = null;
                                draftSupervisorId = null;
                                draftSalespersonId = null;
                              });
                            },
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
                              widget.onStatusChanged(draftStatus);
                              widget.onCustomerChanged(draftCustomerId);
                              widget.onProjectManagerChanged(draftPMId);
                              widget.onSupervisorChanged(draftSupervisorId);
                              widget.onSalespersonChanged(draftSalespersonId);
                              Navigator.pop(builderContext);
                            },
                            child: const Text('Apply'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // Filter sections
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.base, vertical: AppSpacing.sm),
                        children: [
                          // Status section card
                          Container(
                            decoration: BoxDecoration(
                              color: draftStatus != null
                                  ? AppColors.primary.withValues(alpha: 0.04)
                                  : AppColors.surfaceAlt.withValues(alpha: 0.5),
                              border: Border.all(
                                color: draftStatus != null
                                    ? AppColors.primary.withValues(alpha: 0.3)
                                    : AppColors.cardBorder,
                              ),
                              borderRadius: BorderRadius.circular(AppRadius.r12),
                            ),
                            child: Theme(
                              data: Theme.of(builderContext).copyWith(dividerColor: Colors.transparent),
                              child: ExpansionTile(
                                leading: Icon(Icons.flag_outlined, size: 20, color: draftStatus != null ? AppColors.primary : AppColors.textSecondary),
                                title: const Text('Status', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                subtitle: Text(
                                  draftStatus?.displayName ?? 'All',
                                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
                                          selected: draftStatus == null,
                                          onSelected: (_) {
                                            setSheetState(() => draftStatus = null);
                                          },
                                        ),
                                        ...ProjectStatus.values.map((status) {
                                          return ChoiceChip(
                                            label: Text(status.displayName),
                                            avatar: Icon(
                                              Icons.circle,
                                              size: 8,
                                              color: _getStatusColor(status),
                                            ),
                                            selected: draftStatus == status,
                                            onSelected: (_) {
                                              setSheetState(() => draftStatus = status);
                                            },
                                          );
                                        }),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Customer section card
                          if (workspaceId != null) ...[
                            Container(
                              decoration: BoxDecoration(
                                color: draftCustomerId != null
                                    ? AppColors.primary.withValues(alpha: 0.04)
                                    : AppColors.surfaceAlt.withValues(alpha: 0.5),
                                border: Border.all(
                                  color: draftCustomerId != null
                                      ? AppColors.primary.withValues(alpha: 0.3)
                                      : AppColors.cardBorder,
                                ),
                                borderRadius: BorderRadius.circular(AppRadius.r12),
                              ),
                              child: Theme(
                                data: Theme.of(builderContext).copyWith(dividerColor: Colors.transparent),
                                child: ExpansionTile(
                                  leading: Icon(Icons.people_outline, size: 20, color: draftCustomerId != null ? AppColors.primary : AppColors.textSecondary),
                                  title: const Text('Customer', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                  subtitle: Text(
                                    draftCustomerId != null ? 'Selected' : 'All',
                                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                  ),
                                  initiallyExpanded: true,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                      child: StreamBuilder<List<Customer>>(
                                        stream: ServiceLocator.customerService
                                            .getCustomers(workspaceId),
                                        builder: (context, snapshot) {
                                          final customers = snapshot.data ?? [];
                                          return SearchableFilterChips(
                                            items: customers.map((c) => (id: c.id, label: c.businessDisplayName)).toList(),
                                            selectedId: draftCustomerId,
                                            onAllSelected: () => setSheetState(() => draftCustomerId = null),
                                            onItemSelected: (id) => setSheetState(() => draftCustomerId = id),
                                            searchHint: 'Search customers...',
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],

                          // Project Manager section card
                          Container(
                            decoration: BoxDecoration(
                              color: draftPMId != null
                                  ? AppColors.primary.withValues(alpha: 0.04)
                                  : AppColors.surfaceAlt.withValues(alpha: 0.5),
                              border: Border.all(
                                color: draftPMId != null
                                    ? AppColors.primary.withValues(alpha: 0.3)
                                    : AppColors.cardBorder,
                              ),
                              borderRadius: BorderRadius.circular(AppRadius.r12),
                            ),
                            child: Theme(
                              data: Theme.of(builderContext).copyWith(dividerColor: Colors.transparent),
                              child: ExpansionTile(
                                leading: Icon(Icons.manage_accounts_outlined, size: 20, color: draftPMId != null ? AppColors.primary : AppColors.textSecondary),
                                title: Text('$singular Manager', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                subtitle: Text(
                                  draftPMId != null ? (_userDisplayName(draftPMId!) ?? 'Selected') : 'All',
                                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                ),
                                initiallyExpanded: true,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                    child: _isLoadingUsers
                                        ? const Center(
                                            child: SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            ),
                                          )
                                        : SearchableFilterChips(
                                            items: _workspaceUsers
                                                .where((user) =>
                                                    widget.projectManagerIds == null ||
                                                    widget.projectManagerIds!
                                                        .contains(user.id))
                                                .map((u) => (id: u.id, label: u.displayName ?? u.email))
                                                .toList(),
                                            selectedId: draftPMId,
                                            onAllSelected: () => setSheetState(() => draftPMId = null),
                                            onItemSelected: (id) => setSheetState(() => draftPMId = id),
                                            searchHint: 'Search project managers...',
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Supervisor section card
                          Container(
                            decoration: BoxDecoration(
                              color: draftSupervisorId != null
                                  ? AppColors.primary.withValues(alpha: 0.04)
                                  : AppColors.surfaceAlt.withValues(alpha: 0.5),
                              border: Border.all(
                                color: draftSupervisorId != null
                                    ? AppColors.primary.withValues(alpha: 0.3)
                                    : AppColors.cardBorder,
                              ),
                              borderRadius: BorderRadius.circular(AppRadius.r12),
                            ),
                            child: Theme(
                              data: Theme.of(builderContext).copyWith(dividerColor: Colors.transparent),
                              child: ExpansionTile(
                                leading: Icon(Icons.supervisor_account_outlined, size: 20, color: draftSupervisorId != null ? AppColors.primary : AppColors.textSecondary),
                                title: const Text('Supervisor', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                subtitle: Text(
                                  draftSupervisorId != null ? (_userDisplayName(draftSupervisorId!) ?? 'Selected') : 'All',
                                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                ),
                                initiallyExpanded: true,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                    child: _isLoadingUsers
                                        ? const Center(
                                            child: SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            ),
                                          )
                                        : SearchableFilterChips(
                                            items: _workspaceUsers
                                                .where((user) =>
                                                    widget.supervisorIds == null ||
                                                    widget.supervisorIds!
                                                        .contains(user.id))
                                                .map((u) => (id: u.id, label: u.displayName ?? u.email))
                                                .toList(),
                                            selectedId: draftSupervisorId,
                                            onAllSelected: () => setSheetState(() => draftSupervisorId = null),
                                            onItemSelected: (id) => setSheetState(() => draftSupervisorId = id),
                                            searchHint: 'Search supervisors...',
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Sales Person section card
                          Container(
                            decoration: BoxDecoration(
                              color: draftSalespersonId != null
                                  ? AppColors.primary.withValues(alpha: 0.04)
                                  : AppColors.surfaceAlt.withValues(alpha: 0.5),
                              border: Border.all(
                                color: draftSalespersonId != null
                                    ? AppColors.primary.withValues(alpha: 0.3)
                                    : AppColors.cardBorder,
                              ),
                              borderRadius: BorderRadius.circular(AppRadius.r12),
                            ),
                            child: Theme(
                              data: Theme.of(builderContext).copyWith(dividerColor: Colors.transparent),
                              child: ExpansionTile(
                                leading: Icon(Icons.badge_outlined, size: 20, color: draftSalespersonId != null ? AppColors.primary : AppColors.textSecondary),
                                title: const Text('Sales Person', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                subtitle: Text(
                                  draftSalespersonId != null ? (_userDisplayName(draftSalespersonId!) ?? 'Selected') : 'All',
                                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                ),
                                initiallyExpanded: true,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                    child: _isLoadingUsers
                                        ? const Center(
                                            child: SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            ),
                                          )
                                        : SearchableFilterChips(
                                            items: _workspaceUsers
                                                .map((u) => (id: u.id, label: u.displayName ?? u.email))
                                                .toList(),
                                            selectedId: draftSalespersonId,
                                            onAllSelected: () => setSheetState(() => draftSalespersonId = null),
                                            onItemSelected: (id) => setSheetState(() => draftSalespersonId = id),
                                            searchHint: 'Search sales people...',
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
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


  Widget _buildInlineDropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.cardBorder),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label:',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<T>(
            borderRadius: AppRadius.cardRadius,
            value: items.any((item) => item.value == value) ? value : null,
            items: items,
            onChanged: onChanged,
            underline: const SizedBox(),
            isDense: true,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black87,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(ProjectStatus status) {
    return ProjectStatusTheme.color(status);
  }
}
