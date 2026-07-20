import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../models/capacity_planning.dart';
import '../../models/project.dart';
import '../../models/task.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/user_facing_error.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

class TeamCapacityTab extends StatefulWidget {
  final String workspaceId;
  final String currentUserId;
  final String currentUserDisplayName;
  final String currentUserEmail;
  final String? initialProjectId;
  final String? initialMemberId;

  const TeamCapacityTab({
    super.key,
    required this.workspaceId,
    required this.currentUserId,
    required this.currentUserDisplayName,
    required this.currentUserEmail,
    this.initialProjectId,
    this.initialMemberId,
  });

  @override
  State<TeamCapacityTab> createState() => _TeamCapacityTabState();
}

class _TeamCapacityTabState extends State<TeamCapacityTab> {
  static const _rangeOptions = <int>[7, 14, 30];

  int _rangeDays = 14;
  DateTime _start = _startOfWeek(DateTime.now());
  String? _projectId;
  String? _memberId;
  bool _canRebalance = false;

  @override
  void initState() {
    super.initState();
    _projectId = widget.initialProjectId;
    _memberId = widget.initialMemberId;
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    final allowed = await ServiceLocator.capacityPlanningService
        .canExecuteRebalanceActions(
          workspaceId: widget.workspaceId,
          userId: widget.currentUserId,
        );
    if (!mounted) return;
    setState(() => _canRebalance = allowed);
  }

  DateTime get _end => _start.add(Duration(days: _rangeDays - 1));

