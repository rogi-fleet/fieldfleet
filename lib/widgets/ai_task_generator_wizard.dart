import 'dart:async';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/theme.dart';
import '../models/budget_item.dart';
import '../models/project.dart';
import '../models/task.dart';
import '../providers/workspace_provider.dart';
import '../services/ai_service.dart';
import '../services/service_locator.dart';
import 'ai/ai_wizard_shared.dart';
import 'ai/ai_wizard_dialog.dart';
import 'ai_persona_picker.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

/// AI Task Generator Wizard for creating tasks from budget items
class AiTaskGeneratorWizard extends StatefulWidget {
  final String projectId;
  final String workspaceId;
  final Project? project;
  final VoidCallback? onComplete;

  const AiTaskGeneratorWizard({
    super.key,
    required this.projectId,
    required this.workspaceId,
    this.project,
    this.onComplete,
  });

  @override
  State<AiTaskGeneratorWizard> createState() => _AiTaskGeneratorWizardState();
}

class _AiTaskGeneratorWizardState extends State<AiTaskGeneratorWizard> {
  final _pageController = PageController();
  final _instructionsController = TextEditingController();
  int _currentStep = 0;
  static const int _totalSteps = 3;

  // Step 1: Budget item selection
  List<BudgetItem> _budgetItems = [];
  Map<String, BudgetItem> _budgetItemsById = {};
  Set<String> _selectedBudgetItemIds = {};
  bool _isLoadingBudgetItems = true;

  // Step 2: AI generation
  bool _isGenerating = false;
  bool _isCancelled = false;
  List<AiGeneratedTask> _generatedTasks = [];
  String _currentProvider = '';
  String _currentStatus = '';
  String _streamedText = '';
  String _pendingStreamedText = '';
  Timer? _streamUpdateTimer;
  String? _successProvider;
  DateTime? _loadingStartTime;

  // Step 3: Import
  bool _isImporting = false;
  DateTime? _startDate;
  bool _createAsGroup = true;
  String _groupName = '';

  // Step configuration
  static const List<AiStepConfig> _steps = [
    AiStepConfig(
      number: 1,
      title: 'Select Budget Items',
      subtitle: 'Choose items to generate tasks from',
      icon: Icons.checklist,
    ),
    AiStepConfig(
      number: 2,
      title: 'Review Generated Tasks',
      subtitle: 'AI creates tasks with dependencies',
      icon: Icons.auto_awesome,
    ),
    AiStepConfig(
      number: 3,
      title: 'Import Tasks',
      subtitle: 'Add tasks to your project',
      icon: Icons.task_alt,
    ),
  ];

  List<String> get _thinkingMessages {
    final style = context
        .read<WorkspaceProvider>()
        .activeWorkspace
        ?.aiPersonaStyle;
    return getPersonaThinkingMessages(style).isNotEmpty
        ? getPersonaThinkingMessages(style)
        : [
            'Analyzing budget items...',
            'Identifying work sequences...',
            'Creating task hierarchy...',
            'Adding dependencies...',
            'Generating checklists...',
            'Finalizing task list...',
          ];
  }

  @override
  void initState() {
    super.initState();
    _loadBudgetItems();
    _startDate = DateTime.now();
    if (widget.project != null) {
      _groupName = '${widget.project!.name} Tasks';
    }
  }

