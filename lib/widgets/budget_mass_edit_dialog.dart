import 'package:flutter/material.dart';
import '../models/budget_item.dart';
import '../theme/theme.dart';
import '../utils/numeric_input.dart';

/// Shows mass edit dialog for selected budget items
void showBudgetMassEditDialog(
  BuildContext context, {
  required List<BudgetItem> items,
  required Function(List<BudgetItem>) onItemsUpdated,
  VoidCallback? onDelete,
}) {
  showDialog(
    context: context,
    builder: (context) => _BudgetMassEditDialog(
      items: items,
      onItemsUpdated: onItemsUpdated,
      onDelete: onDelete,
    ),
  );
}

class _BudgetMassEditDialog extends StatefulWidget {
  final List<BudgetItem> items;
  final Function(List<BudgetItem>) onItemsUpdated;
  final VoidCallback? onDelete;

  const _BudgetMassEditDialog({
    required this.items,
    required this.onItemsUpdated,
    this.onDelete,
  });

  @override
  State<_BudgetMassEditDialog> createState() => _BudgetMassEditDialogState();
}

class _BudgetMassEditDialogState extends State<_BudgetMassEditDialog> {
  // Field values
  double? _quantity;
  String? _unit;
  double? _unitCost;
  double? _unitPrice;

  // Enable toggles
  bool _updateQuantity = false;
  bool _updateUnit = false;
  bool _updateUnitCost = false;
  bool _updateUnitPrice = false;

  // Controllers for text inputs
  final _quantityController = TextEditingController();
  final _unitController = TextEditingController();
  final _unitCostController = TextEditingController();
  final _unitPriceController = TextEditingController();

  // Common units for dropdown
  static const _commonUnits = [
    'EA',
    'HR',
    'SF',
    'LF',
    'SY',
    'CY',
    'TON',
    'GAL',
    'LS',
    'DAY',
    'WK',
    'MO',
  ];

