import 'dart:async';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme.dart';
import '../../models/project.dart';
import '../../models/budget_item.dart';
import '../../models/task.dart';
import '../../models/property.dart';
import '../../models/area.dart';
import '../../models/workflow_template.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../utils/project_terminology.dart';
import '../ai_persona_picker.dart';
import '../../services/ai_service.dart';
import '../../services/ai_generation_service.dart';
import '../../services/service_locator.dart';
import '../../utils/address_formatter.dart';
import '../../utils/currency_utils.dart';
import 'ai_wizard_shared.dart';
import 'ai_wizard_dialog.dart';
import '../task_scheduler_wizard.dart';

/// Shows the AI Project Setup wizard dialog
void showAiProjectSetupWizard(
  BuildContext context, {
  required Project project,
  required String workspaceId,
  String? initialWorkflowTemplateId,
  VoidCallback? onComplete,
}) {
  final workspaceProvider = context.read<WorkspaceProvider>();
  final ws = workspaceProvider.activeWorkspace;
  final singular =
      singularProjectTerminology(workspaceProvider.projectTerminology);
  final emoji = kPersonaAvatarEmojis[ws?.aiPersonaAvatar ?? 'hard_hat'] ?? '🤖';
  final avatarAssetPath = kPersonaAvatars[ws?.aiPersonaAvatar ?? 'hard_hat'] ??
      'assets/images/avatars/robot.png';
  showAiWizardDialog(
    context,
    title: 'AI $singular Setup',
    personaEmoji: emoji,
    personaAvatarAssetPath: avatarAssetPath,
    width: 750,
    child: AiProjectSetupWizard(
      project: project,
      workspaceId: workspaceId,
      initialWorkflowTemplateId: initialWorkflowTemplateId,
      onComplete: onComplete,
    ),
  );
}

/// AI Project Setup Wizard - generates phases, tasks, and budget items from project info
class AiProjectSetupWizard extends StatefulWidget {
  final Project project;
  final String workspaceId;
  final String? initialWorkflowTemplateId;
  final VoidCallback? onComplete;

  /// When provided, skips generation and opens directly on the Review step.
  final AiProjectPlan? initialPlan;

  const AiProjectSetupWizard({
    super.key,
    required this.project,
    required this.workspaceId,
    this.initialWorkflowTemplateId,
    this.onComplete,
    this.initialPlan,
  });

  @override
  State<AiProjectSetupWizard> createState() => _AiProjectSetupWizardState();
}

class _AiProjectSetupWizardState extends State<AiProjectSetupWizard> {
  final _pageController = PageController();
  final _descriptionController = TextEditingController();
  int _currentStep = 0;
  static const int _totalSteps = 3;

  // Step 1 state
  bool _isGenerating = false;
  bool _isCancelled = false;
  bool _isStartingBackgroundGeneration = false;
  bool _isLoadingWorkflowTemplates = false;
  bool _isSeedingWorkflowTemplates = false;
  List<WorkflowTemplate> _workflowTemplates = const [];
  String? _selectedWorkflowTemplateId;

  // Step 2 state - review
  AiProjectPlan? _plan;
  String _currentProvider = '';
  String _currentStatus = '';
  String _streamedText = '';
  String _pendingStreamedText = '';
  Timer? _streamUpdateTimer;
  String? _successProvider;
  DateTime? _loadingStartTime;
  final Map<String, bool> _expandedPhases = {};

  // Step 3 state - import
  DateTime _startDate = DateTime.now();
  bool _isImporting = false;
  bool _importComplete = false;
  int _importedPhases = 0;
  int _importedTasks = 0;
  int _importedBudgetItems = 0;
  int _importedProperties = 0;

  static const _steps = [
    AiStepConfig(
      number: 1,
      title: 'Review & Generate',
      subtitle: 'Confirm project info and generate a plan',
      icon: Icons.description,
    ),
    AiStepConfig(
      number: 2,
      title: 'Review Plan',
      subtitle: 'Review and customize the generated plan',
      icon: Icons.checklist,
    ),
    AiStepConfig(
      number: 3,
      title: 'Import',
      subtitle: 'Import the plan into your project',
      icon: Icons.download,
    ),
  ];

