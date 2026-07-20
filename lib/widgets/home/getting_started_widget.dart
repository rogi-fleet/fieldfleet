import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/task.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/app_logger.dart';
import '../../utils/project_terminology.dart';
import '../completion_celebration.dart';

class _ChecklistStep {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final String route;

  const _ChecklistStep({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.route,
  });
}

enum _GettingStartedMode { manager, field }

class GettingStartedWidget extends StatefulWidget {
  final String workspaceId;
  final String userId;
  final bool isFieldMode;
  /// Fired when the widget determines it shouldn't be visible (user dismissed
  /// or all onboarding steps complete). The host can remove the widget from
  /// its dashboard layout so an empty cell isn't left behind.
  final VoidCallback? onAutoHide;

  const GettingStartedWidget({
    super.key,
    required this.workspaceId,
    required this.userId,
    this.isFieldMode = false,
    this.onAutoHide,
  });

  @override
  State<GettingStartedWidget> createState() => _GettingStartedWidgetState();
}

class _GettingStartedWidgetState extends State<GettingStartedWidget>
    with SingleTickerProviderStateMixin {
  static const _accentColor = AppColors.success;

  final Map<String, bool> _completed = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final Set<String> _loadedStreams = {};
  bool _hidden = false;
  bool _allComplete = false;
  bool _initialLoadComplete = false;
  bool _showCongrats = false;
  bool _prefsLoaded = false;
  late AnimationController _progressController;
  late Animation<double> _progressAnimation;
  double _currentProgress = 0;
  late final _GettingStartedMode _mode;
  late final List<_ChecklistStep> _steps;

  String? get _prefsScope => widget.isFieldMode ? 'field' : null;
  bool get _isFieldMode => _mode == _GettingStartedMode.field;

  @override
  void initState() {
    super.initState();
    _mode = widget.isFieldMode
        ? _GettingStartedMode.field
        : _GettingStartedMode.manager;
    _steps = _buildSteps();
    for (final step in _steps) {
      _completed[step.id] = false;
    }
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _progressAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeOut),
    );
    _loadPrefsAndSubscribe();
  }

  Future<void> _loadPrefsAndSubscribe() async {
    final prefs = ServiceLocator.userPreferencesService;
    final dismissed = await prefs.isGettingStartedDismissed(
      widget.workspaceId,
      scope: _prefsScope,
    );
    final completed = await prefs.isGettingStartedCompleted(
      widget.workspaceId,
      scope: _prefsScope,
    );

    if (!mounted) return;

    if (dismissed || completed) {
      setState(() {
        _hidden = true;
        _prefsLoaded = true;
      });
      // Notify the host so the now-empty cell doesn't linger in the layout.
      // Schedule post-frame to avoid mutating layout during a build/init pass.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onAutoHide?.call();
      });
      return;
    }

    setState(() => _prefsLoaded = true);
    _subscribeToStreams();
  }

  void _subscribeToStreams() {
    final wid = widget.workspaceId;

    if (_isFieldMode) {
      _subscribeToFieldStreams(wid);
      return;
    }

    _listenToStep(
      stepId: 'create_project',
      stream: ServiceLocator.projectService.getProjects(wid),
      isComplete: (projects) => projects.isNotEmpty,
    );

    _listenToStep(
      stepId: 'add_customer',
      stream: ServiceLocator.customerService.getCustomers(wid),
      isComplete: (customers) => customers.isNotEmpty,
    );

    _listenToStep(
      stepId: 'invite_member',
      stream: ServiceLocator.workspaceMemberService.getWorkspaceMembers(wid),
      isComplete: (members) => members.length > 1,
    );

    _listenToStep(
      stepId: 'create_task',
      stream: ServiceLocator.taskService.getAllWorkspaceTasks(wid),
      isComplete: (tasks) => tasks.isNotEmpty,
    );

    _listenToStep(
      stepId: 'create_document',
      stream: ServiceLocator.documentService.getDocuments(wid),
      isComplete: (docs) => docs.isNotEmpty,
    );
  }

  void _subscribeToFieldStreams(String workspaceId) {
    _subscriptions.add(
      ServiceLocator.taskService
          .getAllWorkspaceTasks(workspaceId)
          .listen(
            (tasks) {
              final assignedTasks = tasks
                  .where(_isAssignedToCurrentUser)
                  .toList(growable: false);
              _updateStep('review_tasks', assignedTasks.isNotEmpty);
              _updateStep(
                'update_task',
                assignedTasks.any(_hasFieldTaskActivity),
              );
            },
            onError: (error, stackTrace) {
              AppLogger.error(
                'Field getting started task stream failed',
                error: error,
                stackTrace: stackTrace is StackTrace ? stackTrace : null,
                metadata: {'workspaceId': widget.workspaceId},
              );
              _updateStep('review_tasks', false);
              _updateStep('update_task', false);
            },
          ),
    );

    _listenToStep(
      stepId: 'clock_in',
      stream: ServiceLocator.timeEntryService.getTimeEntries(
        widget.userId,
        workspaceId: workspaceId,
      ),
      isComplete: (entries) => entries.isNotEmpty,
    );
  }

  void _listenToStep<T>({
    required String stepId,
    required Stream<List<T>> stream,
    required bool Function(List<T> items) isComplete,
  }) {
    _subscriptions.add(
      stream.listen(
        (items) => _updateStep(stepId, isComplete(items)),
        onError: (error, stackTrace) {
          AppLogger.error(
            'Getting started step stream failed',
            error: error,
            stackTrace: stackTrace is StackTrace ? stackTrace : null,
            metadata: {'stepId': stepId, 'workspaceId': widget.workspaceId},
          );
          _updateStep(stepId, false);
        },
      ),
    );
  }

  void _updateStep(String stepId, bool isComplete) {
    if (!mounted) return;

    final wasAllComplete = _allComplete;

    setState(() {
      _completed[stepId] = isComplete;
      _loadedStreams.add(stepId);
    });

    final completedCount = _completed.values.where((v) => v).length;
    final newProgress = completedCount / _steps.length;
    _animateProgress(newProgress);

    final hasLoadedAllSteps = _loadedStreams.length == _steps.length;
    final nowAllComplete = completedCount == _steps.length;
    _allComplete = nowAllComplete;

    if (!_initialLoadComplete && hasLoadedAllSteps) {
      _initialLoadComplete = true;
      if (nowAllComplete) {
        _onAllComplete(triggeredByUser: false);
      }
      return;
    }

    if (!nowAllComplete || wasAllComplete) return;

    _onAllComplete(triggeredByUser: true);
  }

  void _animateProgress(double target) {
    _progressAnimation = Tween<double>(begin: _currentProgress, end: target)
        .animate(
          CurvedAnimation(parent: _progressController, curve: Curves.easeOut),
        );
    _currentProgress = target;
    _progressController.forward(from: 0);
  }

  void _onAllComplete({required bool triggeredByUser}) {
    if (!mounted) return;
    setState(() => _showCongrats = true);
    if (triggeredByUser) {
      showCelebration(context);
    }
    ServiceLocator.userPreferencesService.markGettingStartedCompleted(
      widget.workspaceId,
      scope: _prefsScope,
    );
  }

  void _dismiss() {
    ServiceLocator.userPreferencesService.dismissGettingStarted(
      widget.workspaceId,
      scope: _prefsScope,
    );
    setState(() => _hidden = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onAutoHide?.call();
    });
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    if (!_prefsLoaded) return const SizedBox.shrink();

    // Wait for all streams to load before showing content
    if (_loadedStreams.length < _steps.length) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Column(
            children: [
              _buildHeader(context),
              const SizedBox(height: AppSpacing.base),
              const SizedBox(
                height: 48,
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_showCongrats) {
      return _buildCongratsCard(context);
    }

    return _buildChecklistCard(context);
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _accentColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: const Icon(Icons.rocket_launch, color: _accentColor, size: 20),
        ),
        const SizedBox(width: AppSpacing.iconGap),
        Expanded(
          child: Text(
            'Getting Started',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          onPressed: _dismiss,
          icon: const Icon(Icons.close, size: 18),
          tooltip: 'Dismiss',
          style: IconButton.styleFrom(
            foregroundColor: AppColors.textTertiary,
            padding: EdgeInsets.zero,
            minimumSize: const Size(32, 32),
          ),
        ),
      ],
    );
  }

  Widget _buildChecklistCard(BuildContext context) {
    final completedCount = _completed.values.where((v) => v).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 42),
              child: Text(
                _isFieldMode
                    ? 'Complete these steps to get ready for field work'
                    : 'Complete these steps to set up your workspace',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            // Progress bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$completedCount of ${_steps.length} complete',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        '${(completedCount / _steps.length * 100).round()}%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _accentColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  AnimatedBuilder(
                    animation: _progressAnimation,
                    builder: (context, _) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                        child: LinearProgressIndicator(
                          value: _progressAnimation.value,
                          minHeight: 6,
                          backgroundColor: _accentColor.withValues(alpha: 0.12),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            _accentColor,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            // Checklist items
            ...List.generate(_steps.length, (index) {
              final step = _steps[index];
              final isComplete = _completed[step.id] ?? false;
              return _buildChecklistItem(context, step, isComplete);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildChecklistItem(
    BuildContext context,
    _ChecklistStep step,
    bool isComplete,
  ) {
    return InkWell(
      onTap: isComplete ? null : () => context.go(step.route),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
        child: Row(
          children: [
            // Animated check circle
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isComplete ? _accentColor : Colors.transparent,
                border: Border.all(
                  color: isComplete
                      ? _accentColor
                      : AppColors.textTertiary.withValues(alpha: 0.5),
                  width: 2,
                ),
              ),
              child: isComplete
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: AppSpacing.sm + 4),
            // Text content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isComplete ? AppColors.textTertiary : null,
                      decoration: isComplete
                          ? TextDecoration.lineThrough
                          : null,
                      decorationColor: AppColors.textTertiary,
                    ),
                  ),
                  if (!isComplete)
                    Text(
                      step.subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
            if (!isComplete)
              Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.textTertiary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCongratsCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _accentColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: _accentColor,
                size: 32,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _isFieldMode ? 'You are ready for the field' : "You're all set!",
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              _isFieldMode
                  ? 'Your field dashboard is ready to go.'
                  : 'Your workspace is ready to go.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.base),
            FilledButton(
              onPressed: _dismiss,
              style: FilledButton.styleFrom(backgroundColor: _accentColor),
              child: const Text('Dismiss'),
            ),
          ],
        ),
      ),
    );
  }

  List<_ChecklistStep> _buildSteps() {
    if (_isFieldMode) {
      return const [
        _ChecklistStep(
          id: 'review_tasks',
          title: 'Review your assigned tasks',
          subtitle: 'See what work has been assigned to you',
          icon: Icons.assignment_outlined,
          route: '/tasks',
        ),
        _ChecklistStep(
          id: 'clock_in',
          title: 'Clock in for your first shift',
          subtitle: 'Start tracking time from the field dashboard',
          icon: Icons.timer_outlined,
          route: '/time-tracking',
        ),
        _ChecklistStep(
          id: 'update_task',
          title: 'Update an assigned task',
          subtitle: 'Mark progress so the team can see field activity',
          icon: Icons.task_alt,
          route: '/tasks',
        ),
      ];
    }

    final singularTerminology = singularProjectTerminology(
      context.read<WorkspaceProvider>().projectTerminology,
    );

    return [
      _ChecklistStep(
        id: 'create_project',
        title: 'Create your first ${singularTerminology.toLowerCase()}',
        subtitle: 'Start organizing your work',
        icon: Icons.folder_open,
        route: '/projects',
      ),
      const _ChecklistStep(
        id: 'add_customer',
        title: 'Add a customer',
        subtitle: 'Track your customers and contacts',
        icon: Icons.people_outline,
        route: '/customers',
      ),
      _ChecklistStep(
        id: 'invite_member',
        title: 'Invite a team member',
        subtitle: 'Collaborate with your team',
        icon: Icons.person_add_outlined,
        route: '/settings/invite',
      ),
      const _ChecklistStep(
        id: 'create_task',
        title: 'Create a task',
        subtitle: 'Break work into actionable items',
        icon: Icons.check_circle_outline,
        route: '/tasks',
      ),
      const _ChecklistStep(
        id: 'create_document',
        title: 'Create a document',
        subtitle: 'Generate estimates, invoices, and more',
        icon: Icons.description_outlined,
        route: '/files',
      ),
    ];
  }

  bool _isAssignedToCurrentUser(Task task) {
    return task.assignedToIds.contains(widget.userId) ||
        task.assignedTo == widget.userId;
  }

  bool _hasFieldTaskActivity(Task task) {
    if (!_isAssignedToCurrentUser(task)) {
      return false;
    }

    if (task.isComplete || task.progress > 0) {
      return true;
    }

    final normalizedStatus = task.status.trim().toLowerCase();
    if (normalizedStatus.isNotEmpty &&
        normalizedStatus != 'not_started' &&
        normalizedStatus != 'todo') {
      return true;
    }

    return task.checklistItems.any((item) => item.isComplete);
  }
}
