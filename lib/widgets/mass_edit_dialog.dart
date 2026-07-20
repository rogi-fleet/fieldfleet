import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/task.dart';
import '../models/user.dart';
import '../models/workspace_member.dart';
import '../models/skill.dart';
import '../models/capacity_planning.dart';
import '../services/service_locator.dart';
import '../services/task_scheduler_service.dart';
import '../theme/theme.dart';

/// Shows mass edit dialog for selected tasks
void showMassEditDialog(
  BuildContext context, {
  required List<Task> tasks,
  required List<Task> allTasks,
  required List<AppUser> allWorkspaceUsers,
  required Function(List<Task>) onTasksUpdated,
  VoidCallback? onClone,
}) {
  showDialog(
    context: context,
    builder: (context) => _MassEditDialog(
      tasks: tasks,
      allTasks: allTasks,
      allWorkspaceUsers: allWorkspaceUsers,
      onTasksUpdated: onTasksUpdated,
      onClone: onClone,
    ),
  );
}

class _MassEditDialog extends StatefulWidget {
  final List<Task> tasks;
  final List<Task> allTasks;
  final List<AppUser> allWorkspaceUsers;
  final Function(List<Task>) onTasksUpdated;
  final VoidCallback? onClone;

  const _MassEditDialog({
    required this.tasks,
    required this.allTasks,
    required this.allWorkspaceUsers,
    required this.onTasksUpdated,
    this.onClone,
  });

  @override
  State<_MassEditDialog> createState() => _MassEditDialogState();
}

