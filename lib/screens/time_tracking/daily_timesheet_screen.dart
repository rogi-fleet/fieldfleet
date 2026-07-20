import 'package:flutter/material.dart';
import '../../utils/user_facing_error.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../theme/theme.dart';
import '../../models/time_entry.dart';
import '../../models/time_entry_status.dart';
import '../../models/project.dart';
import '../../services/service_locator.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import 'time_entry_form_dialog.dart';
import 'widgets/time_tracking_view_bar.dart';
import 'widgets/time_entry_quick_form.dart';
import 'widgets/time_entry_gps_pin.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

class DailyTimesheetScreen extends StatefulWidget {
  final String? projectId;
  final ValueChanged<TimeTrackingView>? onViewChanged;
  final bool showViewBar;

  const DailyTimesheetScreen({
    super.key,
    this.projectId,
    this.onViewChanged,
    this.showViewBar = true,
  });

  @override
  State<DailyTimesheetScreen> createState() => _DailyTimesheetScreenState();
}

class _DailyTimesheetScreenState extends State<DailyTimesheetScreen> {
  dynamic get _timeEntryService => ServiceLocator.timeEntryService;
  dynamic get _projectService => ServiceLocator.projectService;
  dynamic get _templateService => ServiceLocator.timeEntryTemplateService;
  DateTime _selectedDate = DateTime.now();
  String? _quickProjectId;
  String? _quickTaskId;

