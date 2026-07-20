import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/catalog_item.dart';
import '../../theme/theme.dart';
import '../../utils/numeric_input.dart';

enum CatalogMassEditPreset { category, costType, unit, pricing, sku }

enum _CatalogSkuEditMode { setValue, generateSequence }

/// Summary of a cascade-to-open-jobs run, returned to the dialog so it can
/// surface a confirmation snackbar.
class CatalogMassEditCascadeSummary {
  final int matchedBudgetItems;
  final int touchedOpenProjects;
  const CatalogMassEditCascadeSummary({
    required this.matchedBudgetItems,
    required this.touchedOpenProjects,
  });
}

void showCatalogMassEditDialog(
  BuildContext context, {
  required List<CatalogItem> items,
  required Future<void> Function(List<CatalogItem>) onItemsUpdated,
  Future<CatalogMassEditCascadeSummary> Function(
    List<String> catalogItemIds,
    Map<String, dynamic> fieldOverrides,
  )?
  onCascadeToOpenJobs,
  CatalogMassEditPreset? preset,
}) {
  showDialog(
    context: context,
    builder: (context) => _CatalogMassEditDialog(
      items: items,
      onItemsUpdated: onItemsUpdated,
      onCascadeToOpenJobs: onCascadeToOpenJobs,
      preset: preset,
    ),
  );
}

class _CatalogMassEditDialog extends StatefulWidget {
  final List<CatalogItem> items;
  final Future<void> Function(List<CatalogItem>) onItemsUpdated;
  final Future<CatalogMassEditCascadeSummary> Function(
    List<String> catalogItemIds,
    Map<String, dynamic> fieldOverrides,
  )?
  onCascadeToOpenJobs;
  final CatalogMassEditPreset? preset;

  const _CatalogMassEditDialog({
    required this.items,
    required this.onItemsUpdated,
    required this.onCascadeToOpenJobs,
    this.preset,
  });

  @override
  State<_CatalogMassEditDialog> createState() => _CatalogMassEditDialogState();
}

class _CatalogMassEditDialogState extends State<_CatalogMassEditDialog> {
  final _unitController = TextEditingController();
  final _categoryController = TextEditingController();
  final _costTypeController = TextEditingController();
  final _skuController = TextEditingController();
  final _skuPrefixController = TextEditingController();
  final _skuStartController = TextEditingController(text: '1');
  final _skuPadWidthController = TextEditingController(text: '3');
  final _unitCostController = TextEditingController();
  final _unitPriceController = TextEditingController();
  final _markupController = TextEditingController();
  final _marginController = TextEditingController();

  bool _updateUnit = false;
  bool _updateCategory = false;
  bool _updateCostType = false;
  bool _updateSku = false;
  bool _updateTaxable = false;
  bool _updateUnitCost = false;
  bool _updateUnitPrice = false;
  bool _updateMarkup = false;
  bool _updateMargin = false;
  bool _taxableValue = true;
  bool _isSaving = false;
  bool _cascadeToOpenJobs = false;
  _CatalogSkuEditMode _skuEditMode = _CatalogSkuEditMode.setValue;

  String? get _presetLabel => switch (widget.preset) {
    CatalogMassEditPreset.category => 'Category',
    CatalogMassEditPreset.costType => 'Cost Type',
    CatalogMassEditPreset.unit => 'Unit',
    CatalogMassEditPreset.pricing => 'Pricing',
    CatalogMassEditPreset.sku => 'SKU',
    null => null,
  };

  @override
  void initState() {
    super.initState();
    switch (widget.preset) {
      case CatalogMassEditPreset.category:
        _updateCategory = true;
        break;
      case CatalogMassEditPreset.costType:
        _updateCostType = true;
        break;
      case CatalogMassEditPreset.unit:
        _updateUnit = true;
        break;
      case CatalogMassEditPreset.pricing:
        _updateUnitCost = true;
        _updateUnitPrice = true;
        break;
      case CatalogMassEditPreset.sku:
        _updateSku = true;
        _skuEditMode = _CatalogSkuEditMode.generateSequence;
        break;
      case null:
        break;
    }
  }

  @override
  void dispose() {
    _unitController.dispose();
    _categoryController.dispose();
    _costTypeController.dispose();
    _skuController.dispose();
    _skuPrefixController.dispose();
    _skuStartController.dispose();
    _skuPadWidthController.dispose();
    _unitCostController.dispose();
    _unitPriceController.dispose();
    _markupController.dispose();
    _marginController.dispose();
    super.dispose();
  }

