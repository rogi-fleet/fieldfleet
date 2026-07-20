import 'package:flutter/material.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import '../models/budget_item.dart';
import '../models/cost_category.dart';
import '../models/catalog_item.dart';
import '../services/service_locator.dart';
import '../theme/theme.dart';
import '../utils/numeric_input.dart';
import '../utils/pricing_fields.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_scaffold.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_footer.dart';

/// Shows the budget item form as a popup dialog
void showBudgetItemFormPopup(
  BuildContext context, {
  required String projectId,
  required String workspaceId,
  String? parentId,
  required int hierarchyLevel,
  bool? isGroup,
  BudgetItem? existingItem,
  BudgetItemSource sourceType = BudgetItemSource.base,
}) {
  final budgetService = ServiceLocator.budgetService;
  final categoryService = ServiceLocator.costCategoryService;

  final isEdit = existingItem != null;
  final bool isItemMode;
  if (existingItem != null) {
    isItemMode = existingItem.itemType == BudgetItemType.item;
  } else if (isGroup != null) {
    isItemMode = !isGroup;
  } else {
    isItemMode = hierarchyLevel >= 2;
  }
  final levelName = existingItem?.hierarchyLevelName ??
      (isItemMode
          ? 'Item'
          : hierarchyLevel == 0
              ? 'Package'
              : 'Section');
  final title = isEdit
      ? (existingItem.name.isNotEmpty
          ? 'Edit ${existingItem.name}'
          : 'Edit $levelName')
      : 'Add $levelName';

  showFormPopup<void>(
    context,
    icon: isEdit ? Icons.edit : Icons.add_circle_outline,
    title: title,
    width: 550,
    fitContent: false,
    builder: (ctx, scrollController) => _BudgetItemFormContent(
      projectId: projectId,
      workspaceId: workspaceId,
      parentId: parentId,
      hierarchyLevel: hierarchyLevel,
      isGroup: isGroup,
      budgetService: budgetService,
      categoryService: categoryService,
      existingItem: existingItem,
      sourceType: sourceType,
      scrollController: scrollController,
    ),
  );
}

/// Form content for creating/editing budget items
class _BudgetItemFormContent extends StatefulWidget {
  final String projectId;
  final String workspaceId;
  final String? parentId;
  final int hierarchyLevel;

  /// When non-null, overrides the hierarchy-level-based group/item inference.
  /// `true` = group (no cost fields), `false` = item (with cost fields).
  final bool? isGroup;
  final dynamic budgetService;
  final dynamic categoryService;
  final BudgetItem? existingItem;

  /// Source type to assign when creating a new item. Ignored on edit
  /// (existing item's sourceType is preserved).
  final BudgetItemSource sourceType;

  final ScrollController? scrollController;

  const _BudgetItemFormContent({
    required this.projectId,
    required this.workspaceId,
    required this.parentId,
    required this.hierarchyLevel,
    this.isGroup,
    required this.budgetService,
    required this.categoryService,
    this.existingItem,
    this.sourceType = BudgetItemSource.base,
    this.scrollController,
  });

  /// Whether the form is creating/editing an item (leaf) vs a group (container).
  bool get isItemMode {
    if (existingItem != null) {
      return existingItem!.itemType == BudgetItemType.item;
    }
    if (isGroup != null) return !isGroup!;
    return hierarchyLevel >= 2;
  }

  @override
  State<_BudgetItemFormContent> createState() => _BudgetItemFormContentState();
}