  @override
  void initState() {
    super.initState();
    _quickProjectId = widget.projectId;
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final userId = authProvider.appUser?.id;
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    if (userId == null || workspaceId == null) {
      return const Scaffold(
        body: Center(child: Text('Error: Not authenticated')),
      );
    }

    // Get start and end of selected date
    final startOfDay = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final endOfDay = startOfDay
        .add(const Duration(days: 1))
        .subtract(const Duration(seconds: 1));

    return Scaffold(
      body: Column(
        children: [
          if (widget.showViewBar)
            TimeTrackingViewBar(
              currentView: TimeTrackingView.timesheet,
              onViewChanged: widget.onViewChanged,
              quickToggles: [
              TextButton.icon(
                onPressed: () => _copyPreviousDay(context),
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy Yesterday', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildDateSelector(),
                  const Divider(height: 1),
                  _buildQuickAddSection(context, workspaceId, userId),
                  const Divider(height: 1),
                  StreamBuilder<List<TimeEntry>>(
                    stream: _timeEntryService.getTimeEntriesForDateRange(
                      userId,
                      startOfDay,
                      endOfDay,
                      workspaceId: workspaceId,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(AppSpacing.xxl),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      if (snapshot.hasError) {
                        return Padding(
                          padding: const EdgeInsets.all(AppSpacing.base),
                          child: Center(
                            child: SelectableText(
                              UserFacingError.uiMessage(
                                snapshot.error,
                                action: 'load data',
                              ),
                            ),
                          ),
                        );
                      }

                      final allEntries = snapshot.data ?? [];
                      final entries = widget.projectId == null
                          ? allEntries
                          : allEntries
                                .where((e) => e.projectId == widget.projectId)
                                .toList();

                      if (entries.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
                          child: _buildEmptyState(),
                        );
                      }

                      if (widget.projectId == null &&
                          _quickProjectId == null &&
                          entries.isNotEmpty) {
                        final latest = entries.first;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _quickProjectId == null) {
                            setState(() {
                              _quickProjectId = latest.projectId;
                              _quickTaskId = latest.taskId;
                            });
                          }
                        });
                      }

                      return Column(
                        children: [
                          _buildSummaryCard(entries),
                          Padding(
                            padding: const EdgeInsets.all(AppSpacing.base),
                            child: Column(
                              children: [
                                for (final entry in entries)
                                  _buildTimeEntryCard(entry),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              setState(() {
                _selectedDate = _selectedDate.subtract(const Duration(days: 1));
              });
            },
          ),
          GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                setState(() {
                  _selectedDate = picked;
                });
              }
            },
            child: Row(
              children: [
                Text(
                  DateFormat('EEEE, MMM d, yyyy').format(_selectedDate),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.calendar_today, size: 20),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.chevron_right,
              color: _isToday() ? AppColors.textTertiary : null,
            ),
            onPressed: _isToday()
                ? null
                : () {
                    setState(() {
                      _selectedDate = _selectedDate.add(
                        const Duration(days: 1),
                      );
                    });
                  },
          ),
        ],
      ),
    );
  }

  bool _isToday() {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  Widget _buildSummaryCard(List<TimeEntry> entries) {
    double totalHours = 0;
    double totalCost = 0;

    for (final entry in entries) {
      totalHours +=
          entry.regularHours + entry.overtimeHours + entry.doubleTimeHours;
      totalCost += entry.totalCost;
    }

    return Card(
      margin: const EdgeInsets.all(AppSpacing.base),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Summary',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryItem(
                  'Total Hours',
                  totalHours.toStringAsFixed(1),
                  Icons.access_time,
                  AppColors.info,
                ),
                _buildSummaryItem(
                  'Total Cost',
                  '\$${totalCost.toStringAsFixed(2)}',
                  Icons.attach_money,
                  AppColors.success,
                ),
                _buildSummaryItem(
                  'Entries',
                  '${entries.length}',
                  Icons.list,
                  AppColors.warning,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildQuickAddSection(
    BuildContext context,
    String workspaceId,
    String userId,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth >= 720 ? 24.0 : 16.0;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding, 16, horizontalPadding, 16,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  child: TimeEntryQuickForm(
                    selectedDate: _selectedDate,
                    initialProjectId: _quickProjectId,
                    initialTaskId: _quickTaskId,
                    onEntrySaved: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Time entry added')),
                      );
                    },
                    onProjectChanged: (id) {
                      setState(() => _quickProjectId = id);
                    },
                    onTaskChanged: (id) {
                      setState(() => _quickTaskId = id);
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }


  Future<void> _copyPreviousDay(BuildContext context) async {
    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.appUser?.id;
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    if (userId == null || workspaceId == null) return;

    final prevDate = _selectedDate.subtract(const Duration(days: 1));
    final startOfPrev = DateTime(prevDate.year, prevDate.month, prevDate.day);
    final endOfPrev = startOfPrev
        .add(const Duration(days: 1))
        .subtract(const Duration(seconds: 1));

    final startOfDay = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final endOfDay = startOfDay
        .add(const Duration(days: 1))
        .subtract(const Duration(seconds: 1));

    try {
      final prevEntries = await _timeEntryService
          .getTimeEntriesForDateRange(
            userId,
            startOfPrev,
            endOfPrev,
            workspaceId: workspaceId,
          )
          .first;
      final todayEntries = await _timeEntryService
          .getTimeEntriesForDateRange(
            userId,
            startOfDay,
            endOfDay,
            workspaceId: workspaceId,
          )
          .first;

      final existingKeys = todayEntries
          .map((e) => '${e.projectId}_${e.taskId ?? ''}')
          .toSet();

      final workspaceProvider = context.read<WorkspaceProvider>();
      final hourlyRate =
          workspaceProvider.activeWorkspace?.hourlyRate ??
          workspaceProvider.activeWorkspace?.defaultHourlyRate ??
          authProvider.appUser?.hourlyRate;

      if (hourlyRate == null || hourlyRate <= 0) {
        throw Exception('Hourly wage not set');
      }

      int created = 0;
      int skipped = 0;
      for (final entry in prevEntries) {
        if (entry.taskId == null) {
          skipped++;
          continue;
        }
        final key = '${entry.projectId}_${entry.taskId}';
        if (existingKeys.contains(key)) {
          skipped++;
          continue;
        }
        final hours =
            entry.regularHours + entry.overtimeHours + entry.doubleTimeHours;
        final clockIn = DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
          8,
          0,
        );
        final totalMinutes = (hours * 60).round();
        final clockOut = clockIn.add(Duration(minutes: totalMinutes));
        await _timeEntryService.createTimeEntry(
          workspaceId: workspaceId,
          workerId: userId,
          projectId: entry.projectId,
          taskId: entry.taskId,
          date: _selectedDate,
          clockIn: clockIn,
          clockOut: clockOut,
          breakDuration: 0,
          hourlyRate: hourlyRate,
          notes: null,
        );
        created++;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Copied $created entries, skipped $skipped')),
        );
      }
    } catch (e) {
      if (mounted) {
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


  Future<void> _showSaveTemplateFromEntry(TimeEntry entry) async {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    final userId = authProvider.appUser?.id;
    if (workspaceId == null || userId == null || entry.taskId == null) return;

    final isAdminOrPm =
        authProvider.canManageUsers || authProvider.canCreateProjects;

    final nameController = TextEditingController();
    bool shared = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Template'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StackedField(
                label: 'Template Name',
                child: TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (isAdminOrPm)
                SwitchListTile(
                  value: shared,
                  onChanged: (value) => setDialogState(() => shared = value),
                  title: const Text('Share with workspace'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final name = nameController.text.trim();
    if (name.isEmpty) return;

    final hours =
        entry.regularHours + entry.overtimeHours + entry.doubleTimeHours;
    await _templateService.createTemplate(
      workspaceId: workspaceId,
      name: name,
      projectId: entry.projectId,
      taskId: entry.taskId!,
      userId: userId,
      shared: shared,
      defaultHours: hours,
      defaultBreakMinutes: entry.breakDuration,
      notesTemplate: entry.notes,
    );
  }

  Widget _buildTimeEntryCard(TimeEntry entry) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: entry.canEdit ? () => _showEditTimeEntryDialog(entry) : null,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: FutureBuilder<Project?>(
                      future: _projectService.getProject(entry.projectId),
                      builder: (context, snapshot) {
                        return Text(
                          snapshot.data?.name ?? 'Loading...',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                    ),
                  ),
                  _buildStatusChip(entry.status),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatTime(entry.clockIn),
                    style: TextStyle(color: AppColors.textPrimary),
                  ),
                  if (entry.hasClockInLocation)
                    TimeEntryGpsPin(
                      latitude: entry.clockInLatitude,
                      longitude: entry.clockInLongitude,
                      accuracyMeters: entry.locationAccuracy,
                      distanceFromProjectMeters: entry.distanceFromProject,
                      label: 'Clock In',
                    ),
                  Text(
                    ' - ${entry.clockOut != null ? _formatTime(entry.clockOut!) : 'Active'}',
                    style: TextStyle(color: AppColors.textPrimary),
                  ),
                  if (entry.hasClockOutLocation)
                    TimeEntryGpsPin(
                      latitude: entry.clockOutLatitude,
                      longitude: entry.clockOutLongitude,
                      accuracyMeters: entry.locationAccuracy,
                      distanceFromProjectMeters: entry.distanceFromProject,
                      label: 'Clock Out',
                    ),
                  const SizedBox(width: 16),
                  Icon(Icons.timer, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    entry.formattedDuration,
                    style: TextStyle(color: AppColors.textPrimary),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Regular: ${entry.regularHours.toStringAsFixed(1)}h',
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (entry.overtimeHours > 0)
                        Text(
                          'OT: ${entry.overtimeHours.toStringAsFixed(1)}h',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.warning,
                          ),
                        ),
                      if (entry.doubleTimeHours > 0)
                        Text(
                          'Double: ${entry.doubleTimeHours.toStringAsFixed(1)}h',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.error,
                          ),
                        ),
                    ],
                  ),
                  Text(
                    entry.formattedTotalCost,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
              if (entry.notes != null && entry.notes!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  entry.notes!,
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              if (entry.canSubmit) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _submitEntry(entry),
                        icon: const Icon(Icons.send, size: 16),
                        label: const Text('Submit for Approval'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => _showSaveTemplateFromEntry(entry),
                      icon: const Icon(Icons.save_alt, size: 16),
                      label: const Text('Save Template'),
                    ),
                    if (entry.status == TimeEntryStatus.draft) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(Icons.delete, color: AppColors.error),
                        onPressed: () => _deleteEntry(entry),
                      ),
                    ],
                  ],
                ),
              ],
              if (!entry.canSubmit) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _showSaveTemplateFromEntry(entry),
                      icon: const Icon(Icons.save_alt, size: 16),
                      label: const Text('Save Template'),
                    ),
                    if (entry.canEdit) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(Icons.delete, color: AppColors.error),
                        onPressed: () => _deleteEntry(entry),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(TimeEntryStatus status) {
    return Chip(
      label: Text(status.displayName, style: const TextStyle(fontSize: 12)),
      backgroundColor: status.color.withOpacity(0.2),
      side: BorderSide(color: status.color),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.schedule, size: 64, color: AppColors.textTertiary),
          const SizedBox(height: 16),
          Text(
            'No time entries for this date',
            style: TextStyle(fontSize: 18, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'Use Quick Add above to log time',
            style: TextStyle(fontSize: 14, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return DateFormat('h:mm a').format(time);
  }

  Future<void> _showEditTimeEntryDialog(TimeEntry entry) async {
    final result = await showTimeEntryFormDialog(
      context,
      selectedDate: _selectedDate,
      existingEntry: entry,
      initialProjectId: entry.projectId,
      initialTaskId: entry.taskId,
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Time entry updated')));
    }
  }

  Future<void> _submitEntry(TimeEntry entry) async {
    try {
      await _timeEntryService.submitTimeEntry(entry.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Time entry submitted for approval')),
        );
      }
    } catch (e) {
      if (mounted) {
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

  Future<void> _deleteEntry(TimeEntry entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Time Entry'),
        content: const Text('Are you sure you want to delete this time entry?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _timeEntryService.deleteTimeEntry(entry.id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Time entry deleted')));
      }
    } catch (e) {
      if (mounted) {
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
