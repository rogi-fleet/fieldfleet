import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/budget_item.dart';
import '../models/document_template.dart';
import '../models/template_category.dart';
import '../services/service_locator.dart';
import '../services/supabase/budget_service.dart';
import '../theme/theme.dart';
import '../utils/user_facing_error.dart';
import 'budget_document_type_picker.dart';
import 'budget_item_selection_table.dart';

/// Full-screen wizard dialog for creating a document from budget items.
/// Step 1: Pick a document template
/// Step 2: Select budget items, see invoiced/remaining amounts, set amounts
/// Then navigates to CreateDocumentScreen with pre-populated data.
/// Data class returned by the wizard when using callback mode.
class BudgetDocumentWizardResult {
  final String templateId;
  final List<Map<String, dynamic>> lineItems;
  final List<String> selectedBudgetItemIds;
  final Map<String, double> budgetItemAmounts;

  const BudgetDocumentWizardResult({
    required this.templateId,
    required this.lineItems,
    required this.selectedBudgetItemIds,
    required this.budgetItemAmounts,
  });
}

class BudgetDocumentWizard extends StatefulWidget {
  final String projectId;
  final String workspaceId;
  final List<BudgetItem> budgetItems;
  final Set<String>? preSelectedItemIds;
  final TemplateCategory? defaultCategory;

  /// When provided, the wizard calls this instead of navigating away.
  final void Function(BudgetDocumentWizardResult result)? onCreateDocument;

  const BudgetDocumentWizard({
    super.key,
    required this.projectId,
    required this.workspaceId,
    required this.budgetItems,
    this.preSelectedItemIds,
    this.defaultCategory,
    this.onCreateDocument,
  });

  static Future<void> show(
    BuildContext context, {
    required String projectId,
    required String workspaceId,
    required List<BudgetItem> budgetItems,
    Set<String>? preSelectedItemIds,
    TemplateCategory? defaultCategory,
    void Function(BudgetDocumentWizardResult result)? onCreateDocument,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => BudgetDocumentWizard(
        projectId: projectId,
        workspaceId: workspaceId,
        budgetItems: budgetItems,
        preSelectedItemIds: preSelectedItemIds,
        defaultCategory: defaultCategory,
        onCreateDocument: onCreateDocument,
      ),
    );
  }

  @override
  State<BudgetDocumentWizard> createState() => _BudgetDocumentWizardState();
}

class _BudgetDocumentWizardState extends State<BudgetDocumentWizard> {
  final _pageController = PageController();
  SupabaseBudgetService get _budgetService =>
      ServiceLocator.budgetService as SupabaseBudgetService;

  DocumentTemplate? _selectedTemplate;
  Map<String, BudgetItemDocumentStatus>? _documentStatusMap;
  bool _isLoadingStatus = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadDocumentStatus();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadDocumentStatus() async {
    setState(() {
      _isLoadingStatus = true;
      _loadError = null;
    });
    try {
      final status = await _budgetService.getDocumentStatusForProject(
        widget.projectId,
        widget.workspaceId,
      );
      if (mounted) {
        setState(() {
          _documentStatusMap = status;
          _isLoadingStatus = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = UserFacingError.uiMessage(
            e,
            action: 'load document status',
          );
          _isLoadingStatus = false;
        });
      }
    }
  }

  void _onTemplateSelected(DocumentTemplate template) {
    setState(() {
      _selectedTemplate = template;
    });
    _pageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _onBackToTemplates() {
    _pageController.animateToPage(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _onCancel() {
    Navigator.of(context).pop();
  }

  void _onConfirm(Map<String, double> selectedItemAmounts) {
    if (_selectedTemplate == null) return;

    // Build line items from selected budget items
    final lineItems = <Map<String, dynamic>>[];
    final selectedIds = <String>[];

    for (final entry in selectedItemAmounts.entries) {
      final idx = widget.budgetItems.indexWhere((i) => i.id == entry.key);
      if (idx == -1) continue;
      final item = widget.budgetItems[idx];

      // Preserve the real quantity × unit price on the document line when we're
      // invoicing the full approved line (so a "1.5 hrs @ $95" line doesn't
      // collapse to "1 @ $142.50"). For a partial / progress amount that
      // doesn't equal qty × unit price, keep a single line at the selected
      // amount.
      final qty = item.approvedQuantity ?? item.quantity;
      final unitPrice = item.approvedUnitPrice ?? item.unitPrice;
      final fullLineTotal = qty * unitPrice;
      final useRealQty =
          qty > 0 && (entry.value - fullLineTotal).abs() < 0.005;

      lineItems.add({
        'description': item.name,
        'quantity': useRealQty ? qty : 1.0,
        'unit': item.unit,
        'rate': useRealQty ? unitPrice : entry.value,
        'amount': entry.value,
        'budgetItemId': item.id,
      });
      selectedIds.add(item.id);
    }

    Navigator.of(context).pop();

    if (widget.onCreateDocument != null) {
      widget.onCreateDocument!(
        BudgetDocumentWizardResult(
          templateId: _selectedTemplate!.id,
          lineItems: lineItems,
          selectedBudgetItemIds: selectedIds,
          budgetItemAmounts: selectedItemAmounts,
        ),
      );
    } else {
      context.go(
        '/documents/create?projectId=${widget.projectId}&templateId=${_selectedTemplate!.id}',
        extra: {
          'lineItems': lineItems,
          'selectedBudgetItemIds': selectedIds,
          'budgetItemAmounts': selectedItemAmounts,
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.r12),
          child: PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              // Step 1: Template picker
              BudgetDocumentTypePicker(
                onTemplateSelected: _onTemplateSelected,
                onCancel: _onCancel,
                defaultCategory: widget.defaultCategory,
              ),

              // Step 2: Item selection
              _buildItemSelectionPage(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemSelectionPage() {
    if (_isLoadingStatus) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 16),
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadDocumentStatus,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_selectedTemplate == null) {
      return const SizedBox.shrink();
    }

    if (widget.budgetItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
              ),
              const SizedBox(height: 16),
              Text(
                'No budget items available',
                style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)),
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _onCancel, child: const Text('Close')),
            ],
          ),
        ),
      );
    }

    return BudgetItemSelectionTable(
      budgetItems: widget.budgetItems,
      documentStatusMap: _documentStatusMap ?? {},
      templateCategory: _selectedTemplate!.category,
      preSelectedItemIds: widget.preSelectedItemIds,
      onBack: _onBackToTemplates,
      onCancel: _onCancel,
      onConfirm: _onConfirm,
    );
  }
}
