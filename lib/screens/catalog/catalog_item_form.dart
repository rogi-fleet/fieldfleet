import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';

import '../../models/catalog_item.dart';
import '../../models/catalog/catalog_kind.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../services/supabase/catalog_service.dart';
import '../../utils/numeric_input.dart';
import '../../utils/pricing_fields.dart';
import '../../utils/project_terminology.dart';
import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';
import '../../theme/theme.dart';

class CatalogItemForm extends StatefulWidget {
  final CatalogItem? item;
  final bool isPopup;
  final String? initialParentId;
  final int? initialHierarchyLevel;
  final bool initialIsGroup;
  final VoidCallback? onSaved;

  /// When true, [item] is a pre-filled draft (e.g. from the web importer):
  /// the form stays in CREATE mode and saving inserts a new row.
  final bool createAsNew;

  const CatalogItemForm({
    super.key,
    this.item,
    this.isPopup = false,
    this.createAsNew = false,
    this.initialParentId,
    this.initialHierarchyLevel,
    this.initialIsGroup = false,
    this.onSaved,
  });

  @override
  State<CatalogItemForm> createState() => _CatalogItemFormState();
}

class _CatalogItemFormState extends State<CatalogItemForm> {
  final _formKey = GlobalKey<FormState>();
  final SupabaseCatalogService _catalogService = SupabaseCatalogService();

  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _unitController;
  // Cost/price/markup/margin controllers + select-all-on-focus nodes +
  // live recalculation, shared with the budget item form.
  late PricingFieldsController _pricing;
  late TextEditingController _costTypeController;
  late TextEditingController _costCodeController;
  late TextEditingController _categoryController;
  late TextEditingController _skuController;
  late TextEditingController _imageUrlController;

  // Accounting & inventory integration fields (catalog robustness)
  late TextEditingController _barcodeController;
  late TextEditingController _currencyController;
  late TextEditingController _minPriceController;
  late TextEditingController _defaultTaxRateController;
  late TextEditingController _purchaseCostController;
  late TextEditingController _purchaseDescriptionController;
  CatalogKind _kind = CatalogKind.service;
  bool _isActive = true;
  bool _inventoryTracked = false;

  bool _isTaxable = true;
  bool _advancedExpanded = false;
  bool _isSaving = false;

  bool get _isEditing => widget.item != null && !widget.createAsNew;

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  void initState() {
    super.initState();
    _advancedExpanded = (widget.item?.imageUrl ?? '').trim().isNotEmpty;
    _initializeControllers();
  }

  void _initializeControllers() {
    _nameController = TextEditingController(text: widget.item?.name ?? '');
    _descriptionController = TextEditingController(
      text: widget.item?.description ?? '',
    );
    _unitController = TextEditingController(text: widget.item?.unit ?? '');
    _pricing = PricingFieldsController(
      cost: widget.item?.unitCost ?? 0,
      price: widget.item?.unitPrice ?? 0,
    );
    _costTypeController = TextEditingController(
      text: widget.item?.costTypeName ?? '',
    );
    _costCodeController = TextEditingController(
      text: widget.item?.costCodeName ?? '',
    );
    _categoryController = TextEditingController(
      text: widget.item?.category ?? '',
    );
    _skuController = TextEditingController(text: widget.item?.sku ?? '');
    _imageUrlController = TextEditingController(
      text: widget.item?.imageUrl ?? '',
    );
    _barcodeController = TextEditingController(
      text: widget.item?.barcode ?? '',
    );
    _currencyController = TextEditingController(
      // New items inherit the workspace currency; editing keeps the item's.
      text: widget.item?.currency ??
          context.read<WorkspaceProvider>().currencyCode,
    );
    _minPriceController = TextEditingController(
      text: widget.item?.minPrice?.toStringAsFixed(2) ?? '',
    );
    _defaultTaxRateController = TextEditingController(
      text: (widget.item?.defaultTaxRate ?? 0).toStringAsFixed(2),
    );
    _purchaseCostController = TextEditingController(
      text: widget.item?.purchaseCost?.toStringAsFixed(2) ?? '',
    );
    _purchaseDescriptionController = TextEditingController(
      text: widget.item?.purchaseDescription ?? '',
    );
    _kind = widget.item?.kind ?? CatalogKind.service;
    _isActive = widget.item?.isActive ?? true;
    _inventoryTracked = widget.item?.inventoryTracked ?? false;
    _isTaxable = widget.item?.isTaxable ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _unitController.dispose();
    _pricing.dispose();
    _costTypeController.dispose();
    _costCodeController.dispose();
    _categoryController.dispose();
    _skuController.dispose();
    _imageUrlController.dispose();
    _barcodeController.dispose();
    _currencyController.dispose();
    _minPriceController.dispose();
    _defaultTaxRateController.dispose();
    _purchaseCostController.dispose();
    _purchaseDescriptionController.dispose();
    super.dispose();
  }