  List<CatalogItem> get _editableItems {
    return widget.items
        .where((item) => item.itemType == CatalogItemType.item)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final editableItems = _editableItems;
    final groupCount = widget.items.length - editableItems.length;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r16)),
      child: Container(
        width: 560,
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.92,
          maxHeight: MediaQuery.of(context).size.height * 0.84,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.base),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit_outlined, color: AppColors.info),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bulk Edit ${widget.items.length} Catalog Item${widget.items.length == 1 ? '' : 's'}',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          _presetLabel != null
                              ? 'Focused on $_presetLabel cleanup${groupCount > 0 ? ' • $groupCount groups excluded' : ''}'
                              : groupCount > 0
                              ? '${editableItems.length} editable items, $groupCount groups excluded'
                              : 'Select the fields to update',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTextEditSection(
                      title: 'Unit',
                      isEnabled: _updateUnit,
                      onChanged: (value) {
                        setState(() => _updateUnit = value ?? false);
                      },
                      controller: _unitController,
                      hintText: 'Set unit or leave blank to clear',
                    ),
                    const SizedBox(height: 16),
                    _buildTextEditSection(
                      title: 'Category',
                      isEnabled: _updateCategory,
                      onChanged: (value) {
                        setState(() => _updateCategory = value ?? false);
                      },
                      controller: _categoryController,
                      hintText: 'Set category or leave blank to clear',
                    ),
                    const SizedBox(height: 16),
                    _buildTextEditSection(
                      title: 'Cost Type',
                      isEnabled: _updateCostType,
                      onChanged: (value) {
                        setState(() => _updateCostType = value ?? false);
                      },
                      controller: _costTypeController,
                      hintText: 'Set cost type or leave blank to clear',
                    ),
                    const SizedBox(height: 16),
                    _buildSkuSection(),
                    const SizedBox(height: 16),
                    _buildTaxableSection(),
                    const SizedBox(height: 16),
                    _buildNumberEditSection(
                      title: 'Unit Cost',
                      isEnabled: _updateUnitCost,
                      onChanged: (value) {
                        setState(() => _updateUnitCost = value ?? false);
                      },
                      controller: _unitCostController,
                      hintText: 'Enter unit cost',
                    ),
                    const SizedBox(height: 16),
                    _buildNumberEditSection(
                      title: 'Unit Price',
                      isEnabled: _updateUnitPrice,
                      onChanged: (value) {
                        setState(() => _updateUnitPrice = value ?? false);
                      },
                      controller: _unitPriceController,
                      hintText: 'Enter unit price',
                    ),
                    const SizedBox(height: 16),
                    _buildNumberEditSection(
                      title: 'Markup %',
                      isEnabled: _updateMarkup,
                      onChanged: (value) {
                        setState(() {
                          _updateMarkup = value ?? false;
                          if (_updateMarkup) _updateMargin = false;
                        });
                      },
                      controller: _markupController,
                      hintText: 'Enter markup percent',
                    ),
                    if (_updateMarkup) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Markup recalculates price from the current or edited unit cost.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _buildNumberEditSection(
                      title: 'Margin %',
                      isEnabled: _updateMargin,
                      onChanged: (value) {
                        setState(() {
                          _updateMargin = value ?? false;
                          if (_updateMargin) _updateMarkup = false;
                        });
                      },
                      controller: _marginController,
                      hintText: 'Enter margin percent (< 100)',
                    ),
                    if (_updateMargin) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Margin recalculates price from the current or edited unit cost.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (widget.onCascadeToOpenJobs != null)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: _buildCascadeSection(),
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '${editableItems.length} item${editableItems.length == 1 ? '' : 's'} will be updated',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _isSaving || editableItems.isEmpty
                        ? null
                        : _applyChanges,
                    child: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Apply Changes'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextEditSection({
    required String title,
    required bool isEnabled,
    required ValueChanged<bool?> onChanged,
    required TextEditingController controller,
    required String hintText,
  }) {
    return _buildSectionShell(
      title: title,
      isEnabled: isEnabled,
      onChanged: onChanged,
      child: TextField(
        controller: controller,
        enabled: isEnabled,
        decoration: InputDecoration(
          hintText: hintText,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
        ),
      ),
    );
  }

  Widget _buildNumberEditSection({
    required String title,
    required bool isEnabled,
    required ValueChanged<bool?> onChanged,
    required TextEditingController controller,
    required String hintText,
  }) {
    return _buildSectionShell(
      title: title,
      isEnabled: isEnabled,
      onChanged: onChanged,
      child: TextField(
        controller: controller,
        enabled: isEnabled,
        keyboardType: NumericInput.keyboard,
        inputFormatters: NumericInput.quantity,
        decoration: InputDecoration(
          hintText: hintText,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
        ),
      ),
    );
  }

  Widget _buildTaxableSection() {
    return _buildSectionShell(
      title: 'Taxable',
      isEnabled: _updateTaxable,
      onChanged: (value) {
        setState(() => _updateTaxable = value ?? false);
      },
      child: DropdownButtonFormField<bool>(
        borderRadius: AppRadius.cardRadius,
        initialValue: _taxableValue,
        decoration: InputDecoration(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
        ),
        items: const [
          DropdownMenuItem<bool>(value: true, child: Text('Taxable')),
          DropdownMenuItem<bool>(value: false, child: Text('Non-taxable')),
        ],
        onChanged: _updateTaxable
            ? (value) {
                if (value == null) return;
                setState(() => _taxableValue = value);
              }
            : null,
      ),
    );
  }

  Widget _buildSkuSection() {
    return _buildSectionShell(
      title: 'SKU',
      isEnabled: _updateSku,
      onChanged: (value) {
        setState(() => _updateSku = value ?? false);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<_CatalogSkuEditMode>(
            segments: const [
              ButtonSegment<_CatalogSkuEditMode>(
                value: _CatalogSkuEditMode.setValue,
                label: Text('Set Value'),
                icon: Icon(Icons.edit_outlined, size: 16),
              ),
              ButtonSegment<_CatalogSkuEditMode>(
                value: _CatalogSkuEditMode.generateSequence,
                label: Text('Generate'),
                icon: Icon(Icons.auto_awesome_outlined, size: 16),
              ),
            ],
            selected: {_skuEditMode},
            onSelectionChanged: _updateSku
                ? (selection) {
                    setState(() => _skuEditMode = selection.first);
                  }
                : null,
          ),
          const SizedBox(height: 12),
          if (_skuEditMode == _CatalogSkuEditMode.setValue)
            TextField(
              controller: _skuController,
              enabled: _updateSku,
              decoration: InputDecoration(
                hintText: 'Set SKU or leave blank to clear',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _skuPrefixController,
                        enabled: _updateSku,
                        decoration: InputDecoration(
                          labelText: 'Prefix',
                          hintText: 'CAB',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.md,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _skuStartController,
                        enabled: _updateSku,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: 'Start',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.md,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _skuPadWidthController,
                        enabled: _updateSku,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: 'Pad',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.md,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Generates sequential SKUs like ${_skuSequenceExample()} in name order.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildCascadeSection() {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: _cascadeToOpenJobs,
            onChanged: _isSaving
                ? null
                : (v) => setState(() => _cascadeToOpenJobs = v ?? false),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Also push these changes into open jobs',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Matches budget items by name on active, on-hold, and awarded '
                  'projects. Contracted (approved) items are left untouched.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionShell({
    required String title,
    required bool isEnabled,
    required ValueChanged<bool?> onChanged,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(value: isEnabled, onChanged: onChanged),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Future<void> _applyChanges() async {
    final editableItems = _editableItems;
    if (editableItems.isEmpty) return;

    final parsedUnitCost = _updateUnitCost
        ? double.tryParse(_unitCostController.text.trim())
        : null;
    final parsedUnitPrice = _updateUnitPrice
        ? double.tryParse(_unitPriceController.text.trim())
        : null;
    final parsedMarkup = _updateMarkup
        ? double.tryParse(_markupController.text.trim())
        : null;
    final parsedMargin = _updateMargin
        ? double.tryParse(_marginController.text.trim())
        : null;
    final parsedSkuStart =
        _updateSku && _skuEditMode == _CatalogSkuEditMode.generateSequence
        ? int.tryParse(_skuStartController.text.trim())
        : null;
    final parsedSkuPadWidth =
        _updateSku && _skuEditMode == _CatalogSkuEditMode.generateSequence
        ? int.tryParse(_skuPadWidthController.text.trim())
        : null;

    if (_updateUnitCost && parsedUnitCost == null) {
      _showError('Enter a valid unit cost.');
      return;
    }
    if (_updateUnitCost && parsedUnitCost != null && parsedUnitCost < 0) {
      _showError('Unit cost cannot be negative.');
      return;
    }
    if (_updateUnitPrice && parsedUnitPrice == null) {
      _showError('Enter a valid unit price.');
      return;
    }
    if (_updateUnitPrice && parsedUnitPrice != null && parsedUnitPrice < 0) {
      _showError('Unit price cannot be negative.');
      return;
    }
    if (_updateMarkup && parsedMarkup == null) {
      _showError('Enter a valid markup value.');
      return;
    }
    if (_updateMargin && parsedMargin == null) {
      _showError('Enter a valid margin value.');
      return;
    }
    if (_updateMargin && parsedMargin != null && parsedMargin >= 100) {
      _showError('Margin must be less than 100%.');
      return;
    }
    if (_updateSku && _skuEditMode == _CatalogSkuEditMode.generateSequence) {
      if (parsedSkuStart == null || parsedSkuStart < 0) {
        _showError('Enter a valid SKU starting number.');
        return;
      }
      if (parsedSkuPadWidth == null ||
          parsedSkuPadWidth < 1 ||
          parsedSkuPadWidth > 12) {
        _showError('Enter a SKU pad width between 1 and 12.');
        return;
      }
    }

    final generatedSkuById = <String, String?>{};
    if (_updateSku && _skuEditMode == _CatalogSkuEditMode.generateSequence) {
      final prefix = _normalizedNullable(_skuPrefixController.text);
      final sortedItems = [...editableItems]
        ..sort((a, b) {
          final nameCompare = a.name.trim().toLowerCase().compareTo(
            b.name.trim().toLowerCase(),
          );
          if (nameCompare != 0) return nameCompare;
          final sortCompare = a.sortOrder.compareTo(b.sortOrder);
          if (sortCompare != 0) return sortCompare;
          return a.createdAt.compareTo(b.createdAt);
        });

      for (var index = 0; index < sortedItems.length; index++) {
        final sequenceNumber = (parsedSkuStart ?? 1) + index;
        final numberLabel = sequenceNumber.toString().padLeft(
          parsedSkuPadWidth ?? 3,
          '0',
        );
        generatedSkuById[sortedItems[index].id] = prefix == null
            ? numberLabel
            : '$prefix-$numberLabel';
      }
    }

    final now = DateTime.now();
    final updatedItems = editableItems
        .map((item) {
          var unitCost = parsedUnitCost ?? item.unitCost;
          var unitPrice = parsedUnitPrice ?? item.unitPrice;

          if (_updateMarkup && parsedMarkup != null) {
            unitPrice = CatalogItem.calculatePriceFromMarkup(
              unitCost,
              parsedMarkup,
            );
          } else if (_updateMargin && parsedMargin != null) {
            unitPrice = CatalogItem.calculatePriceFromMargin(
              unitCost,
              parsedMargin,
            );
          }

          final markup = CatalogItem.calculateMarkup(unitCost, unitPrice);
          final margin = CatalogItem.calculateMargin(unitCost, unitPrice);

          return item.copyWith(
            unit: _updateUnit
                ? _normalizedNullable(_unitController.text)
                : item.unit,
            category: _updateCategory
                ? _normalizedNullable(_categoryController.text)
                : item.category,
            costTypeName: _updateCostType
                ? _normalizedNullable(_costTypeController.text)
                : item.costTypeName,
            sku: _updateSku
                ? _skuEditMode == _CatalogSkuEditMode.generateSequence
                      ? generatedSkuById[item.id]
                      : _normalizedNullable(_skuController.text)
                : item.sku,
            isTaxable: _updateTaxable ? _taxableValue : item.isTaxable,
            unitCost: unitCost,
            unitPrice: unitPrice,
            markup: markup,
            margin: margin,
            updatedAt: now,
          );
        })
        .toList(growable: false);

    setState(() => _isSaving = true);
    try {
      await widget.onItemsUpdated(updatedItems);

      // Optionally cascade the same field overrides into matching budget
      // items on every open project. Only fields the user explicitly toggled
      // on are propagated, mirroring catalog semantics. We rebuild the
      // overrides map from the edited rows so markup/margin recalculations
      // are reflected exactly as they were applied to the catalog row.
      if (_cascadeToOpenJobs && widget.onCascadeToOpenJobs != null) {
        final overrides = _buildCascadeOverrides(
          editableItems,
          updatedItems,
        );
        if (overrides.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                'Catalog updated. Cascade was skipped because the selected '
                'rows produced different per-row prices — apply a fixed '
                'unit price or cost to push a uniform change to open jobs.',
              ),
              behavior: SnackBarBehavior.floating,
            ));
          }
        } else {
          final ids = updatedItems.map((e) => e.id).toList(growable: false);
          try {
            final summary = await widget.onCascadeToOpenJobs!(ids, overrides);
            if (mounted) {
              final msg = summary.matchedBudgetItems == 0
                  ? 'Catalog updated. No matching open-job items found to update.'
                  : 'Catalog updated. Also updated ${summary.matchedBudgetItems} '
                        'budget item${summary.matchedBudgetItems == 1 ? '' : 's'} '
                        'across ${summary.touchedOpenProjects} open '
                        'project${summary.touchedOpenProjects == 1 ? '' : 's'}.';
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(msg),
                behavior: SnackBarBehavior.floating,
              ));
            }
          } catch (e) {
            if (mounted) {
              _showError('Catalog saved, but cascade to open jobs failed: $e');
            }
          }
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to apply bulk edit: $e');
      setState(() => _isSaving = false);
    }
  }

  /// Build the JSONB payload sent to `catalog_cascade_to_open_jobs`. Only
  /// keys for fields the user toggled on are included so unrelated columns
  /// on budget items are never disturbed. When multiple rows received
  /// different recomputed values (e.g. markup-driven price varied per row),
  /// we omit the field from the cascade rather than blasting one row's
  /// value over everything. Inputs/outputs must be in the same order.
  Map<String, dynamic> _buildCascadeOverrides(
    List<CatalogItem> before,
    List<CatalogItem> after,
  ) {
    final overrides = <String, dynamic>{};
    if (_updateUnit) {
      overrides['unit'] = _normalizedNullable(_unitController.text) ?? '';
    }
    if (_updateTaxable) {
      overrides['is_taxable'] = _taxableValue;
    }
    if (_updateUnitCost) {
      final v = double.tryParse(_unitCostController.text.trim());
      if (v != null) overrides['unit_cost'] = v;
    }
    if (_updateUnitPrice) {
      final v = double.tryParse(_unitPriceController.text.trim());
      if (v != null) overrides['unit_price'] = v;
    }
    if (_updateMarkup) {
      // Markup recomputes per-row unit_price from each item's unit_cost,
      // so the resulting prices typically differ between rows. We only
      // propagate `markup` AND the new `unit_price` together when the
      // recomputed prices are uniform across the selection — otherwise
      // we'd push a single markup value to budget rows without a matching
      // price recalculation, which would drift cost/price out of sync.
      if (after.isNotEmpty) {
        final p = after.first.unitPrice;
        final uniform = after.every((e) => (e.unitPrice - p).abs() < 0.005);
        if (uniform) {
          final v = double.tryParse(_markupController.text.trim());
          if (v != null) overrides['markup'] = v;
          overrides['unit_price'] = p;
        }
      }
    }
    if (_updateMargin) {
      // Margin only affects unit_price on the catalog side; propagate only
      // when uniform so we don't blast one row's recomputed value across
      // unrelated budget items.
      if (after.isNotEmpty) {
        final p = after.first.unitPrice;
        final uniform = after.every((e) => (e.unitPrice - p).abs() < 0.005);
        if (uniform) overrides['unit_price'] = p;
      }
    }
    return overrides;
  }

  String? _normalizedNullable(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _skuSequenceExample() {
    final prefix = _normalizedNullable(_skuPrefixController.text);
    final start = int.tryParse(_skuStartController.text.trim()) ?? 1;
    final padWidth = int.tryParse(_skuPadWidthController.text.trim()) ?? 3;
    final numberLabel = start.toString().padLeft(padWidth.clamp(1, 12), '0');
    return prefix == null ? numberLabel : '$prefix-$numberLabel';
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
