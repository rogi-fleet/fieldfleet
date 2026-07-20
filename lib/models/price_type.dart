enum PriceType {
  fixedPrice,
  timeAndMaterial,
  costPlus,
  unitPrice;

  String get displayName {
    switch (this) {
      case PriceType.fixedPrice:
        return 'Fixed Price';
      case PriceType.timeAndMaterial:
        return 'Time & Material';
      case PriceType.costPlus:
        return 'Cost Plus';
      case PriceType.unitPrice:
        return 'Unit Price';
    }
  }

  String get description {
    switch (this) {
      case PriceType.fixedPrice:
        return 'Total project price agreed upfront. Profit = contract amount - actual costs.';
      case PriceType.timeAndMaterial:
        return 'Customer billed for actual hours + materials + markup. Common for uncertain scope.';
      case PriceType.costPlus:
        return 'Customer billed for all costs + agreed percentage or fixed fee. Transparent pricing.';
      case PriceType.unitPrice:
        return 'Pricing based on units of work (e.g., per square foot, per room).';
    }
  }

  static PriceType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'fixedprice':
      case 'fixed_price':
        return PriceType.fixedPrice;
      case 'timeandmaterial':
      case 'time_and_material':
      case 'time&material':
        return PriceType.timeAndMaterial;
      case 'costplus':
      case 'cost_plus':
        return PriceType.costPlus;
      case 'unitprice':
      case 'unit_price':
        return PriceType.unitPrice;
      default:
        return PriceType.timeAndMaterial; // Default fallback
    }
  }

  @override
  String toString() {
    return name;
  }
}