class _MassEditDialogState extends State<_MassEditDialog> {
  int? _progress;
  DateTime? _startDate;
  DateTime? _endDate;
  final Set<String> _assigneeIds = {};
  String? _status;
  bool _updateProgress = false;
  bool _updateStartDate = false;
  bool _updateEndDate = false;
  bool _updateAssignments = false;
  bool _updateStatus = false;
  bool _isAutoAssigning = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r16)),
      child: Container(
        width: 500,
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(AppSpacing.base),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit, color: AppColors.info),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mass Edit ${widget.tasks.length} Task${widget.tasks.length > 1 ? 's' : ''}',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Select fields to update',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Progress section
                    _buildEditSection(
                      title: 'Progress',
                      isEnabled: _updateProgress,
                      onChanged: (value) {
                        setState(() {
                          _updateProgress = value ?? false;
                        });
                      },
                      child: Column(
                        children: [
                          Text(
                            '${_progress ?? 0}%',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Slider(
                            value: (_progress ?? 0).toDouble(),
                            min: 0,
                            max: 100,
                            divisions: 20,
                            label: '${_progress ?? 0}%',
                            onChanged: _updateProgress
                                ? (value) {
                                    setState(() {
                                      _progress = value.toInt();
                                    });
                                  }
                                : null,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (int percent in [0, 25, 50, 75, 100])
                                ElevatedButton(
                                  onPressed: _updateProgress
                                      ? () {
                                          setState(() {
                                            _progress = percent;
                                          });
                                        }
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _progress == percent
                                        ? AppColors.infoDark
                                        : null,
                                    foregroundColor: _progress == percent
                                        ? Colors.white
                                        : null,
                                    minimumSize: const Size(50, 36),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.md,
                                    ),
                                  ),
                                  child: Text('$percent%'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Status section
                    _buildStatusSection(),

                    const SizedBox(height: 16),

                    // Start Date section
                    _buildEditSection(
                      title: 'Start Date',
                      isEnabled: _updateStartDate,
                      onChanged: (value) {
                        setState(() {
                          _updateStartDate = value ?? false;
                        });
                      },
                      child: InkWell(
                        onTap: _updateStartDate
                            ? () async {
                                final DateTime? picked = await showDatePicker(
                                  context: context,
                                  initialDate: _startDate ?? DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null) {
                                  setState(() {
                                    _startDate = DateTime(
                                      picked.year,
                                      picked.month,
                                      picked.day,
                                    );
                                  });
                                }
                              }
                            : null,
                        child: Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.cardBorder),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_today,
                                color: _updateStartDate
                                    ? AppColors.infoDark
                                    : AppColors.textTertiary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _startDate != null
                                    ? DateFormat('MM/dd/yy').format(_startDate!)
                                    : 'Select date',
                                style: TextStyle(
                                  color: _updateStartDate
                                      ? AppColors.infoDark
                                      : AppColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // End Date section
                    _buildEditSection(
                      title: 'End Date',
                      isEnabled: _updateEndDate,
                      onChanged: (value) {
                        setState(() {
                          _updateEndDate = value ?? false;
                        });
                      },
                      child: InkWell(
                        onTap: _updateEndDate
                            ? () async {
                                final DateTime? picked = await showDatePicker(
                                  context: context,
                                  initialDate: _endDate ?? DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null) {
                                  setState(() {
                                    _endDate = DateTime(
                                      picked.year,
                                      picked.month,
                                      picked.day,
                                    );
                                  });
                                }
                              }
                            : null,
                        child: Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.cardBorder),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_today,
                                color: _updateEndDate
                                    ? AppColors.infoDark
                                    : AppColors.textTertiary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _endDate != null
                                    ? DateFormat('MM/dd/yy').format(_endDate!)
                                    : 'Select date',
                                style: TextStyle(
                                  color: _updateEndDate
                                      ? AppColors.infoDark
                                      : AppColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Assignments section
                    _buildEditSection(
                      title: 'Assignments',
                      isEnabled: _updateAssignments,
                      onChanged: (value) {
                        setState(() {
                          _updateAssignments = value ?? false;
                        });
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Auto-assign button
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: _isAutoAssigning
                                  ? null
                                  : _autoAssignSelected,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_isAutoAssigning)
                                      const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    else
                                      Icon(
                                        Icons.auto_fix_high,
                                        size: 14,
                                        color: AppColors.secondaryDark,
                                      ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Auto-assign each task by skills & availability',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children:
                                widget.allWorkspaceUsers.map((user) {
                              final isSelected =
                                  _assigneeIds.contains(user.id);
                              return FilterChip(
                                label: Text(
                                    user.displayName ?? user.email),
                                selected: isSelected,
                                onSelected: _updateAssignments
                                    ? (selected) {
                                        setState(() {
                                          if (selected) {
                                            _assigneeIds.add(user.id);
                                          } else {
                                            _assigneeIds.remove(user.id);
                                          }
                                        });
                                      }
                                    : null,
                                avatar: user.profilePictureUrl != null
                                    ? CircleAvatar(
                                        backgroundImage: CachedNetworkImageProvider(
                                          user.profilePictureUrl!,
                                        ),
                                        radius: 12,
                                      )
                                    : CircleAvatar(
                                        radius: 12,
                                        child:
                                            Text(user.getInitials()),
                                      ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(AppSpacing.base),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppColors.cardBorder)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Clone button row
                  if (widget.onClone != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            widget.onClone!();
                          },
                          icon: const Icon(Icons.copy_outlined),
                          label: Text(
                            'Clone ${widget.tasks.length} Item${widget.tasks.length > 1 ? 's' : ''}',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.infoDark,
                            side: BorderSide(color: AppColors.info),
                          ),
                        ),
                      ),
                    ),
                  // Edit buttons row
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _canSave() ? _handleSave : null,
                          child: const Text('Update Tasks'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditSection({
    required String title,
    required bool isEnabled,
    required Function(bool?) onChanged,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isEnabled ? AppColors.infoLight : AppColors.surfaceAlt,
        border: Border.all(
          color: isEnabled ? AppColors.cardBorder : AppColors.cardBorder,
        ),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(value: isEnabled, onChanged: onChanged),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (isEnabled) ...[const SizedBox(height: 8), child],
        ],
      ),
    );
  }

  bool _canSave() {
    return (_updateProgress && _progress != null) ||
        (_updateStartDate && _startDate != null) ||
        (_updateEndDate && _endDate != null) ||
        (_updateAssignments && _assigneeIds.isNotEmpty) ||
        (_updateStatus && _status != null);
  }

  Widget _buildStatusSection() {
    const statusOptions = [
      ('not_started', 'Not Started', AppColors.textTertiary),
      ('working_on_it', 'Working On It', AppColors.info),
      ('stuck', 'Stuck', AppColors.warning),
      ('done', 'Done', AppColors.success),
    ];

    return _buildEditSection(
      title: 'Status',
      isEnabled: _updateStatus,
      onChanged: (value) {
        setState(() {
          _updateStatus = value ?? false;
        });
      },
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: statusOptions.map((option) {
          final (value, label, color) = option;
          final isSelected = _status == value;
          return ElevatedButton(
            onPressed: _updateStatus
                ? () {
                    setState(() {
                      _status = value;
                    });
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: isSelected ? color : AppColors.cardBorder,
              foregroundColor: isSelected
                  ? Colors.white
                  : AppColors.textPrimary,
              minimumSize: const Size(80, 36),
            ),
            child: Text(label),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _autoAssignSelected() async {
    if (widget.tasks.isEmpty) return;
    final workspaceId = widget.tasks.first.workspaceId;

    setState(() => _isAutoAssigning = true);
    try {
      // Fetch data once, score all tasks locally
      final membersFuture = (ServiceLocator.workspaceMemberService
              .getWorkspaceMembers(workspaceId)
              .first as Future<dynamic>)
          .then((v) => v as List<WorkspaceMember>);
      final skillsFuture = (ServiceLocator.skillService
              .getSkills(workspaceId)
              .first as Future<dynamic>)
          .then((v) => v as List<Skill>);
      final snapshotFuture =
          ServiceLocator.capacityPlanningService.getCapacitySnapshot(
        workspaceId: workspaceId,
        start: DateTime.now(),
        end: DateTime.now().add(const Duration(days: 90)),
      );

      final results = await Future.wait<dynamic>(
          [membersFuture, skillsFuture, snapshotFuture]);
      final members = results[0] as List<WorkspaceMember>;
      final skills = results[1] as List<Skill>;
      final snapshot = results[2] as CapacitySnapshot;

      final displayNames = <String, String>{
        for (final m in snapshot.members) m.userId: m.displayName,
      };
      for (final m in members) {
        displayNames.putIfAbsent(m.userId, () => m.userId);
      }

      final scheduler = TaskSchedulerService();
      var matched = 0;
      final assigneeIds = <String>{};
      for (final task in widget.tasks) {
        if (task.isComplete) continue;
        final proposal = scheduler.findBestAssignee(
          task: task,
          members: members,
          capacitySnapshot: snapshot,
          skills: skills,
          userDisplayNames: displayNames,
        );
        if (proposal != null) {
          assigneeIds.add(proposal.proposedAssigneeId);
          matched++;
        }
      }
      if (mounted) {
        setState(() {
          _assigneeIds.addAll(assigneeIds);
          _isAutoAssigning = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              matched > 0
                  ? 'Found $matched match${matched == 1 ? '' : 'es'} — '
                    '${assigneeIds.length} team member${assigneeIds.length == 1 ? '' : 's'} selected'
                  : 'No matches found for the selected tasks',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAutoAssigning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Auto-assign failed: $e')),
        );
      }
    }
  }

  void _handleSave() {
    final updatedTasks = <Task>[];

    for (final task in widget.tasks) {
      Map<String, dynamic> updates = {};

      if (_updateProgress && _progress != null) {
        updates['progress'] = _progress;
      }

      if (_updateStartDate && _startDate != null) {
        updates['startDate'] = _startDate;
        double? newDuration;
        if (task.dueDate != null) {
          final daysDiff = task.dueDate!.difference(_startDate!).inDays;
          newDuration = (daysDiff * 8).toDouble();
        }
        if (newDuration != null) {
          updates['estimatedDuration'] = newDuration;
        }
      }

      if (_updateEndDate && _endDate != null) {
        updates['dueDate'] = _endDate;
        double? newDuration;
        if (task.startDate != null) {
          final daysDiff = _endDate!.difference(task.startDate!).inDays;
          newDuration = (daysDiff * 8).toDouble();
        }
        if (newDuration != null) {
          updates['estimatedDuration'] = newDuration;
        }
      }

      if (_updateAssignments) {
        updates['assignedToIds'] = _assigneeIds.toList();
      }

      if (_updateStatus && _status != null) {
        updates['status'] = _status;
        // Auto-update isComplete and progress based on status
        if (_status == 'done') {
          updates['isComplete'] = true;
          updates['progress'] = 100;
        } else if (_status == 'not_started') {
          updates['isComplete'] = false;
          updates['progress'] = 0;
        }
      }

      if (updates.isNotEmpty) {
        updatedTasks.add(
          task.copyWith(
            progress: updates['progress'] as int? ?? task.progress,
            startDate: updates['startDate'] as DateTime? ?? task.startDate,
            dueDate: updates['dueDate'] as DateTime? ?? task.dueDate,
            estimatedDuration:
                updates['estimatedDuration'] as double? ??
                task.estimatedDuration,
            assignedToIds:
                updates['assignedToIds'] as List<String>? ?? task.assignedToIds,
            status: updates['status'] as String? ?? task.status,
            isComplete: updates['isComplete'] as bool? ?? task.isComplete,
          ),
        );
      }
    }

    if (updatedTasks.isNotEmpty) {
      widget.onTasksUpdated(updatedTasks);
      Navigator.of(context).pop();
    }
  }
}