class _BudgetItemFormContentState extends State<_BudgetItemFormContent> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _qtyController;
  late TextEditingController _unitController;
  // Cost/price/markup controllers + select-all-on-focus nodes + live
  // recalculation, shared with the catalog item form. (The margin
  // controller exists on the bundle but this form doesn't render it.)
  late PricingFieldsController _pricing;
  late TextEditingController _approvedPriceController;
  late TextEditingController _projectedCostController;
  late TextEditingController _notesController;
  String? _selectedCategoryId;
  bool _isTaxable = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existingItem?.name);
    _descriptionController = TextEditingController(
      text: widget.existingItem?.description,
    );
    _qtyController = TextEditingController(
      text: widget.existingItem?.quantity.toString() ?? '1.0',
    );
    _unitController = TextEditingController(text: widget.existingItem?.unit);
    _pricing = PricingFieldsController(
      cost: widget.existingItem?.unitCost ?? 0,
      price: widget.existingItem?.unitPrice ?? 0,
      onChanged: _calculateTotals,
    );
    _approvedPriceController = TextEditingController(
      text: widget.existingItem?.approvedPrice.toStringAsFixed(2) ?? '0.00',
    );
    _projectedCostController = TextEditingController(
      text: widget.existingItem?.projectedCost.toStringAsFixed(2) ?? '0.00',
    );
    _notesController = TextEditingController(text: widget.existingItem?.notes);
    _selectedCategoryId = widget.existingItem?.categoryId;
    _isTaxable = widget.existingItem?.isTaxable ?? true;

    // Pricing field consistency lives in _pricing; qty only affects totals.
    _qtyController.addListener(_calculateTotals);
  }

  void _calculateTotals() {
    final qty = double.tryParse(_qtyController.text) ?? 0.0;
    final unitCost = _pricing.costValue;
    final unitPrice = _pricing.priceValue;

    final projected = qty * unitCost;

    // Only update if value changed to avoid cursor jumping
    final projectedText = projected.toStringAsFixed(2);
    if (_projectedCostController.text != projectedText) {
      _projectedCostController.text = projectedText;
    }

    // Approved price is the frozen contract total once the item has been
    // approved via a linked document — do not recompute it from live qty.
    if (widget.existingItem?.isApproved ?? false) return;

    final approved = qty * unitPrice;
    final approvedText = approved.toStringAsFixed(2);
    if (_approvedPriceController.text != approvedText) {
      _approvedPriceController.text = approvedText;
    }
  }

  void _onCatalogItemSelected(CatalogItem? item) {
    if (item == null) return;
    setState(() {
      _nameController.text = item.name;
      _descriptionController.text = item.description ?? '';
      _unitController.text = item.unit ?? '';
      _qtyController.text = '1';
      _pricing.setValues(cost: item.unitCost, price: item.unitPrice);
      _isTaxable = item.isTaxable;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _qtyController.dispose();
    _unitController.dispose();
    _pricing.dispose();
    _approvedPriceController.dispose();
    _projectedCostController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<String?> _showAddCategoryDialog(String workspaceId) async {
    final nameController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String? newCategoryId;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Category'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StackedField(
                label: 'Category Name *',
                child: TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.category),
                    helperText: 'e.g., Labor, Materials, Equipment',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Category name is required';
                    }
                    return null;
                  },
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) {
                    if (formKey.currentState!.validate()) {
                      Navigator.of(context).pop(true);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(context).pop(true);
              }
            },
            child: const Text('Create Category'),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        final now = DateTime.now();
        final category = CostCategory(
          id: '',
          workspaceId: workspaceId,
          name: nameController.text.trim(),
          color: '#2196F3',
          isDefault: false,
          createdAt: now,
          updatedAt: now,
        );

        newCategoryId = await widget.categoryService.createCategory(category);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Category created successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: SelectableText(
                'Error creating category: $e',
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: AppColors.error,
              duration: const Duration(seconds: 10),
            ),
          );
        }
      }
    }

    nameController.dispose();
    return newCategoryId;
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingItem != null;
    final levelName =
        widget.existingItem?.hierarchyLevelName ??
        (widget.isItemMode
            ? 'Item'
            : widget.hierarchyLevel == 0
                ? 'Package'
                : 'Section');

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: widget.scrollController,
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                      // Catalog Item Selector (only for new items)
                      if (widget.existingItem == null &&
                          widget.isItemMode)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: StreamBuilder<List<CatalogItem>>(
                            stream: ServiceLocator.catalogService
                                .getCatalogItems(widget.workspaceId),
                            builder: (context, snapshot) {
                              final catalogItems = snapshot.data ?? [];
                              return StackedField(
                                label: 'Pre-fill from Catalog (optional)',
                                child: DropdownButtonFormField<CatalogItem>(
                                  borderRadius: AppRadius.cardRadius,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.list_alt),
                                  ),
                                  hint: const Text('Select a catalog item...'),
                                  items: catalogItems.map((item) {
                                    return DropdownMenuItem<CatalogItem>(
                                      value: item,
                                      child: Text(item.name),
                                    );
                                  }).toList(),
                                  onChanged: _onCatalogItemSelected,
                                ),
                              );
                            },
                          ),
                        ),

                      // Name field
                      StackedField(
                        label: 'Name *',
                        child: TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.label_outline),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Name is required';
                            }
                            return null;
                          },
                          autofocus: !isEdit,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Description field
                      StackedField(
                        label: 'Description',
                        child: TextFormField(
                          controller: _descriptionController,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.description_outlined),
                          ),
                          maxLines: 2,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Only show qty/unit/cost fields for items (not groups)
                      // Groups are containers and aggregate child data
                      if (widget.isItemMode) ...[
                        // Qty and Unit
                        Row(
                          children: [
                            Expanded(
                              child: StackedField(
                                label: 'Quantity *',
                                child: TextFormField(
                                  controller: _qtyController,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.calculate_outlined),
                                  ),
                                  keyboardType: NumericInput.keyboard,
                                  inputFormatters: NumericInput.quantity,
                                  validator: (value) {
                                    if (value == null || value.isEmpty)
                                      return 'Required';
                                    final qty = double.tryParse(value);
                                    if (qty == null) return 'Invalid';
                                    if (qty <= 0) return 'Must be greater than 0';
                                    return null;
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: StackedField(
                                label: 'Unit',
                                child: TextFormField(
                                  controller: _unitController,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    hintText: 'ea, sqft, etc.',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Unit Cost and Unit Price
                        Row(
                          children: [
                            Expanded(
                              child: StackedField(
                                label: 'Est. Unit Cost *',
                                child: TextFormField(
                                  controller: _pricing.cost,
                                  focusNode: _pricing.costFocus,
                                  onTap: () =>
                                      NumericInput.selectAll(_pricing.cost),
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    prefixText: '\$ ',
                                  ),
                                  keyboardType: NumericInput.keyboard,
                                  inputFormatters: NumericInput.currency,
                                  validator: (value) {
                                    if (value == null || value.isEmpty)
                                      return 'Required';
                                    if (double.tryParse(value) == null)
                                      return 'Invalid';
                                    return null;
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: StackedField(
                                label: 'Est. Unit Price *',
                                child: TextFormField(
                                  controller: _pricing.price,
                                  focusNode: _pricing.priceFocus,
                                  onTap: () =>
                                      NumericInput.selectAll(_pricing.price),
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    prefixText: '\$ ',
                                  ),
                                  keyboardType: NumericInput.keyboard,
                                  inputFormatters: NumericInput.currency,
                                  validator: (value) {
                                    if (value == null || value.isEmpty)
                                      return 'Required';
                                    if (double.tryParse(value) == null)
                                      return 'Invalid';
                                    return null;
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Markup % and Taxable
                        Row(
                          children: [
                            Expanded(
                              child: StackedField(
                                label: 'Markup %',
                                child: TextFormField(
                                  controller: _pricing.markup,
                                  focusNode: _pricing.markupFocus,
                                  onTap: () =>
                                      NumericInput.selectAll(_pricing.markup),
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    suffixText: '%',
                                    helperText: 'Updates unit price',
                                  ),
                                  keyboardType: NumericInput.signedKeyboard,
                                  inputFormatters: NumericInput.percent(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: SwitchListTile(
                                title: const Text('Taxable'),
                                subtitle: const Text('Apply sales tax'),
                                value: _isTaxable,
                                onChanged: (value) =>
                                    setState(() => _isTaxable = value),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Price fields (Read-only or calculated)
                        Row(
                          children: [
                            Expanded(
                              child: StackedField(
                                label: 'Total Est. Cost',
                                child: TextFormField(
                                  controller: _projectedCostController,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    prefixText: '\$ ',
                                    helperText: 'Qty × Unit Cost',
                                  ),
                                  readOnly: true,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: StackedField(
                                label: 'Total Approved Price',
                                child: TextFormField(
                                  controller: _approvedPriceController,
                                  decoration: InputDecoration(
                                    border: const OutlineInputBorder(),
                                    prefixText: '\$ ',
                                    helperText:
                                        (widget.existingItem?.isApproved ??
                                                false)
                                            ? 'Locked — contracted via approved document'
                                            : 'Qty × Unit Price',
                                    suffixIcon:
                                        (widget.existingItem?.isApproved ??
                                                false)
                                            ? const Icon(
                                                Icons.lock_outline,
                                                size: 18,
                                              )
                                            : null,
                                  ),
                                  readOnly: true,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Category dropdown
                      StreamBuilder<List<CostCategory>>(
                        stream: widget.categoryService.getCategories(
                          widget.workspaceId,
                        ),
                        builder: (context, snapshot) {
                          final categories = snapshot.data ?? [];
                          return StackedField(
                            label: widget.isItemMode
                                ? 'Category (for actual cost tracking) *'
                                : 'Category (optional)',
                            child: DropdownButtonFormField<String>(
                              borderRadius: AppRadius.cardRadius,
                              value: _selectedCategoryId == null ||
                                      categories.any(
                                        (c) => c.id == _selectedCategoryId,
                                      )
                                  ? _selectedCategoryId
                                  : null,
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                prefixIcon: const Icon(Icons.category_outlined),
                              ),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: null,
                                  child: Text('None'),
                                ),
                                const DropdownMenuItem<String>(
                                  value: '__add_new__',
                                  child: Row(
                                    children: [
                                      Icon(Icons.add_circle, size: 20),
                                      SizedBox(width: 8),
                                      Text(
                                        '+ Add New Category',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const DropdownMenuItem<String>(
                                  value: '__divider__',
                                  enabled: false,
                                  child: Divider(),
                                ),
                                ...categories.map((category) {
                                  return DropdownMenuItem<String>(
                                    value: category.id,
                                    child: Text(category.name),
                                  );
                                }),
                              ],
                              onChanged: (value) async {
                                if (value == '__add_new__') {
                                  final newCategoryId =
                                      await _showAddCategoryDialog(
                                        widget.workspaceId,
                                      );
                                  if (newCategoryId != null) {
                                    setState(() {
                                      _selectedCategoryId = newCategoryId;
                                    });
                                  }
                                } else if (value != '__divider__') {
                                  setState(() {
                                    _selectedCategoryId = value;
                                  });
                                }
                              },
                              validator: (value) {
                                if (widget.isItemMode && value == null) {
                                  return 'Category required for items';
                                }
                                return null;
                              },
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      // Notes field
                      StackedField(
                        label: 'Notes',
                        child: TextFormField(
                          controller: _notesController,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.notes_outlined),
                          ),
                          maxLines: 3,
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
        FormPopupFooter(
          onCancel: _isLoading ? null : () => Navigator.of(context).pop(),
          onSubmit: _isLoading ? null : _saveBudgetItem,
          submitLabel: isEdit ? 'Save Changes' : 'Add $levelName',
          submitIcon: isEdit ? Icons.save : Icons.add,
          busy: _isLoading,
        ),
      ],
    );
  }

  Future<void> _saveBudgetItem() async {
    if (!_formKey.currentState!.validate()) {
      // The failing field (often the required Category) can be below the
      // fold, so a silent no-op reads as a broken button. Tell the user.
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Please complete the highlighted required fields.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final now = DateTime.now();
      final isEdit = widget.existingItem != null;

      if (isEdit) {
        final updatedItem = widget.existingItem!.copyWith(
          name: _nameController.text,
          description: _descriptionController.text.isEmpty
              ? null
              : _descriptionController.text,
          categoryId: _selectedCategoryId,
          quantity: double.tryParse(_qtyController.text) ?? 0.0,
          unit: _unitController.text.isEmpty ? null : _unitController.text,
          unitCost: _pricing.costValue,
          unitPrice: _pricing.priceValue,
          markup: _pricing.markupValue,
          isTaxable: _isTaxable,
          approvedPrice: double.tryParse(_approvedPriceController.text) ?? 0.0,
          projectedCost: double.tryParse(_projectedCostController.text) ?? 0.0,
          notes: _notesController.text.isEmpty ? null : _notesController.text,
          updatedAt: now,
        );

        await widget.budgetService.updateBudgetItem(updatedItem);
      } else {
        final sortOrder = await widget.budgetService.getNextSortOrder(
          widget.parentId,
          widget.projectId,
        );

        final newItem = BudgetItem(
          id: '',
          workspaceId: widget.workspaceId,
          projectId: widget.projectId,
          parentId: widget.parentId,
          hierarchyLevel: widget.hierarchyLevel,
          sortOrder: sortOrder,
          name: _nameController.text,
          description: _descriptionController.text.isEmpty
              ? null
              : _descriptionController.text,
          categoryId: _selectedCategoryId,
          quantity: double.tryParse(_qtyController.text) ?? 0.0,
          unit: _unitController.text.isEmpty ? null : _unitController.text,
          unitCost: _pricing.costValue,
          unitPrice: _pricing.priceValue,
          markup: _pricing.markupValue,
          isTaxable: _isTaxable,
          approvedPrice: double.tryParse(_approvedPriceController.text) ?? 0.0,
          projectedCost: double.tryParse(_projectedCostController.text) ?? 0.0,
          notes: _notesController.text.isEmpty ? null : _notesController.text,
          itemType: widget.isItemMode
              ? BudgetItemType.item
              : BudgetItemType.group,
          createdAt: now,
          updatedAt: now,
          sourceType: widget.sourceType,
          upgradeStatus: widget.sourceType == BudgetItemSource.upgrade
              ? UpgradeStatus.offered
              : null,
        );

        await widget.budgetService.createBudgetItem(newItem);
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEdit ? 'Budget item updated' : 'Budget item added'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'complete this action'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}
