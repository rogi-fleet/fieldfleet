import 'package:flutter/widgets.dart';

import 'numeric_input.dart';
import 'pricing_math.dart';

/// Bundles the cost/price/markup/margin controllers of a pricing form and
/// keeps them consistent without each form re-deriving the relationships:
///
/// - edit **cost** or **markup** → price follows the markup (set your markup
///   once and revising the cost moves the price, not your markup)
/// - edit **price** → markup and margin follow
/// - edit **margin** → price and markup follow
///
/// Also owns select-all-on-focus nodes for each field so a pre-filled
/// "0.00" is replaced rather than appended to. Forms that don't show a
/// margin field simply never render [margin]/[marginFocus].
class PricingFieldsController {
  PricingFieldsController({
    double cost = 0,
    double price = 0,
    this.onChanged,
  })  : cost = TextEditingController(text: cost.toStringAsFixed(2)),
        price = TextEditingController(text: price.toStringAsFixed(2)),
        markup = TextEditingController(
            text: PricingMath.markup(cost, price).toStringAsFixed(2)),
        margin = TextEditingController(
            text: PricingMath.margin(cost, price).toStringAsFixed(2)) {
    costFocus = NumericInput.selectAllOnFocus(this.cost);
    priceFocus = NumericInput.selectAllOnFocus(this.price);
    markupFocus = NumericInput.selectAllOnFocus(markup);
    marginFocus = NumericInput.selectAllOnFocus(margin);
    this.cost.addListener(_handleCostChanged);
    this.price.addListener(_handlePriceChanged);
    markup.addListener(_handleMarkupChanged);
    margin.addListener(_handleMarginChanged);
  }

  final TextEditingController cost;
  final TextEditingController price;
  final TextEditingController markup;
  final TextEditingController margin;

  late final FocusNode costFocus;
  late final FocusNode priceFocus;
  late final FocusNode markupFocus;
  late final FocusNode marginFocus;

  /// Fired after any recompute settles, so hosts can update dependent
  /// totals (e.g. qty × cost) without their own listeners on every field.
  final VoidCallback? onChanged;

  bool _updating = false;

  double get costValue => NumericInput.parse(cost.text);
  double get priceValue => NumericInput.parse(price.text);
  double get markupValue => NumericInput.parse(markup.text);
  double get marginValue => NumericInput.parse(margin.text);

  /// Programmatic prefill (e.g. picking a catalog item): sets cost + price
  /// and derives markup/margin without the edit-listeners fighting over
  /// which field "wins".
  void setValues({required double cost, required double price}) {
    _updating = true;
    this.cost.text = cost.toStringAsFixed(2);
    this.price.text = price.toStringAsFixed(2);
    _setDerived(markup, PricingMath.markup(cost, price));
    _setDerived(margin, PricingMath.margin(cost, price));
    _updating = false;
    onChanged?.call();
  }

  void _handleCostChanged() =>
      _recompute(() => _applyMarkup(markupValue));

  void _handleMarkupChanged() =>
      _recompute(() => _applyMarkup(markupValue));

  void _handlePriceChanged() => _recompute(() {
        _setDerived(markup, PricingMath.markup(costValue, priceValue));
        _setDerived(margin, PricingMath.margin(costValue, priceValue));
      });

  void _handleMarginChanged() => _recompute(() {
        final newPrice = PricingMath.priceFromMargin(costValue, marginValue);
        _setDerived(price, newPrice);
        _setDerived(markup, PricingMath.markup(costValue, newPrice));
      });

  void _applyMarkup(double markupPercent) {
    final newPrice = PricingMath.priceFromMarkup(costValue, markupPercent);
    _setDerived(price, newPrice);
    _setDerived(margin, PricingMath.margin(costValue, newPrice));
  }

  void _recompute(VoidCallback body) {
    if (_updating) return;
    _updating = true;
    body();
    _updating = false;
    onChanged?.call();
  }

  /// Writes a derived field only when its rendered text actually changes,
  /// so idempotent recomputes don't clobber the field's caret/selection.
  void _setDerived(TextEditingController controller, double value) {
    final text = value.toStringAsFixed(2);
    if (controller.text != text) controller.text = text;
  }

  void dispose() {
    cost.dispose();
    price.dispose();
    markup.dispose();
    margin.dispose();
    costFocus.dispose();
    priceFocus.dispose();
    markupFocus.dispose();
    marginFocus.dispose();
  }
}
