import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../theme/theme.dart';
import '../../models/project.dart';
import '../../models/property.dart';
import '../../models/area.dart';
import '../../models/task.dart';
import '../../providers/workspace_provider.dart';
import '../../services/ai_service.dart';
import '../../services/service_locator.dart';
import '../../services/supabase/area_service.dart';
import '../../utils/project_terminology.dart';
import '../../utils/user_facing_error.dart';
import '../ai/ai_wizard_dialog.dart';
import '../ai/ai_wizard_shared.dart';

/// Tab showing tasks linked to this property with summary stats,
/// area grouping, quick-add, and AI task generation.
class PropertyTasksTab extends StatefulWidget {
  final Property property;
  final Project project;

  const PropertyTasksTab({
    super.key,
    required this.property,
    required this.project,
  });

  @override
  State<PropertyTasksTab> createState() => _PropertyTasksTabState();
}

class _PropertyTasksTabState extends State<PropertyTasksTab> {
  final SupabaseAreaService _areaService = SupabaseAreaService();
  StreamSubscription<List<Area>>? _areaSubscription;
  String? _selectedAreaId; // null = all areas
  List<Area> _areas = [];

  // Quick-add
  final _quickAddController = TextEditingController();
  final _quickAddFocusNode = FocusNode();
  bool _showQuickAdd = false;
  String? _quickAddAreaId;
  bool _isQuickAdding = false;

  @override
  void initState() {
    super.initState();
    _loadAreas();
  }

  @override
  void dispose() {
    _areaSubscription?.cancel();
    _quickAddController.dispose();
    _quickAddFocusNode.dispose();
    super.dispose();
  }

  void _loadAreas() {
    _areaSubscription = _areaService
        .getAreas(widget.property.id,
            workspaceId: widget.property.workspaceId)
        .listen((areas) {
      if (mounted) {
        setState(() {
          _areas = areas;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Filter bar with AI button
        _buildFilterBar(context),
        // Tasks list
        Expanded(
          child: StreamBuilder<List<Task>>(
            stream: ServiceLocator.taskService.getTasksByProperty(
              widget.property.id,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    UserFacingError.uiMessage(
                      snapshot.error,
                      action: 'load tasks',
                    ),
                  ),
                );
              }

              var tasks = snapshot.data ?? [];

              // Filter by area if selected
              if (_selectedAreaId != null) {
                tasks = tasks
                    .where((t) => t.areaIds.contains(_selectedAreaId))
                    .toList();
              }

              if (tasks.isEmpty && !_showQuickAdd) {
                return _buildEmptyState(context);
              }

              return _buildTasksBody(context, tasks);
            },
          ),
        ),
      ],
    );
  }

  // ── Filter bar ──────────────────────────────────────────────

