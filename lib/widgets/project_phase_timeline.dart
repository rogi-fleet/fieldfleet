import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/task.dart';
import '../providers/workspace_provider.dart';
import '../services/service_locator.dart';
import '../theme/theme.dart';
import '../utils/project_terminology.dart';
import 'task_form_popup.dart';

/// A horizontal timeline widget showing project phases
/// Displays only top-level phases (summary tasks with no parent)
class ProjectPhaseTimeline extends StatefulWidget {
  final String projectId;
  final String workspaceId;

  const ProjectPhaseTimeline({
    super.key,
    required this.projectId,
    required this.workspaceId,
  });

  @override
  State<ProjectPhaseTimeline> createState() => _ProjectPhaseTimelineState();
}

class _ProjectPhaseTimelineState extends State<ProjectPhaseTimeline> {
  late Stream<List<Task>> _tasksStream;

  @override
  void initState() {
    super.initState();
    _tasksStream = _createTasksStream();
  }

  @override
  void didUpdateWidget(covariant ProjectPhaseTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId ||
        oldWidget.workspaceId != widget.workspaceId) {
      _tasksStream = _createTasksStream();
    }
  }

  Stream<List<Task>> _createTasksStream() {
    return ServiceLocator.taskService.getTasks(
      widget.projectId,
      workspaceId: widget.workspaceId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final singular = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    );
    final phasesTitle = '$singular Phases';
    return StreamBuilder<List<Task>>(
      stream: _tasksStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.timeline, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        phasesTitle,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Center(child: CircularProgressIndicator()),
                ],
              ),
            ),
          );
        }

        final allTasks = snapshot.data ?? [];

        // Filter for top-level phases only (summary tasks with no parent)
        final phases = allTasks
            .where(
              (task) =>
                  task.taskType == TaskType.summary && task.parentId == null,
            )
            .toList();

        // Sort by start date or created date
        phases.sort((a, b) {
          final aDate = a.startDate ?? a.createdAt;
          final bDate = b.startDate ?? b.createdAt;
          return aDate.compareTo(bDate);
        });

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.timeline, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      phasesTitle,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (phases.isEmpty)
                  Center(
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.r12),
                      child: InkWell(
                        onTap: () {
                          showTaskFormPopup(
                            context,
                            projectId: widget.projectId,
                          );
                        },
                        borderRadius: BorderRadius.circular(AppRadius.r12),
                        hoverColor: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.05),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.xl,
                            horizontal: AppSpacing.xxl,
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.timeline_outlined,
                                size: 48,
                                color: AppColors.textTertiary,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No phases defined yet',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Click to create a phase',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Create task groups to define ${singular.toLowerCase()} phases',
                                style: TextStyle(
                                  color: AppColors.textTertiary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  _buildPhaseTimeline(context, phases, allTasks),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPhaseTimeline(
    BuildContext context,
    List<Task> phases,
    List<Task> allTasks,
  ) {
    final isMobile = MediaQuery.of(context).size.width < AppBreakpoints.mobile;

    if (isMobile) {
      return Column(
        children: List.generate(phases.length * 2 - 1, (index) {
          if (index.isOdd) {
            // Downward connector arrow between cards
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Icon(
                Icons.keyboard_arrow_down,
                size: 20,
                color: AppColors.textTertiary,
              ),
            );
          }
          final phaseIndex = index ~/ 2;
          return _PhaseCard(
            phase: phases[phaseIndex],
            phaseNumber: phaseIndex + 1,
            allTasks: allTasks,
            showConnector: false,
            compact: true,
          );
        }),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 16,
      children: List.generate(phases.length, (index) {
        final phase = phases[index];
        final isLast = index == phases.length - 1;

        return _PhaseCard(
          phase: phase,
          phaseNumber: index + 1,
          allTasks: allTasks,
          showConnector: !isLast,
        );
      }),
    );
  }
}

class _PhaseCard extends StatelessWidget {
  final Task phase;
  final int phaseNumber;
  final List<Task> allTasks;
  final bool showConnector;
  final bool compact;

  const _PhaseCard({
    required this.phase,
    required this.phaseNumber,
    required this.allTasks,
    required this.showConnector,
    this.compact = false,
  });

  /// Phase title with any leading "Phase N" prefix stripped — the numbered
  /// badge/pill alongside already conveys the phase number, so a title like
  /// "Phase 1 — Demolition" would otherwise read the word "Phase" twice.
  String get _displayTitle {
    final stripped = phase.title.replaceFirst(
      RegExp(r'^\s*phase\s+\d+\s*[—:\-–]?\s*', caseSensitive: false),
      '',
    );
    return stripped.isEmpty ? phase.title : stripped;
  }

