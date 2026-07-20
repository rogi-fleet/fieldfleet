import 'package:flutter/material.dart';
import '../models/project.dart';
import '../models/task.dart';
import '../models/skill.dart';
import '../models/workspace_member.dart';
import '../models/capacity_planning.dart';
import '../services/service_locator.dart';
import '../services/task_scheduler_service.dart';
import '../theme/theme.dart';
import 'ai/ai_wizard_dialog.dart';
import 'ai/ai_wizard_shared.dart';

void showTaskSchedulerWizard(
  BuildContext context, {
  required Project project,
  required String workspaceId,
}) {
  showAiWizardDialog(
    context,
    title: 'Task Scheduler — ${project.name}',
    icon: Icons.event_available,
    child: _TaskSchedulerWizard(
      project: project,
      workspaceId: workspaceId,
    ),
  );
}

class _TaskSchedulerWizard extends StatefulWidget {
  final Project project;
  final String workspaceId;

  const _TaskSchedulerWizard({
    required this.project,
    required this.workspaceId,
  });

  @override
  State<_TaskSchedulerWizard> createState() => _TaskSchedulerWizardState();
}

class _TaskSchedulerWizardState extends State<_TaskSchedulerWizard> {
  static const _steps = [
    AiStepConfig(
      number: 1,
      title: 'Configure',
      subtitle: 'Set scheduling preferences',
      icon: Icons.tune,
    ),
    AiStepConfig(
      number: 2,
      title: 'Review Assignments',
      subtitle: 'Adjust proposed team assignments',
      icon: Icons.checklist,
    ),
    AiStepConfig(
      number: 3,
      title: 'Done',
      subtitle: 'Assignments applied',
      icon: Icons.check_circle_outline,
    ),
  ];

  final _pageController = PageController();
  int _currentStep = 0;

  // Config
  double _maxUtilization = 0.8;
  bool _requireFullSkillMatch = false;

  // State
  bool _isLoading = false;
  bool _isApplying = false;
  bool _applyComplete = false;
  bool _applyCancelled = false;
  String? _error;
  int _appliedCount = 0;
  int _failedCount = 0;
  int _totalToApply = 0;
  final List<TaskAssignmentProposal> _appliedProposals = [];

  // Data
  _TaskBreakdown? _breakdown;
  SchedulerResult? _result;
  Map<String, Skill> _skillMap = {};
  Map<String, String> _displayNames = {};
  List<WorkspaceMember> _members = [];
  List<Skill> _skills = [];
  CapacitySnapshot? _snapshot;

  // Sort
  _SortMode _sortMode = _SortMode.score;

