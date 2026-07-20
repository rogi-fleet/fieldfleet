import 'dart:convert';
import 'package:taskfleet_ops/utils/user_facing_error.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../services/ai_service.dart';
import '../../utils/workspace_gated_loader.dart';
import '../../services/service_locator.dart';
import '../../services/supabase/asset_service.dart';
import '../../models/project.dart';
import '../../models/task.dart';
import '../../models/asset.dart';
import '../../models/user.dart';
import '../../models/user_role.dart';
import '../../widgets/file_upload_widget.dart';
import '../../widgets/file_gallery_widget.dart';
import '../../widgets/asset_multi_selector.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/task_comments_widget.dart';
import '../../widgets/skill_multi_selector.dart';
import '../../widgets/checklist_widget.dart';
import '../../widgets/field_forms/task_required_forms_widget.dart';
import '../../widgets/property_area_selector.dart';
import '../../widgets/budget_item_multi_selector.dart';
import '../../models/budget_task_link.dart';
import '../../services/task_scheduler_service.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

class TaskFormScreen extends StatelessWidget {
  final String projectId;
  final String? taskId;

  const TaskFormScreen({super.key, required this.projectId, this.taskId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(taskId == null ? 'New Task' : 'Edit Task'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/projects/$projectId');
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/projects/$projectId');
              }
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
      body: TaskFormContent(
        projectId: projectId,
        taskId: taskId,
        isPopup: false,
      ),
    );
  }
}

/// The actual form content, extracted for reuse in popups and screens
class TaskFormContent extends StatefulWidget {
  final String projectId;
  final String? taskId;
  final bool isPopup;
  final DateTime? initialStartDate;
  final List<String>? initialAssignedUserIds;
  final int? initialTabIndex;
  final ValueNotifier<bool>? dirtyNotifier;

  const TaskFormContent({
    super.key,
    required this.projectId,
    this.taskId,
    this.isPopup = false,
    this.initialStartDate,
    this.initialAssignedUserIds,
    this.initialTabIndex,
    this.dirtyNotifier,
  });

  @override
  State<TaskFormContent> createState() => _TaskFormContentState();
}

