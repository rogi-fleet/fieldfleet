enum PaymentTerms {
  cod,
  net15,
  net30,
  net60,
  net90,
  dueOnReceipt,
  custom;

  String get displayName {
    switch (this) {
      case PaymentTerms.cod:
        return 'COD (Cash on Delivery)';
      case PaymentTerms.net15:
        return 'Net 15';
      case PaymentTerms.net30:
        return 'Net 30';
      case PaymentTerms.net60:
        return 'Net 60';
      case PaymentTerms.net90:
        return 'Net 90';
      case PaymentTerms.dueOnReceipt:
        return 'Due on Receipt';
      case PaymentTerms.custom:
        return 'Custom Terms';
    }
  }

  /// Convert to database value
  /// DB enum: 'net_cash', 'net_15', 'net_30', 'net_45', 'net_60'
  String toDbValue() {
    switch (this) {
      case PaymentTerms.cod:
      case PaymentTerms.dueOnReceipt:
        return 'net_cash';
      case PaymentTerms.net15:
        return 'net_15';
      case PaymentTerms.net30:
      case PaymentTerms.custom:
        return 'net_30';
      case PaymentTerms.net60:
        return 'net_60';
      case PaymentTerms.net90:
        return 'net_60'; // DB doesn't have net_90
    }
  }

  static PaymentTerms fromString(String value) {
    switch (value.toLowerCase()) {
      case 'net_cash':
      case 'cod':
        return PaymentTerms.cod;
      case 'net_15':
      case 'net15':
        return PaymentTerms.net15;
      case 'net_30':
      case 'net30':
        return PaymentTerms.net30;
      case 'net_45':
        return PaymentTerms.net30; // No exact match, use net30
      case 'net_60':
      case 'net60':
        return PaymentTerms.net60;
      case 'net90':
        return PaymentTerms.net90;
      case 'dueonreceipt':
        return PaymentTerms.dueOnReceipt;
      case 'custom':
        return PaymentTerms.custom;
      default:
        return PaymentTerms.net30;
    }
  }
}