  @override
  void dispose() {
    _streamUpdateTimer?.cancel();
    _pageController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  void _handleStreamUpdate(
    String providerName,
    String delta,
    String accumulated,
  ) {
    if (!mounted || _isCancelled) return;
    _pendingStreamedText = accumulated;
    if (_streamUpdateTimer != null) return;
    _streamUpdateTimer = Timer(const Duration(milliseconds: 120), () {
      _streamUpdateTimer = null;
      if (!mounted || _isCancelled) return;
      setState(() {
        _streamedText = _pendingStreamedText;
      });
    });
  }

  Future<void> _loadBudgetItems() async {
    try {
      final budgetService = ServiceLocator.budgetService;
      final items = await budgetService
          .getBudgetItems(widget.projectId, workspaceId: widget.workspaceId)
          .first;

      // Build lookup map
      final itemsById = <String, BudgetItem>{};
      for (final item in items) {
        itemsById[item.id] = item;
      }

      setState(() {
        _budgetItems = items;
        _budgetItemsById = itemsById;
        _isLoadingBudgetItems = false;
        // Pre-select all leaf items (not groups)
        _selectedBudgetItemIds = items
            .where((item) => item.itemType == BudgetItemType.item)
            .map((item) => item.id)
            .toSet();
      });
    } catch (e) {
      debugPrint('Error loading budget items: $e');
      setState(() {
        _isLoadingBudgetItems = false;
      });
    }
  }

  String? _getParentName(BudgetItem item) {
    if (item.parentId == null) return null;
    final parent = _budgetItemsById[item.parentId];
    return parent?.name;
  }

  void _goToStep(int step) {
    if (step >= 0 && step < _totalSteps) {
      _pageController.animateToPage(
        step,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentStep = step);
    }
  }

  void _nextStep() {
    if (_currentStep == 0) {
      _generateTasks();
    } else if (_currentStep < _totalSteps - 1) {
      _goToStep(_currentStep + 1);
    } else {
      _importTasks();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _goToStep(_currentStep - 1);
    }
  }

  void _cancelGeneration() {
    setState(() {
      _isCancelled = true;
      _isGenerating = false;
      _currentProvider = '';
      _currentStatus = '';
      _loadingStartTime = null;
    });
    _goToStep(0);
  }

  Future<void> _generateTasks() async {
    if (_selectedBudgetItemIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one budget item'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
      _isCancelled = false;
      _currentProvider = 'Mimo V2 Flash';
      _currentStatus = 'Initializing...';
      _streamedText = '';
      _pendingStreamedText = '';
      _successProvider = null;
      _loadingStartTime = DateTime.now();
    });

    _goToStep(1);

    try {
      // Build budget item inputs
      final budgetItemInputs = _selectedBudgetItemIds.map((id) {
        final item = _budgetItemsById[id]!;
        return BudgetItemInput(
          id: item.id,
          name: item.name,
          parentName: _getParentName(item),
          laborHours: item.unit?.toLowerCase() == 'hr' ? item.quantity : null,
          unit: item.unit,
          quantity: item.quantity,
        );
      }).toList();

      // Build project context
      AiProjectContext? projectContext;
      if (widget.project != null) {
        final p = widget.project!;
        projectContext = AiProjectContext(
          projectName: p.name,
          location: p.address,
          jobType: p.jobType?.displayName,
        );
      }

      final aiService = AiService();
      final tasks = await aiService.generateTasks(
        budgetItems: budgetItemInputs,
        additionalInstructions: _instructionsController.text.isNotEmpty
            ? _instructionsController.text
            : null,
        projectContext: projectContext,
        persona: context.read<WorkspaceProvider>().aiPersonaContext,
        onProgress: (providerName, status) {
          if (mounted && !_isCancelled) {
            setState(() {
              _currentProvider = providerName;
              _currentStatus = status;
            });
          }
        },
        onStream: _handleStreamUpdate,
      );

      if (_isCancelled) return;

      _generatedTasks = tasks;
      _successProvider = _currentProvider;

      if (mounted) {
        setState(() {
          _isGenerating = false;
          _streamedText = _pendingStreamedText;
          _loadingStartTime = null;
        });
        _goToStep(1);
      }
    } catch (e) {
      debugPrint('AI task generation failed: $e');

      if (_isCancelled) return;

      // Generate fallback tasks from budget items directly
      _generateFallbackTasks();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Using basic task generation (AI unavailable)'),
            backgroundColor: AppColors.warning,
            duration: Duration(seconds: 3),
          ),
        );
        setState(() {
          _isGenerating = false;
          _loadingStartTime = null;
          _successProvider = 'Template';
        });
        _goToStep(1);
      }
    }
  }

  void _generateFallbackTasks() {
    final tasks = <AiGeneratedTask>[];
    int taskIndex = 0;

    // Group budget items by their parent
    final groupedItems = <String?, List<BudgetItem>>{};
    for (final id in _selectedBudgetItemIds) {
      final item = _budgetItemsById[id]!;
      final parentName = _getParentName(item);
      groupedItems.putIfAbsent(parentName, () => []).add(item);
    }

    // Create tasks for each group
    for (final entry in groupedItems.entries) {
      final groupName = entry.key;
      final items = entry.value;

      String? groupTempId;

      // Create summary task for group if there's a parent
      if (groupName != null && items.length > 1) {
        groupTempId = 'group_$taskIndex';
        tasks.add(
          AiGeneratedTask(
            tempId: groupTempId,
            title: groupName,
            taskType: 'summary',
            priority: 'medium',
          ),
        );
        taskIndex++;
      }

      // Create tasks for each item
      String? previousTempId;
      for (final item in items) {
        final tempId = 'task_$taskIndex';
        final isLabor = item.unit?.toLowerCase() == 'hr';

        tasks.add(
          AiGeneratedTask(
            tempId: tempId,
            title: _generateTaskTitle(item.name),
            description: 'Complete ${item.name.toLowerCase()}',
            taskType: 'standard',
            parentTempId: groupTempId,
            predecessorTempIds: previousTempId != null ? [previousTempId] : [],
            estimatedDuration: isLabor
                ? item.quantity
                : _estimateDuration(item),
            priority: 'medium',
            checklistItems: _generateBasicChecklist(item.name),
            sourceBudgetItemId: item.id,
          ),
        );

        previousTempId = tempId;
        taskIndex++;
      }
    }

    _generatedTasks = tasks;
  }

  String _generateTaskTitle(String budgetItemName) {
    final lower = budgetItemName.toLowerCase();

    if (lower.contains('labor') || lower.contains('installation')) {
      return budgetItemName;
    } else if (lower.contains('removal') || lower.contains('demo')) {
      return budgetItemName;
    } else if (lower.contains('paint')) {
      return 'Apply $budgetItemName';
    } else {
      return 'Install $budgetItemName';
    }
  }

  double _estimateDuration(BudgetItem item) {
    final lower = item.name.toLowerCase();

    if (lower.contains('cabinet')) return 16.0;
    if (lower.contains('countertop')) return 8.0;
    if (lower.contains('tile') || lower.contains('flooring')) return 16.0;
    if (lower.contains('paint')) return 8.0;
    if (lower.contains('plumbing')) return 6.0;
    if (lower.contains('electrical')) return 8.0;
    if (lower.contains('hvac')) return 16.0;
    if (lower.contains('door') || lower.contains('window')) return 4.0;

    return 8.0;
  }

  List<String> _generateBasicChecklist(String itemName) {
    final lower = itemName.toLowerCase();

    if (lower.contains('cabinet')) {
      return [
        'Verify delivery and inspect',
        'Mark layout positions',
        'Install mounting hardware',
        'Level and secure',
        'Install doors and adjust',
      ];
    } else if (lower.contains('countertop')) {
      return [
        'Confirm measurements',
        'Prepare substrate',
        'Apply adhesive/support',
        'Set countertop',
        'Seal edges',
      ];
    } else if (lower.contains('tile') || lower.contains('flooring')) {
      return [
        'Prepare subfloor',
        'Layout pattern',
        'Apply thinset/adhesive',
        'Set tiles/flooring',
        'Grout and seal',
      ];
    } else if (lower.contains('paint')) {
      return [
        'Prep surfaces',
        'Apply primer',
        'Apply first coat',
        'Apply second coat',
        'Touch up and cleanup',
      ];
    } else if (lower.contains('plumbing')) {
      return [
        'Shut off water supply',
        'Install/connect fixtures',
        'Test connections',
        'Check for leaks',
      ];
    } else if (lower.contains('electrical')) {
      return [
        'Turn off power',
        'Install wiring/devices',
        'Make connections',
        'Test circuits',
        'Install covers/plates',
      ];
    }

    return [
      'Review specifications',
      'Prepare work area',
      'Complete installation',
      'Verify quality',
      'Clean up',
    ];
  }

  Future<void> _importTasks() async {
    final selectedTasks = _generatedTasks.where((t) => t.isSelected).toList();

    if (selectedTasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one task to import'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _isImporting = true);

    try {
      final taskService = ServiceLocator.taskService;
      final now = DateTime.now();

      // Map of tempId -> created task ID
      final tempIdToRealId = <String, String>{};

      // Sort tasks: summary tasks first, then by order
      final sortedTasks = List<AiGeneratedTask>.from(selectedTasks);
      sortedTasks.sort((a, b) {
        if (a.isSummary && !b.isSummary) return -1;
        if (!a.isSummary && b.isSummary) return 1;
        return 0;
      });

      // Optionally create a root group
      String? rootGroupId;
      if (_createAsGroup && _groupName.isNotEmpty) {
        final rootTask = await taskService.createTask(
          workspaceId: widget.workspaceId,
          projectId: widget.projectId,
          title: _groupName,
          taskType: TaskType.summary,
          startDate: _startDate,
        );
        rootGroupId = rootTask.id;
      }

      // Calculate dates based on dependencies
      final taskDates = <String, DateTime>{};
      final baseDate = _startDate ?? now;

      // First pass: create all tasks
      for (final task in sortedTasks) {
        // Determine parent ID
        String? parentId;
        if (task.parentTempId != null &&
            tempIdToRealId.containsKey(task.parentTempId)) {
          parentId = tempIdToRealId[task.parentTempId];
        } else if (rootGroupId != null && task.parentTempId == null) {
          parentId = rootGroupId;
        }

        // Calculate start date based on predecessors
        DateTime startDate = baseDate;
        for (final predTempId in task.predecessorTempIds) {
          if (taskDates.containsKey(predTempId)) {
            final predEndDate = taskDates[predTempId]!;
            if (predEndDate.isAfter(startDate)) {
              startDate = predEndDate;
            }
          }
        }

        // Calculate end date
        final durationHours = task.estimatedDuration ?? 8.0;
        final durationDays = (durationHours / 8.0).ceil();
        final endDate = startDate.add(Duration(days: durationDays));
        taskDates[task.tempId] = endDate;

        // Create the task
        final createdTask = await taskService.createTask(
          workspaceId: widget.workspaceId,
          projectId: widget.projectId,
          title: task.title,
          description: task.description,
          taskType: task.isSummary ? TaskType.summary : TaskType.standard,
          parentId: parentId,
          startDate: task.isSummary ? null : startDate,
          dueDate: task.isSummary ? null : endDate,
          estimatedDuration: task.estimatedDuration,
          priority: task.priority,
          status: 'not_started',
        );

        tempIdToRealId[task.tempId] = createdTask.id;

        // Add checklist items
        if (task.checklistItems.isNotEmpty) {
          for (final checklistTitle in task.checklistItems) {
            await taskService.addChecklistItem(createdTask.id, checklistTitle);
          }
        }
      }

      // Second pass: update predecessor IDs
      for (final task in sortedTasks) {
        if (task.predecessorTempIds.isNotEmpty) {
          final realPredecessorIds = task.predecessorTempIds
              .where((tempId) => tempIdToRealId.containsKey(tempId))
              .map((tempId) => tempIdToRealId[tempId]!)
              .toList();

          if (realPredecessorIds.isNotEmpty) {
            final realTaskId = tempIdToRealId[task.tempId];
            if (realTaskId != null) {
              await taskService.updateTask(
                taskId: realTaskId,
                predecessorIds: realPredecessorIds,
              );
            }
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Created ${selectedTasks.length} tasks'),
            backgroundColor: AppColors.success,
          ),
        );
        widget.onComplete?.call();
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('Error importing tasks: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'importing tasks'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  void _selectAllTasks(bool select) {
    setState(() {
      for (final task in _generatedTasks) {
        task.isSelected = select;
      }
    });
  }

  void _selectAllBudgetItems(bool select) {
    setState(() {
      if (select) {
        _selectedBudgetItemIds = _budgetItems
            .where((item) => item.itemType == BudgetItemType.item)
            .map((item) => item.id)
            .toSet();
      } else {
        _selectedBudgetItemIds.clear();
      }
    });
  }

  int get _selectedTaskCount =>
      _generatedTasks.where((t) => t.isSelected).length;

  double get _totalEstimatedHours => _generatedTasks
      .where((t) => t.isSelected && t.estimatedDuration != null)
      .fold(0.0, (sum, t) => sum + t.estimatedDuration!);

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        AiWizardHeader(
          currentStep: _currentStep,
          totalSteps: _totalSteps,
          steps: _steps,
        ),
        Expanded(
          child: PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            onPageChanged: (index) => setState(() => _currentStep = index),
            children: [
              _buildStep1BudgetSelection(),
              _buildStep2Review(),
              _buildStep3Import(),
            ],
          ),
        ),
        _buildNavigationBar(primaryColor),
      ],
    );
  }

  Widget _buildNavigationBar(Color primaryColor) {
    final isLastStep = _currentStep == _totalSteps - 1;
    bool canProceed;

    if (_currentStep == 0) {
      canProceed = _selectedBudgetItemIds.isNotEmpty;
    } else if (_currentStep == 1) {
      canProceed = _selectedTaskCount > 0;
    } else {
      canProceed = true;
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            TextButton.icon(
              onPressed: _previousStep,
              icon: const Icon(Icons.chevron_left),
              label: const Text('Back'),
            )
          else
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          const Spacer(),
          if (_currentStep == 0) ...[
            Text(
              '${_selectedBudgetItemIds.length} items selected',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)),
            ),
            const SizedBox(width: 16),
          ],
          if (_currentStep == 1 && !_isGenerating) ...[
            Text(
              '$_selectedTaskCount tasks',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)),
            ),
            const SizedBox(width: 16),
          ],
          FilledButton.icon(
            onPressed: (_isGenerating || _isImporting || !canProceed)
                ? null
                : _nextStep,
            icon: (_isGenerating || _isImporting)
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    isLastStep
                        ? Icons.task_alt
                        : (_currentStep == 0
                              ? Icons.auto_awesome
                              : Icons.arrow_forward),
                  ),
            label: Text(
              _isGenerating
                  ? 'Generating...'
                  : _isImporting
                  ? 'Importing...'
                  : isLastStep
                  ? 'Create Tasks'
                  : (_currentStep == 0 ? 'Generate Tasks' : 'Next'),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== STEP 1: BUDGET SELECTION ====================

  Widget _buildStep1BudgetSelection() {
    if (_isLoadingBudgetItems) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_budgetItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)),
            const SizedBox(height: 16),
            Text(
              'No budget items found',
              style: TextStyle(fontSize: 18, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)),
            ),
            const SizedBox(height: 8),
            Text(
              'Add budget items first to generate tasks',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Selection controls
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
          ),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () => _selectAllBudgetItems(true),
                icon: const Icon(Icons.select_all, size: 18),
                label: const Text('Select All'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => _selectAllBudgetItems(false),
                icon: const Icon(Icons.deselect, size: 18),
                label: const Text('Deselect All'),
              ),
            ],
          ),
        ),

        // Budget items list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.base),
            itemCount: _budgetItems.length,
            itemBuilder: (context, index) {
              final item = _budgetItems[index];
              return _buildBudgetItemTile(item);
            },
          ),
        ),

        // Optional instructions
        Container(
          padding: const EdgeInsets.all(AppSpacing.base),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            border: Border(top: BorderSide(color: AppColors.cardBorder)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Special Instructions (optional)',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _instructionsController,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText:
                      'e.g., "Kitchen work first, then bathroom. Electrical must happen before drywall."',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.all(AppSpacing.md),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBudgetItemTile(BudgetItem item) {
    final isGroup = item.itemType == BudgetItemType.group;
    final isSelected = _selectedBudgetItemIds.contains(item.id);
    final indent = item.hierarchyLevel * 24.0;

    if (isGroup) {
      return Padding(
        padding: EdgeInsets.only(left: indent, top: 8, bottom: 4),
        child: Row(
          children: [
            Icon(
              Icons.folder_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
            ),
            const SizedBox(width: 8),
            Text(
              item.name,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: InkWell(
        onTap: () {
          setState(() {
            if (isSelected) {
              _selectedBudgetItemIds.remove(item.id);
            } else {
              _selectedBudgetItemIds.add(item.id);
            }
          });
        },
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.05)
                : Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : AppColors.cardBorder,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Checkbox(
                value: isSelected,
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _selectedBudgetItemIds.add(item.id);
                    } else {
                      _selectedBudgetItemIds.remove(item.id);
                    }
                  });
                },
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    if (item.quantity > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${item.quantity} ${item.unit ?? "units"}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (item.unit?.toLowerCase() == 'hr')
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.infoLight,
                    borderRadius: BorderRadius.circular(AppRadius.r12),
                  ),
                  child: Text(
                    '${item.quantity.toInt()} hrs',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.infoDark,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== STEP 2: REVIEW ====================

  Widget _buildStep2Review() {
    if (_isGenerating) {
      return AiLoadingState(
        currentProvider: _currentProvider,
        currentStatus: _currentStatus,
        loadingStartTime: _loadingStartTime,
        thinkingMessages: _thinkingMessages,
        streamedText: _streamedText,
        showStreamPreview: true,
        onCancel: _cancelGeneration,
      );
    }

    return Column(
      children: [
        // Selection controls
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
          ),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () => _selectAllTasks(true),
                icon: const Icon(Icons.select_all, size: 18),
                label: const Text('Select All'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => _selectAllTasks(false),
                icon: const Icon(Icons.deselect, size: 18),
                label: const Text('Deselect All'),
              ),
              const Spacer(),
              if (_successProvider != null) ...[
                AiProviderBadge(providerName: _successProvider!),
                const SizedBox(width: 12),
              ],
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                ),
                child: Text(
                  '${_totalEstimatedHours.toInt()} hrs total',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Tasks list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.base),
            itemCount: _generatedTasks.length,
            itemBuilder: (context, index) {
              final task = _generatedTasks[index];
              return _buildTaskCard(task);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTaskCard(AiGeneratedTask task) {
    final theme = Theme.of(context);
    final isGroup = task.isSummary;
    final indent = task.parentTempId != null ? 24.0 : 0.0;

    // Find predecessor names
    final predecessorNames = task.predecessorTempIds
        .map(
          (id) => _generatedTasks
              .firstWhere(
                (t) => t.tempId == id,
                orElse: () => AiGeneratedTask(
                  tempId: '',
                  title: 'Unknown',
                  taskType: 'standard',
                ),
              )
              .title,
        )
        .where((name) => name != 'Unknown')
        .toList();

    return Padding(
      padding: EdgeInsets.only(left: indent, bottom: 8),
      child: InkWell(
        onTap: () {
          setState(() => task.isSelected = !task.isSelected);
        },
        borderRadius: BorderRadius.circular(AppRadius.r12),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.base),
          decoration: BoxDecoration(
            color: task.isSelected
                ? (isGroup
                      ? Colors.indigo.shade50
                      : theme.colorScheme.primary.withValues(alpha: 0.05))
                : Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.r12),
            border: Border.all(
              color: task.isSelected
                  ? (isGroup ? Colors.indigo : theme.colorScheme.primary)
                  : AppColors.cardBorder,
              width: task.isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Checkbox(
                    value: task.isSelected,
                    onChanged: (value) {
                      setState(() => task.isSelected = value ?? false);
                    },
                  ),
                  if (isGroup)
                    Icon(Icons.folder, color: Colors.indigo.shade400, size: 20)
                  else
                    Icon(
                      Icons.task_alt,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      task.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: isGroup ? Colors.indigo.shade700 : null,
                      ),
                    ),
                  ),
                  if (isGroup)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade100,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        'Phase',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.indigo.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )
                  else if (task.estimatedDuration != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        '${task.estimatedDuration!.toInt()} hrs',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
              if (task.description != null) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 48),
                  child: Text(
                    task.description!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
              if (predecessorNames.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 48),
                  child: Row(
                    children: [
                      Icon(
                        Icons.arrow_right_alt,
                        size: 16,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Depends on: ${predecessorNames.join(", ")}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.warningDark,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (task.checklistItems.isNotEmpty && !isGroup) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(left: 48),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(left: 16),
                    title: Text(
                      '${task.checklistItems.length} checklist items',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                    children: task.checklistItems
                        .map(
                          (item) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.check_box_outline_blank,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    item,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ==================== STEP 3: IMPORT ====================

  Widget _buildStep3Import() {
    final selectedTasks = _generatedTasks.where((t) => t.isSelected).toList();
    final summaryCount = selectedTasks.where((t) => t.isSummary).length;
    final standardCount = selectedTasks.where((t) => t.isStandard).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary card
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadius.r12),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.summarize,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Import Summary',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildSummaryRow('Total Tasks', '${selectedTasks.length}'),
                _buildSummaryRow('Phase Tasks', '$summaryCount'),
                _buildSummaryRow('Work Tasks', '$standardCount'),
                _buildSummaryRow(
                  'Estimated Duration',
                  '${_totalEstimatedHours.toInt()} hours',
                  highlight: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Options
          Text(
            'Import Options',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),

          // Start date
          Container(
            padding: const EdgeInsets.all(AppSpacing.base),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.r12),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)),
                const SizedBox(width: 12),
                const Text('Start Date'),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _startDate ?? DateTime.now(),
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 30),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date != null) {
                      setState(() => _startDate = date);
                    }
                  },
                  child: Text(
                    _startDate != null
                        ? '${_startDate!.month}/${_startDate!.day}/${_startDate!.year}'
                        : 'Select',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Create as group option
          Container(
            padding: const EdgeInsets.all(AppSpacing.base),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.r12),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.folder_outlined, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)),
                    const SizedBox(width: 12),
                    const Expanded(child: Text('Create as Task Phase')),
                    Switch(
                      value: _createAsGroup,
                      onChanged: (value) {
                        setState(() => _createAsGroup = value);
                      },
                    ),
                  ],
                ),
                if (_createAsGroup) ...[
                  const SizedBox(height: 12),
                  StackedField(
                    label: 'Phase Name',
                    child: TextField(
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.md,
                        ),
                      ),
                      controller: TextEditingController(text: _groupName),
                      onChanged: (value) => _groupName = value,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Task preview
          Text(
            'Tasks to be created:',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ...selectedTasks.map(
            (task) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    task.isSummary ? Icons.folder : Icons.check_circle,
                    color: task.isSummary
                        ? AppColors.messageAccent
                        : AppColors.success,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(task.title)),
                  if (task.estimatedDuration != null)
                    Text(
                      '${task.estimatedDuration!.toInt()} hrs',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value, {
    bool highlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65))),
          Text(
            value,
            style: TextStyle(
              fontWeight: highlight ? FontWeight.bold : FontWeight.w500,
              color: highlight ? AppColors.successDark : null,
              fontSize: highlight ? 16 : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows the AI Task Generator wizard as a dialog
void showAiTaskGeneratorWizard(
  BuildContext context, {
  required String projectId,
  required String workspaceId,
  Project? project,
  VoidCallback? onComplete,
}) {
  final ws = context.read<WorkspaceProvider>().activeWorkspace;
  final emoji = kPersonaAvatarEmojis[ws?.aiPersonaAvatar ?? 'hard_hat'] ?? '🤖';
  showAiWizardDialog(
    context,
    title: 'AI Task Generator',
    personaEmoji: emoji,
    width: 700,
    child: AiTaskGeneratorWizard(
      projectId: projectId,
      workspaceId: workspaceId,
      project: project,
      onComplete: onComplete,
    ),
  );
}
