/// A single line in a bundle's recipe — references a child catalog item and
/// the quantity of it that the bundle includes.
class CatalogBundleComponent {
  final String id;
  final String workspaceId;
  final String bundleId;
  final String componentId;
  final double quantity;
  final int sortOrder;

  CatalogBundleComponent({
    required this.id,
    required this.workspaceId,
    required this.bundleId,
    required this.componentId,
    this.quantity = 1,
    this.sortOrder = 0,
  });

  factory CatalogBundleComponent.fromRow(Map<String, dynamic> r) =>
      CatalogBundleComponent(
        id: r['id'] as String,
        workspaceId: r['workspace_id'] as String,
        bundleId: r['bundle_id'] as String,
        componentId: r['component_id'] as String,
        quantity: (r['quantity'] as num?)?.toDouble() ?? 1.0,
        sortOrder: (r['sort_order'] as int?) ?? 0,
      );

  Map<String, dynamic> toInsert() => {
        'workspace_id': workspaceId,
        'bundle_id': bundleId,
        'component_id': componentId,
        'quantity': quantity,
        'sort_order': sortOrder,
      };
}
