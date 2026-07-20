/// Tiered pricing entry — either customer-specific or a named tier
/// ("retail", "wholesale"…), optionally with a volume break and a date window.
class CatalogPriceTier {
  final String id;
  final String workspaceId;
  final String catalogItemId;
  final String? customerId;
  final String? tierName;
  final double minQuantity;
  final double unitPrice;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String? notes;

  CatalogPriceTier({
    required this.id,
    required this.workspaceId,
    required this.catalogItemId,
    this.customerId,
    this.tierName,
    this.minQuantity = 1,
    required this.unitPrice,
    this.startsAt,
    this.endsAt,
    this.notes,
  });

  factory CatalogPriceTier.fromRow(Map<String, dynamic> r) => CatalogPriceTier(
        id: r['id'] as String,
        workspaceId: r['workspace_id'] as String,
        catalogItemId: r['catalog_item_id'] as String,
        customerId: r['customer_id'] as String?,
        tierName: r['tier_name'] as String?,
        minQuantity: (r['min_quantity'] as num?)?.toDouble() ?? 1.0,
        unitPrice: (r['unit_price'] as num).toDouble(),
        startsAt: r['starts_at'] == null
            ? null
            : DateTime.parse(r['starts_at'] as String),
        endsAt: r['ends_at'] == null
            ? null
            : DateTime.parse(r['ends_at'] as String),
        notes: r['notes'] as String?,
      );

  Map<String, dynamic> toInsert() => {
        'workspace_id': workspaceId,
        'catalog_item_id': catalogItemId,
        'customer_id': customerId,
        'tier_name': tierName,
        'min_quantity': minQuantity,
        'unit_price': unitPrice,
        'starts_at': startsAt?.toIso8601String().substring(0, 10),
        'ends_at': endsAt?.toIso8601String().substring(0, 10),
        'notes': notes,
      };
}
