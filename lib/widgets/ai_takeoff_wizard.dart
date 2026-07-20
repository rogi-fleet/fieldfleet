import 'dart:async';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/budget_item.dart';
import '../models/project.dart';
import '../providers/workspace_provider.dart';
import '../services/service_locator.dart';
import '../services/ai_service.dart';
import '../utils/app_toast.dart';
import '../utils/currency_utils.dart';
import 'ai/ai_wizard_shared.dart';
import 'ai/ai_wizard_dialog.dart';
import 'ai_persona_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../theme/theme.dart';

/// Mock budget item for AI-generated suggestions
class _MockBudgetItem {
  final String name;
  final double quantity;
  final String unit;
  final double unitCost;
  final double unitPrice;
  bool isSelected;

  _MockBudgetItem({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.unitCost,
    required this.unitPrice,
    this.isSelected = true,
  });

  double get totalCost => quantity * unitCost;
  double get totalPrice => quantity * unitPrice;
}

/// AI Takeoff Wizard for generating budget items from text/image input
class AiTakeoffWizard extends StatefulWidget {
  final String projectId;
  final String workspaceId;
  final String? parentId;
  final VoidCallback? onComplete;
  final Project? project; // Optional project for context

  const AiTakeoffWizard({
    super.key,
    required this.projectId,
    required this.workspaceId,
    this.parentId,
    this.onComplete,
    this.project,
  });

  @override
  State<AiTakeoffWizard> createState() => _AiTakeoffWizardState();
}

class _AiTakeoffWizardState extends State<AiTakeoffWizard> {
  final _pageController = PageController();
  final _descriptionController = TextEditingController();
  int _currentStep = 0;
  static const int _totalSteps = 3;
  bool _isLoading = false;
  bool _isImporting = false;
  bool _isCancelled = false;
  List<_MockBudgetItem> _generatedItems = [];
  String? _selectedCategory;

  // AI loading state
  String _currentProvider = '';
  String _currentStatus = '';
  String _streamedText = '';
  String _pendingStreamedText = '';
  Timer? _streamUpdateTimer;
  String? _successProvider;
  DateTime? _loadingStartTime;

  // PDF upload state
  Uint8List? _pdfBytes;
  String? _pdfFileName;

  // Quick category chips
  static const List<String> _categories = [
    'Kitchen',
    'Bathroom',
    'Electrical',
    'Plumbing',
    'HVAC',
    'Flooring',
    'Painting',
    'Roofing',
    'General',
  ];