  @override
  void dispose() {
    _quantityController.dispose();
    _unitController.dispose();
    _unitCostController.dispose();
    _unitPriceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Count leaf items (items that can actually be edited)
    final editableItems = widget.items.where((i) => i.itemType == BudgetItemType.item).toList();
    final groupCount = widget.items.length - editableItems.length;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r16)),
      child: Container(
        width: 500,
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(AppSpacing.base),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.edit, color: AppColors.info),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mass Edit ${widget.items.length} Item${widget.items.length > 1 ? 's' : ''}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        Text(
                          groupCount > 0
                              ? '${editableItems.length} editable items, $groupCount groups (field changes apply to items only)'
                              : 'Select fields to update',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Quantity section
                    _buildEditSection(
                      title: 'Quantity',
                      isEnabled: _updateQuantity,
                      onChanged: (value) {
                        setState(() {
                          _updateQuantity = value ?? false;
                        });
                      },
                      child: TextField(
                        controller: _quantityController,
                        enabled: _updateQuantity,
                        keyboardType: NumericInput.keyboard,
                        inputFormatters: NumericInput.quantity,
                        decoration: InputDecoration(
                          hintText: 'Enter quantity',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.md,
                          ),
                        ),
                        onChanged: (value) {
                          _quantity = double.tryParse(value);
                        },
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Unit section
                    _buildEditSection(
                      title: 'Unit',
                      isEnabled: _updateUnit,
                      onChanged: (value) {
                        setState(() {
                          _updateUnit = value ?? false;
                        });
                      },
                      child: Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              borderRadius: AppRadius.cardRadius,
                              decoration: InputDecoration(
                                hintText: 'Select unit',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(AppRadius.sm),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md,
                                  vertical: AppSpacing.md,
                                ),
                              ),
                              items: _commonUnits
                                  .map((unit) => DropdownMenuItem(
                                        value: unit,
                                        child: Text(unit),
                                      ))
                                  .toList(),
                              onChanged: _updateUnit
                                  ? (value) {
                                      setState(() {
                                        _unit = value;
                                        _unitController.text = value ?? '';
                                      });
                                    }
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text('or'),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _unitController,
                              enabled: _updateUnit,
                              decoration: InputDecoration(
                                hintText: 'Custom',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(AppRadius.sm),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md,
                                  vertical: AppSpacing.md,
                                ),
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _unit = value.isEmpty ? null : value;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Unit Cost section
                    _buildEditSection(
                      title: 'Unit Cost',
                      isEnabled: _updateUnitCost,
                      onChanged: (value) {
                        setState(() {
                          _updateUnitCost = value ?? false;
                        });
                      },
                      child: TextField(
                        controller: _unitCostController,
                        enabled: _updateUnitCost,
                        keyboardType: NumericInput.keyboard,
                        inputFormatters: NumericInput.quantity,
                        decoration: InputDecoration(
                          hintText: 'Enter unit cost',
                          prefixText: '\$ ',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.md,
                          ),
                        ),
                        onChanged: (value) {
                          _unitCost = double.tryParse(value);
                        },
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Unit Price section
                    _buildEditSection(
                      title: 'Unit Price',
                      isEnabled: _updateUnitPrice,
                      onChanged: (value) {
                        setState(() {
                          _updateUnitPrice = value ?? false;
                        });
                      },
                      child: TextField(
                        controller: _unitPriceController,
                        enabled: _updateUnitPrice,
                        keyboardType: NumericInput.keyboard,
                        inputFormatters: NumericInput.quantity,
                        decoration: InputDecoration(
                          hintText: 'Enter unit price',
                          prefixText: '\$ ',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.md,
                          ),
                        ),
                        onChanged: (value) {
                          _unitPrice = double.tryParse(value);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(AppSpacing.base),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppColors.cardBorder)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Delete button row
                  if (widget.onDelete != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            widget.onDelete!();
                          },
                          icon: const Icon(Icons.delete_outline),
                          label: Text(
                            'Delete ${widget.items.length} Item${widget.items.length > 1 ? 's' : ''}',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.errorDark,
                            side: BorderSide(color: AppColors.error),
                          ),
                        ),
                      ),
                    ),
                  // Edit buttons row
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _canSave() && editableItems.isNotEmpty
                              ? _handleSave
                              : null,
                          child: const Text('Update Items'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditSection({
    required String title,
    required bool isEnabled,
    required Function(bool?) onChanged,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isEnabled ? AppColors.infoLight : AppColors.surfaceAlt,
        border: Border.all(
          color: isEnabled ? AppColors.cardBorder : AppColors.cardBorder,
        ),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(value: isEnabled, onChanged: onChanged),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          if (isEnabled) ...[const SizedBox(height: 8), child],
        ],
      ),
    );
  }

  bool _canSave() {
    return (_updateQuantity && _quantity != null) ||
        (_updateUnit && _unit != null && _unit!.isNotEmpty) ||
        (_updateUnitCost && _unitCost != null) ||
        (_updateUnitPrice && _unitPrice != null);
  }

  void _handleSave() {
    final updatedItems = <BudgetItem>[];

    for (final item in widget.items) {
      // Only update leaf items, not groups
      if (item.itemType == BudgetItemType.group) continue;

      double newQuantity = item.quantity;
      String? newUnit = item.unit;
      double newUnitCost = item.unitCost;
      double newUnitPrice = item.unitPrice;
      bool hasChanges = false;

      if (_updateQuantity && _quantity != null) {
        newQuantity = _quantity!;
        hasChanges = true;
      }

      if (_updateUnit && _unit != null) {
        newUnit = _unit;
        hasChanges = true;
      }

      if (_updateUnitCost && _unitCost != null) {
        newUnitCost = _unitCost!;
        hasChanges = true;
      }

      if (_updateUnitPrice && _unitPrice != null) {
        newUnitPrice = _unitPrice!;
        hasChanges = true;
      }

      if (hasChanges) {
        // Calculate new totals
        final newProjectedCost = newQuantity * newUnitCost;
        final newApprovedPrice = newQuantity * newUnitPrice;

        updatedItems.add(
          item.copyWith(
            quantity: newQuantity,
            unit: newUnit,
            unitCost: newUnitCost,
            unitPrice: newUnitPrice,
            projectedCost: newProjectedCost,
            approvedPrice: newApprovedPrice,
            updatedAt: DateTime.now(),
          ),
        );
      }
    }

    if (updatedItems.isNotEmpty) {
      widget.onItemsUpdated(updatedItems);
      Navigator.of(context).pop();
    }
  }
}