  Future<CapacitySnapshot> _loadSnapshot() {
    return ServiceLocator.capacityPlanningService.getCapacitySnapshot(
      workspaceId: widget.workspaceId,
      start: _start,
      end: _end,
      projectId: _projectId,
      memberId: _memberId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CapacitySnapshot>(
      future: _loadSnapshot(),
      builder: (context, snapshot) {
        return Column(
          children: [
            _buildToolbar(),
            const Divider(height: 1),
            Expanded(
              child: snapshot.connectionState == ConnectionState.waiting
                  ? const Center(child: CircularProgressIndicator())
                  : snapshot.hasError
                  ? Center(
                      child: Text(
                        UserFacingError.uiMessage(
                          snapshot.error,
                          action: 'load capacity',
                        ),
                      ),
                    )
                  : _buildContent(snapshot.data!),
            ),
          ],
        );
      },
    );
  }

  Widget _buildToolbar() {
    final chrome = ChromeColors.of(context);
    final projectTerminology = context.watch<WorkspaceProvider>().projectTerminology;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Wrap(
        runSpacing: 8,
        spacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Capacity Planner',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: chrome.scaffoldText,
            ),
          ),
          const SizedBox(width: 12),
          DropdownButton<int>(
            borderRadius: AppRadius.cardRadius,
            value: _rangeDays,
            style: TextStyle(color: chrome.scaffoldText),
            dropdownColor: chrome.surface,
            iconEnabledColor: chrome.scaffoldTextSecondary,
            items: _rangeOptions
                .map(
                  (days) => DropdownMenuItem(
                    value: days,
                    child: Text(
                      days == 7
                          ? '1 week'
                          : days == 14
                          ? '2 weeks'
                          : '1 month',
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => _rangeDays = v);
            },
          ),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _start = _startOfWeek(DateTime.now());
              });
            },
            icon: const Icon(Icons.today),
            label: const Text('Today'),
          ),
          StreamBuilder<List<Project>>(
            stream: ServiceLocator.projectService.getProjects(
              widget.workspaceId,
            ),
            builder: (context, snap) {
              final projects = snap.data ?? const <Project>[];
              return DropdownButton<String?>(
                borderRadius: AppRadius.cardRadius,
                value: _projectId,
                hint: Text('All ${projectTerminology.toLowerCase()}',
                    style: TextStyle(color: chrome.scaffoldTextSecondary)),
                style: TextStyle(color: chrome.scaffoldText),
                dropdownColor: chrome.surface,
                iconEnabledColor: chrome.scaffoldTextSecondary,
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All ${projectTerminology.toLowerCase()}'),
                  ),
                  ...projects.map(
                    (p) => DropdownMenuItem<String?>(
                      value: p.id,
                      child: Text(p.name),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _projectId = v),
              );
            },
          ),
          FutureBuilder<CapacitySnapshot>(
            future: _loadSnapshot(),
            builder: (context, snap) {
              final members = snap.data?.members ?? const <CapacityMemberRow>[];
              return DropdownButton<String?>(
                borderRadius: AppRadius.cardRadius,
                value: _memberId,
                hint: Text('All members',
                    style: TextStyle(color: chrome.scaffoldTextSecondary)),
                style: TextStyle(color: chrome.scaffoldText),
                dropdownColor: chrome.surface,
                iconEnabledColor: chrome.scaffoldTextSecondary,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All members'),
                  ),
                  ...members.map(
                    (m) => DropdownMenuItem<String?>(
                      value: m.userId,
                      child: Text(m.displayName),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _memberId = v),
              );
            },
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => setState(() {}),
            icon: Icon(Icons.refresh, color: chrome.scaffoldTextSecondary),
          ),
          OutlinedButton.icon(
            onPressed: _canRebalance ? _openAvailabilityManager : null,
            icon: const Icon(Icons.event_busy),
            label: const Text('Manage Availability'),
          ),
          if (!_canRebalance)
            const Chip(
              label: Text('Read-only'),
              avatar: Icon(Icons.lock_outline, size: 16),
            ),
        ],
      ),
    );
  }

  Widget _buildContent(CapacitySnapshot snapshot) {
    if (snapshot.members.isEmpty) {
      return const Center(child: Text('No members found for this workspace.'));
    }

    return Column(
      children: [
        _buildIssuesCard(snapshot),
        const SizedBox(height: 8),
        Expanded(child: _buildHeatmap(snapshot)),
      ],
    );
  }

  Widget _buildIssuesCard(CapacitySnapshot snapshot) {
    final issues = snapshot.issues.take(12).toList();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Capacity Issues (${snapshot.issues.length})',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (issues.isEmpty)
              const Text('No overload or high-risk days in the selected range.')
            else
              ...issues.map((issue) {
                final isOver = issue.issueType == 'over_capacity';
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    isOver ? Icons.error_outline : Icons.warning_amber_rounded,
                    color: isOver ? AppColors.error : AppColors.warning,
                  ),
                  title: Text(
                    '${issue.displayName} • ${_formatDay(issue.date)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${issue.committedHours.toStringAsFixed(1)}h / ${issue.capacityHours.toStringAsFixed(1)}h (${(issue.utilizationPct * 100).toStringAsFixed(0)}%)',
                  ),
                  trailing: _canRebalance
                      ? const Icon(Icons.chevron_right)
                      : null,
                  onTap: _canRebalance
                      ? () => _openRebalanceActions(snapshot, issue)
                      : null,
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildHeatmap(CapacitySnapshot snapshot) {
    final chrome = ChromeColors.of(context);
    final dayHeaders = _daysInRange(snapshot.start, snapshot.end);
    final headingStyle = TextStyle(color: chrome.scaffoldTextSecondary);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 860),
        child: DataTable(
          headingRowHeight: 44,
          dataRowMinHeight: 44,
          dataRowMaxHeight: 48,
          columns: [
            DataColumn(label: Text('Member', style: headingStyle)),
            ...dayHeaders.map(
              (d) => DataColumn(
                  label: Text(_formatShortDay(d), style: headingStyle)),
            ),
            DataColumn(label: Text('Util', style: headingStyle)),
          ],
          rows: snapshot.members.map((member) {
            return DataRow(
              cells: [
                DataCell(
                  SizedBox(
                    width: 180,
                    child: Text(
                      member.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: chrome.scaffoldText,
                      ),
                    ),
                  ),
                ),
                ...member.days.map((day) {
                  final color = _cellColor(day.utilizationPct);
                  return DataCell(
                    Container(
                      width: 54,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: color.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        day.committedHours.toStringAsFixed(1),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: chrome.scaffoldText,
                        ),
                      ),
                    ),
                  );
                }),
                DataCell(
                  Text(
                    '${(member.utilizationPct * 100).toStringAsFixed(0)}%',
                    style: TextStyle(color: chrome.scaffoldText),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _openRebalanceActions(
    CapacitySnapshot snapshot,
    CapacityIssue issue,
  ) async {
    final tasks =
        await ServiceLocator.taskService
                .getAllWorkspaceTasks(widget.workspaceId)
                .first
            as List<Task>;
    final day = _dayOnly(issue.date);
    final candidateTasks = tasks.where((task) {
      if (task.isComplete) return false;
      if (!task.assignedToIds.contains(issue.userId)) return false;
      if (_projectId != null && task.projectId != _projectId) return false;
      final range = _taskRange(task);
      return !day.isBefore(range.$1) && !day.isAfter(range.$2);
    }).toList();

    if (!mounted) return;
    if (candidateTasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No matching tasks found for this issue.'),
        ),
      );
      return;
    }

    Task selectedTask = candidateTasks.first;
    String? targetAssignee;
    for (final member in snapshot.members) {
      if (member.userId != issue.userId) {
        targetAssignee = member.userId;
        break;
      }
    }
    var shiftByDays = 1;
    var mode = 'reassign';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Rebalance Workload'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${issue.displayName} • ${_formatDay(issue.date)}'),
                    const SizedBox(height: 10),
                    StackedField(
                      label: 'Task',
                      child: DropdownButtonFormField<Task>(
                        borderRadius: AppRadius.cardRadius,
                        initialValue: selectedTask,
                        decoration: const InputDecoration(),
                        items: candidateTasks
                            .map(
                              (t) => DropdownMenuItem(
                                value: t,
                                child: Text(t.title),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setLocalState(() => selectedTask = v);
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'reassign',
                          label: Text('Reassign'),
                        ),
                        ButtonSegment(
                          value: 'shift',
                          label: Text('Shift Date'),
                        ),
                      ],
                      selected: {mode},
                      onSelectionChanged: (s) {
                        setLocalState(() => mode = s.first);
                      },
                    ),
                    const SizedBox(height: 10),
                    if (mode == 'reassign')
                      StackedField(
                        label: 'New assignee',
                        child: DropdownButtonFormField<String>(
                          borderRadius: AppRadius.cardRadius,
                          initialValue: targetAssignee,
                          decoration: const InputDecoration(),
                          items: snapshot.members
                              .where((m) => m.userId != issue.userId)
                              .map(
                                (m) => DropdownMenuItem(
                                  value: m.userId,
                                  child: Text(m.displayName),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setLocalState(() => targetAssignee = v),
                        ),
                      )
                    else
                      StackedField(
                        label: 'Shift by',
                        child: DropdownButtonFormField<int>(
                          borderRadius: AppRadius.cardRadius,
                          initialValue: shiftByDays,
                          decoration: const InputDecoration(),
                          items: const [
                            DropdownMenuItem(value: 1, child: Text('+1 day')),
                            DropdownMenuItem(value: 2, child: Text('+2 days')),
                            DropdownMenuItem(value: 3, child: Text('+3 days')),
                            DropdownMenuItem(value: 5, child: Text('+5 days')),
                          ],
                          onChanged: (v) =>
                              setLocalState(() => shiftByDays = v ?? 1),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) return;

    try {
      if (mode == 'reassign') {
        if (targetAssignee == null) return;
        final String targetUserId = targetAssignee!;
        final assignees = List<String>.from(selectedTask.assignedToIds)
          ..remove(issue.userId);
        if (!assignees.contains(targetUserId)) {
          assignees.add(targetUserId);
        }
        await ServiceLocator.capacityPlanningService.reassignTask(
          taskId: selectedTask.id,
          assigneeIds: assignees,
        );
      } else {
        final showBusinessDaysOnly = context
            .read<WorkspaceProvider>()
            .showBusinessDaysOnly;
        final range = _taskRange(selectedTask);
        final newStart = _shiftDate(
          range.$1,
          shiftByDays,
          showBusinessDaysOnly,
        );
        final newDue = _shiftDate(range.$2, shiftByDays, showBusinessDaysOnly);
        await ServiceLocator.capacityPlanningService.shiftTask(
          taskId: selectedTask.id,
          newStart: newStart,
          newDue: newDue,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Rebalance action applied')));
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to rebalance: $e')));
    }
  }

  Future<void> _openAvailabilityManager() async {
    final snapshot = await ServiceLocator.capacityPlanningService
        .getCapacitySnapshot(
          workspaceId: widget.workspaceId,
          start: _start,
          end: _end,
        );
    if (!mounted) return;
    if (snapshot.members.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No members available.')));
      return;
    }

    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => _ManageAvailabilityDialog(
        workspaceId: widget.workspaceId,
        currentUserId: widget.currentUserId,
        currentUserDisplayName: widget.currentUserDisplayName,
        currentUserEmail: widget.currentUserEmail,
        rangeStart: _start,
        rangeEnd: _end,
        members: snapshot.members,
        initialUserId: _memberId,
      ),
    );

    if (mounted) {
      FocusManager.instance.primaryFocus?.unfocus();
      if (updated == true) setState(() {});
    }
  }

  static DateTime _shiftDate(DateTime date, int days, bool businessOnly) {
    var cursor = date;
    var moved = 0;
    while (moved < days) {
      cursor = cursor.add(const Duration(days: 1));
      if (!businessOnly || _isBusinessDay(cursor)) {
        moved++;
      }
    }
    return cursor;
  }

  static (DateTime, DateTime) _taskRange(Task task) {
    final now = _dayOnly(DateTime.now());
    var start = _dayOnly(task.startDate ?? task.dueDate ?? now);
    var end = _dayOnly(task.dueDate ?? task.startDate ?? now);
    if (end.isBefore(start)) {
      final temp = start;
      start = end;
      end = temp;
    }
    return (start, end);
  }

  static DateTime _startOfWeek(DateTime date) {
    final d = _dayOnly(date);
    return d.subtract(Duration(days: d.weekday - DateTime.monday));
  }

  static DateTime _dayOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static bool _isBusinessDay(DateTime d) =>
      d.weekday != DateTime.saturday && d.weekday != DateTime.sunday;

  static List<DateTime> _daysInRange(DateTime start, DateTime end) {
    final days = <DateTime>[];
    var cursor = _dayOnly(start);
    while (!cursor.isAfter(_dayOnly(end))) {
      days.add(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }
    return days;
  }

  static Color _cellColor(double util) {
    if (util > 1.0) return AppColors.error;
    if (util >= 0.9) return AppColors.warning;
    if (util >= 0.7) return AppColors.info;
    return AppColors.success;
  }

  static String _formatShortDay(DateTime day) {
    final weekday = ['M', 'T', 'W', 'T', 'F', 'S', 'S'][day.weekday - 1];
    return '$weekday ${day.month}/${day.day}';
  }

  static String _formatDay(DateTime day) =>
      '${day.month}/${day.day}/${day.year}';
}

class _ManageAvailabilityDialog extends StatefulWidget {
  final String workspaceId;
  final String currentUserId;
  final String currentUserDisplayName;
  final String currentUserEmail;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final List<CapacityMemberRow> members;
  final String? initialUserId;

  const _ManageAvailabilityDialog({
    required this.workspaceId,
    required this.currentUserId,
    required this.currentUserDisplayName,
    required this.currentUserEmail,
    required this.rangeStart,
    required this.rangeEnd,
    required this.members,
    required this.initialUserId,
  });

  @override
  State<_ManageAvailabilityDialog> createState() =>
      _ManageAvailabilityDialogState();
}

class _ManageAvailabilityDialogState extends State<_ManageAvailabilityDialog> {
  final _weeklyCapacityController = TextEditingController();
  final _reasonController = TextEditingController();
  List<MemberCapacityException> _exceptions = const [];
  bool _loading = false;
  bool _savingWeekly = false;
  bool _savingException = false;
  bool _didUpdate = false;
  late DateTime _exceptionStart;
  late DateTime _exceptionEnd;
  double _exceptionMultiplier = 0.0;
  String? _selectedUserId;

  @override
  void initState() {
    super.initState();
    _selectedUserId =
        widget.initialUserId != null &&
            widget.members.any((m) => m.userId == widget.initialUserId)
        ? widget.initialUserId
        : widget.members.first.userId;
    _exceptionStart = _dayOnly(widget.rangeStart);
    _exceptionEnd = _dayOnly(widget.rangeStart);
    _loadSelectedMember();
  }

  @override
  void dispose() {
    _weeklyCapacityController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadSelectedMember() async {
    final userId = _selectedUserId;
    if (userId == null) return;
    setState(() => _loading = true);
    try {
      final weekly = await ServiceLocator.capacityPlanningService
          .getMemberWeeklyCapacity(
            workspaceId: widget.workspaceId,
            userId: userId,
          );
      final exceptions = await ServiceLocator.capacityPlanningService
          .getMemberCapacityExceptions(
            workspaceId: widget.workspaceId,
            userId: userId,
            start: widget.rangeStart,
            end: widget.rangeEnd,
          );
      if (!mounted) return;
      setState(() {
        _weeklyCapacityController.text = weekly?.toStringAsFixed(1) ?? '';
        _exceptions = exceptions;
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _saveWeeklyCapacity() async {
    final userId = _selectedUserId;
    if (userId == null || _savingWeekly) return;
    setState(() => _savingWeekly = true);
    try {
      final trimmed = _weeklyCapacityController.text.trim();
      final weekly = trimmed.isEmpty ? null : double.tryParse(trimmed);
      if (trimmed.isNotEmpty && weekly == null) {
        throw Exception('Weekly capacity must be a number.');
      }
      await ServiceLocator.capacityPlanningService.upsertMemberCapacity(
        workspaceId: widget.workspaceId,
        userId: userId,
        weeklyCapacityHours: weekly,
      );
      _didUpdate = true;
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Weekly capacity saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save capacity: $e')));
    } finally {
      if (mounted) {
        setState(() => _savingWeekly = false);
      }
    }
  }

  Future<void> _createException() async {
    final userId = _selectedUserId;
    if (userId == null || _savingException) return;
    if (_exceptionEnd.isBefore(_exceptionStart)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End date must be on or after start date'),
        ),
      );
      return;
    }
    setState(() => _savingException = true);
    try {
      await ServiceLocator.capacityPlanningService
          .createCapacityException(
            workspaceId: widget.workspaceId,
            userId: userId,
            startDate: _exceptionStart,
            endDate: _exceptionEnd,
            capacityMultiplier: _exceptionMultiplier,
            reason: _reasonController.text.trim().isEmpty
                ? null
                : _reasonController.text.trim(),
          );
      _reasonController.clear();
      _didUpdate = true;
      await _loadSelectedMember();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Availability saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to add exception: $e')));
    } finally {
      if (mounted) {
        setState(() => _savingException = false);
      }
    }
  }

  Future<void> _deleteException(String exceptionId) async {
    try {
      await ServiceLocator.capacityPlanningService.deleteCapacityException(
        exceptionId,
      );
      _didUpdate = true;
      await _loadSelectedMember();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Availability exception removed')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to remove exception: $e')));
    }
  }

  Future<void> _pickDate({
    required DateTime current,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) onPicked(_dayOnly(picked));
  }

  String _memberName(String userId) {
    for (final member in widget.members) {
      if (member.userId == userId) return member.displayName;
    }
    return userId;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Manage Availability'),
      content: SizedBox(
        width: 700,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Adjust weekly capacity and time-off/partial-availability overrides for the selected range.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              StackedField(
                label: 'Crew member',
                child: DropdownButtonFormField<String>(
                  borderRadius: AppRadius.cardRadius,
                  key: ValueKey(_selectedUserId),
                  initialValue: _selectedUserId,
                  decoration: const InputDecoration(),
                  items: widget.members
                      .map(
                        (m) => DropdownMenuItem(
                          value: m.userId,
                          child: Text(m.displayName),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null || value == _selectedUserId) return;
                    setState(() => _selectedUserId = value);
                    _loadSelectedMember();
                  },
                ),
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: StackedField(
                        label:
                            'Weekly capacity hours (blank = workspace default)',
                        child: TextField(
                          controller: _weeklyCapacityController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: _savingWeekly ? null : _saveWeeklyCapacity,
                      child: _savingWeekly
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'Add Exception',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickDate(
                          current: _exceptionStart,
                          onPicked: (d) => setState(() => _exceptionStart = d),
                        ),
                        child: Text('Start: ${_formatDay(_exceptionStart)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickDate(
                          current: _exceptionEnd,
                          onPicked: (d) => setState(() => _exceptionEnd = d),
                        ),
                        child: Text('End: ${_formatDay(_exceptionEnd)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                StackedField(
                  label: 'Capacity level during exception',
                  child: DropdownButtonFormField<double>(
                    borderRadius: AppRadius.cardRadius,
                    initialValue: _exceptionMultiplier,
                    decoration: const InputDecoration(),
                    items: const [
                      DropdownMenuItem(value: 0.0, child: Text('0% (Out)')),
                      DropdownMenuItem(value: 0.25, child: Text('25%')),
                      DropdownMenuItem(value: 0.5, child: Text('50%')),
                      DropdownMenuItem(value: 0.75, child: Text('75%')),
                      DropdownMenuItem(value: 1.0, child: Text('100%')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _exceptionMultiplier = value);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 8),
                StackedField(
                  label: 'Reason (optional)',
                  child: TextField(
                    controller: _reasonController,
                    decoration: const InputDecoration(),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _savingException ? null : _createException,
                    icon: _savingException
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add),
                    label: const Text('Add Exception'),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Exceptions in range (${widget.rangeStart.month}/${widget.rangeStart.day} - ${widget.rangeEnd.month}/${widget.rangeEnd.day})',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (_exceptions.isEmpty)
                  Text(
                    'No availability exceptions for ${_memberName(_selectedUserId ?? '')} in this range.',
                    style: TextStyle(color: AppColors.textSecondary),
                  )
                else
                  ..._exceptions.map((ex) {
                    final pct = (ex.capacityMultiplier * 100).toStringAsFixed(
                      0,
                    );
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${_formatDay(ex.startDate)} - ${_formatDay(ex.endDate)} • $pct%',
                      ),
                      subtitle: ex.reason?.isNotEmpty == true
                          ? Text(ex.reason!)
                          : null,
                      trailing: IconButton(
                        tooltip: 'Delete',
                        onPressed: () => _deleteException(ex.id),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    );
                  }),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_didUpdate),
          child: const Text('Done'),
        ),
      ],
    );
  }

  static DateTime _dayOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);
  static String _formatDay(DateTime day) =>
      '${day.month}/${day.day}/${day.year}';
}
