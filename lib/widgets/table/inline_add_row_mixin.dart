import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Mixin for inline add-row state classes that share the standard set of
/// text field controllers and focus nodes (name, description, unit, unit cost,
/// unit price), plus the scroll-into-view initState pattern.
///
/// Usage:
/// ```dart
/// class _MyAddRowState extends State<MyAddRow> with InlineAddRowMixin {
///   @override
///   void initState() {
///     super.initState();
///     initAddRow();
///   }
///
///   @override
///   void dispose() {
///     disposeAddRow();
///     super.dispose();
///   }
/// }
/// ```
mixin InlineAddRowMixin<T extends StatefulWidget> on State<T> {
  final nameController = TextEditingController();
  final descriptionController = TextEditingController();
  final unitController = TextEditingController();
  final unitCostController = TextEditingController();
  final unitPriceController = TextEditingController();

  final nameFocus = FocusNode();
  final descriptionFocus = FocusNode();
  final unitFocus = FocusNode();
  final unitCostFocus = FocusNode();
  final unitPriceFocus = FocusNode();

  final tapRegionGroup = Object();
  final scrollKey = GlobalKey();

  /// Call from [initState] to focus the name field and scroll the row into view.
  void initAddRow() {
    nameFocus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        scrollKey.currentContext ?? context,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  /// Call from [dispose] (before super.dispose) to clean up the shared resources.
  void disposeAddRow() {
    nameController.dispose();
    descriptionController.dispose();
    unitController.dispose();
    unitCostController.dispose();
    unitPriceController.dispose();
    nameFocus.dispose();
    descriptionFocus.dispose();
    unitFocus.dispose();
    unitCostFocus.dispose();
    unitPriceFocus.dispose();
  }

  /// Returns [KeyEventResult.handled] and calls [onCancel] when Escape is pressed.
  KeyEventResult handleEscapeKey(KeyEvent event, VoidCallback onCancel) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      onCancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}
