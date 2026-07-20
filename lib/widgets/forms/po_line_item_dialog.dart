/// Shared "Add line item" dialog used by the Materials, Rentals, and
/// Subcontracts boards. Captures description, quantity, unit, unit cost,
/// and (optionally) a budget category so the line is tied back to the
/// budget as a tracked commitment.
library;

import 'package:flutter/material.dart';

import '../../models/budget_item.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';

/// Result returned by [PoLineItemDialog] when the user submits.
class PoLineItemResult {
  final String description;
  final double quantity;
  final String? unit;
  final double unitCost;
  final String? budgetItemId;

  const PoLineItemResult({
    required this.description,
    this.quantity = 1,
    this.unit,
    this.unitCost = 0,
    this.budgetItemId,
  });
}

/// Shows the dialog; returns `null` on cancel.
Future<PoLineItemResult?> showPoLineItemDialog(
  BuildContext context, {
  required String projectId,
  required String workspaceId,
  String title = 'Add item',
}) {
  return showDialog<PoLineItemResult>(
    context: context,
    builder: (_) => PoLineItemDialog(
      projectId: projectId,
      workspaceId: workspaceId,
      title: title,
    ),
  );
}

class PoLineItemDialog extends StatefulWidget {
  final String projectId;
  final String workspaceId;
  final String title;
  const PoLineItemDialog({
    super.key,
    required this.projectId,
    required this.workspaceId,
    this.title = 'Add item',
  });

  @override
  State<PoLineItemDialog> createState() => _PoLineItemDialogState();
}

class _PoLineItemDialogState extends State<PoLineItemDialog> {
  final _desc = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _unit = TextEditingController();
  final _cost = TextEditingController(text: '0');
  String? _budgetItemId;

  @override
  void dispose() {
    _desc.dispose();
    _qty.dispose();
    _unit.dispose();
    _cost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _desc,
              decoration: const InputDecoration(labelText: 'Description *'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _qty,
                    decoration: const InputDecoration(labelText: 'Qty'),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _unit,
                    decoration: const InputDecoration(labelText: 'Unit'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _cost,
                    decoration: const InputDecoration(labelText: 'Unit cost'),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            StreamBuilder<List<BudgetItem>>(
              stream: ServiceLocator.budgetService.getBudgetItems(
                widget.projectId,
                workspaceId: widget.workspaceId,
              ),
              builder: (context, snap) {
                final all = snap.data ?? const <BudgetItem>[];
                // Only leaf items (type == item) can receive commitments.
                final leaves = all
                    .where((b) => b.itemType == BudgetItemType.item)
                    .toList()
                  ..sort((a, b) => a.name.toLowerCase()
                      .compareTo(b.name.toLowerCase()));
                return DropdownButtonFormField<String?>(
                  isExpanded: true,
                  value: _budgetItemId,
                  decoration: const InputDecoration(
                    labelText: 'Budget category',
                    helperText:
                        'Tie this line to a budget item to track committed cost.',
                    helperMaxLines: 2,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('— None —',
                          style: TextStyle(color: AppColors.textTertiary)),
                    ),
                    for (final b in leaves)
                      DropdownMenuItem<String?>(
                        value: b.id,
                        child: Text(
                          b.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _budgetItemId = v),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            if (_desc.text.trim().isEmpty) return;
            Navigator.of(context).pop(PoLineItemResult(
              description: _desc.text.trim(),
              quantity: double.tryParse(_qty.text.trim()) ?? 1,
              unit: _unit.text.trim().isEmpty ? null : _unit.text.trim(),
              unitCost: double.tryParse(_cost.text.trim()) ?? 0,
              budgetItemId: _budgetItemId,
            ));
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
