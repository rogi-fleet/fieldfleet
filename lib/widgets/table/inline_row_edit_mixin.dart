import 'package:flutter/material.dart';

/// Mixin for row widget state classes that share the six common inline-edit
/// controllers: name, description, unit, unit cost, unit price, markup.
///
/// Budget row adds extra controllers (qty, approvedPrice, projectedCost,
/// profit, margin) on top of these; catalog row uses only these six.
///
/// Usage:
/// ```dart
/// class _MyRowState extends State<MyRow> with InlineRowEditMixin {
///   @override
///   void initState() {
///     super.initState();
///     initRowControllers(
///       name: widget.item.name,
///       description: widget.item.description ?? '',
///       unit: widget.item.unit ?? '',
///       unitCost: widget.item.unitCost,
///       unitPrice: widget.item.unitPrice,
///       markup: widget.item.markup,
///     );
///   }
///
///   @override
///   void dispose() {
///     disposeRowControllers();
///     super.dispose();
///   }
/// }
/// ```
mixin InlineRowEditMixin<T extends StatefulWidget> on State<T> {
  late TextEditingController nameController;
  late TextEditingController descriptionController;
  late TextEditingController unitController;
  late TextEditingController unitCostController;
  late TextEditingController unitPriceController;
  late TextEditingController markupController;

  /// Initialises the six shared controllers from current item values.
  ///
  /// [markupFormat] defaults to two decimal places; pass
  /// `(v) => v.toStringAsFixed(1)` for budget rows.
  void initRowControllers({
    required String name,
    String description = '',
    String unit = '',
    required double unitCost,
    required double unitPrice,
    required double markup,
    String Function(double) markupFormat = _twoDecimal,
  }) {
    nameController = TextEditingController(text: name);
    descriptionController = TextEditingController(text: description);
    unitController = TextEditingController(text: unit);
    unitCostController =
        TextEditingController(text: unitCost.toStringAsFixed(2));
    unitPriceController =
        TextEditingController(text: unitPrice.toStringAsFixed(2));
    markupController = TextEditingController(text: markupFormat(markup));
  }

  /// Disposes the six shared controllers. Call before [super.dispose].
  void disposeRowControllers() {
    nameController.dispose();
    descriptionController.dispose();
    unitController.dispose();
    unitCostController.dispose();
    unitPriceController.dispose();
    markupController.dispose();
  }

  static String _twoDecimal(double v) => v.toStringAsFixed(2);
}
