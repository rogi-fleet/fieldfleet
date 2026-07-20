import 'package:flutter/widgets.dart';

/// Selects the entire contents of [controller] so the next keystroke
/// replaces them. No-op when the field is empty.
///
/// This is the single home for the "select all" gesture used when a field
/// enters edit mode (name/title cells) or gains focus (numeric fields with
/// pre-filled "0.00" — see NumericInput, which delegates here). When the
/// edit-mode switch rebuilds the field, call this inside a post-frame
/// callback so the new selection isn't clobbered by the focus change.
void selectAllText(TextEditingController controller) {
  if (controller.text.isEmpty) return;
  controller.selection = TextSelection(
    baseOffset: 0,
    extentOffset: controller.text.length,
  );
}

/// Builds a [FocusNode] that selects the field's entire contents when it
/// gains focus (covers keyboard/tab traversal; pair with an onTap calling
/// [selectAllText] for pointer focus — the tap that focuses a field also
/// places a collapsed caret after the focus listener runs). Caller owns
/// disposal.
FocusNode selectAllOnFocusNode(TextEditingController controller) {
  final node = FocusNode();
  node.addListener(() {
    if (node.hasFocus) selectAllText(controller);
  });
  return node;
}
