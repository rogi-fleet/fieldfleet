/// Type of a catalog item. Drives where it is suggested in the UI and what
/// default document wiring is applied when it is added to a document.
enum CatalogKind {
  product('product', 'Product'),
  service('service', 'Service'),
  bundle('bundle', 'Bundle'),
  labor('labor', 'Labor'),
  expense('expense', 'Expense'),
  fee('fee', 'Fee'),
  nonInventory('non_inventory', 'Non-inventory');

  final String wire;
  final String label;
  const CatalogKind(this.wire, this.label);

  static CatalogKind fromWire(String? v) {
    if (v == null) return CatalogKind.service;
    for (final k in CatalogKind.values) {
      if (k.wire == v) return k;
    }
    return CatalogKind.service;
  }
}