  Widget _buildFilterBar(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withAlpha(50)),
        ),
      ),
      child: Row(
        children: [
          // Area filter
          if (_areas.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  borderRadius: AppRadius.cardRadius,
                  value: _selectedAreaId,
                  hint: const Text('All Areas',
                      style: TextStyle(fontSize: 13)),
                  isDense: true,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All Areas'),
                    ),
                    ..._areas.map(
                      (area) => DropdownMenuItem<String?>(
                        value: area.id,
                        child: Text(area.name),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedAreaId = value;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          const Spacer(),
          // AI generate button
          OutlinedButton.icon(
            onPressed: () => _showAiTaskGenerator(context),
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: const Text('Generate'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.secondaryDark,
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          // Add task button
          FilledButton.icon(
            onPressed: () => _toggleQuickAdd(),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Task'),
            style: FilledButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tasks body with stats + grouped list ─────────────────────

  Widget _buildTasksBody(BuildContext context, List<Task> tasks) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats strip
          _buildStatsStrip(context, tasks),
          const SizedBox(height: 16),

          // Quick-add bar
          if (_showQuickAdd) ...[
            _buildQuickAddBar(context),
            const SizedBox(height: 16),
          ],

          // Grouped tasks
          if (_selectedAreaId == null && _areas.isNotEmpty)
            _buildGroupedTasks(context, tasks)
          else
            _buildFlatTaskList(context, tasks),
        ],
      ),
    );
  }

  Widget _buildStatsStrip(BuildContext context, List<Task> tasks) {
    final total = tasks.length;
    final completed = tasks.where((t) => t.isComplete).length;
    final inProgress =
        tasks.where((t) => t.status == 'working_on_it').length;
    final overdue = tasks.where((t) => t.isOverdue()).length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 400;

        return Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            children: [
              _buildStatChip('Total', '$total', AppColors.textPrimary),
              const SizedBox(width: 16),
              _buildStatChip('Done', '$completed', AppColors.success),
              if (!isCompact) ...[
                const SizedBox(width: 16),
                _buildStatChip(
                    'In Progress', '$inProgress', AppColors.info),
              ],
              if (overdue > 0 && !isCompact) ...[
                const SizedBox(width: 16),
                _buildStatChip('Overdue', '$overdue', AppColors.error),
              ],
              const Spacer(),
              if (total > 0)
                SizedBox(
                  width: 80,
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                        child: LinearProgressIndicator(
                          value: completed / total,
                          backgroundColor: AppColors.cardBorder,
                          valueColor: AlwaysStoppedAnimation(
                            completed == total
                                ? AppColors.success
                                : AppColors.info,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${(completed / total * 100).toInt()}%',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatChip(String label, String value, Color color) {
    return Column(
      children: [
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
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  // ── Quick add ───────────────────────────────────────────────

  void _toggleQuickAdd() {
    setState(() {
      _showQuickAdd = !_showQuickAdd;
      if (_showQuickAdd) {
        _quickAddController.clear();
        _quickAddAreaId = _selectedAreaId;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _quickAddFocusNode.requestFocus();
        });
      }
    });
  }

  Widget _buildQuickAddBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _quickAddController,
              focusNode: _quickAddFocusNode,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Task title...',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              ),
              onSubmitted: (_) => _submitQuickAdd(),
            ),
          ),
          if (_areas.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(6),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  borderRadius: AppRadius.cardRadius,
                  value: _quickAddAreaId,
                  hint: const Text('No area',
                      style: TextStyle(fontSize: 11)),
                  isDense: true,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('No area'),
                    ),
                    ..._areas.map(
                      (area) => DropdownMenuItem<String?>(
                        value: area.id,
                        child: Text(area.name),
                      ),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => _quickAddAreaId = v),
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          IconButton(
            onPressed: _isQuickAdding ? null : _submitQuickAdd,
            icon: _isQuickAdding
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child:
                        CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send, size: 18),
            tooltip: 'Create task',
            style: IconButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => setState(() => _showQuickAdd = false),
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Cancel',
          ),
        ],
      ),
    );
  }

  Future<void> _submitQuickAdd() async {
    final title = _quickAddController.text.trim();
    if (title.isEmpty) return;

    setState(() => _isQuickAdding = true);

    try {
      await ServiceLocator.taskService.createTask(
        workspaceId: widget.project.workspaceId,
        projectId: widget.project.id,
        title: title,
        propertyIds: [widget.property.id],
        areaIds: _quickAddAreaId != null ? [_quickAddAreaId!] : [],
      );

      if (mounted) {
        _quickAddController.clear();
        _quickAddFocusNode.requestFocus();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'create task'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isQuickAdding = false);
    }
  }

  // ── Grouped tasks ───────────────────────────────────────────

  Widget _buildGroupedTasks(BuildContext context, List<Task> tasks) {
    // Group tasks by area
    final unlinked = <Task>[];
    final byArea = <String, List<Task>>{};

    for (final task in tasks) {
      if (task.areaIds.isEmpty) {
        unlinked.add(task);
      } else {
        for (final areaId in task.areaIds) {
          byArea.putIfAbsent(areaId, () => []).add(task);
        }
      }
    }

    // Build area name lookup
    final areaNames = <String, String>{};
    for (final area in _areas) {
      areaNames[area.id] = area.name;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Area-grouped sections
        for (final entry in byArea.entries) ...[
          _buildAreaSection(
            context,
            areaNames[entry.key] ?? 'Unknown Area',
            entry.value,
          ),
          const SizedBox(height: 12),
        ],
        // Unlinked tasks
        if (unlinked.isNotEmpty) ...[
          _buildAreaSection(context, 'General', unlinked),
        ],
      ],
    );
  }

  Widget _buildAreaSection(
      BuildContext context, String areaName, List<Task> tasks) {
    final completed = tasks.where((t) => t.isComplete).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header with background
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(6),
            border: Border(
              left: BorderSide(
                color: AppColors.primary.withValues(alpha: 0.4),
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.room_outlined,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                areaName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$completed/${tasks.length}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
        // Task cards
        ...tasks.map((task) => _buildTaskCard(context, task)),
      ],
    );
  }

  Widget _buildFlatTaskList(BuildContext context, List<Task> tasks) {
    return Column(
      children: tasks.map((task) => _buildTaskCard(context, task)).toList(),
    );
  }

  // ── Task card ───────────────────────────────────────────────

  Widget _buildTaskCard(BuildContext context, Task task) {
    // Status color
    Color statusColor;
    switch (task.status) {
      case 'done':
        statusColor = AppColors.success;
        break;
      case 'working_on_it':
        statusColor = AppColors.info;
        break;
      case 'stuck':
        statusColor = AppColors.error;
        break;
      default:
        statusColor = AppColors.textTertiary;
    }

    // Priority icon
    IconData priorityIcon;
    Color priorityColor;
    switch (task.priority) {
      case 'high':
        priorityIcon = Icons.keyboard_arrow_up;
        priorityColor = AppColors.error;
        break;
      case 'low':
        priorityIcon = Icons.keyboard_arrow_down;
        priorityColor = AppColors.info;
        break;
      default:
        priorityIcon = Icons.remove;
        priorityColor = AppColors.textTertiary;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(
          color: task.isComplete
              ? AppColors.success.withValues(alpha: 0.3)
              : AppColors.cardBorder,
        ),
      ),
      child: InkWell(
        onTap: () => _openTaskDetail(context, task),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              // Completion toggle
              InkWell(
                onTap: () => _toggleTaskComplete(task),
                borderRadius: BorderRadius.circular(AppRadius.r12),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: task.isComplete
                          ? AppColors.success
                          : AppColors.textTertiary,
                      width: 2,
                    ),
                    color: task.isComplete
                        ? AppColors.success
                        : Colors.transparent,
                  ),
                  child: task.isComplete
                      ? const Icon(Icons.check,
                          size: 14, color: Colors.white)
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              // Title and metadata
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                        decoration: task.isComplete
                            ? TextDecoration.lineThrough
                            : null,
                        color: task.isComplete
                            ? AppColors.textTertiary
                            : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        // Status badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                          ),
                          child: Text(
                            _formatStatus(task.status),
                            style: TextStyle(
                              fontSize: 10,
                              color: statusColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        // Due date
                        if (task.dueDate != null) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.calendar_today,
                            size: 12,
                            color: task.isOverdue()
                                ? AppColors.error
                                : AppColors.textTertiary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            _formatDate(task.dueDate!),
                            style: TextStyle(
                              fontSize: 10,
                              color: task.isOverdue()
                                  ? AppColors.error
                                  : AppColors.textTertiary,
                              fontWeight: task.isOverdue()
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                        // Checklist progress
                        if (task.hasChecklist) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.checklist,
                              size: 12,
                              color: AppColors.textTertiary),
                          const SizedBox(width: 3),
                          Text(
                            '${task.completedChecklistCount}/${task.totalChecklistCount}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Priority
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: priorityColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child:
                    Icon(priorityIcon, size: 14, color: priorityColor),
              ),
              // Progress bar
              if (task.progress > 0 && !task.isComplete) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 40,
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: task.progress / 100,
                          backgroundColor: AppColors.cardBorder,
                          valueColor:
                              AlwaysStoppedAnimation(statusColor),
                          minHeight: 3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${task.progress}%',
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Empty state ─────────────────────────────────────────────

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.task_alt, size: 56, color: AppColors.textTertiary),
          const SizedBox(height: 16),
          Text(
            _selectedAreaId != null
                ? 'No tasks for this area'
                : 'No tasks linked to this property',
            style: const TextStyle(
                fontSize: 15, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          const Text(
            'Create tasks manually or generate them with AI',
            style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: () => _showAiTaskGenerator(context),
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('Generate with AI'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.secondaryDark,
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => _toggleQuickAdd(),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Task'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── AI Task Generator ───────────────────────────────────────

  void _showAiTaskGenerator(BuildContext context) {
    showAiWizardDialog(
      context,
      title: 'Generate Property Tasks',
      icon: Icons.auto_awesome,
      child: _PropertyTaskAiWizard(
        property: widget.property,
        project: widget.project,
        areas: _areas,
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────

  String _formatStatus(String status) {
    switch (status) {
      case 'not_started':
        return 'Not Started';
      case 'working_on_it':
        return 'In Progress';
      case 'stuck':
        return 'Stuck';
      case 'done':
        return 'Done';
      default:
        return status;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }

  void _openTaskDetail(BuildContext context, Task task) {
    context.push('/projects/${widget.project.id}/tasks/${task.id}');
  }

  void _toggleTaskComplete(Task task) async {
    try {
      await ServiceLocator.taskService.toggleTaskCompletion(
        task.id,
        task.isComplete,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'updating task'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// AI Property Task Generator Wizard
// ═══════════════════════════════════════════════════════════════

class _PropertyTaskAiWizard extends StatefulWidget {
  final Property property;
  final Project project;
  final List<Area> areas;

  const _PropertyTaskAiWizard({
    required this.property,
    required this.project,
    required this.areas,
  });

  @override
  State<_PropertyTaskAiWizard> createState() => _PropertyTaskAiWizardState();
}

class _PropertyTaskAiWizardState extends State<_PropertyTaskAiWizard> {
  final _pageController = PageController();
  final _instructionsController = TextEditingController();
  int _currentStep = 0;

  // Generation state
  bool _isGenerating = false;
  bool _isCancelled = false;
  List<AiGeneratedTask> _generatedTasks = [];
  String _currentStatus = '';
  String _streamedText = '';
  String _pendingStreamedText = '';
  Timer? _streamUpdateTimer;

  // Import state
  bool _isImporting = false;

  List<AiStepConfig> _steps(String singular) => [
    AiStepConfig(
      number: 1,
      title: 'Configure',
      subtitle: 'Add instructions for task generation',
      icon: Icons.tune,
    ),
    AiStepConfig(
      number: 2,
      title: 'Review Tasks',
      subtitle: 'AI generates tasks for this property',
      icon: Icons.auto_awesome,
    ),
    AiStepConfig(
      number: 3,
      title: 'Import',
      subtitle: 'Add tasks to your ${singular.toLowerCase()}',
      icon: Icons.task_alt,
    ),
  ];

  @override
  void dispose() {
    _streamUpdateTimer?.cancel();
    _pageController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  void _goToStep(int step) {
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    setState(() => _currentStep = step);
  }

  void _handleStreamUpdate(
      String providerName, String delta, String accumulated) {
    if (!mounted || _isCancelled) return;
    _pendingStreamedText = accumulated;
    if (_streamUpdateTimer != null) return;
    _streamUpdateTimer = Timer(const Duration(milliseconds: 120), () {
      _streamUpdateTimer = null;
      if (!mounted || _isCancelled) return;
      setState(() => _streamedText = _pendingStreamedText);
    });
  }

  @override
  Widget build(BuildContext context) {
    final singular = singularProjectTerminology(context.watch<WorkspaceProvider>().projectTerminology);
    final steps = _steps(singular);
    return Column(
      children: [
        // Step header
        AiWizardHeader(
          currentStep: _currentStep,
          totalSteps: steps.length,
          steps: steps,
        ),
        // Pages
        Expanded(
          child: PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildConfigureStep(),
              _buildReviewStep(),
              _buildImportStep(),
            ],
          ),
        ),
        // Footer
        _buildFooter(context),
      ],
    );
  }

  // ── Step 1: Configure ───────────────────────────────────────

  Widget _buildConfigureStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Property context
          Container(
            padding: const EdgeInsets.all(AppSpacing.base),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.home_work,
                        size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      widget.property.displayLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: 2),
                      decoration: BoxDecoration(
                        color: widget.property.status.color
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: Text(
                        widget.property.status.displayName,
                        style: TextStyle(
                          fontSize: 11,
                          color: widget.property.status.color,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                if (widget.areas.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: widget.areas.map((area) {
                      return Chip(
                        label: Text(area.name),
                        avatar: Icon(
                          area.isAffected
                              ? Icons.warning_amber
                              : Icons.room,
                          size: 14,
                          color: area.isAffected
                              ? AppColors.warning
                              : AppColors.textSecondary,
                        ),
                        visualDensity: VisualDensity.compact,
                        labelStyle: const TextStyle(fontSize: 11),
                        backgroundColor: area.isAffected
                            ? AppColors.warningLight
                            : null,
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Instructions
          const Text(
            'Additional instructions (optional)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _instructionsController,
            maxLines: 4,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              hintText:
                  'e.g., Focus on mitigation tasks, include moisture monitoring...',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.all(AppSpacing.md),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'The AI will generate tasks based on the property status, '
            'affected areas, and any instructions you provide.',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 2: Review ──────────────────────────────────────────

  Widget _buildReviewStep() {
    if (_isGenerating) {
      return _buildGeneratingState();
    }

    if (_generatedTasks.isEmpty) {
      return const Center(
        child: Text('No tasks generated',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.base),
      itemCount: _generatedTasks.length,
      itemBuilder: (context, index) {
        final task = _generatedTasks[index];
        final isChild = task.parentTempId != null;

        return Padding(
          padding: EdgeInsets.only(
            left: isChild ? 24 : 0,
            bottom: 6,
          ),
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              side: BorderSide(
                color: task.isSelected
                    ? AppColors.primary.withValues(alpha: 0.3)
                    : AppColors.cardBorder,
              ),
            ),
            child: InkWell(
              onTap: () {
                setState(() => task.isSelected = !task.isSelected);
              },
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    // Selection checkbox
                    Checkbox(
                      value: task.isSelected,
                      onChanged: (v) {
                        setState(
                            () => task.isSelected = v ?? true);
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 8),
                    // Task info
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (task.isSummary)
                                const Padding(
                                  padding:
                                      EdgeInsets.only(right: 6),
                                  child: Icon(Icons.folder_outlined,
                                      size: 14,
                                      color: AppColors.primary),
                                ),
                              Expanded(
                                child: Text(
                                  task.title,
                                  style: TextStyle(
                                    fontWeight: task.isSummary
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (task.description != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              task.description!,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (task.checklistItems.isNotEmpty ||
                              task.areaName != null ||
                              task.estimatedDuration != null) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                if (task.areaName != null)
                                  _buildMiniTag(
                                    Icons.room_outlined,
                                    task.areaName!,
                                    AppColors.info,
                                  ),
                                if (task.estimatedDuration != null)
                                  _buildMiniTag(
                                    Icons.schedule,
                                    '${task.estimatedDuration!.toInt()}h',
                                    AppColors.textSecondary,
                                  ),
                                if (task.checklistItems.isNotEmpty)
                                  _buildMiniTag(
                                    Icons.checklist,
                                    '${task.checklistItems.length} items',
                                    AppColors.textSecondary,
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Priority badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _priorityColor(task.priority)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: Text(
                        task.priority,
                        style: TextStyle(
                          fontSize: 10,
                          color: _priorityColor(task.priority),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMiniTag(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: color),
        ),
      ],
    );
  }

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'high':
        return AppColors.error;
      case 'low':
        return AppColors.info;
      default:
        return AppColors.textSecondary;
    }
  }

  Widget _buildGeneratingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(),
          ),
          const SizedBox(height: 20),
          Text(
            _currentStatus.isNotEmpty
                ? _currentStatus
                : 'Generating tasks...',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Analyzing ${widget.property.displayLabel}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          if (_streamedText.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              constraints: const BoxConstraints(maxHeight: 150),
              child: SingleChildScrollView(
                child: Text(
                  _streamedText,
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Step 3: Import ──────────────────────────────────────────

  Widget _buildImportStep() {
    final selectedCount =
        _generatedTasks.where((t) => t.isSelected).length;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_isImporting) ...[
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            const Text('Creating tasks...',
                style: TextStyle(fontSize: 14)),
          ] else ...[
            Icon(Icons.task_alt, size: 56, color: AppColors.success),
            const SizedBox(height: 16),
            Text(
              '$selectedCount tasks ready to import',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tasks will be linked to ${widget.property.displayLabel}',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Footer ──────────────────────────────────────────────────

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Back
          if (_currentStep > 0 && !_isGenerating && !_isImporting)
            TextButton(
              onPressed: () => _goToStep(_currentStep - 1),
              child: const Text('Back'),
            )
          else
            const SizedBox(),
          // Next / Generate / Import
          Row(
            children: [
              if (_isGenerating)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isCancelled = true;
                      _isGenerating = false;
                    });
                    _goToStep(0);
                  },
                  child: const Text('Cancel'),
                ),
              if (!_isGenerating && !_isImporting) ...[
                if (_currentStep == 0)
                  FilledButton.icon(
                    onPressed: _generateTasks,
                    icon: const Icon(Icons.auto_awesome, size: 16),
                    label: const Text('Generate Tasks'),
                    style: FilledButton.styleFrom(
                      foregroundColor: AppColors.secondaryDark,
                      backgroundColor: AppColors.secondarySurface,
                    ),
                  ),
                if (_currentStep == 1)
                  FilledButton(
                    onPressed: _generatedTasks
                            .any((t) => t.isSelected)
                        ? () => _goToStep(2)
                        : null,
                    child: const Text('Continue'),
                  ),
                if (_currentStep == 2)
                  FilledButton.icon(
                    onPressed: _importTasks,
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('Import Tasks'),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── Generation logic ────────────────────────────────────────

  Future<void> _generateTasks() async {
    setState(() {
      _isGenerating = true;
      _isCancelled = false;
      _currentStatus = 'Initializing...';
      _streamedText = '';
      _pendingStreamedText = '';
    });

    _goToStep(1);

    try {
      final aiService = AiService();
      final areaInputs = widget.areas
          .map((a) => PropertyAreaInput(
                name: a.name,
                status: a.status.name,
                isAffected: a.isAffected,
                trend: a.trend,
              ))
          .toList();

      AiProjectContext? projectContext;
      final p = widget.project;
      projectContext = AiProjectContext(
        projectName: p.name,
        location: p.address,
        jobType: p.jobType?.displayName,
      );

      final tasks = await aiService.generatePropertyTasks(
        propertyName: widget.property.displayLabel,
        propertyStatus: widget.property.status.displayName,
        areas: areaInputs,
        additionalInstructions:
            _instructionsController.text.isNotEmpty
                ? _instructionsController.text
                : null,
        projectContext: projectContext,
        persona:
            context.read<WorkspaceProvider>().aiPersonaContext,
        onProgress: (providerName, status) {
          if (mounted && !_isCancelled) {
            setState(() {
              // _currentProvider tracked for debugging
              _currentStatus = status;
            });
          }
        },
        onStream: _handleStreamUpdate,
      );

      if (_isCancelled) return;

      setState(() {
        _generatedTasks = tasks;
        _isGenerating = false;
        // generation complete
      });
    } catch (e) {
      if (_isCancelled) return;

      // Fallback: generate basic tasks
      _generateFallbackTasks();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Using basic task generation (AI unavailable)'),
            backgroundColor: AppColors.warning,
          ),
        );
        setState(() {
          _isGenerating = false;
          // generation complete
        });
      }
    }
  }

  void _generateFallbackTasks() {
    final tasks = <AiGeneratedTask>[];
    int idx = 0;

    // Generate based on property status
    final status = widget.property.status.displayName.toLowerCase();

    if (status == 'pending' || status == 'mitigation') {
      tasks.add(AiGeneratedTask(
        tempId: 'task_${idx++}',
        title: 'Initial Inspection & Documentation',
        taskType: 'standard',
        priority: 'high',
        estimatedDuration: 4,
        checklistItems: [
          'Document damage with photos',
          'Measure affected areas',
          'Identify moisture source',
          'Note safety concerns',
        ],
      ));
      tasks.add(AiGeneratedTask(
        tempId: 'task_${idx++}',
        title: 'Set Up Containment',
        taskType: 'standard',
        priority: 'high',
        estimatedDuration: 4,
        predecessorTempIds: ['task_0'],
        checklistItems: [
          'Install poly sheeting',
          'Set up negative air',
          'Mark containment boundaries',
        ],
      ));
    }

    // Area-specific tasks
    for (final area in widget.areas.where((a) => a.isAffected)) {
      tasks.add(AiGeneratedTask(
        tempId: 'task_${idx++}',
        title: 'Remediate ${area.name}',
        taskType: 'standard',
        priority: 'medium',
        estimatedDuration: 8,
        areaName: area.name,
        checklistItems: [
          'Remove damaged materials',
          'Clean and treat surfaces',
          'Place drying equipment',
          'Document progress',
        ],
      ));
    }

    if (status == 'monitoring' || status == 'mitigation') {
      tasks.add(AiGeneratedTask(
        tempId: 'task_${idx++}',
        title: 'Moisture Monitoring',
        taskType: 'standard',
        priority: 'medium',
        estimatedDuration: 2,
        checklistItems: [
          'Take moisture readings',
          'Log readings in system',
          'Adjust equipment as needed',
          'Check for secondary damage',
        ],
      ));
    }

    _generatedTasks = tasks;
  }

  // ── Import logic ────────────────────────────────────────────

  Future<void> _importTasks() async {
    final selectedTasks =
        _generatedTasks.where((t) => t.isSelected).toList();
    if (selectedTasks.isEmpty) return;

    setState(() => _isImporting = true);

    try {
      final taskService = ServiceLocator.taskService;
      final tempIdToRealId = <String, String>{};

      // Build area name -> id lookup
      final areaIdByName = <String, String>{};
      for (final area in widget.areas) {
        areaIdByName[area.name.toLowerCase()] = area.id;
      }

      // Sort: summary first
      final sorted = List<AiGeneratedTask>.from(selectedTasks)
        ..sort((a, b) {
          if (a.isSummary && !b.isSummary) return -1;
          if (!a.isSummary && b.isSummary) return 1;
          return 0;
        });

      for (final task in sorted) {
        String? parentId;
        if (task.parentTempId != null) {
          parentId = tempIdToRealId[task.parentTempId];
        }

        // Resolve area IDs from area name
        final areaIds = <String>[];
        if (task.areaName != null) {
          final resolved =
              areaIdByName[task.areaName!.toLowerCase()];
          if (resolved != null) areaIds.add(resolved);
        }

        final created = await taskService.createTask(
          workspaceId: widget.project.workspaceId,
          projectId: widget.project.id,
          title: task.title,
          description: task.description,
          taskType: task.isSummary
              ? TaskType.summary
              : TaskType.standard,
          parentId: parentId,
          estimatedDuration: task.estimatedDuration,
          priority: task.priority,
          propertyIds: [widget.property.id],
          areaIds: areaIds,
        );

        tempIdToRealId[task.tempId] = created.id;

        // Add checklist items
        for (final item in task.checklistItems) {
          await taskService.addChecklistItem(created.id, item);
        }
      }

      // Update predecessors
      for (final task in sorted) {
        if (task.predecessorTempIds.isNotEmpty) {
          final realIds = task.predecessorTempIds
              .where((id) => tempIdToRealId.containsKey(id))
              .map((id) => tempIdToRealId[id]!)
              .toList();
          if (realIds.isNotEmpty) {
            final realId = tempIdToRealId[task.tempId];
            if (realId != null) {
              await taskService.updateTask(
                taskId: realId,
                predecessorIds: realIds,
              );
            }
          }
        }
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Created ${selectedTasks.length} tasks for ${widget.property.displayLabel}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'import tasks'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
        setState(() => _isImporting = false);
      }
    }
  }
}
