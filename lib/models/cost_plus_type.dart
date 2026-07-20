enum CostPlusType {
  percentage,
  fixedFee;

  String get displayName {
    switch (this) {
      case CostPlusType.percentage:
        return 'Percentage Fee';
      case CostPlusType.fixedFee:
        return 'Fixed Fee';
    }
  }

  static CostPlusType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'percentage':
        return CostPlusType.percentage;
      case 'fixedfee':
      case 'fixed_fee':
        return CostPlusType.fixedFee;
      default:
        return CostPlusType.percentage;
    }
  }

  @override
  String toString() {
    return name;
  }
}
