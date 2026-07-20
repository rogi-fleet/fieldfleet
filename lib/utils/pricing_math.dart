/// The cost / price / markup% / margin% relationships used everywhere
/// pricing is entered or displayed (catalog items, budget items, inline
/// grid cells). Single home for the math that was previously reimplemented
/// per form. Pure Dart — safe to use from models.
abstract final class PricingMath {
  static double markup(double cost, double price) =>
      cost == 0 ? 0 : ((price - cost) / cost) * 100;

  static double margin(double cost, double price) =>
      price == 0 ? 0 : ((price - cost) / price) * 100;

  static double priceFromMarkup(double cost, double markupPercent) =>
      cost * (1 + markupPercent / 100);

  static double priceFromMargin(double cost, double marginPercent) =>
      marginPercent >= 100 ? cost : cost / (1 - marginPercent / 100);

  /// Equivalent margin % for a markup % (25% markup ↔ 20% margin).
  static double marginFromMarkup(double markupPercent) {
    final denominator = 100 + markupPercent;
    if (denominator == 0) return 0;
    return (markupPercent / denominator) * 100;
  }

  /// Equivalent markup % for a margin % (20% margin ↔ 25% markup).
  static double markupFromMargin(double marginPercent) {
    final denominator = 100 - marginPercent;
    if (denominator == 0) return 0;
    return (marginPercent / denominator) * 100;
  }
}
