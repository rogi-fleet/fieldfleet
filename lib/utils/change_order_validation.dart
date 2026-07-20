import '../models/document_line_item.dart';

/// Pure validation helpers for change-order documents.
///
/// A change order amends the **existing approved contract** — every visible
/// leaf line item on a CO must therefore be linked to an existing budget
/// item (`budgetItemId` set) and there must be at least one such line.
///
/// Kept as a top-level utility so the create-document form *and* unit tests
/// can share the exact same rules, instead of duplicating the predicate
/// across the UI and a test fixture.
class ChangeOrderValidation {
  ChangeOrderValidation._();

  /// Visible leaf items (`isItem && isVisible`) that aren't linked to a
  /// budget item. These are the lines a save-time guard should reject on a
  /// CO. Group rows and hidden rows are ignored: groups don't carry money,
  /// hidden lines aren't part of the customer-visible scope being amended.
  static List<DocumentLineItem> unlinkedVisibleLeaves(
    Iterable<DocumentLineItem> items,
  ) {
    return items
        .where((li) => li.type == DocumentLineItemType.item && li.isVisible)
        .where((li) => (li.budgetItemId ?? '').isEmpty)
        .toList(growable: false);
  }

  /// Whether the document has at least one item-type line at all (visible or
  /// not). Used to distinguish "empty CO — pick something from the budget"
  /// from "CO has lines but some are free-form — fix or remove them".
  static bool hasAnyItemLine(Iterable<DocumentLineItem> items) {
    return items.any((li) => li.type == DocumentLineItemType.item);
  }

  /// Returns the user-facing validation message for a CO, or null if the
  /// items are valid.
  static String? messageFor(Iterable<DocumentLineItem> items) {
    final unlinked = unlinkedVisibleLeaves(items);
    if (unlinked.isEmpty && !hasAnyItemLine(items)) {
      return 'Add at least one line item from the budget. Change orders '
          'can only amend existing approved budget items.';
    }
    if (unlinked.isNotEmpty) {
      return 'Every line on a change order must be picked from the '
          'existing approved budget. Remove the ${unlinked.length} '
          'free-form line${unlinked.length == 1 ? '' : 's'} or '
          'replace ${unlinked.length == 1 ? 'it' : 'them'} via '
          '"Import from Budget".';
    }
    return null;
  }
}