  CatalogItem _buildItem({
    required String workspaceId,
    bool duplicateAsNew = false,
  }) {
    final now = DateTime.now();

    return CatalogItem(
      id: (duplicateAsNew || widget.createAsNew)
          ? ''
          : (widget.item?.id ?? ''),
      workspaceId: workspaceId,
      name: _nameController.text.trim(),
      description: _emptyToNull(_descriptionController.text),
      unit: _emptyToNull(_unitController.text),
      unitCost: _pricing.costValue,
      unitPrice: _pricing.priceValue,
      markup: _pricing.markupValue,
      margin: _pricing.marginValue,
      isTaxable: _isTaxable,
      costTypeName: _emptyToNull(_costTypeController.text),
      costCodeName: _emptyToNull(_costCodeController.text),
      imageUrl: _emptyToNull(_imageUrlController.text),
      category: _emptyToNull(_categoryController.text),
      sku: _emptyToNull(_skuController.text),
      createdAt: duplicateAsNew ? now : (widget.item?.createdAt ?? now),
      updatedAt: now,
      parentId: widget.item?.parentId ?? widget.initialParentId,
      hierarchyLevel:
          widget.item?.hierarchyLevel ?? widget.initialHierarchyLevel ?? 0,
      itemType: widget.item?.itemType ??
          (widget.initialIsGroup
              ? CatalogItemType.group
              : CatalogItemType.item),
      sortOrder: widget.item?.sortOrder ?? 0,
      kind: _kind,
      isActive: _isActive,
      barcode: _emptyToNull(_barcodeController.text),
      currency: _currencyController.text.trim().isEmpty
          ? context.read<WorkspaceProvider>().currencyCode
          : _currencyController.text.trim().toUpperCase(),
      minPrice: double.tryParse(_minPriceController.text),
      defaultTaxRate: double.tryParse(_defaultTaxRateController.text) ?? 0,
      purchaseCost: double.tryParse(_purchaseCostController.text),
      purchaseDescription: _emptyToNull(_purchaseDescriptionController.text),
      inventoryTracked: _inventoryTracked,
      defaultVendorId: widget.item?.defaultVendorId,
      inventoryItemId: widget.item?.inventoryItemId,
      tags: widget.item?.tags ?? const [],
      internalNotes: widget.item?.internalNotes,
      purchaseUnit: widget.item?.purchaseUnit,
      usageCount: widget.item?.usageCount ?? 0,
      lastUsedAt: widget.item?.lastUsedAt,
    );
  }

  Future<void> _save({
    bool addAnother = false,
    bool duplicateAsNew = false,
  }) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final authProvider = context.read<AuthProvider>();
      final workspaceId = authProvider.appUser?.currentWorkspaceId;
      if (workspaceId == null) return;

      final item = _buildItem(
        workspaceId: workspaceId,
        duplicateAsNew: duplicateAsNew,
      );

      if (_isEditing && !duplicateAsNew) {
        await _catalogService.updateCatalogItem(workspaceId, item);
      } else {
        await _catalogService.addCatalogItem(workspaceId, item);
      }

      if (!mounted) return;

