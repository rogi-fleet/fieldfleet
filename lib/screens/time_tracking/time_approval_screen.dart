import 'package:flutter/material.dart';
import '../../utils/user_facing_error.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../theme/theme.dart';
import '../../models/time_entry.dart';
import '../../models/project.dart';
import '../../models/user.dart';
import '../../services/service_locator.dart';
import '../../providers/auth_provider.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';
import '../../widgets/common/list_skeleton.dart';
import '../../widgets/user_avatar.dart';
import 'widgets/time_tracking_view_bar.dart';
import 'widgets/time_entry_gps_pin.dart';

class TimeApprovalScreen extends StatefulWidget {
  final String? projectId;
  final ValueChanged<TimeTrackingView>? onViewChanged;
  final bool showViewBar;

  const TimeApprovalScreen({
    super.key,
    this.projectId,
    this.onViewChanged,
    this.showViewBar = true,
  });

  @override
  State<TimeApprovalScreen> createState() => _TimeApprovalScreenState();
}

class _TimeApprovalScreenState extends State<TimeApprovalScreen> {
  dynamic get _timeEntryService => ServiceLocator.timeEntryService;
  dynamic get _projectService => ServiceLocator.projectService;
  final dynamic _userService = ServiceLocator.userService;

  final Set<String> _selectedEntries = {};
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    final userId = authProvider.appUser?.id;

    if (workspaceId == null || userId == null) {
      return const Scaffold(
        body: Center(child: Text('Error: Not authenticated')),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          if (widget.showViewBar)
            TimeTrackingViewBar(
              currentView: TimeTrackingView.approvals,
              onViewChanged: widget.onViewChanged,
              quickToggles: [
              if (_selectedEntries.isNotEmpty)
                FilledButton.icon(
                  onPressed: _isProcessing ? null : () => _bulkApprove(userId),
                  icon: const Icon(Icons.check_circle, size: 16),
                  label: Text(
                    'Approve ${_selectedEntries.length}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
          Expanded(
            child: StreamBuilder<List<TimeEntry>>(
        stream: _timeEntryService.getPendingTimeEntries(workspaceId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const ListSkeleton();
          }

          if (snapshot.hasError) {
            return Center(
              child: SelectableText(
                UserFacingError.uiMessage(snapshot.error, action: 'load data'),
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
            return _buildEmptyState();
          }

          return Column(
            children: [
              _buildSummaryHeader(entries),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    return _buildApprovalCard(entries[index], userId);
                  },
                ),
              ),
            ],
          );
        },
      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryHeader(List<TimeEntry> entries) {
    double totalHours = 0;
    double totalCost = 0;

    for (final entry in entries) {
      totalHours +=
          entry.regularHours + entry.overtimeHours + entry.doubleTimeHours;
      totalCost += entry.totalCost;
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      color: AppColors.infoLight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryItem(
            'Pending',
            '${entries.length}',
            Icons.pending_actions,
            AppColors.warning,
          ),
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
        ],
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
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
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

  Widget _buildApprovalCard(TimeEntry entry, String managerId) {
    final isSelected = _selectedEntries.contains(entry.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          CheckboxListTile(
            value: isSelected,
            onChanged: (value) {
              setState(() {
                if (value == true) {
                  _selectedEntries.add(entry.id);
                } else {
                  _selectedEntries.remove(entry.id);
                }
              });
            },
            title: FutureBuilder<AppUser?>(
              future: _userService.getUserById(entry.workerId),
              builder: (context, snapshot) {
                final worker = snapshot.data;
                return Row(
                  children: [
                    UserAvatar(
                      user: worker,
                      userId: entry.workerId,
                      size: AvatarSize.small,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        worker?.displayName ?? 'Loading...',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                );
              },
            ),
            subtitle: FutureBuilder<Project?>(
              future: _projectService.getProject(entry.projectId),
              builder: (context, snapshot) {
                return Text(
                  snapshot.data?.name ?? 'Loading...',
                  style: TextStyle(color: AppColors.textSecondary),
                );
              },
            ),
            secondary: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  DateFormat('MMM d').format(entry.date),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  DateFormat('yyyy').format(entry.date),
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
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
                      ' - ${entry.clockOut != null ? _formatTime(entry.clockOut!) : 'N/A'}',
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
                    Expanded(
                      child: Column(
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
                          if (entry.breakDuration > 0)
                            Text(
                              'Break: ${entry.breakDuration} min',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      entry.formattedTotalCost,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
                if (entry.notes != null && entry.notes!.isNotEmpty) ...{
                  const SizedBox(height: 8),
                  Text(
                    entry.notes!,
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textSecondary,
                    ),
                  ),
                },
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isProcessing
                            ? null
                            : () => _approveEntry(entry.id, managerId),
                        icon: Icon(
                          Icons.check_circle,
                          size: 16,
                          color: AppColors.success,
                        ),
                        label: const Text('Approve'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.success,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isProcessing
                            ? null
                            : () => _showRejectDialog(entry.id, managerId),
                        icon: Icon(
                          Icons.cancel,
                          size: 16,
                          color: AppColors.error,
                        ),
                        label: const Text('Reject'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.task_alt, size: 64, color: AppColors.textTertiary),
          const SizedBox(height: 16),
          Text(
            'No pending time entries',
            style: TextStyle(fontSize: 18, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'All time entries have been reviewed',
            style: TextStyle(fontSize: 14, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return DateFormat('h:mm a').format(time);
  }

  Future<void> _approveEntry(String entryId, String managerId) async {
    setState(() => _isProcessing = true);

    try {
      await _timeEntryService.approveTimeEntry(entryId, managerId);
      if (mounted) {
        _selectedEntries.remove(entryId);
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Time entry approved'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
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

  Future<void> _bulkApprove(String managerId) async {
    setState(() => _isProcessing = true);

    try {
      await _timeEntryService.bulkApprove(_selectedEntries.toList(), managerId);
      if (mounted) {
        final count = _selectedEntries.length;
        setState(() {
          _selectedEntries.clear();
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$count time entries approved'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
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

  Future<void> _showRejectDialog(String entryId, String managerId) async {
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Time Entry'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Please provide a reason for rejection:'),
            const SizedBox(height: 12),
            StackedField(
              label: 'Reason *',
              child: TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'e.g., Incorrect hours, missing approval',
                ),
                maxLines: 3,
                autofocus: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please provide a reason')),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isProcessing = true);

      try {
        await _timeEntryService.rejectTimeEntry(
          entryId,
          managerId,
          reasonController.text.trim(),
        );
        if (mounted) {
          setState(() => _isProcessing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Time entry rejected'),
              backgroundColor: AppColors.warning,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isProcessing = false);
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

    reasonController.dispose();
  }
}