class _TaskFormContentState extends State<TaskFormContent>
    with WorkspaceGatedLoader {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _durationController = TextEditingController();
  final dynamic _userService = ServiceLocator.userService;
  final dynamic _workspaceMemberService = ServiceLocator.workspaceMemberService;
  DateTime? _selectedDueDate;
  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;
  bool _isLoading = false;
  Project? _project;
  Task? _existingTask;
  List<String> _selectedAssetIds = [];
  List<String> _selectedAssignedUserIds = [];
  List<AppUser> _workspaceUsers = [];
  bool _isLoadingUsers = true;
  bool _isAutoAssigning = false;

  // New fields for parent, progress, status, priority
  String? _selectedParentId;
  int _progress = 0;
  String _status = 'not_started';
  String _priority = 'medium';
  TaskType _taskType = TaskType.standard;
  Color _groupColor = const Color(0xFF2196F3); // matches Task default
  // Resolved once for the project so new tasks can link to the project's
  List<Task> _projectTasks = [];
  bool _isLoadingTasks = true;
  List<String> _selectedPredecessorIds = []; // Task dependencies
  List<String> _selectedRequiredSkillIds = []; // Required skills for this task
  List<String> _selectedPropertyIds =
      []; // Linked properties (for restoration workflows)
  List<String> _selectedAreaIds = []; // Linked areas within properties
  List<String> _selectedBudgetItemIds =
      []; // Linked budget items (for cost tracking)
  int _activeTabIndex = 0;

  // Recurrence fields
  bool _isRecurring = false;
  String _recurrenceFrequency = 'weekly';
  DateTime? _recurrenceEndDate;
  int? _recurrenceMaxOccurrences;

  // AI inline action fields
  final AiService _aiService = AiService();
  bool _isImprovingDescription = false;
  bool _isGeneratingChecklist = false;
  bool _isEstimatingDuration = false;
  List<String> _pendingChecklistTitles = [];

  AiPersonaContext? get _persona =>
      context.read<WorkspaceProvider>().aiPersonaContext;

  bool _initialLoadComplete = false;

  void _markDirty() {
    if (_initialLoadComplete) {
      widget.dirtyNotifier?.value = true;
    }
  }

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_markDirty);
    _descriptionController.addListener(_markDirty);
    if (widget.taskId != null && widget.initialTabIndex != null) {
      _activeTabIndex = widget.initialTabIndex!.clamp(0, 4).toInt();
    }
    // Set initial start date if provided (e.g., from calendar day click)
    if (widget.initialStartDate != null && widget.taskId == null) {
      _selectedStartDate = widget.initialStartDate;
    }
    if (widget.taskId == null &&
        widget.initialAssignedUserIds != null &&
        widget.initialAssignedUserIds!.isNotEmpty) {
      _selectedAssignedUserIds = List<String>.from(
        widget.initialAssignedUserIds!,
      );
    }
    if (widget.taskId != null) {
      _loadTask().then((_) => _initialLoadComplete = true);
    } else {
      _initialLoadComplete = true;
    }
  }

  @override
  void onWorkspaceReady(String workspaceId) {
    // Workspace users / project tasks / project loaded once the workspace
    // hydrates via WorkspaceGatedLoader — avoids cold-load empty pickers.
    _loadWorkspaceUsers(workspaceId);
    _loadProjectTasks(workspaceId);
    _loadProject(workspaceId);
  }

  Future<void> _loadProjectTasks(String workspaceId) async {
    try {
      final tasks = await ServiceLocator.taskService
          .getTasks(widget.projectId, workspaceId: workspaceId)
          .first;
      if (mounted) {
        setState(() {
          _projectTasks = tasks;
          _isLoadingTasks = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingTasks = false;
        });
      }
    }
  }

  Future<void> _loadProject(String workspaceId) async {
    try {
      final project = await ServiceLocator.projectService.getProject(
        widget.projectId,
        workspaceId: workspaceId,
      );
      if (mounted) {
        setState(() {
          _project = project;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadWorkspaceUsers(String workspaceId) async {
    try {
      final members = await _workspaceMemberService
          .getWorkspaceMembers(workspaceId)
          .first;
      final List<AppUser> users = [];
      for (final member in members) {
        final user = await _userService.getUserById(member.userId);
        if (user != null) {
          users.add(user);
        }
      }
      if (mounted) {
        setState(() {
          _workspaceUsers = users;
          _isLoadingUsers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingUsers = false;
        });
      }
    }
  }

  Future<void> _loadTask() async {
    setState(() => _isLoading = true);
    debugPrint('TaskFormScreen: Loading task ${widget.taskId}');
    try {
      final task = await ServiceLocator.taskService.getTask(widget.taskId!);
      debugPrint(
        'TaskFormScreen: Task loaded: ${task?.title}, status: ${task?.status}, priority: ${task?.priority}',
      );
      if (task != null) {
        List<String>? linkedBudgetItemIds;
        // Also load linked budget items from junction table for Supabase.
        try {
          final linkIds = await ServiceLocator.budgetTaskLinkService
              .getBudgetItemIdsForTask(task.id);
          if (linkIds.isNotEmpty) {
            linkedBudgetItemIds = linkIds;
          }
        } catch (_) {}

        setState(() {
          _existingTask = task;
          _titleController.text = task.title;
          _descriptionController.text = task.description ?? '';
          _selectedDueDate = task.dueDate;
          _selectedStartDate = task.startDate;
          _selectedEndDate = task.endDate;
          _durationController.text = task.estimatedDuration?.toString() ?? '';
          _selectedAssetIds = List.from(task.requiredAssetIds);
          _selectedAssignedUserIds = List.from(task.assignedToIds);
          _selectedParentId = task.parentId;
          _progress = task.progress;
          _status = _normalizeStatus(task.status);
          _priority = _normalizePriority(task.priority);
          _taskType = task.taskType;
          _groupColor = task.groupColor;
          _selectedPredecessorIds = List.from(task.predecessorIds);
          _selectedRequiredSkillIds = List.from(task.requiredSkillIds);
          _selectedPropertyIds = List.from(task.propertyIds);
          _selectedAreaIds = List.from(task.areaIds);
          _selectedBudgetItemIds = List.from(task.budgetItemIds);
          if (linkedBudgetItemIds != null) {
            _selectedBudgetItemIds = linkedBudgetItemIds;
          }
          _isRecurring = task.isRecurring;
          if (task.recurrenceRule != null) {
            _recurrenceFrequency =
                task.recurrenceRule!['frequency'] as String? ?? 'weekly';
            _recurrenceEndDate = task.recurrenceRule!['endDate'] != null
                ? DateTime.tryParse(task.recurrenceRule!['endDate'] as String)
                : null;
            _recurrenceMaxOccurrences =
                task.recurrenceRule!['maxOccurrences'] as int?;
          }
        });
        debugPrint(
          'TaskFormScreen: State updated, _status=$_status, _priority=$_priority',
        );
      }
    } catch (e) {
      debugPrint('TaskFormScreen: Error loading task: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.uiMessage(e, action: 'loading task')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Normalize status value to match dropdown options
  String _normalizeStatus(String status) {
    switch (status.toLowerCase().replaceAll(' ', '_')) {
      case 'not_started':
      case 'notstarted':
        return 'not_started';
      case 'working_on_it':
      case 'workingonit':
      case 'in_progress':
        return 'working_on_it';
      case 'stuck':
      case 'blocked':
        return 'stuck';
      case 'done':
      case 'complete':
      case 'completed':
        return 'done';
      default:
        return 'not_started';
    }
  }

  /// Normalize priority value to match dropdown options
  String _normalizePriority(String priority) {
    switch (priority.toLowerCase()) {
      case 'low':
        return 'low';
      case 'medium':
      case 'normal':
        return 'medium';
      case 'high':
      case 'critical':
        return 'high';
      default:
        return 'medium';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _selectStartDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedStartDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );

    if (picked != null) {
      setState(() {
        _selectedStartDate = picked;
        // Auto-calculate due date if duration is set
        _autoCalculateDueDate();
      });
    }
  }

  Future<void> _selectDueDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );

    if (picked != null) {
      setState(() {
        _selectedDueDate = picked;
      });
    }
  }

  Future<void> _selectEndDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedEndDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );

    if (picked != null) {
      setState(() {
        _selectedEndDate = picked;
      });
    }
  }

  void _autoCalculateDueDate() {
    if (_selectedStartDate != null && _durationController.text.isNotEmpty) {
      final duration = double.tryParse(_durationController.text);
      if (duration != null && duration > 0) {
        final days = duration / 8.0; // 8 hours = 1 work day
        setState(() {
          _selectedDueDate = _selectedStartDate!.add(
            Duration(hours: (days * 24).round()),
          );
        });
      }
    }
  }

  String? _validateDependencies() {
    final currentTaskId = widget.taskId;
    if (currentTaskId != null &&
        _selectedPredecessorIds.contains(currentTaskId)) {
      return 'A task cannot depend on itself.';
    }

    if (currentTaskId != null) {
      for (final predecessorId in _selectedPredecessorIds) {
        for (final task in _projectTasks) {
          if (task.id == predecessorId &&
              task.predecessorIds.contains(currentTaskId)) {
            return 'Circular dependency with "${task.title}".';
          }
        }
      }
    }

    return null;
  }

  Future<void> _handleSave() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _activeTabIndex = 0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a task title'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final durationText = _durationController.text.trim();
    if (durationText.isNotEmpty) {
      final parsedDuration = double.tryParse(durationText);
      if (parsedDuration == null || parsedDuration <= 0) {
        setState(() => _activeTabIndex = 1);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Duration must be a positive number'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
    }

    if (_isRecurring &&
        _recurrenceMaxOccurrences != null &&
        _recurrenceMaxOccurrences! <= 0) {
      setState(() => _activeTabIndex = 1);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Max occurrences must be a positive number'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final dependencyError = _validateDependencies();
    if (dependencyError != null) {
      setState(() => _activeTabIndex = 1);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(dependencyError),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authProvider = context.read<AuthProvider>();
      final workspaceId = authProvider.appUser?.currentWorkspaceId;

      if (workspaceId == null) {
        throw Exception('No workspace found');
      }

      // Parse estimated duration
      final double? duration = _durationController.text.trim().isNotEmpty
          ? double.tryParse(_durationController.text.trim())
          : null;

      // Build recurrence rule if recurring
      Map<String, dynamic>? recurrenceRule;
      if (_isRecurring) {
        recurrenceRule = {
          'frequency': _recurrenceFrequency,
          if (_recurrenceEndDate != null)
            'endDate': _recurrenceEndDate!.toIso8601String(),
          if (_recurrenceMaxOccurrences != null)
            'maxOccurrences': _recurrenceMaxOccurrences,
          'occurrenceCount': 0,
        };
      }

      String savedTaskId;
      if (widget.taskId == null) {
        final createdTask = await ServiceLocator.taskService.createTask(
          workspaceId: workspaceId,
          projectId: widget.projectId,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim().isNotEmpty
              ? _descriptionController.text.trim()
              : null,
          dueDate: _selectedDueDate,
          startDate: _selectedStartDate,
          endDate: _selectedEndDate,
          estimatedDuration: duration,
          assignedToIds: _selectedAssignedUserIds,
          requiredAssetIds: _selectedAssetIds,
          requiredSkillIds: _selectedRequiredSkillIds,
          propertyIds: _selectedPropertyIds,
          areaIds: _selectedAreaIds,
          status: _status,
          priority: _priority,
          taskType: _taskType,
          isRecurring: _isRecurring,
          recurrenceRule: recurrenceRule,
        );
        savedTaskId = createdTask.id;
        // createTask doesn't take groupColor — apply via update once the row
        // exists.
        if (_groupColor.value != const Color(0xFF2196F3).value) {
          await ServiceLocator.taskService.updateTask(
            taskId: savedTaskId,
            groupColor: _groupColor,
          );
        }
      } else {
        // Update existing task
        await ServiceLocator.taskService.updateTask(
          taskId: widget.taskId!,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim().isNotEmpty
              ? _descriptionController.text.trim()
              : null,
          dueDate: _selectedDueDate,
          startDate: _selectedStartDate,
          endDate: _selectedEndDate,
          clearEndDate: _selectedEndDate == null && _existingTask?.endDate != null,
          estimatedDuration: duration,
          assignedToIds: _selectedAssignedUserIds,
          requiredAssetIds: _selectedAssetIds,
          requiredSkillIds: _selectedRequiredSkillIds,
          parentId: _selectedParentId,
          clearParentId:
              _selectedParentId == null && _existingTask?.parentId != null,
          progress: _progress,
          status: _status,
          priority: _priority,
          predecessorIds: _selectedPredecessorIds,
          propertyIds: _selectedPropertyIds,
          areaIds: _selectedAreaIds,
          isRecurring: _isRecurring,
          recurrenceRule: recurrenceRule,
          clearRecurrence:
              !_isRecurring && (_existingTask?.isRecurring ?? false),
          groupColor: _groupColor,
        );
        // updateTask doesn't carry taskType (it has its own RPC). Only call
        // when the user actually changed it to avoid an extra round-trip.
        if (_existingTask != null && _existingTask!.taskType != _taskType) {
          await ServiceLocator.taskService
              .updateTaskType(widget.taskId!, _taskType);
        }
        savedTaskId = widget.taskId!;
      }

      // Save any AI-generated pending checklist items (new task only)
      if (widget.taskId == null && _pendingChecklistTitles.isNotEmpty) {
        try {
          for (final title in _pendingChecklistTitles) {
            await ServiceLocator.taskService.addChecklistItem(
              savedTaskId,
              title,
            );
          }
        } catch (_) {
          // Non-critical
        }
      }

      // Save budget item links via junction table
      if (_selectedBudgetItemIds.isNotEmpty || widget.taskId != null) {
        try {
          final now = DateTime.now();
          final links = _selectedBudgetItemIds
              .map(
                (budgetItemId) => BudgetTaskLink(
                  taskId: savedTaskId,
                  budgetItemId: budgetItemId,
                  workspaceId: workspaceId,
                  createdAt: now,
                ),
              )
              .toList();
          await ServiceLocator.budgetTaskLinkService.setTaskBudgetItems(
            savedTaskId,
            links,
          );
        } catch (_) {
          // Non-critical: task was saved successfully
        }
      }

      if (mounted) {
        if (widget.isPopup) {
          Navigator.of(context).pop();
        } else {
          context.go('/projects/${widget.projectId}');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.uiMessage(e, action: 'saving task')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }

  // Helper method to build modern input decoration
  InputDecoration _buildInputDecoration({
    required String label,
    required IconData icon,
    String? helperText,
    bool isRequired = false,
    bool showOptionalSuffix = true,
  }) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return InputDecoration(
      hintText: isRequired || !showOptionalSuffix ? label : '$label (optional)',
      helperText: helperText,
      helperStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45), fontSize: 12),
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
      prefixIcon: Container(
        margin: const EdgeInsets.only(left: 12, right: 8),
        child: Icon(icon, color: primaryColor.withOpacity(0.7), size: 22),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 48),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.r12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.r12),
        borderSide: BorderSide(color: AppColors.cardBorder, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.r12),
        borderSide: BorderSide(color: primaryColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.r12),
        borderSide: BorderSide(color: theme.colorScheme.error, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.r12),
        borderSide: BorderSide(color: theme.colorScheme.error, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.base),
    );
  }

  // Helper method to build modern date picker container
  Widget _buildDatePicker({
    required String label,
    required IconData icon,
    required DateTime? selectedDate,
    required VoidCallback onTap,
    required VoidCallback onClear,
  }) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final hasDate = selectedDate != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.r12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.base),
            decoration: BoxDecoration(
              color: hasDate
                  ? primaryColor.withOpacity(0.08)
                  : theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(AppRadius.r12),
              border: Border.all(
                color: hasDate
                    ? primaryColor.withOpacity(0.3)
                    : AppColors.cardBorder,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: hasDate
                        ? primaryColor.withOpacity(0.15)
                        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: hasDate ? primaryColor : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasDate ? _formatDate(selectedDate) : 'Not set',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: hasDate
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: hasDate
                              ? theme.colorScheme.onSurface
                              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasDate)
                  IconButton(
                    onPressed: onClear,
                    icon: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                    ),
                    tooltip: 'Clear date',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  )
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── AI inline actions ───────────────────────────────────────────────────

  Widget _buildAiActionBar() {
    final anyLoading =
        _isImprovingDescription ||
        _isGeneratingChecklist ||
        _isEstimatingDuration;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 8,
        children: [
          _AiActionChip(
            icon: Icons.auto_awesome,
            label: 'Improve',
            loading: _isImprovingDescription,
            disabled: anyLoading,
            onTap: _improveDescription,
          ),
          _AiActionChip(
            icon: Icons.auto_awesome,
            label:
                'Checklist${_pendingChecklistTitles.isNotEmpty ? ' (${_pendingChecklistTitles.length})' : ''}',
            loading: _isGeneratingChecklist,
            disabled: anyLoading,
            onTap: _generateChecklist,
          ),
          _AiActionChip(
            icon: Icons.schedule,
            label: 'Estimate',
            loading: _isEstimatingDuration,
            disabled: anyLoading,
            onTap: _estimateDuration,
          ),
        ],
      ),
    );
  }

  Future<void> _improveDescription() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    setState(() => _isImprovingDescription = true);
    try {
      final desc = _descriptionController.text.trim();
      final prompt =
          'Rewrite this task description to be clearer and more actionable for a construction crew. '
          'Task: "$title". Description: "${desc.isNotEmpty ? desc : '(none)'}". '
          'Return only the improved description text, no extra commentary.';
      final result = await _aiService.askQuestion(
        question: prompt,
        persona: _persona,
      );
      if (mounted) {
        setState(() => _descriptionController.text = result.trim());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('AI suggestions are unavailable right now.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isImprovingDescription = false);
    }
  }

  Future<void> _generateChecklist() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    setState(() => _isGeneratingChecklist = true);
    try {
      final desc = _descriptionController.text.trim();
      final prompt =
          'Generate 4-8 practical checklist steps for this construction task: "$title". '
          '${desc.isNotEmpty ? 'Description: "$desc". ' : ''}'
          'Return a JSON array of strings only, e.g. ["Step 1", "Step 2"].';
      final result = await _aiService.askQuestion(
        question: prompt,
        persona: _persona,
      );
      final jsonStr = RegExp(
        r'\[.*\]',
        dotAll: true,
      ).firstMatch(result)?.group(0);
      if (jsonStr == null) return;
      final steps = (jsonDecode(jsonStr) as List).cast<String>();
      if (!mounted) return;
      if (widget.taskId != null && _existingTask != null) {
        // Existing task: save directly
        for (final step in steps) {
          await ServiceLocator.taskService.addChecklistItem(
            widget.taskId!,
            step,
          );
        }
        await _loadTask();
      } else {
        // New task: store as pending
        setState(() => _pendingChecklistTitles.addAll(steps));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('AI suggestions are unavailable right now.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingChecklist = false);
    }
  }

  Future<void> _estimateDuration() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    setState(() => _isEstimatingDuration = true);
    try {
      final desc = _descriptionController.text.trim();
      final prompt =
          'Estimate the labor hours for this construction task: "$title". '
          '${desc.isNotEmpty ? 'Description: "$desc". ' : ''}'
          'Return only a number (decimal hours), nothing else.';
      final result = await _aiService.askQuestion(
        question: prompt,
        persona: _persona,
      );
      final hours = double.tryParse(
        result.trim().replaceAll(RegExp(r'[^0-9.]'), ''),
      );
      if (hours != null && mounted) {
        setState(() => _durationController.text = hours.toStringAsFixed(1));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('AI suggestions are unavailable right now.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isEstimatingDuration = false);
    }
  }

  // Helper method to build section headers
  Widget _buildSectionHeader({
    required String title,
    required IconData icon,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 18, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (trailing != null) ...[const Spacer(), trailing],
        ],
      ),
    );
  }

  Widget _buildAutoAssignButton() {
    final theme = Theme.of(context);
    return Tooltip(
      message: 'Auto-select based on skills & availability',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: _isAutoAssigning ? null : _autoAssign,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isAutoAssigning)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                )
              else
                Icon(
                  Icons.auto_fix_high,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
              const SizedBox(width: 4),
              Text(
                'Auto',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _autoAssign() async {
    final workspaceId =
        Provider.of<AuthProvider>(context, listen: false)
            .appUser
            ?.currentWorkspaceId;
    if (workspaceId == null) return;

    // Build a temporary Task object with current form state for scoring
    final tempTask = Task(
      id: widget.taskId ?? '',
      workspaceId: workspaceId,
      projectId: widget.projectId,
      title: _titleController.text,
      startDate: _selectedStartDate,
      dueDate: _selectedDueDate,
      requiredSkillIds: _selectedRequiredSkillIds,
      assignedToIds: _selectedAssignedUserIds,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    setState(() => _isAutoAssigning = true);
    try {
      final proposal = await TaskSchedulerService.autoAssign(
        task: tempTask,
        workspaceId: workspaceId,
      );
      if (!mounted) return;
      if (proposal == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No matching team member found')),
        );
      } else if (_selectedAssignedUserIds.contains(proposal.proposedAssigneeId)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${proposal.proposedAssigneeName} is already assigned'),
          ),
        );
      } else {
        setState(() {
          _selectedAssignedUserIds.add(proposal.proposedAssigneeId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added ${proposal.proposedAssigneeName}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Auto-assign failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isAutoAssigning = false);
    }
  }

  Widget _buildTabChip({
    required int index,
    required IconData icon,
    required String label,
    required bool enabled,
  }) {
    final theme = Theme.of(context);
    final isSelected = _activeTabIndex == index;
    final primary = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: isSelected,
        showCheckmark: false,
        avatar: Icon(
          icon,
          size: 16,
          color: Colors.white,
        ),
        label: Text(label, style: const TextStyle(color: Colors.white)),
        // Override the global chipTheme.color (a light surface tint) which
        // otherwise takes precedence over selectedColor/backgroundColor in M3
        // and leaves the white label/icon invisible on a pale background.
        color: WidgetStateProperty.all(primary),
        selectedColor: primary,
        backgroundColor: primary,
        disabledColor: primary,
        side: isSelected
            ? BorderSide(color: Colors.white.withOpacity(0.5), width: 1.5)
            : BorderSide.none,
        onSelected: enabled
            ? (_) {
                setState(() => _activeTabIndex = index);
              }
            : null,
      ),
    );
  }

  Widget _buildDetailsTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        TextFormField(
          controller: _titleController,
          decoration: _buildInputDecoration(
            label: 'Task Title',
            icon: Icons.task_alt_rounded,
            isRequired: true,
          ),
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _descriptionController,
          decoration: _buildInputDecoration(
            label: 'Description',
            icon: Icons.notes_rounded,
            showOptionalSuffix: false,
          ),
          maxLines: 4,
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _titleController,
          builder: (context, value, _) {
            if (value.text.trim().isEmpty) return const SizedBox.shrink();
            return _buildAiActionBar();
          },
        ),
        if (widget.taskId != null && _existingTask != null) ...[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(AppSpacing.base),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppRadius.r16),
              border: Border.all(color: AppColors.surfaceAlt),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader(
                  title: 'Checklist',
                  icon: Icons.checklist_rounded,
                  trailing: _existingTask!.hasChecklist
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: AppSpacing.xs,
                          ),
                          decoration: BoxDecoration(
                            color:
                                _existingTask!.completedChecklistCount ==
                                    _existingTask!.totalChecklistCount
                                ? AppColors.success.withOpacity(0.1)
                                : theme.colorScheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(AppRadius.r12),
                          ),
                          child: Text(
                            '${_existingTask!.completedChecklistCount}/${_existingTask!.totalChecklistCount}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color:
                                  _existingTask!.completedChecklistCount ==
                                      _existingTask!.totalChecklistCount
                                  ? AppColors.success
                                  : theme.colorScheme.primary,
                            ),
                          ),
                        )
                      : null,
                ),
                ChecklistWidget(
                  task: _existingTask!,
                  isEditable: true,
                  onChanged: _loadTask,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(AppSpacing.base),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppRadius.r16),
              border: Border.all(color: AppColors.surfaceAlt),
            ),
            child: TaskRequiredFormsWidget(
              taskId: _existingTask!.id,
              projectId: widget.projectId,
            ),
          ),
        ],
        Container(
          padding: const EdgeInsets.all(AppSpacing.base),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppRadius.r16),
            border: Border.all(color: AppColors.surfaceAlt),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(
                title: 'Status',
                icon: Icons.table_chart_rounded,
              ),
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(1.1),
                  1: FlexColumnWidth(2.2),
                },
                children: [
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          'Status',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withOpacity(0.5),
                            borderRadius: BorderRadius.circular(AppRadius.r12),
                            border: Border.all(color: AppColors.cardBorder),
                          ),
                          child: DropdownButtonFormField<String>(
                            borderRadius: AppRadius.cardRadius,
                            initialValue: _status,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.sm,
                              ),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'not_started',
                                child: Text('Not Started'),
                              ),
                              DropdownMenuItem(
                                value: 'working_on_it',
                                child: Text('Working on it'),
                              ),
                              DropdownMenuItem(
                                value: 'stuck',
                                child: Text('Stuck'),
                              ),
                              DropdownMenuItem(
                                value: 'done',
                                child: Text('Done'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _status = value);
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          'Priority',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withOpacity(0.5),
                            borderRadius: BorderRadius.circular(AppRadius.r12),
                            border: Border.all(color: AppColors.cardBorder),
                          ),
                          child: DropdownButtonFormField<String>(
                            borderRadius: AppRadius.cardRadius,
                            initialValue: _priority,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.sm,
                              ),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'low',
                                child: Text('Low'),
                              ),
                              DropdownMenuItem(
                                value: 'medium',
                                child: Text('Medium'),
                              ),
                              DropdownMenuItem(
                                value: 'high',
                                child: Text('High'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _priority = value);
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          'Type',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withOpacity(0.5),
                            borderRadius: BorderRadius.circular(AppRadius.r12),
                            border: Border.all(color: AppColors.cardBorder),
                          ),
                          child: DropdownButtonFormField<TaskType>(
                            borderRadius: AppRadius.cardRadius,
                            initialValue: _taskType,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.sm,
                              ),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: TaskType.standard,
                                child: Text('Standard'),
                              ),
                              DropdownMenuItem(
                                value: TaskType.summary,
                                child: Text('Summary (group)'),
                              ),
                              DropdownMenuItem(
                                value: TaskType.milestone,
                                child: Text('Milestone'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _taskType = value);
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          'Color',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: _GroupColorPicker(
                          value: _groupColor,
                          onChanged: (c) => setState(() => _groupColor = c),
                        ),
                      ),
                    ],
                  ),
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'Progress',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$_progress%',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            SliderTheme(
                              data: SliderTheme.of(
                                context,
                              ).copyWith(trackHeight: 8),
                              child: Slider(
                                value: _progress.toDouble(),
                                min: 0,
                                max: 100,
                                divisions: 20,
                                label: '$_progress%',
                                activeColor: _progress >= 100
                                    ? AppColors.success
                                    : theme.colorScheme.primary,
                                onChanged: widget.taskId == null
                                    ? null
                                    : (value) {
                                        setState(() {
                                          _progress = value.round();
                                        });
                                      },
                              ),
                            ),
                            if (widget.taskId == null)
                              Text(
                                'Progress is editable after task creation.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(AppSpacing.base),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppRadius.r16),
            border: Border.all(color: AppColors.surfaceAlt),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(
                title: 'Assigned To',
                icon: Icons.group_rounded,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_selectedAssignedUserIds.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text('${_selectedAssignedUserIds.length} selected'),
                      ),
                    _buildAutoAssignButton(),
                  ],
                ),
              ),
              if (_selectedAssignedUserIds.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _selectedAssignedUserIds.map((userId) {
                    final user = _workspaceUsers.firstWhere(
                      (u) => u.id == userId,
                      orElse: () => AppUser(
                        id: userId,
                        email: 'Unknown User',
                        displayName: 'Unknown User',
                        workspaceId: '',
                        role: UserRole.fieldTechnician,
                        createdAt: DateTime.now(),
                        updatedAt: DateTime.now(),
                      ),
                    );
                    return Chip(
                      avatar: UserAvatar(
                        user: user,
                        size: AvatarSize.small,
                        onTap: null,
                      ),
                      label: Text(user.displayName ?? user.email),
                      onDeleted: () {
                        setState(() {
                          _selectedAssignedUserIds.remove(userId);
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
              ],
              if (_isLoadingUsers)
                const Center(child: CircularProgressIndicator())
              else
                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withOpacity(0.5),
                    borderRadius: BorderRadius.circular(AppRadius.r12),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: DropdownButtonFormField<String>(
                    borderRadius: AppRadius.cardRadius,
                    value: null,
                    decoration: InputDecoration(
                      hintText: 'Add team member...',
                      hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.base,
                        vertical: AppSpacing.md,
                      ),
                      prefixIcon: Icon(
                        Icons.person_add_rounded,
                        color: theme.colorScheme.primary.withOpacity(0.7),
                      ),
                    ),
                    icon: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    items: _workspaceUsers
                        .where(
                          (user) => !_selectedAssignedUserIds.contains(user.id),
                        )
                        .map((user) {
                          return DropdownMenuItem<String>(
                            value: user.id,
                            child: Row(
                              children: [
                                UserAvatar(
                                  user: user,
                                  size: AvatarSize.small,
                                  onTap: null,
                                ),
                                const SizedBox(width: 8),
                                Text(user.displayName ?? user.email),
                              ],
                            ),
                          );
                        })
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedAssignedUserIds.add(value);
                        });
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildScheduleTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.base),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppRadius.r16),
            border: Border.all(color: AppColors.surfaceAlt),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(
                title: 'Schedule',
                icon: Icons.schedule_rounded,
              ),
              const SizedBox(height: 4),
              _buildScheduleRow(),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(AppSpacing.base),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppRadius.r16),
            border: Border.all(color: AppColors.surfaceAlt),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(
                title: 'Parent Task',
                icon: Icons.account_tree_rounded,
              ),
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withOpacity(
                    0.5,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.r12),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: _isLoadingTasks
                    ? const Padding(
                        padding: EdgeInsets.all(AppSpacing.base),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : DropdownButtonFormField<String?>(
                      borderRadius: AppRadius.cardRadius,
                        value: _selectedParentId,
                        decoration: InputDecoration(
                          hintText: 'None (root level task)',
                          hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.base,
                            vertical: AppSpacing.md,
                          ),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('None (root level task)'),
                          ),
                          ..._projectTasks
                              .where((t) => t.id != widget.taskId)
                              .map(
                                (task) => DropdownMenuItem<String?>(
                                  value: task.id,
                                  child: Text(
                                    task.title,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedParentId = value;
                          });
                        },
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(AppSpacing.base),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppRadius.r16),
            border: Border.all(color: AppColors.surfaceAlt),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(
                title: 'Dependencies',
                icon: Icons.link_rounded,
              ),
              Text(
                'Select tasks that must be completed before this task can start.',
                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)),
              ),
              const SizedBox(height: 12),
              if (_isLoadingTasks)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.base),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                if (_selectedPredecessorIds.isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _selectedPredecessorIds.map((predId) {
                      final predTask = _projectTasks.firstWhere(
                        (t) => t.id == predId,
                        orElse: () => Task(
                          id: predId,
                          title: 'Unknown Task',
                          projectId: widget.projectId,
                          workspaceId: '',
                          createdAt: DateTime.now(),
                          updatedAt: DateTime.now(),
                        ),
                      );
                      return Chip(
                        avatar: Icon(
                          Icons.check_circle_outline_rounded,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        label: Text(predTask.title),
                        onDeleted: () {
                          setState(() {
                            _selectedPredecessorIds.remove(predId);
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                ],
                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withOpacity(0.5),
                    borderRadius: BorderRadius.circular(AppRadius.r12),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: DropdownButtonFormField<String?>(
                    borderRadius: AppRadius.cardRadius,
                    value: null,
                    decoration: InputDecoration(
                      hintText: 'Add predecessor task...',
                      hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.base,
                        vertical: AppSpacing.md,
                      ),
                      prefixIcon: Icon(
                        Icons.add_circle_outline_rounded,
                        color: theme.colorScheme.primary.withOpacity(0.7),
                      ),
                    ),
                    items: _projectTasks
                        .where(
                          (t) =>
                              t.id != widget.taskId &&
                              !_selectedPredecessorIds.contains(t.id),
                        )
                        .map(
                          (task) => DropdownMenuItem<String?>(
                            value: task.id,
                            child: Text(
                              task.title,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedPredecessorIds.add(value);
                        });
                      }
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(AppSpacing.base),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppRadius.r16),
            border: Border.all(color: AppColors.surfaceAlt),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.repeat,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Recurring Task',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                value: _isRecurring,
                onChanged: (value) {
                  setState(() => _isRecurring = value);
                },
              ),
              if (_isRecurring) ...[
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withOpacity(0.5),
                    borderRadius: BorderRadius.circular(AppRadius.r12),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: StackedField(
                    label: 'Frequency',
                    child: DropdownButtonFormField<String>(
                      borderRadius: AppRadius.cardRadius,
                      value: _recurrenceFrequency,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.base,
                          vertical: AppSpacing.md,
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'daily', child: Text('Daily')),
                        DropdownMenuItem(
                          value: 'weekly',
                          child: Text('Weekly'),
                        ),
                        DropdownMenuItem(
                          value: 'biweekly',
                          child: Text('Bi-weekly'),
                        ),
                        DropdownMenuItem(
                          value: 'monthly',
                          child: Text('Monthly'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _recurrenceFrequency = value);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _buildDatePicker(
                  label: 'End Date (optional)',
                  icon: Icons.event_busy_rounded,
                  selectedDate: _recurrenceEndDate,
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate:
                          _recurrenceEndDate ??
                          DateTime.now().add(const Duration(days: 90)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(
                        const Duration(days: 365 * 3),
                      ),
                    );
                    if (picked != null) {
                      setState(() => _recurrenceEndDate = picked);
                    }
                  },
                  onClear: () => setState(() => _recurrenceEndDate = null),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: _recurrenceMaxOccurrences?.toString() ?? '',
                  decoration: _buildInputDecoration(
                    label: 'Max Occurrences',
                    icon: Icons.pin_rounded,
                    helperText: 'Leave empty for unlimited',
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    setState(() {
                      _recurrenceMaxOccurrences = value.isNotEmpty
                          ? int.tryParse(value)
                          : null;
                    });
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildScheduleRow() {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 5,
              child: _buildDateSegment(
                label: 'Start',
                icon: Icons.play_arrow_rounded,
                date: _selectedStartDate,
                onTap: _selectStartDate,
                onClear: () => setState(() => _selectedStartDate = null),
                isFirst: true,
              ),
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: AppColors.cardBorder,
            ),
            Expanded(flex: 3, child: _buildDurationSegment()),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: AppColors.cardBorder,
            ),
            Expanded(
              flex: 5,
              child: _buildDateSegment(
                label: 'Due',
                icon: Icons.flag_rounded,
                date: _selectedDueDate,
                onTap: _selectDueDate,
                onClear: () => setState(() => _selectedDueDate = null),
                isFirst: false,
              ),
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: AppColors.cardBorder,
            ),
            Expanded(
              flex: 5,
              child: _buildDateSegment(
                label: 'End',
                icon: Icons.stop_circle_rounded,
                date: _selectedEndDate,
                onTap: _selectEndDate,
                onClear: () => setState(() => _selectedEndDate = null),
                isFirst: false,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSegment({
    required String label,
    required IconData icon,
    required DateTime? date,
    required VoidCallback onTap,
    required VoidCallback onClear,
    required bool isFirst,
  }) {
    final theme = Theme.of(context);
    final hasDate = date != null;
    final primary = theme.colorScheme.primary;
    final borderRadius = BorderRadius.horizontal(
      left: isFirst ? const Radius.circular(13) : Radius.zero,
      right: isFirst ? Radius.zero : const Radius.circular(13),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    size: 11,
                    color: hasDate ? primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: hasDate ? primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                  const Spacer(),
                  if (hasDate)
                    GestureDetector(
                      onTap: onClear,
                      child: Icon(
                        Icons.close_rounded,
                        size: 13,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                hasDate ? _formatDate(date) : '—',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: hasDate ? FontWeight.w600 : FontWeight.w400,
                  color: hasDate
                      ? theme.colorScheme.onSurface
                      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDurationSegment() {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final hasValue = _durationController.text.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.timelapse_rounded,
                size: 11,
                color: hasValue ? primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
              ),
              const SizedBox(width: 3),
              Text(
                'Duration',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: hasValue ? primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: TextFormField(
                  controller: _durationController,
                  keyboardType: TextInputType.number,
                  onChanged: (_) {
                    _autoCalculateDueDate();
                    setState(() {});
                  },
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: '—',
                    hintStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                      fontSize: 13,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              if (hasValue)
                Text(
                  ' h',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          if (hasValue)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '8h = 1d',
                style: TextStyle(
                  fontSize: 9,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResourcesTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        _buildAssetSelectorField(),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 16),
        Builder(
          builder: (context) {
            final authProvider = context.watch<AuthProvider>();
            final workspaceId = authProvider.appUser?.currentWorkspaceId;
            if (workspaceId == null) return const SizedBox.shrink();
            return SkillMultiSelector(
              workspaceId: workspaceId,
              selectedSkillIds: _selectedRequiredSkillIds,
              label: 'Required Skills',
              onChanged: (skillIds) {
                setState(() {
                  _selectedRequiredSkillIds = skillIds;
                });
              },
            );
          },
        ),
        const SizedBox(height: 16),
        Builder(
          builder: (context) {
            final authProvider = context.watch<AuthProvider>();
            final workspaceId = authProvider.appUser?.currentWorkspaceId;
            if (workspaceId == null) return const SizedBox.shrink();
            return BudgetItemMultiSelector(
              projectId: widget.projectId,
              workspaceId: workspaceId,
              selectedBudgetItemIds: _selectedBudgetItemIds,
              onChanged: (budgetItemIds) {
                setState(() {
                  _selectedBudgetItemIds = budgetItemIds;
                });
              },
            );
          },
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(AppSpacing.base),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppRadius.r16),
            border: Border.all(color: AppColors.surfaceAlt),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(
                title: 'Location',
                icon: Icons.location_on_rounded,
              ),
              Text(
                'Link this task to a property or area (for restoration workflows).',
                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)),
              ),
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final authProvider = context.watch<AuthProvider>();
                  final workspaceId = authProvider.appUser?.currentWorkspaceId;
                  if (workspaceId == null) return const SizedBox.shrink();
                  return PropertyAreaSelector(
                    projectId: widget.projectId,
                    workspaceId: workspaceId,
                    selectedPropertyIds: _selectedPropertyIds,
                    selectedAreaIds: _selectedAreaIds,
                    onPropertyIdsChanged: (propertyIds) {
                      setState(() {
                        _selectedPropertyIds = propertyIds;
                      });
                    },
                    onAreaIdsChanged: (areaIds) {
                      setState(() {
                        _selectedAreaIds = areaIds;
                      });
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAssetSelectorField() {
    return Builder(
      builder: (context) {
        final authProvider = context.watch<AuthProvider>();
        final workspaceId = authProvider.appUser?.currentWorkspaceId;
        if (workspaceId == null) return const SizedBox.shrink();
        final assetService = SupabaseAssetService(workspaceId: workspaceId);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                ),
                const SizedBox(width: 6),
                Text(
                  'Required Equipment',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.cardBorder),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                color: AppColors.surfaceAlt,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _selectAssets(workspaceId),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _selectedAssetIds.isEmpty
                              ? Icons.add_circle_outline
                              : Icons.edit_outlined,
                          size: 18,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _selectedAssetIds.isEmpty
                                ? 'Select required equipment...'
                                : 'Manage selected equipment...',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<Asset>>(
              stream: assetService.getAssets(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }

                final selectedAssets = (snapshot.data ?? [])
                    .where((a) => _selectedAssetIds.contains(a.id))
                    .toList();
                if (selectedAssets.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Text(
                      'No equipment selected',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)),
                    ),
                  );
                }

                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: selectedAssets.map((asset) {
                    return Chip(
                      label: Text(asset.name),
                      avatar: const Icon(Icons.inventory_2, size: 16),
                      onDeleted: () {
                        setState(() {
                          _selectedAssetIds.remove(asset.id);
                        });
                      },
                    );
                  }).toList(),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _selectAssets(String workspaceId) async {
    final isMobile = MediaQuery.of(context).size.width < AppBreakpoints.compact;
    final selected = isMobile
        ? await showModalBottomSheet<List<String>>(
            context: context,
            isScrollControlled: true,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            builder: (context) => AssetMultiSelector(
              workspaceId: workspaceId,
              projectId: widget.projectId,
              selectedAssetIds: _selectedAssetIds,
              useSheetPresentation: true,
            ),
          )
        : await showDialog<List<String>>(
            context: context,
            builder: (context) => AssetMultiSelector(
              workspaceId: workspaceId,
              projectId: widget.projectId,
              selectedAssetIds: _selectedAssetIds,
            ),
          );

    if (selected != null) {
      setState(() {
        _selectedAssetIds = selected;
      });
    }
  }

  Widget _buildFilesTab(ThemeData theme) {
    if (widget.taskId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(
            'Save the task first to upload and manage files.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        Row(
          children: [
            Icon(Icons.attach_file, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)),
            const SizedBox(width: 8),
            Text('Task Files', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 16),
        Builder(
          builder: (context) {
            final authProvider = context.watch<AuthProvider>();
            final workspaceId = authProvider.appUser?.currentWorkspaceId;
            final userId = authProvider.appUser?.id;
            if (workspaceId == null || userId == null) {
              return const SizedBox.shrink();
            }
            return Column(
              children: [
                FileUploadWidget(
                  workspaceId: workspaceId,
                  projectId: widget.projectId,
                  taskId: widget.taskId,
                  uploadedBy: userId,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 360,
                  child: FileGalleryWidget(
                    workspaceId: workspaceId,
                    projectId: widget.projectId,
                    taskId: widget.taskId,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildNotesTab(ThemeData theme) {
    if (widget.taskId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(
            'Save the task first to add notes and comments.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        Builder(
          builder: (context) {
            final authProvider = context.watch<AuthProvider>();
            final workspaceId = authProvider.appUser?.currentWorkspaceId;
            if (workspaceId == null) return const SizedBox.shrink();
            return TaskCommentsWidget(
              taskId: widget.taskId!,
              workspaceId: workspaceId,
            );
          },
        ),
      ],
    );
  }

  Widget _buildSaveButton(ThemeData theme) {
    final authProvider = context.watch<AuthProvider>();
    final canSave = widget.taskId == null
        ? authProvider.canCreateTasks
        : authProvider.canEditTasks;
    if (!canSave) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primary.withOpacity(0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : _handleSave,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            width: double.infinity,
            child: _isLoading
                ? const Center(
                    child: SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        widget.taskId == null
                            ? Icons.add_task_rounded
                            : Icons.save_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        widget.taskId == null ? 'Create Task' : 'Save Changes',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  void _navigateToEntity(String route) {
    final router = GoRouter.of(context);
    if (widget.isPopup && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    router.go(route);
  }

  Future<void> _openDirections() async {
    final project = _project;
    if (project == null) return;

    final address = project.address.trim();
    final lat = project.latitude;
    final lng = project.longitude;

    Uri? uri;
    if (lat != null && lng != null) {
      uri = Uri.parse('https://maps.google.com/maps?daddr=$lat,$lng');
    } else if (address.isNotEmpty) {
      uri = Uri.parse(
        'https://maps.google.com/maps?daddr=${Uri.encodeComponent(address)}',
      );
    }

    if (uri == null) return;

    final launched = await launchUrl(
      uri,
      mode: LaunchMode.platformDefault,
      webOnlyWindowName: '_blank',
    );

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open directions')),
      );
    }
  }

  Widget _buildProjectMetaHeader(ThemeData theme) {
    final project = _project;
    if (project == null) return const SizedBox.shrink();

    final serialNumber = project.serialNumber?.trim();
    final customerName = project.customerName?.trim();
    final customerId = project.clientId?.trim();
    final address = project.address.trim();
    final projectPlural = context.read<WorkspaceProvider>().projectTerminology;
    final projectSingular = projectPlural.endsWith('s') && projectPlural.length > 1
        ? projectPlural.substring(0, projectPlural.length - 1)
        : projectPlural;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxChipWidth = constraints.maxWidth;
        final chips = <Widget>[
          _buildMetaChip(
            theme: theme,
            label: projectSingular,
            value: project.name,
            maxWidth: maxChipWidth,
            onTap: () => _navigateToEntity('/projects/${project.id}'),
          ),
          if (serialNumber != null && serialNumber.isNotEmpty)
            _buildMetaChip(
              theme: theme,
              label: '$projectSingular#',
              value: serialNumber,
              maxWidth: maxChipWidth,
              onTap: () => _navigateToEntity('/projects/${project.id}'),
            ),
          if (customerName != null && customerName.isNotEmpty)
            _buildMetaChip(
              theme: theme,
              label: 'Customer',
              value: customerName,
              maxWidth: maxChipWidth,
              onTap: customerId != null && customerId.isNotEmpty
                  ? () => _navigateToEntity('/customers/$customerId')
                  : null,
            ),
          if (address.isNotEmpty)
            _buildMetaChip(
              theme: theme,
              label: 'Address',
              value: address,
              maxWidth: maxChipWidth,
              onTap: _openDirections,
            ),
        ];

        return Wrap(spacing: 8, runSpacing: 8, children: chips);
      },
    );
  }

  Widget _buildMetaChip({
    required ThemeData theme,
    required String label,
    required String value,
    required double maxWidth,
    VoidCallback? onTap,
  }) {
    final isClickable = onTap != null;
    final borderColor = isClickable
        ? theme.colorScheme.primary.withValues(alpha: 0.28)
        : AppColors.cardBorder;
    final backgroundColor = isClickable
        ? theme.colorScheme.primary.withValues(alpha: 0.08)
        : theme.colorScheme.surface;
    final labelColor = isClickable
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    final valueColor = theme.colorScheme.onSurface;

    final chip = Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        border: Border.all(color: borderColor),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(color: labelColor, fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: value,
              style: TextStyle(color: valueColor, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        style: theme.textTheme.bodySmall,
        softWrap: true,
      ),
    );

    if (!isClickable) {
      return chip;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.r12),
          child: chip,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _isLoading && _existingTask == null
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border(
                      bottom: BorderSide(color: AppColors.cardBorder),
                    ),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildTabChip(
                          index: 0,
                          icon: Icons.task_alt_rounded,
                          label: 'Details',
                          enabled: true,
                        ),
                        _buildTabChip(
                          index: 1,
                          icon: Icons.schedule_rounded,
                          label: 'Schedule',
                          enabled: true,
                        ),
                        _buildTabChip(
                          index: 2,
                          icon: Icons.inventory_2_rounded,
                          label: 'Resources',
                          enabled: true,
                        ),
                        _buildTabChip(
                          index: 3,
                          icon: Icons.attach_file_rounded,
                          label: 'Files',
                          enabled: true,
                        ),
                        _buildTabChip(
                          index: 4,
                          icon: Icons.comment_rounded,
                          label: 'Notes',
                          enabled: true,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_project != null &&
                    MediaQuery.viewInsetsOf(context).bottom == 0)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.base,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLow,
                      border: Border(
                        bottom: BorderSide(color: AppColors.cardBorder),
                      ),
                    ),
                    child: _buildProjectMetaHeader(theme),
                  ),
                Expanded(
                  child: IndexedStack(
                    index: _activeTabIndex,
                    children: [
                      _buildDetailsTab(theme),
                      _buildScheduleTab(theme),
                      _buildResourcesTab(theme),
                      _buildFilesTab(theme),
                      _buildNotesTab(theme),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: _buildSaveButton(theme),
                  ),
                ),
              ],
            ),
          );
  }
}

/// Small chip button used in the AI action bar
class _AiActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool loading;
  final bool disabled;
  final VoidCallback onTap;

  const _AiActionChip({
    required this.icon,
    required this.label,
    required this.loading,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ActionChip(
      avatar: loading
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.sidebarText,
              ),
            )
          : Icon(icon, size: 14, color: AppColors.sidebarText),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: disabled ? null : onTap,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Inline swatch picker for the per-task group color. Tap a swatch to
/// select; selected one shows a check overlay. Keeps the editor row at
/// roughly the same height as the surrounding dropdowns.
class _GroupColorPicker extends StatelessWidget {
  final Color value;
  final ValueChanged<Color> onChanged;
  const _GroupColorPicker({required this.value, required this.onChanged});

  // Curated palette — matches the typical group-color choices the app uses
  // elsewhere (blue default, plus categorical hues that read well in the
  // Gantt and board views).
  static const _swatches = <Color>[
    Color(0xFF2196F3), // blue (default)
    Color(0xFF26A69A), // teal
    Color(0xFF66BB6A), // green
    Color(0xFFFFA726), // orange
    Color(0xFFEF5350), // red
    Color(0xFFAB47BC), // purple
    Color(0xFF8D6E63), // brown
    Color(0xFF78909C), // blue-grey
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withOpacity(0.5),
        borderRadius: BorderRadius.circular(AppRadius.r12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final c in _swatches)
            InkWell(
              onTap: () => onChanged(c),
              borderRadius: BorderRadius.circular(AppRadius.xl),
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: c.value == value.value
                        ? Theme.of(context).colorScheme.onSurface
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: c.value == value.value
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}