      if (addAnother) {
        _resetForAnotherEntry();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Catalog item saved. Ready for the next one.'),
          ),
        );
      } else {
        if (duplicateAsNew) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Catalog item duplicated')),
          );
        }
        widget.onSaved?.call();
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.uiMessage(e, action: 'saving item')),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _resetForAnotherEntry() {
    _nameController.clear();
    _descriptionController.clear();
    _unitController.clear();
    _pricing.setValues(cost: 0, price: 0);
    _costTypeController.clear();
    _costCodeController.clear();
    _categoryController.clear();
    _skuController.clear();
    _imageUrlController.clear();

    setState(() {
      _isTaxable = true;
      _advancedExpanded = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildIntroCard(context),
            const SizedBox(height: 20),
            _buildSection(
              context,
              title: 'Core',
              description:
                  'Keep the fields people use most for search and quoting up front.',
              child: Column(
                children: [
                  StackedField(
                    label: 'Name',
                    child: TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'e.g. Interior paint labor',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Required'
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  StackedField(
                    label: 'Description',
                    child: TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText:
                            'Optional scope notes or installation details',
                      ),
                      maxLines: 3,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: StackedField(
                          label: 'Unit',
                          child: TextFormField(
                            controller: _unitController,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'Each, Hour, Lump Sum',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: StackedField(
                          label: 'SKU',
                          child: TextFormField(
                            controller: _skuController,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'Internal code',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: StackedField(
                          label: 'Category',
                          child: TextFormField(
                            controller: _categoryController,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'Painting, Flooring, Demo',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: SwitchListTile(
                          title: const Text('Taxable'),
                          subtitle: const Text('Apply sales tax by default'),
                          value: _isTaxable,
                          onChanged: (value) =>
                              setState(() => _isTaxable = value),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildSection(
              context,
              title: 'Pricing',
              description:
                  'Cost, price, markup, and margin stay linked as you edit.',
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: StackedField(
                          label: 'Unit Cost',
                          child: TextFormField(
                            controller: _pricing.cost,
                            focusNode: _pricing.costFocus,
                            onTap: () => NumericInput.selectAll(_pricing.cost),
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              prefixText: '\$',
                            ),
                            keyboardType: NumericInput.keyboard,
                            inputFormatters: NumericInput.currency,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: StackedField(
                          label: 'Unit Price',
                          child: TextFormField(
                            controller: _pricing.price,
                            focusNode: _pricing.priceFocus,
                            onTap: () => NumericInput.selectAll(_pricing.price),
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              prefixText: '\$',
                            ),
                            keyboardType: NumericInput.keyboard,
                            inputFormatters: NumericInput.currency,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
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
                            ),
                            keyboardType: NumericInput.signedKeyboard,
                            inputFormatters: NumericInput.percent(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: StackedField(
                          label: 'Margin %',
                          child: TextFormField(
                            controller: _pricing.margin,
                            focusNode: _pricing.marginFocus,
                            onTap: () =>
                                NumericInput.selectAll(_pricing.margin),
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              suffixText: '%',
                            ),
                            keyboardType: NumericInput.signedKeyboard,
                            inputFormatters: NumericInput.percent(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildSection(
              context,
              title: 'Company Metadata',
              description:
                  'Optional internal fields used to classify and route catalog items.',
              child: Row(
                children: [
                  Expanded(
                    child: StackedField(
                      label: 'Cost Type',
                      child: DropdownButtonFormField<String>(
                        borderRadius: AppRadius.cardRadius,
                        value: _costTypeController.text.isEmpty
                            ? null
                            : _costTypeController.text,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                        hint: const Text('Select type'),
                        items: const [
                          DropdownMenuItem(
                            value: 'Labor',
                            child: Text('Labor'),
                          ),
                          DropdownMenuItem(
                            value: 'Material',
                            child: Text('Material'),
                          ),
                          DropdownMenuItem(
                            value: 'Subcontractor',
                            child: Text('Subcontractor'),
                          ),
                          DropdownMenuItem(
                            value: 'Other',
                            child: Text('Other'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _costTypeController.text = value ?? '';
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: StackedField(
                      label: 'Cost Code',
                      child: TextFormField(
                        controller: _costCodeController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Optional code',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildAccountingInventorySection(context),
            const SizedBox(height: 20),
            _buildAdvancedSection(context),
            const SizedBox(height: 28),
            _buildActionRow(context),
          ],
        ),
      ),
    );
  }

  Widget _buildIntroCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.r16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isEditing ? 'Edit catalog item' : 'Create catalog item',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            _isEditing
                ? 'Update the company library entry and keep the key pricing fields easy to scan.'
                : 'Add a reusable company catalog entry that can be pulled into ${singularProjectTerminology(context.read<WorkspaceProvider>().projectTerminology).toLowerCase()} budgets.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required String description,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.r16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildAccountingInventorySection(BuildContext context) {
    final usage = widget.item?.usageCount ?? 0;
    return _buildSection(
      context,
      title: 'Accounting & inventory',
      description:
          'Make this item the canonical record across invoices, bills, expenses, and inventory.',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: StackedField(
                  label: 'Item kind',
                  child: DropdownButtonFormField<CatalogKind>(
                    borderRadius: AppRadius.cardRadius,
                    value: _kind,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: CatalogKind.values
                        .map(
                          (k) => DropdownMenuItem(
                            value: k,
                            child: Text(k.label),
                          ),
                        )
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _kind = v ?? CatalogKind.service),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SwitchListTile(
                  title: const Text('Active'),
                  subtitle: const Text('Available in pickers and search'),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: StackedField(
                  label: 'Currency',
                  child: TextFormField(
                    controller: _currencyController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'USD',
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: StackedField(
                  label: 'Default tax rate %',
                  child: TextFormField(
                    controller: _defaultTaxRateController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      suffixText: '%',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: StackedField(
                  label: 'Min price',
                  child: TextFormField(
                    controller: _minPriceController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      prefixText: '\$',
                      hintText: 'Optional floor',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: StackedField(
                  label: 'Barcode / UPC',
                  child: TextFormField(
                    controller: _barcodeController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Scannable code',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: StackedField(
                  label: 'Purchase cost',
                  child: TextFormField(
                    controller: _purchaseCostController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      prefixText: '\$',
                      hintText: 'From vendor',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          StackedField(
            label: 'Purchase description',
            child: TextFormField(
              controller: _purchaseDescriptionController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Shown on bills and expense lines',
              ),
              maxLines: 2,
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Track inventory'),
            subtitle: const Text(
              'Decrement stock when this item is sold or used',
            ),
            value: _inventoryTracked,
            onChanged: (v) => setState(() => _inventoryTracked = v),
            contentPadding: EdgeInsets.zero,
          ),
          if (_isEditing) ...[
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                children: [
                  const Icon(Icons.insights_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Used $usage time${usage == 1 ? '' : 's'}'
                      '${widget.item?.lastUsedAt != null ? ' · last on ${_formatDate(widget.item!.lastUsedAt!)}' : ''}',
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatDate(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  Widget _buildAdvancedSection(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.r16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: ExpansionTile(
        key: ValueKey(_advancedExpanded),
        initiallyExpanded: _advancedExpanded,
        onExpansionChanged: (value) {
          setState(() => _advancedExpanded = value);
        },
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        title: Text(
          'Advanced',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          'Less frequently used fields like image references.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        children: [
          StackedField(
            label: 'Image URL',
            child: TextFormField(
              controller: _imageUrlController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'https://...',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        if (_isEditing)
          OutlinedButton.icon(
            onPressed: _isSaving ? null : () => _save(duplicateAsNew: true),
            icon: const Icon(Icons.content_copy_outlined, size: 18),
            label: const Text('Duplicate as New'),
          ),
        if (!_isEditing)
          OutlinedButton.icon(
            onPressed: _isSaving ? null : () => _save(addAnother: true),
            icon: const Icon(Icons.playlist_add_outlined, size: 18),
            label: const Text('Save and Add Another'),
          ),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isEditing ? 'Update Item' : 'Create Item'),
          ),
        ),
      ],
    );
  }
}
