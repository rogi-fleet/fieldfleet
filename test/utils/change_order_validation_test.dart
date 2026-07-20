import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/models/document_line_item.dart';
import 'package:taskfleet_ops/utils/change_order_validation.dart';

/// Test fixture for a single document line item. Keeps the test bodies
/// short and makes the intent of each case obvious (linked vs. free-form,
/// item vs. group, visible vs. hidden).
DocumentLineItem _line({
  required String id,
  String? budgetItemId,
  DocumentLineItemType type = DocumentLineItemType.item,
  bool isVisible = true,
  double quantity = 1,
  double unitPrice = 100,
}) {
  return DocumentLineItem(
    id: id,
    budgetItemId: budgetItemId,
    type: type,
    sortOrder: 0,
    name: id,
    quantity: quantity,
    unitPrice: unitPrice,
    isVisible: isVisible,
  );
}

void main() {
  group('ChangeOrderValidation.unlinkedVisibleLeaves', () {
    test('treats every visible item without a budgetItemId as unlinked', () {
      final result = ChangeOrderValidation.unlinkedVisibleLeaves([
        _line(id: 'a', budgetItemId: null),
        _line(id: 'b', budgetItemId: 'bi-1'),
        _line(id: 'c', budgetItemId: ''),
      ]);
      expect(result.map((l) => l.id).toList(), ['a', 'c']);
    });

    test('ignores group rows even when they have no budgetItemId', () {
      final result = ChangeOrderValidation.unlinkedVisibleLeaves([
        _line(id: 'g', type: DocumentLineItemType.group, budgetItemId: null),
        _line(id: 'a', budgetItemId: 'bi-1'),
      ]);
      expect(result, isEmpty);
    });

    test('ignores hidden items', () {
      // Hidden items aren't part of the customer-visible scope, so they
      // shouldn't count as an "unlinked" line that needs fixing.
      final result = ChangeOrderValidation.unlinkedVisibleLeaves([
        _line(id: 'a', budgetItemId: null, isVisible: false),
        _line(id: 'b', budgetItemId: 'bi-1'),
      ]);
      expect(result, isEmpty);
    });
  });

  group('ChangeOrderValidation.messageFor', () {
    test('null when every visible leaf is linked to a budget item', () {
      final result = ChangeOrderValidation.messageFor([
        _line(id: 'a', budgetItemId: 'bi-1'),
        _line(id: 'b', budgetItemId: 'bi-2'),
      ]);
      expect(result, isNull);
    });

    test('null when only groups and hidden free-form lines remain', () {
      // A CO with just a group header (no money) but at least one linked
      // visible item is still a no-op for the validator; the linked item
      // carries the change.
      final result = ChangeOrderValidation.messageFor([
        _line(id: 'g', type: DocumentLineItemType.group, budgetItemId: null),
        _line(id: 'a', budgetItemId: 'bi-1'),
        _line(id: 'b', budgetItemId: null, isVisible: false),
      ]);
      expect(result, isNull);
    });

    test('asks for at least one line when the CO is empty', () {
      final result = ChangeOrderValidation.messageFor(const []);
      expect(result, isNotNull);
      expect(result, contains('Add at least one line item from the budget'));
    });

    test('asks for at least one line when only an empty group is present', () {
      // A group header with nothing inside is not an amendable scope —
      // surface the same "empty CO" message.
      final result = ChangeOrderValidation.messageFor([
        _line(id: 'g', type: DocumentLineItemType.group, budgetItemId: null),
      ]);
      expect(result, isNotNull);
      expect(result, contains('Add at least one line item from the budget'));
    });

    test('counts free-form lines in singular form for one violation', () {
      final result = ChangeOrderValidation.messageFor([
        _line(id: 'a', budgetItemId: null),
        _line(id: 'b', budgetItemId: 'bi-1'),
      ]);
      expect(result, isNotNull);
      expect(result, contains('1 free-form line'));
      // Singular pronoun.
      expect(result, contains('replace it'));
    });

    test('counts free-form lines in plural form for multiple violations', () {
      final result = ChangeOrderValidation.messageFor([
        _line(id: 'a', budgetItemId: null),
        _line(id: 'b', budgetItemId: null),
        _line(id: 'c', budgetItemId: 'bi-1'),
      ]);
      expect(result, isNotNull);
      expect(result, contains('2 free-form lines'));
      expect(result, contains('replace them'));
    });

    test('explains why a CO needs budget-linked lines', () {
      // The phrasing is part of the contract with the UI — without the
      // explanation the user sees a bare "invalid" message and can't tell
      // what's wrong.
      final result = ChangeOrderValidation.messageFor([
        _line(id: 'a', budgetItemId: null),
      ]);
      expect(result, contains('"Import from Budget"'));
    });
  });
}