  List<String> get _thinkingMessages {
    final style =
        context.read<WorkspaceProvider>().activeWorkspace?.aiPersonaStyle;
    return getPersonaThinkingMessages(style).isNotEmpty
        ? getPersonaThinkingMessages(style)
        : [
            'Designing project phases...',
            'Creating task sequences...',
            'Estimating costs and materials...',
            'Building task dependencies...',
            'Generating checklists...',
            'Optimizing construction sequencing...',
          ];
  }

  // Currency formatting
  String get _currencyCode => context.read<WorkspaceProvider>().currencyCode;
  String _formatCurrency(double amount) =>
      CurrencyUtils.formatCurrency(amount, _currencyCode);

  @override
  void initState() {
    super.initState();
    _descriptionController.text = widget.project.description ?? '';
    _loadWorkflowTemplates();

    // If a pre-loaded plan was provided, jump straight to the review step
    if (widget.initialPlan != null) {
      _plan = widget.initialPlan;
      for (final phase in widget.initialPlan!.phases) {
        _expandedPhases[phase.tempId] = true;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _goToStep(1));
    }
  }

  @override
  void dispose() {
    _streamUpdateTimer?.cancel();
    _pageController.dispose();
    _descriptionController.dispose();
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

  void _goToStep(int step) {
    setState(() => _currentStep = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _loadWorkflowTemplates() async {
    setState(() => _isLoadingWorkflowTemplates = true);
    try {
      final templates = await ServiceLocator.workflowTemplateService
          .getTemplatesOnce(widget.workspaceId);
      if (!mounted) return;
      final hasInitial = widget.initialWorkflowTemplateId != null &&
          templates.any((t) => t.id == widget.initialWorkflowTemplateId);
      setState(() {
        _workflowTemplates = templates;
        if (_selectedWorkflowTemplateId == null && hasInitial) {
          _selectedWorkflowTemplateId = widget.initialWorkflowTemplateId;
        }
        _isLoadingWorkflowTemplates = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingWorkflowTemplates = false);
    }
  }

  Future<void> _seedCoreWorkflowTemplates() async {
    final createdBy = context.read<AuthProvider>().appUser?.id ?? '';
    if (createdBy.isEmpty) return;

    setState(() => _isSeedingWorkflowTemplates = true);
    try {
      await ServiceLocator.workflowTemplateService.initializeCoreTemplates(
        workspaceId: widget.workspaceId,
        createdBy: createdBy,
      );
      await _loadWorkflowTemplates();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Core workflow templates generated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate templates: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSeedingWorkflowTemplates = false);
      }
    }
  }

  Future<void> _generatePlan() async {
    setState(() {
      _isGenerating = true;
      _isCancelled = false;
      _loadingStartTime = DateTime.now();
      _currentProvider = '';
      _currentStatus = 'Initializing...';
      _streamedText = '';
      _pendingStreamedText = '';
    });

    _goToStep(1);

    try {
      final selectedWorkflowTemplate = _selectedWorkflowTemplate;

      final aiService = AiService();
      final plan = await aiService.generateProjectPlan(
        projectName: widget.project.name,
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        jobType: widget.project.jobType?.displayName,
        address:
            widget.project.address.isNotEmpty ? widget.project.address : null,
        projectContext: AiProjectContext(
          projectName: widget.project.name,
          location:
              widget.project.address.isNotEmpty ? widget.project.address : null,
          jobType: widget.project.jobType?.displayName,
          estimatedBudget: widget.project.estimatedBudget,
          materialMarkupPercent: widget.project.materialMarkupPercent,
          laborMarkupPercent: widget.project.laborMarkupPercent,
        ),
        workflowTemplateName: selectedWorkflowTemplate?.name,
        workflowTemplateDescription: selectedWorkflowTemplate?.description,
        workflowTemplateMarkdown: selectedWorkflowTemplate?.workflowMarkdown,
        workflowTemplateSchema: selectedWorkflowTemplate?.workflowSchema,
        persona: context.read<WorkspaceProvider>().aiPersonaContext,
        onProgress: (provider, status) {
          if (!_isCancelled && mounted) {
            setState(() {
              _currentProvider = provider;
              _currentStatus = status;
            });
          }
        },
        onStream: _handleStreamUpdate,
      );

      if (!_isCancelled && mounted) {
        setState(() {
          _plan = plan;
          _isGenerating = false;
          _successProvider = _currentProvider;
          _streamedText = _pendingStreamedText;
          // Expand all phases by default
          for (final phase in plan.phases) {
            _expandedPhases[phase.tempId] = true;
          }
        });
      }
    } catch (e) {
      if (!_isCancelled && mounted) {
        setState(() {
          _isGenerating = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'generating plan'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
        _goToStep(0);
      }
    }
  }

  void _cancelGeneration() {
    setState(() {
      _isCancelled = true;
      _isGenerating = false;
    });
    _goToStep(0);
  }

  Future<void> _generateInBackground() async {
    if (_isStartingBackgroundGeneration) return;
    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.appUser?.id;
    if (userId == null) return;

    try {
      setState(() => _isStartingBackgroundGeneration = true);
      await AiGenerationService.instance.generateInBackground(
        project: widget.project,
        workspaceId: widget.workspaceId,
        userId: userId,
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        workflowTemplate: _selectedWorkflowTemplate,
        persona: context.read<WorkspaceProvider>().aiPersonaContext,
        currency: context.read<WorkspaceProvider>().currencyCode,
      );

      if (!mounted) return;
      // Close the wizard — user will be notified when done
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Generating plan in the background. We\'ll notify you when it\'s ready.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start background generation: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isStartingBackgroundGeneration = false);
      }
    }
  }

  Future<void> _restartInBackground() async {
    if (_isStartingBackgroundGeneration) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restart in background?'),
        content: const Text(
          'The current streamed run cannot be transferred mid-generation yet. '
          'FieldFleet can close this window and start a fresh background job instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep Current Run'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restart in Background'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await _generateInBackground();
  }

  // Count selected items
  int get _selectedTaskCount {
    if (_plan == null) return 0;
    return _plan!.phases.fold(
      0,
      (sum, phase) => sum + phase.tasks.where((t) => t.isSelected).length,
    );
  }

  int get _selectedBudgetItemCount {
    if (_plan == null) return 0;
    return _plan!.phases.fold(
      0,
      (sum, phase) =>
          sum + phase.budgetItems.where((bi) => bi.isSelected).length,
    );
  }

  double get _totalEstimatedCost {
    if (_plan == null) return 0;
    return _plan!.phases.fold(
      0.0,
      (sum, phase) =>
          sum +
          phase.budgetItems
              .where((bi) => bi.isSelected)
              .fold(0.0, (s, bi) => s + bi.totalPrice),
    );
  }

  int get _selectedPropertyCount {
    if (_plan == null) return 0;
    return _plan!.properties.where((p) => p.isSelected).length;
  }

  WorkflowTemplate? get _selectedWorkflowTemplate {
    for (final template in _workflowTemplates) {
      if (template.id == _selectedWorkflowTemplateId) {
        return template;
      }
    }
    return null;
  }

  String get _personaAvatarPath {
    final ws = context.read<WorkspaceProvider>().activeWorkspace;
    final slug = ws?.aiPersonaAvatar ?? 'hard_hat';
    return kPersonaAvatars[slug] ?? 'assets/images/avatars/robot.png';
  }

  String get _personaName {
    final ws = context.read<WorkspaceProvider>().activeWorkspace;
    return ws?.aiPersonaName?.isNotEmpty == true
        ? ws!.aiPersonaName!
        : 'AI Assistant';
  }

  Future<void> _showWorkflowTemplatePreview(WorkflowTemplate template) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(template.name),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: SelectableText(
              template.workflowMarkdown,
              style: const TextStyle(fontSize: 13, height: 1.45),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _selectAll() {
    if (_plan == null) return;
    setState(() {
      for (final phase in _plan!.phases) {
        for (final task in phase.tasks) {
          task.isSelected = true;
        }
        for (final bi in phase.budgetItems) {
          bi.isSelected = true;
        }
      }
      for (final prop in _plan!.properties) {
        prop.isSelected = true;
      }
    });
  }

  void _deselectAll() {
    if (_plan == null) return;
    setState(() {
      for (final phase in _plan!.phases) {
        for (final task in phase.tasks) {
          task.isSelected = false;
        }
        for (final bi in phase.budgetItems) {
          bi.isSelected = false;
        }
      }
      for (final prop in _plan!.properties) {
        prop.isSelected = false;
      }
    });
  }

  Future<void> _importPlan() async {
    if (_plan == null) return;

    setState(() {
      _isImporting = true;
      _importedPhases = 0;
      _importedTasks = 0;
      _importedBudgetItems = 0;
      _importedProperties = 0;
    });

    _goToStep(2);

    try {
      final taskService = ServiceLocator.taskService;
      final budgetService = ServiceLocator.budgetService;
      final projectId = widget.project.id;
      final workspaceId = widget.workspaceId;

      // Map temp IDs to real IDs for dependency resolution
      final tempToRealTaskId = <String, String>{};
      final tempToRealBudgetGroupId = <String, String>{};

      // Get starting sort order for budget items
      var budgetSortOrder = await budgetService.getNextSortOrder(
        null,
        projectId,
      );

      for (final phase in _plan!.phases) {
        // 1. Create phase summary task
        final phaseTask = await taskService.createTask(
          workspaceId: workspaceId,
          projectId: projectId,
          title: phase.name,
          description: phase.description,
          taskType: TaskType.summary,
          startDate: _startDate,
          priority: 'medium',
        );
        tempToRealTaskId[phase.tempId] = phaseTask.id;
        _importedPhases++;

        // 2. Create tasks under this phase
        for (final task in phase.tasks.where((t) => t.isSelected)) {
          final createdTask = await taskService.createTask(
            workspaceId: workspaceId,
            projectId: projectId,
            title: task.title,
            description: task.description,
            taskType: TaskType.standard,
            parentId: phaseTask.id,
            startDate: _startDate,
            estimatedDuration: task.estimatedDuration,
            priority: task.priority,
          );
          tempToRealTaskId[task.tempId] = createdTask.id;

          // 3. Add checklist items
          for (final item in task.checklistItems) {
            await taskService.addChecklistItem(createdTask.id, item);
          }

          _importedTasks++;
          if (mounted) setState(() {});
        }

        // 4. Create budget item group for this phase
        final selectedBudgetItems =
            phase.budgetItems.where((bi) => bi.isSelected).toList();
        if (selectedBudgetItems.isNotEmpty) {
          final now = DateTime.now();
          final groupId = await budgetService.createBudgetItem(
            BudgetItem(
              id: '',
              workspaceId: workspaceId,
              projectId: projectId,
              hierarchyLevel: 0,
              sortOrder: budgetSortOrder++,
              name: phase.name,
              itemType: BudgetItemType.group,
              approvedPrice: 0,
              projectedCost: 0,
              createdAt: now,
              updatedAt: now,
            ),
          );
          tempToRealBudgetGroupId[phase.tempId] = groupId;

          // 5. Create budget items under group
          var itemSortOrder = await budgetService.getNextSortOrder(
            groupId,
            projectId,
          );
          for (final bi in selectedBudgetItems) {
            await budgetService.createBudgetItem(
              BudgetItem(
                id: '',
                workspaceId: workspaceId,
                projectId: projectId,
                parentId: groupId,
                hierarchyLevel: 1,
                sortOrder: itemSortOrder++,
                name: bi.name,
                quantity: bi.quantity,
                unit: bi.unit,
                unitCost: bi.unitCost,
                unitPrice: bi.unitPrice,
                approvedPrice: bi.totalPrice,
                projectedCost: bi.totalCost,
                itemType: BudgetItemType.item,
                createdAt: now,
                updatedAt: now,
              ),
            );
            _importedBudgetItems++;
            if (mounted) setState(() {});
          }
        }
      }

      // 6. Second pass: update task predecessor IDs (temp → real)
      for (final phase in _plan!.phases) {
        for (final task in phase.tasks.where((t) => t.isSelected)) {
          if (task.predecessorTempIds.isNotEmpty) {
            final realPredecessorIds = task.predecessorTempIds
                .map((tempId) => tempToRealTaskId[tempId])
                .where((id) => id != null)
                .cast<String>()
                .toList();

            if (realPredecessorIds.isNotEmpty) {
              final realTaskId = tempToRealTaskId[task.tempId];
              if (realTaskId != null) {
                await taskService.updateTask(
                  taskId: realTaskId,
                  predecessorIds: realPredecessorIds,
                );
              }
            }
          }
        }
      }

      // 7. Create properties for emergency/restoration jobs
      final selectedProperties =
          _plan!.properties.where((p) => p.isSelected).toList();
      if (selectedProperties.isNotEmpty) {
        final propertyService = ServiceLocator.propertyService;
        final areaService = ServiceLocator.areaService;
        final now = DateTime.now();

        for (final prop in selectedProperties) {
          final propertyId = await propertyService.createProperty(
            Property(
              id: '',
              workspaceId: workspaceId,
              projectId: projectId,
              name: prop.name,
              identifier: prop.identifier,
              floor: prop.floor,
              createdAt: now,
              updatedAt: now,
            ),
          );

          // Create areas for this property
          for (final areaName in prop.areas) {
            await areaService.createArea(
              Area(
                id: '',
                workspaceId: workspaceId,
                projectId: projectId,
                propertyId: propertyId,
                name: areaName,
                createdAt: now,
                updatedAt: now,
              ),
            );
          }

          _importedProperties++;
          if (mounted) setState(() {});
        }
      }

      if (mounted) {
        setState(() {
          _isImporting = false;
          _importComplete = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isImporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'importing plan'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
            children: [
              _buildStep1ReviewGenerate(),
              _buildStep2ReviewPlan(),
              _buildStep3Import(),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 1: Review & Generate
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep1ReviewGenerate() {
    final theme = Theme.of(context);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // AI disclaimer
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.secondarySurface,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: AppColors.warningDark,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'AI will generate phases, tasks, and budget items based on your project info. You can review and customize everything before importing.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.warningDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Project info cards
                Text(
                  'Project Information',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _buildInfoCard(
                  'Project Name',
                  widget.project.name,
                  Icons.folder,
                ),
                if (widget.project.jobType != null)
                  _buildInfoCard(
                    'Job Type',
                    widget.project.jobType!.displayName,
                    Icons.work,
                  ),
                if (widget.project.address.isNotEmpty)
                  _buildInfoCard(
                    'Address',
                    AddressFormatter.condense(widget.project.address),
                    Icons.location_on,
                  ),
                if (widget.project.estimatedBudget != null)
                  _buildInfoCard(
                    'Estimated Budget',
                    _formatCurrency(widget.project.estimatedBudget!),
                    Icons.attach_money,
                  ),

                const SizedBox(height: 24),

                // Editable description
                Text(
                  'Description',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Add or edit the project description to help AI generate a better plan.',
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.65),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _descriptionController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText:
                        'e.g., Full kitchen renovation including cabinets, countertops, flooring, and plumbing fixtures...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Workflow Template (Optional)',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Use a workspace workflow template as a baseline and let AI tailor it to this project.',
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.65),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                if (_isLoadingWorkflowTemplates || _isSeedingWorkflowTemplates)
                  const LinearProgressIndicator(minHeight: 2)
                else if (_workflowTemplates.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.secondarySurface,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No workflow templates available in this workspace.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.65),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _seedCoreWorkflowTemplates,
                              icon: const Icon(Icons.auto_fix_high, size: 16),
                              label: const Text('Generate Core Templates'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.secondaryDark,
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _loadWorkflowTemplates,
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Refresh'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                else
                  DropdownButtonFormField<String?>(
                    borderRadius: AppRadius.cardRadius,
                    initialValue: _selectedWorkflowTemplateId,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          'None (Generate from project context only)',
                        ),
                      ),
                      ..._workflowTemplates.map((template) {
                        return DropdownMenuItem<String?>(
                          value: template.id,
                          child: Text(template.name),
                        );
                      }),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedWorkflowTemplateId = value;
                      });
                    },
                  ),
                if (_selectedWorkflowTemplateId != null) ...[
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final selected = _selectedWorkflowTemplate;
                      if (selected == null) return const SizedBox.shrink();
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.secondarySurface,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: Text(
                          selected.description ?? 'No description provided.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.65),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        final selected = _selectedWorkflowTemplate;
                        if (selected != null) {
                          _showWorkflowTemplatePreview(selected);
                        }
                      },
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: const Text('Preview Template'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Bottom bar
        Container(
          padding: const EdgeInsets.all(AppSpacing.base),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(top: BorderSide(color: AppColors.cardBorder)),
          ),
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _isStartingBackgroundGeneration
                    ? null
                    : _generateInBackground,
                icon: const Icon(Icons.notifications_active_outlined, size: 18),
                label: const Text('Generate in Background'),
              ),
              FilledButton.icon(
                onPressed: _generatePlan,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Generate Plan'),
                style: FilledButton.styleFrom(
                  foregroundColor: AppColors.secondaryDark,
                  backgroundColor: AppColors.secondarySurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon,
              size: 18,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.65)),
          const SizedBox(width: 10),
          Text(
            '$label: ',
            style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.65),
                fontSize: 14),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 2: Review Plan
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep2ReviewPlan() {
    if (_isGenerating) {
      return AiLoadingState(
        currentProvider: _currentProvider,
        currentStatus: _currentStatus,
        loadingStartTime: _loadingStartTime,
        thinkingMessages: _thinkingMessages,
        streamedText: _streamedText,
        showStreamPreview: true,
        personaName: _personaName,
        personaAvatarAssetPath: _personaAvatarPath,
        onRunInBackground: _restartInBackground,
        backgroundActionLabel: 'Restart in Background',
        isBackgroundActionBusy: _isStartingBackgroundGeneration,
        onCancel: _cancelGeneration,
      );
    }

    if (_plan == null) {
      return const Center(child: Text('No plan generated yet.'));
    }

    final theme = Theme.of(context);

    return Column(
      children: [
        // Summary bar
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_successProvider != null) ...[
                    AiProviderBadge(
                      providerName: _successProvider!,
                      personaName: _personaName,
                      personaAvatarAssetPath: _personaAvatarPath,
                    ),
                    const SizedBox(width: 12),
                  ],
                  Text(
                    '${_plan!.phases.length} phases | $_selectedTaskCount tasks | $_selectedBudgetItemCount items | ',
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    _formatCurrency(_totalEstimatedCost),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: _selectAll,
                    child: const Text('Select All',
                        style: TextStyle(fontSize: 12)),
                  ),
                  TextButton(
                    onPressed: _deselectAll,
                    child: const Text(
                      'Deselect All',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      _goToStep(0);
                      _generatePlan();
                    },
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text(
                      'Regenerate',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Plan tree view
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.base),
            itemCount:
                _plan!.phases.length + (_plan!.properties.isNotEmpty ? 1 : 0),
            itemBuilder: (context, index) {
              if (index < _plan!.phases.length) {
                return _buildPhaseCard(_plan!.phases[index]);
              }
              // Properties section
              return _buildPropertiesCard();
            },
          ),
        ),

        // Bottom bar
        Container(
          padding: const EdgeInsets.all(AppSpacing.base),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(top: BorderSide(color: AppColors.cardBorder)),
          ),
          child: Row(
            children: [
              OutlinedButton(
                onPressed: () => _goToStep(0),
                child: const Text('Back'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed:
                    (_selectedTaskCount > 0 || _selectedBudgetItemCount > 0)
                        ? _importPlan
                        : null,
                icon: const Icon(Icons.download),
                label: const Text('Import Plan'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPhaseCard(AiProjectPhase phase) {
    final isExpanded = _expandedPhases[phase.tempId] ?? false;
    final taskCount = phase.tasks.where((t) => t.isSelected).length;
    final biCount = phase.budgetItems.where((bi) => bi.isSelected).length;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          // Phase header
          InkWell(
            onTap: () {
              setState(() {
                _expandedPhases[phase.tempId] = !isExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Icon(
                    isExpanded ? Icons.expand_more : Icons.chevron_right,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.65),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.folder_outlined,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          phase.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        if (phase.description != null)
                          Text(
                            phase.description!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.65),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.infoLight,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Text(
                      '$taskCount tasks',
                      style: TextStyle(fontSize: 11, color: AppColors.infoDark),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.successLight,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Text(
                      '$biCount items',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.successDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Expanded content
          if (isExpanded) ...[
            const Divider(height: 1),
            // Tasks
            if (phase.tasks.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.task_alt,
                      size: 14,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.45),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Tasks',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
              ...phase.tasks.map((task) => _buildTaskRow(task)),
            ],
            // Budget Items
            if (phase.budgetItems.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.receipt_long,
                      size: 14,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.45),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Budget Items',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
              ...phase.budgetItems.map((bi) => _buildBudgetItemRow(bi)),
            ],
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildTaskRow(AiPhaseTask task) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 2),
      child: Row(
        children: [
          Checkbox(
            value: task.isSelected,
            onChanged: (v) => setState(() => task.isSelected = v ?? false),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: TextStyle(
                    fontSize: 13,
                    decoration:
                        task.isSelected ? null : TextDecoration.lineThrough,
                    color: task.isSelected
                        ? null
                        : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.45),
                  ),
                ),
                if (task.checklistItems.isNotEmpty)
                  Text(
                    '${task.checklistItems.length} checklist items',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.45),
                    ),
                  ),
              ],
            ),
          ),
          if (task.estimatedDuration != null)
            Text(
              '${task.estimatedDuration!.toStringAsFixed(0)}h',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.65)),
            ),
          const SizedBox(width: 8),
          _buildPriorityBadge(task.priority),
        ],
      ),
    );
  }

  Widget _buildPriorityBadge(String priority) {
    final Color bgColor;
    final Color textColor;
    switch (priority) {
      case 'high':
        bgColor = AppColors.errorLight;
        textColor = AppColors.errorDark;
      case 'low':
        bgColor = AppColors.infoLight;
        textColor = AppColors.infoDark;
      default:
        bgColor = AppColors.secondarySurface;
        textColor = AppColors.warningDark;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        priority,
        style: TextStyle(
          fontSize: 10,
          color: textColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildBudgetItemRow(AiPhaseBudgetItem bi) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 2),
      child: Row(
        children: [
          Checkbox(
            value: bi.isSelected,
            onChanged: (v) => setState(() => bi.isSelected = v ?? false),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Text(
              bi.name,
              style: TextStyle(
                fontSize: 13,
                decoration: bi.isSelected ? null : TextDecoration.lineThrough,
                color: bi.isSelected
                    ? null
                    : Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.45),
              ),
            ),
          ),
          Text(
            '${bi.quantity.toStringAsFixed(bi.quantity == bi.quantity.roundToDouble() ? 0 : 1)} ${bi.unit}',
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.65)),
          ),
          const SizedBox(width: 12),
          Text(
            _formatCurrency(bi.totalPrice),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildPropertiesCard() {
    if (_plan!.properties.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Icon(
                  Icons.home_work,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Properties & Areas',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...(_plan!.properties.map(
            (prop) => Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Checkbox(
                    value: prop.isSelected,
                    onChanged: (v) =>
                        setState(() => prop.isSelected = v ?? false),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${prop.name} (${prop.identifier})',
                          style: TextStyle(
                            fontSize: 13,
                            decoration: prop.isSelected
                                ? null
                                : TextDecoration.lineThrough,
                            color: prop.isSelected
                                ? null
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.45),
                          ),
                        ),
                        if (prop.areas.isNotEmpty)
                          Text(
                            prop.areas.join(', '),
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.45),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (prop.floor != null)
                    Text(
                      'Floor: ${prop.floor}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.65),
                      ),
                    ),
                ],
              ),
            ),
          )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 3: Import
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStep3Import() {
    final theme = Theme.of(context);

    if (_plan == null) {
      return const Center(child: Text('Generate a plan first.'));
    }

    if (_importComplete) {
      return _buildImportSuccess(theme);
    }

    if (_isImporting) {
      return _buildImportProgress(theme);
    }

    // This step is shown before import starts (date picker + summary)
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Import Summary',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                // Start date picker
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 18,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.65),
                    ),
                    const SizedBox(width: 10),
                    const Text('Start Date:'),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _startDate,
                          firstDate: DateTime(2020),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365 * 5)),
                        );
                        if (picked != null) {
                          setState(() => _startDate = picked);
                        }
                      },
                      child: Text(
                        '${_startDate.month}/${_startDate.day}/${_startDate.year}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Summary
                _buildSummaryRow(
                  Icons.folder,
                  'Phases',
                  '${_plan!.phases.length}',
                ),
                _buildSummaryRow(
                  Icons.task_alt,
                  'Tasks',
                  '$_selectedTaskCount',
                ),
                _buildSummaryRow(
                  Icons.receipt_long,
                  'Budget Items',
                  '$_selectedBudgetItemCount',
                ),
                _buildSummaryRow(
                  Icons.attach_money,
                  'Total Estimated Cost',
                  _formatCurrency(_totalEstimatedCost),
                ),
                if (_selectedPropertyCount > 0)
                  _buildSummaryRow(
                    Icons.home_work,
                    'Properties',
                    '$_selectedPropertyCount',
                  ),
              ],
            ),
          ),
        ),

