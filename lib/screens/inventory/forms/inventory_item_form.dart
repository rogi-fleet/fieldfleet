import 'package:flutter/material.dart';

import '../../../models/inventory/inventory_item.dart';
import '../../../models/inventory/inventory_supplier.dart';
import '../../../services/service_locator.dart';
import '../tabs/inventory_items_tab.dart' show inventoryCategoryOptions;
import '../../../theme/theme.dart';

class InventoryItemForm extends StatefulWidget {
  final String workspaceId;
  final InventoryItem? existing;

  const InventoryItemForm({
    super.key,
    required this.workspaceId,
    this.existing,
  });

  @override
  State<InventoryItemForm> createState() => _InventoryItemFormState();
}

class _InventoryItemFormState extends State<InventoryItemForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _sku = TextEditingController();
  final _description = TextEditingController();
  final _unitCost = TextEditingController(text: '0');
  final _unitSale = TextEditingController();
  final _reorder = TextEditingController(text: '0');
  final _location = TextEditingController();
  String _category = 'other';
  String _uom = 'each';
  String? _supplierId;
  List<InventorySupplier> _suppliers = const [];
  bool _saving = false;

  static const _uoms = [
    'each',
    'box',
    'case',
    'gallon',
    'liter',
    'sqft',
    'sqm',
    'lbs',
    'kg',
    'roll',
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e.name;
      _sku.text = e.sku ?? '';
      _description.text = e.description ?? '';
      _unitCost.text = e.unitCost.toString();
      _unitSale.text = e.unitSalePrice?.toString() ?? '';
      _reorder.text = e.reorderPoint.toString();
      _location.text = e.storageLocation ?? '';
      _category = e.category;
      _uom = e.unitOfMeasure;
      _supplierId = e.defaultSupplierId;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final svc = ServiceLocator.inventorySupplierServiceFor(widget.workspaceId);
        final list = await svc.listSuppliers();
        if (mounted) setState(() => _suppliers = list);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _description.dispose();
    _unitCost.dispose();
    _unitSale.dispose();
    _reorder.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final svc = ServiceLocator.inventoryItemServiceFor(widget.workspaceId);
      final item = InventoryItem(
        id: widget.existing?.id ?? '',
        workspaceId: widget.workspaceId,
        name: _name.text.trim(),
        sku: _sku.text.trim().isEmpty ? null : _sku.text.trim(),
        description:
            _description.text.trim().isEmpty ? null : _description.text.trim(),
        category: _category,
        unitOfMeasure: _uom,
        defaultSupplierId: _supplierId,
        unitCost: double.tryParse(_unitCost.text.trim()) ?? 0,
        unitSalePrice: double.tryParse(_unitSale.text.trim()),
        reorderPoint: double.tryParse(_reorder.text.trim()) ?? 0,
        storageLocation:
            _location.text.trim().isEmpty ? null : _location.text.trim(),
        onHandQty: widget.existing?.onHandQty ?? 0,
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );
      if (widget.existing == null) {
        await svc.create(item);
      } else {
        await svc.update(item);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isEdit ? 'Edit item' : 'New inventory item',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _sku,
                      decoration: const InputDecoration(
                        labelText: 'SKU',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _uom,
                      decoration: const InputDecoration(
                        labelText: 'Unit',
                        border: OutlineInputBorder(),
                      ),
                      items: _uoms
                          .map((u) =>
                              DropdownMenuItem(value: u, child: Text(u)))
                          .toList(),
                      onChanged: (v) => setState(() => _uom = v ?? 'each'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: inventoryCategoryOptions
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _category = v ?? 'other'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _supplierId,
                decoration: const InputDecoration(
                  labelText: 'Default supplier',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('— None —'),
                  ),
                  ..._suppliers.map(
                    (s) =>
                        DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
                  ),
                ],
                onChanged: (v) => setState(() => _supplierId = v),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _unitCost,
                      decoration: const InputDecoration(
                        labelText: 'Unit cost',
                        prefixText: '\$ ',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _unitSale,
                      decoration: const InputDecoration(
                        labelText: 'Sale price (optional)',
                        prefixText: '\$ ',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _reorder,
                      decoration: const InputDecoration(
                        labelText: 'Reorder at',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _location,
                decoration: const InputDecoration(
                  labelText: 'Storage location',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              if (isEdit) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.inventory_2, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'On hand: ${widget.existing!.onHandQty.toStringAsFixed(2)} ${widget.existing!.unitOfMeasure}',
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: Text(isEdit ? 'Save' : 'Create'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
