import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/models/document_line_item.dart';
import 'package:taskfleet_ops/models/document_type.dart';

void main() {
  group('LineItemVisibility.fromString', () {
    test('parses canonical database values', () {
      expect(LineItemVisibility.fromString('all'), LineItemVisibility.all);
      expect(
        LineItemVisibility.fromString('top_level'),
        LineItemVisibility.topLevel,
      );
      expect(LineItemVisibility.fromString('none'), LineItemVisibility.none);
    });

    test('accepts the legacy camelCase topLevel value', () {
      expect(
        LineItemVisibility.fromString('topLevel'),
        LineItemVisibility.topLevel,
      );
    });

    test('falls back to all for unknown or null values', () {
      expect(LineItemVisibility.fromString(null), LineItemVisibility.all);
      expect(
        LineItemVisibility.fromString('unexpected'),
        LineItemVisibility.all,
      );
    });
  });

  group('DocumentType line-item behavior', () {
    test('uses cost-side budget values for vendor documents', () {
      expect(DocumentType.requestForBid.usesBudgetUnitCostForLineItems, isTrue);
      expect(DocumentType.purchaseOrder.usesBudgetUnitCostForLineItems, isTrue);
      expect(DocumentType.bill.usesBudgetUnitCostForLineItems, isTrue);
      expect(DocumentType.vendorCredit.usesBudgetUnitCostForLineItems, isTrue);
      expect(DocumentType.expense.usesBudgetUnitCostForLineItems, isTrue);
      expect(DocumentType.vendorRefund.usesBudgetUnitCostForLineItems, isTrue);
    });

    test('uses price-side budget values for customer documents', () {
      expect(DocumentType.quotation.usesBudgetUnitCostForLineItems, isFalse);
      expect(DocumentType.changeOrder.usesBudgetUnitCostForLineItems, isFalse);
      expect(DocumentType.invoice.usesBudgetUnitCostForLineItems, isFalse);
      expect(
        DocumentType.progressInvoice.usesBudgetUnitCostForLineItems,
        isFalse,
      );
      expect(DocumentType.credit.usesBudgetUnitCostForLineItems, isFalse);
      expect(DocumentType.refund.usesBudgetUnitCostForLineItems, isFalse);
    });

    test('request for bid hides internal price columns in previews', () {
      expect(DocumentType.requestForBid.lineItemColumns, const [
        LineItemColumn.description,
        LineItemColumn.quantity,
        LineItemColumn.bidPrice,
        LineItemColumn.bidTotal,
      ]);
    });
  });
}
