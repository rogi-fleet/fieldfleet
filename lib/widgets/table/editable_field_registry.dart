import 'package:flutter/services.dart';

/// Describes a single editable field in a row for keyboard navigation.
class EditableFieldEntry {
  const EditableFieldEntry({
    required this.id,
    required this.isEditing,
    required this.enter,
    required this.save,
    required this.cancel,
  });

  final String id;
  final bool Function() isEditing;
  final VoidCallback enter;
  final VoidCallback save;
  final VoidCallback cancel;
}

/// Coordinates Tab / Shift+Tab / Escape keyboard navigation between
/// editable fields within a single row.
class EditableFieldRegistry {
  EditableFieldRegistry(this.fields);

  final List<EditableFieldEntry> fields;

  /// Handle a key event for the field identified by [currentFieldId].
  /// Returns `true` if the event was consumed.
  bool handleKeyEvent(KeyEvent event, String currentFieldId) {
    if (event is! KeyDownEvent) return false;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      final field = fields.firstWhere(
        (f) => f.id == currentFieldId,
        orElse: () => fields.first,
      );
      field.cancel();
      return true;
    }

    if (event.logicalKey == LogicalKeyboardKey.tab) {
      final currentIndex = fields.indexWhere((f) => f.id == currentFieldId);
      if (currentIndex < 0) return false;

      // Save the current field
      fields[currentIndex].save();

      final isShift = HardwareKeyboard.instance.isShiftPressed;
      final nextIndex = isShift ? currentIndex - 1 : currentIndex + 1;
      if (nextIndex >= 0 && nextIndex < fields.length) {
        // Defer entry to let save complete
        Future.microtask(() => fields[nextIndex].enter());
      }
      return true;
    }

    return false;
  }
}