  // Mock AI responses
  static final Map<String, List<_MockBudgetItem>> _mockResponses = {
    'kitchen': [
      _MockBudgetItem(
        name: 'Kitchen Cabinets',
        quantity: 1,
        unit: 'set',
        unitCost: 3500,
        unitPrice: 4500,
      ),
      _MockBudgetItem(
        name: 'Countertops - Granite',
        quantity: 25,
        unit: 'sqft',
        unitCost: 45,
        unitPrice: 65,
      ),
      _MockBudgetItem(
        name: 'Kitchen Sink - Stainless',
        quantity: 1,
        unit: 'ea',
        unitCost: 250,
        unitPrice: 400,
      ),
      _MockBudgetItem(
        name: 'Faucet with Sprayer',
        quantity: 1,
        unit: 'ea',
        unitCost: 150,
        unitPrice: 250,
      ),
      _MockBudgetItem(
        name: 'Backsplash Tile',
        quantity: 20,
        unit: 'sqft',
        unitCost: 12,
        unitPrice: 25,
      ),
      _MockBudgetItem(
        name: 'Cabinet Installation Labor',
        quantity: 8,
        unit: 'hr',
        unitCost: 65,
        unitPrice: 95,
      ),
      _MockBudgetItem(
        name: 'Garbage Disposal',
        quantity: 1,
        unit: 'ea',
        unitCost: 120,
        unitPrice: 200,
      ),
    ],
    'bathroom': [
      _MockBudgetItem(
        name: 'Toilet - Standard',
        quantity: 1,
        unit: 'ea',
        unitCost: 250,
        unitPrice: 400,
      ),
      _MockBudgetItem(
        name: 'Vanity with Sink',
        quantity: 1,
        unit: 'ea',
        unitCost: 450,
        unitPrice: 700,
      ),
      _MockBudgetItem(
        name: 'Shower Tile',
        quantity: 50,
        unit: 'sqft',
        unitCost: 8,
        unitPrice: 18,
      ),
      _MockBudgetItem(
        name: 'Bathroom Fixtures Set',
        quantity: 1,
        unit: 'set',
        unitCost: 200,
        unitPrice: 350,
      ),
      _MockBudgetItem(
        name: 'Vanity Mirror',
        quantity: 1,
        unit: 'ea',
        unitCost: 80,
        unitPrice: 150,
      ),
      _MockBudgetItem(
        name: 'Plumbing Labor',
        quantity: 6,
        unit: 'hr',
        unitCost: 85,
        unitPrice: 125,
      ),
      _MockBudgetItem(
        name: 'Exhaust Fan',
        quantity: 1,
        unit: 'ea',
        unitCost: 75,
        unitPrice: 150,
      ),
    ],
    'electrical': [
      _MockBudgetItem(
        name: 'Electrical Outlets',
        quantity: 10,
        unit: 'ea',
        unitCost: 15,
        unitPrice: 35,
      ),
      _MockBudgetItem(
        name: 'Light Switches',
        quantity: 5,
        unit: 'ea',
        unitCost: 12,
        unitPrice: 30,
      ),
      _MockBudgetItem(
        name: 'Breaker Panel Upgrade',
        quantity: 1,
        unit: 'ea',
        unitCost: 800,
        unitPrice: 1200,
      ),
      _MockBudgetItem(
        name: 'Romex Wiring 12/2',
        quantity: 200,
        unit: 'ft',
        unitCost: 1.5,
        unitPrice: 3,
      ),
      _MockBudgetItem(
        name: 'Recessed Light Fixtures',
        quantity: 6,
        unit: 'ea',
        unitCost: 75,
        unitPrice: 150,
      ),
      _MockBudgetItem(
        name: 'Electrician Labor',
        quantity: 12,
        unit: 'hr',
        unitCost: 95,
        unitPrice: 140,
      ),
    ],
    'plumbing': [
      _MockBudgetItem(
        name: 'Water Heater 50 Gal',
        quantity: 1,
        unit: 'ea',
        unitCost: 650,
        unitPrice: 1000,
      ),
      _MockBudgetItem(
        name: 'PEX Piping',
        quantity: 100,
        unit: 'ft',
        unitCost: 2,
        unitPrice: 5,
      ),
      _MockBudgetItem(
        name: 'Shut-off Valves',
        quantity: 6,
        unit: 'ea',
        unitCost: 15,
        unitPrice: 35,
      ),
      _MockBudgetItem(
        name: 'Drain Lines',
        quantity: 50,
        unit: 'ft',
        unitCost: 8,
        unitPrice: 18,
      ),
      _MockBudgetItem(
        name: 'Plumber Labor',
        quantity: 10,
        unit: 'hr',
        unitCost: 85,
        unitPrice: 125,
      ),
    ],
    'hvac': [
      _MockBudgetItem(
        name: 'AC Unit 3 Ton',
        quantity: 1,
        unit: 'ea',
        unitCost: 2500,
        unitPrice: 4000,
      ),
      _MockBudgetItem(
        name: 'Furnace',
        quantity: 1,
        unit: 'ea',
        unitCost: 1800,
        unitPrice: 3000,
      ),
      _MockBudgetItem(
        name: 'Ductwork',
        quantity: 100,
        unit: 'lf',
        unitCost: 12,
        unitPrice: 25,
      ),
      _MockBudgetItem(
        name: 'Thermostat - Smart',
        quantity: 1,
        unit: 'ea',
        unitCost: 150,
        unitPrice: 300,
      ),
      _MockBudgetItem(
        name: 'HVAC Labor',
        quantity: 16,
        unit: 'hr',
        unitCost: 90,
        unitPrice: 135,
      ),
    ],
    'flooring': [
      _MockBudgetItem(
        name: 'Hardwood Flooring',
        quantity: 500,
        unit: 'sqft',
        unitCost: 6,
        unitPrice: 12,
      ),
      _MockBudgetItem(
        name: 'Underlayment',
        quantity: 500,
        unit: 'sqft',
        unitCost: 0.5,
        unitPrice: 1,
      ),
      _MockBudgetItem(
        name: 'Baseboards',
        quantity: 200,
        unit: 'lf',
        unitCost: 2,
        unitPrice: 5,
      ),
      _MockBudgetItem(
        name: 'Floor Installation Labor',
        quantity: 24,
        unit: 'hr',
        unitCost: 55,
        unitPrice: 85,
      ),
    ],
    'painting': [
      _MockBudgetItem(
        name: 'Interior Paint - Premium',
        quantity: 10,
        unit: 'gal',
        unitCost: 45,
        unitPrice: 65,
      ),
      _MockBudgetItem(
        name: 'Primer',
        quantity: 5,
        unit: 'gal',
        unitCost: 25,
        unitPrice: 40,
      ),
      _MockBudgetItem(
        name: 'Painting Supplies',
        quantity: 1,
        unit: 'set',
        unitCost: 100,
        unitPrice: 150,
      ),
      _MockBudgetItem(
        name: 'Painter Labor',
        quantity: 32,
        unit: 'hr',
        unitCost: 45,
        unitPrice: 70,
      ),
    ],
    'roofing': [
      _MockBudgetItem(
        name: 'Architectural Shingles',
        quantity: 30,
        unit: 'sq',
        unitCost: 95,
        unitPrice: 150,
      ),
      _MockBudgetItem(
        name: 'Underlayment Felt',
        quantity: 30,
        unit: 'roll',
        unitCost: 25,
        unitPrice: 40,
      ),
      _MockBudgetItem(
        name: 'Flashing',
        quantity: 50,
        unit: 'lf',
        unitCost: 3,
        unitPrice: 8,
      ),
      _MockBudgetItem(
        name: 'Ridge Vent',
        quantity: 40,
        unit: 'lf',
        unitCost: 5,
        unitPrice: 12,
      ),
      _MockBudgetItem(
        name: 'Roofing Labor',
        quantity: 40,
        unit: 'hr',
        unitCost: 55,
        unitPrice: 85,
      ),
    ],
    'general': [
      _MockBudgetItem(
        name: 'General Labor',
        quantity: 20,
        unit: 'hr',
        unitCost: 45,
        unitPrice: 70,
      ),
      _MockBudgetItem(
        name: 'Materials - Misc',
        quantity: 1,
        unit: 'lot',
        unitCost: 500,
        unitPrice: 750,
      ),
      _MockBudgetItem(
        name: 'Equipment Rental',
        quantity: 1,
        unit: 'day',
        unitCost: 150,
        unitPrice: 225,
      ),
      _MockBudgetItem(
        name: 'Permits & Fees',
        quantity: 1,
        unit: 'ea',
        unitCost: 300,
        unitPrice: 350,
      ),
      _MockBudgetItem(
        name: 'Dumpster Rental',
        quantity: 1,
        unit: 'ea',
        unitCost: 400,
        unitPrice: 500,
      ),
    ],
  };

