import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/utils/numeric_input.dart';
import 'package:taskfleet_ops/utils/pricing_fields.dart';
import 'package:taskfleet_ops/utils/pricing_math.dart';

void main() {
  group('PricingMath', () {
    test('markup and margin from cost/price', () {
      expect(PricingMath.markup(100, 125), 25);
      expect(PricingMath.margin(100, 125), 20);
      expect(PricingMath.markup(0, 50), 0);
      expect(PricingMath.margin(100, 0), 0);
    });

    test('price from markup and margin', () {
      expect(PricingMath.priceFromMarkup(100, 25), 125);
      expect(PricingMath.priceFromMargin(100, 20), closeTo(125, 0.0001));
      // 100% margin guard: falls back to cost instead of dividing by zero.
      expect(PricingMath.priceFromMargin(100, 100), 100);
    });

    test('markup % <-> margin % conversions', () {
      expect(PricingMath.marginFromMarkup(25), closeTo(20, 0.0001));
      expect(PricingMath.markupFromMargin(20), closeTo(25, 0.0001));
      // Division-by-zero guards.
      expect(PricingMath.marginFromMarkup(-100), 0);
      expect(PricingMath.markupFromMargin(100), 0);
    });
  });

  group('NumericInput.parse', () {
    test('parses amounts and falls back to zero', () {
      expect(NumericInput.parse('12.50'), 12.50);
      expect(NumericInput.parse(' 7 '), 7);
      expect(NumericInput.parse(''), 0);
      expect(NumericInput.parse('abc'), 0);
    });
  });

  group('PricingFieldsController', () {
    late PricingFieldsController pricing;

    tearDown(() => pricing.dispose());

    test('initializes derived markup/margin from cost and price', () {
      pricing = PricingFieldsController(cost: 100, price: 125);
      expect(pricing.cost.text, '100.00');
      expect(pricing.price.text, '125.00');
      expect(pricing.markup.text, '25.00');
      expect(pricing.margin.text, '20.00');
    });

    test('editing price recomputes markup and margin', () {
      pricing = PricingFieldsController(cost: 100, price: 100);
      pricing.price.text = '150';
      expect(pricing.markup.text, '50.00');
      expect(pricing.margin.text, '33.33');
    });

    test('editing markup recomputes price and margin', () {
      pricing = PricingFieldsController(cost: 200, price: 200);
      pricing.markup.text = '25';
      expect(pricing.price.text, '250.00');
      expect(pricing.margin.text, '20.00');
    });

    test('editing margin recomputes price and markup', () {
      pricing = PricingFieldsController(cost: 100, price: 100);
      pricing.margin.text = '20';
      expect(pricing.price.text, '125.00');
      expect(pricing.markup.text, '25.00');
    });

    test('editing cost keeps markup and moves the price', () {
      pricing = PricingFieldsController(cost: 100, price: 125);
      expect(pricing.markup.text, '25.00');
      pricing.cost.text = '200';
      expect(pricing.price.text, '250.00');
      expect(pricing.markup.text, '25.00');
      expect(pricing.margin.text, '20.00');
    });

    test('setValues prefills cost+price and derives the percents', () {
      pricing = PricingFieldsController();
      pricing.setValues(cost: 80, price: 100);
      expect(pricing.cost.text, '80.00');
      expect(pricing.price.text, '100.00');
      expect(pricing.markup.text, '25.00');
      expect(pricing.margin.text, '20.00');
    });

    test('notifies onChanged after recomputes settle', () {
      var notified = 0;
      pricing = PricingFieldsController(
        cost: 100,
        price: 100,
        onChanged: () => notified++,
      );
      pricing.price.text = '150';
      expect(notified, greaterThan(0));
      expect(pricing.markupValue, 50);
      expect(pricing.priceValue, 150);
    });
  });
}