  @override
  Widget build(BuildContext context) {
    final aggregateProgress = _calculateAggregateProgress();
    final progress = _calculateDisplayProgress(aggregateProgress);
    final status = _getDisplayStatus(aggregateProgress, progress);
    final statusColor = _getStatusColor(status);

    if (compact) {
      return _buildCompactCard(context, progress, status, statusColor);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Phase card
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.r12),
            onTap: () {
              showTaskFormPopup(
                context,
                projectId: phase.projectId,
                taskId: phase.id,
              );
            },
            child: Container(
              width: 200,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: phase.groupColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.r12),
                border: Border.all(
                  color: phase.groupColor.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header: Phase number + Status
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: phase.groupColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'PHASE ${phaseNumber.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: phase.groupColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      _buildStatusBadge(status, statusColor),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Phase name
                  Text(
                    _displayTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  // Progress bar
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Progress',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          Text(
                            '${progress.round()}%',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                        child: LinearProgressIndicator(
                          value: progress / 100,
                          backgroundColor: AppColors.cardBorder,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            statusColor,
                          ),
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        // Connector arrow
        if (showConnector)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Icon(
              Icons.arrow_forward,
              size: 20,
              color: AppColors.textTertiary,
            ),
          ),
      ],
    );
  }

  /// Compact single-row card for mobile: phase label + name + progress + status
  Widget _buildCompactCard(
    BuildContext context,
    double progress,
    String status,
    Color statusColor,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () {
          showTaskFormPopup(
            context,
            projectId: phase.projectId,
            taskId: phase.id,
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: phase.groupColor.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: phase.groupColor.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              // Phase number pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: phase.groupColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text(
                  '$phaseNumber',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: phase.groupColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Phase name
              Expanded(
                child: Text(
                  _displayTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // Progress bar (compact)
              SizedBox(
                width: 48,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress / 100,
                    backgroundColor: AppColors.cardBorder,
                    valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                    minHeight: 4,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Percentage
              Text(
                '${progress.round()}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 8),
              // Status badge (compact)
              _buildCompactStatusBadge(status, statusColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactStatusBadge(String status, Color color) {
    IconData icon;
    switch (status) {
      case 'Complete':
        icon = Icons.check;
        break;
      case 'In Progress':
        icon = Icons.play_arrow;
        break;
      case 'Blocked':
        icon = Icons.block;
        break;
      default:
        icon = Icons.schedule;
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, size: 12, color: Colors.white),
    );
  }

  Widget _buildStatusBadge(String status, Color color) {
    IconData icon;
    switch (status) {
      case 'Complete':
        icon = Icons.check;
        break;
      case 'In Progress':
        icon = Icons.play_arrow;
        break;
      case 'Blocked':
        icon = Icons.block;
        break;
      default:
        icon = Icons.schedule;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            status.toUpperCase(),
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  double _calculateAggregateProgress() {
    // Get all child tasks of this phase
    final children = allTasks.where((t) => t.parentId == phase.id).toList();

    if (children.isEmpty) {
      // If no children, use the phase's own progress
      return phase.progress.toDouble();
    }

    // Calculate average progress of direct children
    double totalProgress = 0;
    for (final child in children) {
      if (child.taskType == TaskType.summary) {
        // For nested groups, recursively calculate
        totalProgress += _calculateChildGroupProgress(child);
      } else {
        totalProgress += child.progress;
      }
    }

    return totalProgress / children.length;
  }

  double _calculateDisplayProgress(double aggregateProgress) {
    final phaseProgress = phase.progress.toDouble();
    return aggregateProgress > phaseProgress
        ? aggregateProgress
        : phaseProgress;
  }

  double _calculateChildGroupProgress(Task group) {
    final children = allTasks.where((t) => t.parentId == group.id).toList();
    if (children.isEmpty) {
      return group.progress.toDouble();
    }

    double total = 0;
    for (final child in children) {
      if (child.taskType == TaskType.summary) {
        total += _calculateChildGroupProgress(child);
      } else {
        total += child.progress;
      }
    }
    return total / children.length;
  }

  String _getStatus(double progress) {
    if (progress >= 100) return 'Complete';
    if (progress > 0) return 'In Progress';
    return 'Not Started';
  }

  String _getDisplayStatus(double aggregateProgress, double displayProgress) {
    final explicitStatus = _getStatusFromTask();
    final aggregateStatus = _getStatus(aggregateProgress);

    if (aggregateStatus == 'Complete') return aggregateStatus;
    if (explicitStatus != 'Not Started') return explicitStatus;
    return _getStatus(displayProgress);
  }

  String _getStatusFromTask() {
    switch (phase.status) {
      case 'done':
        return 'Complete';
      case 'working_on_it':
        return 'In Progress';
      case 'stuck':
        return 'Blocked';
      default:
        return 'Not Started';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Complete':
        return AppColors.success;
      case 'In Progress':
        return AppColors.info;
      case 'Blocked':
        return AppColors.warning;
      default:
        return AppColors.textTertiary;
    }
  }
}