  @override
  void initState() {
    super.initState();
    _loadInitialCounts();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialCounts() async {
    try {
      final tasks = await ServiceLocator.taskService
          .getTasks(widget.project.id, workspaceId: widget.workspaceId)
          .first as List<Task>;
      final incomplete = tasks.where((t) =>
          !t.isComplete && t.taskType != TaskType.summary);
      final unassigned = incomplete.where((t) => t.assignedToIds.isEmpty);
      final withDates = unassigned.where((t) =>
          t.startDate != null || t.dueDate != null);
      final withSkills = unassigned.where((t) =>
          t.requiredSkillIds.isNotEmpty);
      if (mounted) {
        setState(() => _breakdown = _TaskBreakdown(
          totalIncomplete: incomplete.length,
          totalUnassigned: unassigned.length,
          withDates: withDates.length,
          withSkills: withSkills.length,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Failed to load tasks: $e');
      }
    }
  }

  void _goToStep(int step) {
    setState(() => _currentStep = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _runScheduler() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final tasksFuture = (ServiceLocator.taskService
              .getTasks(widget.project.id, workspaceId: widget.workspaceId)
              .first as Future<dynamic>)
          .then((v) => v as List<Task>);
      final membersFuture = (ServiceLocator.workspaceMemberService
              .getWorkspaceMembers(widget.workspaceId)
              .first as Future<dynamic>)
          .then((v) => v as List<WorkspaceMember>);
      final skillsFuture = (ServiceLocator.skillService
              .getSkills(widget.workspaceId)
              .first as Future<dynamic>)
          .then((v) => v as List<Skill>);
      final snapshotFuture =
          ServiceLocator.capacityPlanningService.getCapacitySnapshot(
        workspaceId: widget.workspaceId,
        start: DateTime.now(),
        end: DateTime.now().add(const Duration(days: 90)),
        projectId: widget.project.id,
      );

      final results = await Future.wait<dynamic>(
          [tasksFuture, membersFuture, skillsFuture, snapshotFuture]);

      final tasks = results[0] as List<Task>;
      final members = results[1] as List<WorkspaceMember>;
      final skills = results[2] as List<Skill>;
      final snapshot = results[3] as CapacitySnapshot;
      _skillMap = {for (final s in skills) s.id: s};
      _members = members;
      _skills = skills;
      _snapshot = snapshot;

      final displayNames = <String, String>{
        for (final m in snapshot.members) m.userId: m.displayName,
      };
      for (final m in members) {
        displayNames.putIfAbsent(m.userId, () => m.userId);
      }
      _displayNames = displayNames;

      final scheduler = TaskSchedulerService();
      final result = scheduler.computeAssignments(
        tasks: tasks,
        members: members,
        capacitySnapshot: snapshot,
        skills: skills,
        userDisplayNames: displayNames,
        config: SchedulerConfig(
          maxUtilizationThreshold: _maxUtilization,
          requireFullSkillMatch: _requireFullSkillMatch,
        ),
      );

      if (mounted) {
        setState(() {
          _result = result;
          _isLoading = false;
        });
        _goToStep(1);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _confirmAndApply() async {
    final acceptedCount =
        _result!.proposals.where((p) => p.accepted).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apply assignments?'),
        content: Text(
          'This will assign team members to $acceptedCount '
          'task${acceptedCount == 1 ? '' : 's'}. '
          'Existing assignees will be replaced.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _applyAssignments();
  }

  Future<void> _applyAssignments() async {
    final accepted =
        _result!.proposals.where((p) => p.accepted).toList();
    if (accepted.isEmpty) return;

    setState(() {
      _isApplying = true;
      _applyCancelled = false;
      _appliedCount = 0;
      _failedCount = 0;
      _totalToApply = accepted.length;
      _appliedProposals.clear();
    });
    _goToStep(2);

    for (final proposal in accepted) {
      if (_applyCancelled) break;
      try {
        await ServiceLocator.taskService.updateTask(
          taskId: proposal.task.id,
          assignedToIds: [proposal.proposedAssigneeId],
        );
        if (mounted) {
          _appliedProposals.add(proposal);
          setState(() => _appliedCount++);
        }
      } catch (_) {
        if (mounted) setState(() => _failedCount++);
      }
    }

    if (mounted) {
      setState(() {
        _isApplying = false;
        _applyComplete = true;
      });
    }
  }

  List<TaskAssignmentProposal> get _sortedProposals {
    if (_result == null) return [];
    final list = List<TaskAssignmentProposal>.from(_result!.proposals);
    switch (_sortMode) {
      case _SortMode.score:
        list.sort((a, b) => b.combinedScore.compareTo(a.combinedScore));
      case _SortMode.assignee:
        list.sort((a, b) => a.proposedAssigneeName
            .compareTo(b.proposedAssigneeName));
      case _SortMode.date:
        list.sort((a, b) {
          final aDate = a.task.startDate ?? a.task.dueDate ?? DateTime(2099);
          final bDate = b.task.startDate ?? b.task.dueDate ?? DateTime(2099);
          return aDate.compareTo(bDate);
        });
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AiWizardHeader(
          currentStep: _currentStep,
          totalSteps: 3,
          steps: _steps,
        ),
        Expanded(
          child: PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildConfigureStep(),
              _buildReviewStep(),
              _buildApplyStep(),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════ Step 1: Configure ═══════════════════════════

  Widget _buildConfigureStep() {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 20),
            Text(
              'Fetching team data and tasks...',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Matching skills and availability',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65), fontSize: 14),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () {
                setState(() {
                  _isLoading = false;
                });
              },
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
    }

    final bd = _breakdown;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Summary card with breakdown ──
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppRadius.r12),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.15),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color:
                            theme.colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Icon(
                        Icons.assignment_ind,
                        color: theme.colorScheme.primary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${bd?.totalUnassigned ?? 0} unassigned tasks',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'The scheduler matches team members to tasks '
                            'based on their skills and current workload.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (bd != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Row(
                      children: [
                        _buildBreakdownStat(
                          bd.totalUnassigned.toString(),
                          'Unassigned',
                          Icons.person_off_outlined,
                          AppColors.warning,
                        ),
                        _buildBreakdownDivider(),
                        _buildBreakdownStat(
                          bd.withDates.toString(),
                          'With dates',
                          Icons.calendar_today,
                          AppColors.success,
                        ),
                        _buildBreakdownDivider(),
                        _buildBreakdownStat(
                          bd.withSkills.toString(),
                          'With skills',
                          Icons.construction,
                          theme.colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── Max workload slider ──
          Text(
            'Max Workload',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Don\'t assign to team members already above this workload level.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6,
                    thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8),
                  ),
                  child: Slider(
                    value: _maxUtilization,
                    min: 0.5,
                    max: 1.0,
                    divisions: 10,
                    label: '${(_maxUtilization * 100).round()}%',
                    onChanged: (v) => setState(() => _maxUtilization = v),
                  ),
                ),
              ),
              Container(
                width: 56,
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: _utilizationColor(_maxUtilization)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${(_maxUtilization * 100).round()}%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: _utilizationColor(_maxUtilization),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Full skill match toggle ──
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Require all skills'),
            subtitle: Text(
              'Only suggest members who have every skill the task requires.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            value: _requireFullSkillMatch,
            onChanged: (v) => setState(() => _requireFullSkillMatch = v),
          ),

          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: AppColors.error, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: AppColors.error, fontSize: 13),
                    ),
                  ),
                  if (_breakdown == null)
                    TextButton(
                      onPressed: () {
                        setState(() => _error = null);
                        _loadInitialCounts();
                      },
                      child: const Text('Retry'),
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 28),

          // ── Run button ──
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (bd?.withDates ?? 0) == 0 ? null : _runScheduler,
              icon: const Icon(Icons.assignment_ind),
              label: const Text('Run Scheduler'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          if (bd != null && bd.totalUnassigned > 0 && bd.withDates == 0) ...[
            const SizedBox(height: 10),
            Text(
              'All unassigned tasks are missing start/due dates. '
              'Add dates to tasks before scheduling.',
              style: TextStyle(
                color: AppColors.warning,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBreakdownStat(
      String value, String label, IconData icon, Color color) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownDivider() {
    return Container(
      width: 1,
      height: 36,
      color: AppColors.cardBorder,
    );
  }

  // ═══════════════════════════ Step 2: Review ═══════════════════════════

  Widget _buildReviewStep() {
    final result = _result;
    if (result == null) {
      return const Center(child: Text('No results yet.'));
    }

    final theme = Theme.of(context);
    final acceptedCount = result.proposals.where((p) => p.accepted).length;
    final sorted = _sortedProposals;

    // Build per-assignee summary
    final assigneeSummary = <String, int>{};
    for (final p in result.proposals.where((p) => p.accepted)) {
      assigneeSummary[p.proposedAssigneeName] =
          (assigneeSummary[p.proposedAssigneeName] ?? 0) + 1;
    }

    return Column(
      children: [
        // ── Assignee distribution bar ──
        if (assigneeSummary.isNotEmpty)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.04),
              border: Border(
                bottom: BorderSide(color: AppColors.cardBorder),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Team Distribution',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                _buildDistributionBar(assigneeSummary, acceptedCount),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    ...assigneeSummary.entries.take(6).map((e) {
                      final color =
                          _assigneeColor(e.key, assigneeSummary.keys.toList());
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${e.key} (${e.value})',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                            ),
                          ),
                        ],
                      );
                    }),
                    if (assigneeSummary.length > 6)
                      Text(
                        '+${assigneeSummary.length - 6} more',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

        // ── Summary + sort bar ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: AppColors.cardBorder),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      children: [
                        Text.rich(TextSpan(children: [
                          TextSpan(
                            text: '${result.proposals.length}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(
                            text: ' of ${result.totalEligibleTasks} matched',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)),
                          ),
                        ])),
                        if (result.unassignableTasks.isNotEmpty)
                          Text(
                            '• ${result.unassignableTasks.length} unmatched',
                            style: TextStyle(
                                color: AppColors.warning, fontSize: 13),
                          ),
                        if (result.skippedNoDates > 0)
                          Text(
                            '• ${result.skippedNoDates} no dates',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45), fontSize: 13),
                          ),
                      ],
                    ),
                  ),
                  // Sort dropdown
                  PopupMenuButton<_SortMode>(
                    tooltip: 'Sort',
                    icon: const Icon(Icons.sort, size: 20),
                    onSelected: (v) => setState(() => _sortMode = v),
                    itemBuilder: (_) => [
                      _buildSortItem(
                          _SortMode.score, 'Best match', Icons.stars),
                      _buildSortItem(
                          _SortMode.assignee, 'Assignee', Icons.person),
                      _buildSortItem(
                          _SortMode.date, 'Task date', Icons.calendar_today),
                    ],
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        final allAccepted =
                            result.proposals.every((p) => p.accepted);
                        for (final p in result.proposals) {
                          p.accepted = !allAccepted;
                        }
                      });
                    },
                    child: Text(
                      result.proposals.every((p) => p.accepted)
                          ? 'Deselect All'
                          : 'Select All',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // ── Proposal list ──
        Expanded(
          child: result.proposals.isEmpty
              ? _buildEmptyProposals()
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  itemCount: sorted.length +
                      (result.unassignableTasks.isNotEmpty ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    if (index < sorted.length) {
                      return _buildProposalCard(sorted[index]);
                    }
                    return _buildUnassignableSection(
                        result.unassignableTasks);
                  },
                ),
        ),

        // ── Bottom action bar ──
        Container(
          padding: const EdgeInsets.all(AppSpacing.base),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(top: BorderSide(color: AppColors.cardBorder)),
          ),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _goToStep(0),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Back'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: acceptedCount == 0 ? null : _confirmAndApply,
                icon: const Icon(Icons.check),
                label: Text(
                    'Apply $acceptedCount Assignment${acceptedCount == 1 ? '' : 's'}'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  PopupMenuItem<_SortMode> _buildSortItem(
      _SortMode mode, String label, IconData icon) {
    return PopupMenuItem(
      value: mode,
      child: Row(
        children: [
          Icon(icon, size: 18,
              color: _sortMode == mode ? Theme.of(context).colorScheme.primary : null),
          const SizedBox(width: 8),
          Text(label,
              style: _sortMode == mode
                  ? TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary)
                  : null),
        ],
      ),
    );
  }

  Widget _buildDistributionBar(
      Map<String, int> summary, int total) {
    if (total == 0) return const SizedBox.shrink();
    final keys = summary.keys.toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: SizedBox(
        height: 8,
        child: Row(
          children: keys.map((name) {
            final count = summary[name]!;
            return Expanded(
              flex: count,
              child: Container(
                color: _assigneeColor(name, keys),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildEmptyProposals() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_search, size: 56, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)),
          const SizedBox(height: 16),
          Text(
            'No matches found',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try lowering the max workload threshold\nor disabling "require all skills".',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => _goToStep(0),
            child: const Text('Back to Settings'),
          ),
        ],
      ),
    );
  }

  Color _confidenceColor(double score) {
    if (score >= 0.7) return AppColors.success;
    if (score >= 0.4) return AppColors.warning;
    return AppColors.error;
  }

  Widget _buildProposalCard(TaskAssignmentProposal proposal) {
    final theme = Theme.of(context);
    final skillPct = (proposal.skillMatchScore * 100).round();
    final confidence = _confidenceColor(proposal.combinedScore);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(
          color: proposal.accepted
              ? theme.colorScheme.primary.withValues(alpha: 0.3)
              : AppColors.cardBorder,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () =>
            setState(() => proposal.accepted = !proposal.accepted),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Confidence accent bar
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: proposal.accepted
                      ? confidence
                      : AppColors.cardBorder,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(10),
                    bottomLeft: Radius.circular(10),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: proposal.accepted,
                        onChanged: (v) =>
                            setState(() => proposal.accepted = v ?? false),
                      ),
                      Expanded(
                        child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Task title + date
                    Text(
                      proposal.task.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (proposal.task.startDate != null ||
                        proposal.task.dueDate != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _formatDateRange(
                            proposal.task.startDate, proposal.task.dueDate),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),

                    // ── Assignee row with override dropdown ──
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor:
                              theme.colorScheme.primary.withValues(alpha: 0.15),
                          child: Text(
                            _initials(proposal.proposedAssigneeName),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            proposal.proposedAssigneeName,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        // Override button
                        _buildOverrideButton(proposal),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // ── Visual metric bars ──
                    _buildMetricBar(
                      label: 'Skill match',
                      value: proposal.skillMatchScore,
                      displayValue: '$skillPct%',
                      color: skillPct == 100
                          ? AppColors.success
                          : skillPct >= 50
                              ? AppColors.warning
                              : AppColors.error,
                    ),
                    const SizedBox(height: 6),
                    _buildMetricBar(
                      label: 'Available',
                      value: proposal.availabilityScore.clamp(0.0, 1.0),
                      displayValue: '${(proposal.availabilityScore * 100).round()}%',
                      color: _utilizationColor(
                          proposal.avgUtilizationDuringTask),
                    ),

                    // Skill chips
                    if (proposal.matchedSkillNames.isNotEmpty ||
                        proposal.missingSkillNames.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          ...proposal.matchedSkillNames
                              .map((s) => _buildSkillTag(s, matched: true)),
                          ...proposal.missingSkillNames
                              .map((s) => _buildSkillTag(s, matched: false)),
                        ],
                      ),
                    ],
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
      ),
    );
  }

  Widget _buildOverrideButton(TaskAssignmentProposal proposal) {
    return PopupMenuButton<String>(
      tooltip: 'Change assignee',
      icon: Icon(Icons.swap_horiz, size: 18, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)),
      onSelected: (userId) {
        setState(() {
          proposal.proposedAssigneeId = userId;
          proposal.proposedAssigneeName =
              _displayNames[userId] ?? userId;
          // Recalculate scores for the new assignee
          if (_snapshot != null) {
            final member = _members
                .where((m) => m.userId == userId)
                .firstOrNull;
            if (member != null) {
              final rescored = TaskSchedulerService().scoreSpecificMember(
                task: proposal.task,
                member: member,
                capacitySnapshot: _snapshot!,
                skills: _skills,
                userDisplayNames: _displayNames,
              );
              if (rescored != null) {
                proposal.skillMatchScore = rescored.skillMatchScore;
                proposal.availabilityScore = rescored.availabilityScore;
                proposal.combinedScore = rescored.combinedScore;
                proposal.matchedSkillNames = rescored.matchedSkillNames;
                proposal.missingSkillNames = rescored.missingSkillNames;
                proposal.avgUtilizationDuringTask =
                    rescored.avgUtilizationDuringTask;
              }
            }
          }
        });
      },
      itemBuilder: (_) {
        return _displayNames.entries
            .where((e) => e.key != proposal.proposedAssigneeId)
            .map((e) => PopupMenuItem<String>(
                  value: e.key,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.12),
                        child: Text(
                          _initials(e.value),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(e.value),
                    ],
                  ),
                ))
            .toList();
      },
    );
  }

  Widget _buildMetricBar({
    required String label,
    required double value,
    required String displayValue,
    required Color color,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: LinearProgressIndicator(
                value: value.clamp(0.0, 1.0),
                backgroundColor: AppColors.cardBorder,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 36,
          child: Text(
            displayValue,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildSkillTag(String name, {required bool matched}) {
    final skill = _skillMap.values.where((s) => s.name == name).firstOrNull;
    final color = matched
        ? (skill?.color ?? AppColors.success)
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: matched
            ? null
            : Border.all(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45).withValues(alpha: 0.3),
                strokeAlign: BorderSide.strokeAlignInside,
              ),
      ),
      child: Text(
        matched ? name : '$name (missing)',
        style: TextStyle(
          fontSize: 10,
          color: matched ? color : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildUnassignableSection(List<Task> tasks) {
    final theme = Theme.of(context);
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      title: Text(
        '${tasks.length} task${tasks.length == 1 ? '' : 's'} could not be matched',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: AppColors.warning,
          fontWeight: FontWeight.w500,
        ),
      ),
      leading: Icon(Icons.warning_amber_rounded,
          color: AppColors.warning, size: 20),
      children: tasks
          .map((t) => ListTile(
                dense: true,
                title: Text(t.title, style: const TextStyle(fontSize: 13)),
                subtitle: Text(
                  t.requiredSkillIds.isEmpty
                      ? 'All members are over capacity'
                      : 'No members with required skills available',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
              ))
          .toList(),
    );
  }

  // ═══════════════════════════ Step 3: Apply ═══════════════════════════

  Widget _buildApplyStep() {
    final theme = Theme.of(context);

    if (_isApplying) {
      final progress =
          _totalToApply > 0 ? (_appliedCount + _failedCount) / _totalToApply : 0.0;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 4,
                        backgroundColor: AppColors.cardBorder,
                      ),
                    ),
                    Text(
                      '${_appliedCount + _failedCount}/$_totalToApply',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Applying assignments...',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.xs),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: AppColors.cardBorder,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$_appliedCount assigned${_failedCount > 0 ? ', $_failedCount failed' : ''}',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65), fontSize: 13),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => setState(() => _applyCancelled = true),
                icon: const Icon(Icons.stop, size: 18),
                label: const Text('Stop'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!_applyComplete) {
      return const Center(child: Text('Waiting...'));
    }

    // Build per-assignee summary from actually-applied proposals
    final assigneeTasks = <String, List<String>>{};
    for (final p in _appliedProposals) {
      assigneeTasks
          .putIfAbsent(p.proposedAssigneeName, () => [])
          .add(p.task.title);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(AppSpacing.base),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.success.withValues(alpha: 0.12),
            ),
            child: Icon(
              Icons.check_circle,
              size: 56,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '$_appliedCount task${_appliedCount == 1 ? '' : 's'} assigned',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          if (_failedCount > 0) ...[
            const SizedBox(height: 8),
            Text(
              '$_failedCount assignment${_failedCount == 1 ? '' : 's'} failed',
              style: TextStyle(color: AppColors.error),
            ),
          ],
          if (_applyCancelled) ...[
            const SizedBox(height: 8),
            Text(
              'Stopped early — ${_totalToApply - _appliedCount - _failedCount} '
              'remaining assignments were skipped.',
              style: TextStyle(color: AppColors.warning, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],

          // ── Per-assignee breakdown ──
          if (assigneeTasks.isNotEmpty) ...[
            const SizedBox(height: 28),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Assignment Summary',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...assigneeTasks.entries.map((entry) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: theme.colorScheme.primary
                                .withValues(alpha: 0.15),
                            child: Text(
                              _initials(entry.key),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            entry.key,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${entry.value.length} task${entry.value.length == 1 ? '' : 's'}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...entry.value.map((title) => Padding(
                            padding: const EdgeInsets.only(left: 36, top: 2),
                            child: Row(
                              children: [
                                Icon(Icons.check,
                                    size: 14, color: AppColors.success),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    title,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )),
                    ],
                  ),
                )),
          ],

          const SizedBox(height: 24),
          SizedBox(
            width: 160,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════ Helpers ═══════════════════════════

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  String _formatDateRange(DateTime? start, DateTime? end) {
    String fmt(DateTime d) =>
        '${d.month}/${d.day}/${d.year.toString().substring(2)}';
    if (start != null && end != null) return '${fmt(start)} – ${fmt(end)}';
    if (start != null) return 'Starts ${fmt(start)}';
    if (end != null) return 'Due ${fmt(end)}';
    return '';
  }

  Color _utilizationColor(double util) {
    if (util < 0.6) return AppColors.success;
    if (util < 0.8) return AppColors.warning;
    return AppColors.error;
  }

  static const _assigneeColors = [
    Color(0xFF4285F4), // blue
    Color(0xFF34A853), // green
    Color(0xFFFBBC04), // yellow
    Color(0xFFEA4335), // red
    Color(0xFF9C27B0), // purple
    Color(0xFF00BCD4), // cyan
    Color(0xFFFF9800), // orange
    Color(0xFF795548), // brown
  ];

  Color _assigneeColor(String name, List<String> allNames) {
    final index = allNames.indexOf(name);
    return _assigneeColors[index % _assigneeColors.length];
  }
}

class _TaskBreakdown {
  final int totalIncomplete;
  final int totalUnassigned;
  final int withDates;
  final int withSkills;

  const _TaskBreakdown({
    required this.totalIncomplete,
    required this.totalUnassigned,
    required this.withDates,
    required this.withSkills,
  });
}

enum _SortMode { score, assignee, date }
