import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'text_selection_utils.dart';

/// Shared building blocks for numeric (money / percent / quantity) text
/// fields, so every form and inline cell accepts the same characters,
/// parses the same way, and fixes the "typing appends to a pre-filled
/// 0.00" problem (caret lands at the end, '45' becomes '0.0045') with the
/// same select-all-on-focus behavior.
abstract final class NumericInput {
  /// Money amounts: unsigned digits with up to two decimals.
  static final List<TextInputFormatter> currency = [
    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
  ];

  /// Money amounts that may be negative (credits, adjustments).
  static final List<TextInputFormatter> signedCurrency = [
    FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d{0,2}')),
  ];

  /// Unsigned decimal quantities (any precision).
  static final List<TextInputFormatter> quantity = [
    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
  ];

  /// Generic decimal that may be negative (custom number fields).
  static final List<TextInputFormatter> signedDecimal = [
    FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*')),
  ];

  /// Percentages. Signed by default (markup/margin can dip below zero);
  /// pass [signed] false for rates that can't be negative (holdback %).
  static List<TextInputFormatter> percent({
    int decimals = 2,
    bool signed = true,
  }) =>
      [
        FilteringTextInputFormatter.allow(
          RegExp('^${signed ? '-?' : ''}\\d*\\.?\\d{0,$decimals}'),
        ),
      ];

  static const TextInputType keyboard =
      TextInputType.numberWithOptions(decimal: true);
  static const TextInputType signedKeyboard =
      TextInputType.numberWithOptions(decimal: true, signed: true);

  /// Parses a user-entered amount; blank or invalid input is 0.
  static double parse(String text) => double.tryParse(text.trim()) ?? 0.0;

  /// Selects the field's entire contents so typing replaces them. Call from
  /// a field's onTap: the tap that focuses a field also places a collapsed
  /// caret AFTER any focus listener runs, so the focus listener alone is
  /// unreliable. Delegates to the neutral [selectAllText] helper, which
  /// name/title edit fields use directly.
  static void selectAll(TextEditingController controller) =>
      selectAllText(controller);

  /// Builds a [FocusNode] that selects the field's entire contents when it
  /// gains focus (covers keyboard/tab traversal; pair with an onTap calling
  /// [selectAll] for pointer focus). Caller owns disposal.
  static FocusNode selectAllOnFocus(TextEditingController controller) =>
      selectAllOnFocusNode(controller);
}