        // Bottom bar
        Container(
          padding: const EdgeInsets.all(AppSpacing.base),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(top: BorderSide(color: AppColors.cardBorder)),
          ),
          child: Row(
            children: [
              OutlinedButton(
                onPressed: () => _goToStep(1),
                child: const Text('Back'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _importPlan,
                icon: const Icon(Icons.download),
                label: const Text('Import'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon,
              size: 18,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.65)),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 14)),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildImportProgress(ThemeData theme) {
    final total = _plan!.phases.length +
        _selectedTaskCount +
        _selectedBudgetItemCount +
        _selectedPropertyCount;
    final done = _importedPhases +
        _importedTasks +
        _importedBudgetItems +
        _importedProperties;
    final progress = total > 0 ? done / total : 0.0;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(value: progress, strokeWidth: 6),
            ),
            const SizedBox(height: 24),
            Text(
              'Importing...',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$_importedPhases phases, $_importedTasks tasks, $_importedBudgetItems budget items',
              style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.65)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportSuccess(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.successLight,
              ),
              child: Icon(
                Icons.check_circle,
                size: 64,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Import Complete!',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '$_importedPhases phases, $_importedTasks tasks, $_importedBudgetItems budget items created',
              style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.65),
                  fontSize: 14),
              textAlign: TextAlign.center,
            ),
            if (_importedProperties > 0) ...[
              const SizedBox(height: 4),
              Text(
                '$_importedProperties properties created',
                style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.65),
                    fontSize: 14),
              ),
            ],
            const SizedBox(height: 24),
            if (_importedTasks > 0)
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  showTaskSchedulerWizard(
                    context,
                    project: widget.project,
                    workspaceId: widget.workspaceId,
                  );
                },
                icon: const Icon(Icons.auto_fix_high,
                    color: AppColors.secondaryDark),
                label: const Text('Auto-assign Team'),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                widget.onComplete?.call();
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.arrow_forward),
              label: Text(
                  'Go to ${singularProjectTerminology(context.read<WorkspaceProvider>().projectTerminology)}'),
            ),
          ],
        ),
      ),
    );
  }
}