  // Step configuration
  static const List<AiStepConfig> _steps = [
    AiStepConfig(
      number: 1,
      title: 'Describe Your Needs',
      subtitle: 'Tell us what you\'re working on',
      icon: Icons.edit_note,
    ),
    AiStepConfig(
      number: 2,
      title: 'Review Generated Items',
      subtitle: 'Select items to import into your budget',
      icon: Icons.auto_awesome,
    ),
    AiStepConfig(
      number: 3,
      title: 'Import to Budget',
      subtitle: 'Confirm and add items to your project',
      icon: Icons.check_circle,
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
            'Analyzing project requirements...',
            'Estimating quantities...',
            'Calculating material costs...',
            'Adding labor estimates...',
            'Organizing line items...',
            'Finalizing budget items...',
          ];
  }

  @override
  void initState() {
    super.initState();
    // Pre-fill description with project description if available
    if (widget.project?.description != null &&
        widget.project!.description!.isNotEmpty) {
      _descriptionController.text = widget.project!.description!;
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
      _generateItems();
    } else if (_currentStep < _totalSteps - 1) {
      _goToStep(_currentStep + 1);
    } else {
      _importItems();
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
      _isLoading = false;
      _currentProvider = '';
      _currentStatus = '';
      _loadingStartTime = null;
    });
    // Go back to input step
    _goToStep(0);
  }

  Future<void> _generateItems() async {
    final description = _descriptionController.text;

    if (description.isEmpty && _selectedCategory == null && _pdfBytes == null) {
      showWarningToast(
        context,
        'Please enter a description, select a category, or upload a PDF',
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _isCancelled = false;
      _currentProvider = '';
      _currentStatus = 'Initializing...';
      _streamedText = '';
      _pendingStreamedText = '';
      _successProvider = null;
      _loadingStartTime = DateTime.now();
    });

    // Navigate to step 2 immediately to show the loading animation
    _goToStep(1);

    try {
      // Build project context if project is available
      AiProjectContext? projectContext;
      final workspaceProvider = context.read<WorkspaceProvider>();
      final currencyCode = workspaceProvider.currencyCode;

      if (widget.project != null) {
        final p = widget.project!;
        projectContext = AiProjectContext(
          projectName: p.name,
          location: p.address,
          jobType: p.jobType?.displayName,
          estimatedBudget: p.estimatedBudget,
          materialMarkupPercent: p.materialMarkupPercent,
          laborMarkupPercent: p.laborMarkupPercent,
          currency: currencyCode,
        );
      } else {
        // Even without a project, pass the currency from workspace
        projectContext = AiProjectContext(currency: currencyCode);
      }

      // Try to get items from AI service
      final aiService = AiService();
      final aiItems = await aiService.generateBudgetItems(
        description: description,
        category: _selectedCategory,
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
        pdfBase64: _pdfBytes != null ? base64Encode(_pdfBytes!) : null,
      );

      // Check if cancelled
      if (_isCancelled) return;

      // Convert AI items to display items
      _generatedItems = aiItems
          .map(
            (item) => _MockBudgetItem(
              name: item.name,
              quantity: item.quantity,
              unit: item.unit,
              unitCost: item.unitCost,
              unitPrice: item.unitPrice,
              isSelected: true,
            ),
          )
          .toList();

      _successProvider = _currentProvider;

      if (mounted) {
        setState(() {
          _isLoading = false;
          _streamedText = _pendingStreamedText;
          _loadingStartTime = null;
        });
      }
    } catch (e) {
      debugPrint('AI generation failed, using fallback: $e');

      // Check if cancelled
      if (_isCancelled) return;

      // Fallback to mock data if AI fails
      _useFallbackMockData(description.toLowerCase());

      if (mounted) {
        showWarningToast(context, 'Using template items (AI unavailable)');
        setState(() {
          _isLoading = false;
          _loadingStartTime = null;
          _successProvider = 'Template';
        });
        _goToStep(1);
      }
    }
  }

  void _useFallbackMockData(String description) {
    // Determine which mock response to use
    String matchedCategory = 'general';

    // Check selected category first
    if (_selectedCategory != null) {
      matchedCategory = _selectedCategory!.toLowerCase();
    }

    // Then check description keywords
    for (final category in _mockResponses.keys) {
      if (description.contains(category)) {
        matchedCategory = category;
        break;
      }
    }

    // Get mock items and create fresh copies
    final mockItems =
        _mockResponses[matchedCategory] ?? _mockResponses['general']!;
    _generatedItems = mockItems
        .map(
          (item) => _MockBudgetItem(
            name: item.name,
            quantity: item.quantity,
            unit: item.unit,
            unitCost: item.unitCost,
            unitPrice: item.unitPrice,
            isSelected: true,
          ),
        )
        .toList();
  }

  Future<void> _importItems() async {
    final selectedItems = _generatedItems
        .where((item) => item.isSelected)
        .toList();

    if (selectedItems.isEmpty) {
      showWarningToast(context, 'Please select at least one item to import');
      return;
    }

    setState(() => _isImporting = true);

    try {
      final budgetService = ServiceLocator.budgetService;
      final now = DateTime.now();
      int sortOrder = await budgetService.getNextSortOrder(
        widget.parentId,
        widget.projectId,
      );

      // Determine hierarchy level from parent
      int hierarchyLevel = 0;
      if (widget.parentId != null) {
        final parent = await budgetService.getBudgetItem(widget.parentId!);
        hierarchyLevel = (parent?.hierarchyLevel ?? 0) + 1;
      }

      for (final item in selectedItems) {
        final budgetItem = BudgetItem(
          id: '', // Will be assigned by Firestore
          workspaceId: widget.workspaceId,
          projectId: widget.projectId,
          parentId: widget.parentId,
          hierarchyLevel: hierarchyLevel,
          sortOrder: sortOrder++,
          name: item.name,
          quantity: item.quantity,
          unit: item.unit,
          unitCost: item.unitCost,
          unitPrice: item.unitPrice,
          approvedPrice: item.totalPrice,
          projectedCost: item.totalCost,
          itemType: BudgetItemType.item,
          createdAt: now,
          updatedAt: now,
        );

        await budgetService.createBudgetItem(budgetItem);
      }

      if (mounted) {
        showSuccessToast(
            context, 'Imported ${selectedItems.length} items to budget');
        widget.onComplete?.call();
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(
          context,
          UserFacingError.uiMessage(e, action: 'importing items'),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  void _selectAll(bool select) {
    setState(() {
      for (final item in _generatedItems) {
        item.isSelected = select;
      }
    });
  }

  double get _selectedTotalCost {
    return _generatedItems
        .where((item) => item.isSelected)
        .fold(0.0, (sum, item) => sum + item.totalCost);
  }

  double get _selectedTotalPrice {
    return _generatedItems
        .where((item) => item.isSelected)
        .fold(0.0, (sum, item) => sum + item.totalPrice);
  }

  int get _selectedCount {
    return _generatedItems.where((item) => item.isSelected).length;
  }

  // Currency formatting helpers
  String get _currencyCode => context.read<WorkspaceProvider>().currencyCode;
  String _formatCurrency(double amount) =>
      CurrencyUtils.formatCurrency(amount, _currencyCode);

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

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        // Header with step indicator
        AiWizardHeader(
          currentStep: _currentStep,
          totalSteps: _totalSteps,
          steps: _steps,
        ),

        // Step content
        Expanded(
          child: PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            onPageChanged: (index) => setState(() => _currentStep = index),
            children: [
              _buildStep1Input(),
              _buildStep2Review(),
              _buildStep3Import(),
            ],
          ),
        ),

        // Navigation buttons
        _buildNavigationBar(primaryColor),
      ],
    );
  }

  Widget _buildNavigationBar(Color primaryColor) {
    final isLastStep = _currentStep == _totalSteps - 1;
    final canProceed = _currentStep == 0
        ? (_descriptionController.text.isNotEmpty ||
              _selectedCategory != null ||
              _pdfBytes != null)
        : (_currentStep == 1 ? _selectedCount > 0 : true);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
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
          if (_currentStep == 1) ...[
            Text(
              '$_selectedCount selected',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(width: 16),
          ],
          FilledButton.icon(
            onPressed: (_isLoading || _isImporting || !canProceed)
                ? null
                : _nextStep,
            icon: (_isLoading || _isImporting)
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
                        ? Icons.download
                        : (_currentStep == 0
                              ? Icons.auto_awesome
                              : Icons.arrow_forward),
                  ),
            label: Text(
              _isLoading
                  ? 'Analyzing...'
                  : _isImporting
                  ? 'Importing...'
                  : isLastStep
                  ? 'Import Items'
                  : (_currentStep == 0 ? 'Generate Items' : 'Next'),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== STEP 1: INPUT ====================

  void _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );

    if (result != null && result.files.single.bytes != null) {
      setState(() {
        _pdfBytes = result.files.single.bytes;
        _pdfFileName = result.files.single.name;
      });
    }
  }

  Widget _buildStep1Input() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quick category chips
          const Text(
            'Quick Categories',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _categories.map((category) {
              final isSelected = _selectedCategory == category;
              return FilterChip(
                label: Text(category),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _selectedCategory = selected ? category : null;
                  });
                },
                avatar: isSelected ? const Icon(Icons.check, size: 18) : null,
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // PDF Upload
          const Text(
            'Upload a PDF Budget',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 12),
          if (_pdfFileName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Chip(
                avatar: const Icon(
                  Icons.picture_as_pdf,
                  size: 18,
                  color: Colors.red,
                ),
                label: Text(_pdfFileName!, overflow: TextOverflow.ellipsis),
                deleteIcon: const Icon(Icons.close, size: 18),
                onDeleted: () {
                  setState(() {
                    _pdfBytes = null;
                    _pdfFileName = null;
                  });
                },
              ),
            )
          else
            OutlinedButton.icon(
              onPressed: _pickPdf,
              icon: const Icon(Icons.upload_file),
              label: const Text('Select PDF File'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.r12),
                ),
              ),
            ),
          const SizedBox(height: 24),

          const SizedBox(height: 24),

          // Text description
          const Text(
            'Describe Your Project',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            maxLines: 5,
            decoration: InputDecoration(
              hintText:
                  'e.g., "Kitchen renovation with new cabinets, countertops, sink, and backsplash tile..."',
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 24),

          // AI disclaimer
          Container(
            padding: const EdgeInsets.all(AppSpacing.base),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(AppRadius.r12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                ClipOval(
                  child: Image.asset(
                    _personaAvatarPath,
                    width: 20,
                    height: 20,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$_personaName-Powered Takeoff',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Based on your input, we\'ll generate suggested budget items with quantities and pricing estimates.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blue.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== STEP 2: REVIEW ====================

  Widget _buildStep2Review() {
    if (_isLoading) {
      return AiLoadingState(
        currentProvider: _currentProvider,
        currentStatus: _currentStatus,
        loadingStartTime: _loadingStartTime,
        thinkingMessages: _thinkingMessages,
        streamedText: _streamedText,
        showStreamPreview: true,
        personaName: _personaName,
        personaAvatarAssetPath: _personaAvatarPath,
        onCancel: _cancelGeneration,
      );
    }

    return Column(
      children: [
        // Selection controls
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () => _selectAll(true),
                icon: const Icon(Icons.select_all, size: 18),
                label: const Text('Select All'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => _selectAll(false),
                icon: const Icon(Icons.deselect, size: 18),
                label: const Text('Deselect All'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () {
                  _goToStep(0);
                  _generateItems();
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Regenerate'),
              ),
              const Spacer(),
              // Provider badge
              if (_successProvider != null) ...[
                AiProviderBadge(
                  providerName: _successProvider!,
                  personaName: _personaName,
                  personaAvatarAssetPath: _personaAvatarPath,
                ),
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
                  'Est. Total: ${_formatCurrency(_selectedTotalPrice)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Items list
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.base),
            itemCount: _generatedItems.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = _generatedItems[index];
              return _buildItemCard(item);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildItemCard(_MockBudgetItem item) {
    return InkWell(
      onTap: () {
        setState(() => item.isSelected = !item.isSelected);
      },
      borderRadius: BorderRadius.circular(AppRadius.r12),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(
          color: item.isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.05)
              : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.r12),
          border: Border.all(
            color: item.isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade300,
            width: item.isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Checkbox(
              value: item.isSelected,
              onChanged: (value) {
                setState(() => item.isSelected = value ?? false);
              },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.quantity} ${item.unit} x ${_formatCurrency(item.unitPrice)}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatCurrency(item.totalPrice),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                Text(
                  'Cost: ${_formatCurrency(item.totalCost)}',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==================== STEP 3: IMPORT ====================

  Widget _buildStep3Import() {
    final selectedItems = _generatedItems
        .where((item) => item.isSelected)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary card
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(AppRadius.r12),
              border: Border.all(color: Colors.grey.shade200),
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
                _buildSummaryRow('Items to Import', '${selectedItems.length}'),
                _buildSummaryRow(
                  'Total Est. Cost',
                  _formatCurrency(_selectedTotalCost),
                ),
                _buildSummaryRow(
                  'Total Est. Price',
                  _formatCurrency(_selectedTotalPrice),
                ),
                _buildSummaryRow(
                  'Est. Profit',
                  _formatCurrency(_selectedTotalPrice - _selectedTotalCost),
                  highlight: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Item preview list
          Text(
            'Items to be added:',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 12),
          ...selectedItems.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item.name)),
                  Text(
                    _formatCurrency(item.totalPrice),
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Contextual AI suggestion
          _buildContextualSuggestion(selectedItems),
        ],
      ),
    );
  }

  Widget _buildContextualSuggestion(List<_MockBudgetItem> selectedItems) {
    // Build a contextual suggestion based on what's being imported
    String suggestion;
    final hasLabor = selectedItems.any(
      (i) => i.name.toLowerCase().contains('labor'),
    );
    final hasMaterial = selectedItems.any(
      (i) => !i.name.toLowerCase().contains('labor'),
    );
    final profit = _selectedTotalPrice - _selectedTotalCost;
    final marginPercent =
        _selectedTotalPrice > 0 ? (profit / _selectedTotalPrice * 100) : 0;

    if (marginPercent < 15) {
      suggestion =
          'Your profit margin is ${marginPercent.toStringAsFixed(0)}%, which is below the typical 15-20% range. Consider adjusting unit prices before importing.';
    } else if (hasLabor && !hasMaterial) {
      suggestion =
          'This takeoff only includes labor items. Consider adding material line items for a complete budget.';
    } else if (hasMaterial && !hasLabor) {
      suggestion =
          'No labor items detected. Consider adding installation or labor line items to capture the full project cost.';
    } else {
      suggestion =
          'Consider adding a contingency line item (typically 5-10% of total) for unexpected costs.';
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.tips_and_updates, color: Colors.amber.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Suggestion',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.amber.shade800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  suggestion,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.amber.shade700,
                  ),
                ),
              ],
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
          Text(label, style: TextStyle(color: Colors.grey.shade600)),
          Text(
            value,
            style: TextStyle(
              fontWeight: highlight ? FontWeight.bold : FontWeight.w500,
              color: highlight ? Colors.green.shade700 : null,
              fontSize: highlight ? 16 : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows the AI Takeoff wizard as a dialog
void showAiTakeoffWizard(
  BuildContext context, {
  required String projectId,
  required String workspaceId,
  String? parentId,
  VoidCallback? onComplete,
  Project? project,
}) {
  final ws = context.read<WorkspaceProvider>().activeWorkspace;
  final emoji = kPersonaAvatarEmojis[ws?.aiPersonaAvatar ?? 'hard_hat'] ?? '🤖';
  final avatarAssetPath =
      kPersonaAvatars[ws?.aiPersonaAvatar ?? 'hard_hat'] ??
      'assets/images/avatars/robot.png';
  final personaName = ws?.aiPersonaName?.isNotEmpty == true
      ? ws!.aiPersonaName!
      : 'AI Assistant';
  showAiWizardDialog(
    context,
    title: '$personaName Takeoff',
    personaEmoji: emoji,
    personaAvatarAssetPath: avatarAssetPath,
    width: 650,
    child: AiTakeoffWizard(
      projectId: projectId,
      workspaceId: workspaceId,
      parentId: parentId,
      onComplete: onComplete,
      project: project,
    ),
  );
}
