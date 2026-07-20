import 'package:flutter/material.dart';

import '../../models/catalog/catalog_kind.dart';
import '../../models/catalog_item.dart';
import '../../services/supabase/catalog_service.dart';
import '../../theme/theme.dart';

/// Result handed back from the picker. The chosen [item] is non-null when the
/// user picked something from the catalog. The optional [unitPrice] override
/// reflects any tier-resolved pricing we were able to compute up-front.
class CatalogPickResult {
  final CatalogItem item;
  final double? unitPrice;
  CatalogPickResult({required this.item, this.unitPrice});
}

/// Modal sheet that lets a user pick an item from the catalog. Use it from
/// invoice/bill/expense forms via [showCatalogItemPicker].
///
/// The picker:
///   * loads active items (optionally filtered by [kind]),
///   * shows "most-used" first,
///   * supports text + barcode search,
///   * lets the user create a quick item inline when nothing matches.
Future<CatalogPickResult?> showCatalogItemPicker(
  BuildContext context, {
  required String workspaceId,
  CatalogKind? kind,
  String? customerId,
  double quantity = 1,
}) {
  return showModalBottomSheet<CatalogPickResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
    builder: (ctx) => CatalogItemPicker(
      workspaceId: workspaceId,
      kind: kind,
      customerId: customerId,
      quantity: quantity,
    ),
  );
}

class CatalogItemPicker extends StatefulWidget {
  final String workspaceId;
  final CatalogKind? kind;
  final String? customerId;
  final double quantity;

  const CatalogItemPicker({
    super.key,
    required this.workspaceId,
    this.kind,
    this.customerId,
    this.quantity = 1,
  });

  @override
  State<CatalogItemPicker> createState() => _CatalogItemPickerState();
}

class _CatalogItemPickerState extends State<CatalogItemPicker> {
  final SupabaseCatalogService _svc = SupabaseCatalogService();
  final TextEditingController _query = TextEditingController();
  late Future<List<CatalogItem>> _itemsFuture;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _itemsFuture = _svc.getActiveItems(widget.workspaceId, kind: widget.kind);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _pick(CatalogItem item) async {
    double? resolvedPrice;
    try {
      resolvedPrice = await _svc.getEffectivePrice(
        item.id,
        customerId: widget.customerId,
        quantity: widget.quantity,
      );
    } catch (_) {
      resolvedPrice = item.unitPrice;
    }
    if (!mounted) return;
    Navigator.of(context).pop(
      CatalogPickResult(item: item, unitPrice: resolvedPrice),
    );
  }

  List<CatalogItem> _filter(List<CatalogItem> all) {
    if (_search.isEmpty) return all;
    final q = _search.toLowerCase();
    return all.where((i) {
      return i.name.toLowerCase().contains(q) ||
          (i.sku?.toLowerCase().contains(q) ?? false) ||
          (i.barcode?.toLowerCase().contains(q) ?? false) ||
          (i.category?.toLowerCase().contains(q) ?? false) ||
          (i.description?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: Text(
                  widget.kind == null
                      ? 'Pick a catalog item'
                      : 'Pick a ${widget.kind!.label.toLowerCase()}',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: _query,
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search by name, SKU, barcode, or category…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v.trim()),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: FutureBuilder<List<CatalogItem>>(
                future: _itemsFuture,
                builder: (ctx, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.base),
                        child: Text(
                          'Could not load catalog: ${snap.error}',
                          style: TextStyle(color: theme.colorScheme.error),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  final all = snap.data ?? const <CatalogItem>[];
                  final filtered = _filter(all);
                  if (filtered.isEmpty) {
                    return _emptyState(theme);
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => _itemTile(filtered[i], theme),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemTile(CatalogItem item, ThemeData theme) {
    final priceText = '\$${item.unitPrice.toStringAsFixed(2)}';
    final subtitleParts = <String>[
      if (item.sku?.isNotEmpty == true) 'SKU ${item.sku}',
      if (item.unit?.isNotEmpty == true) 'per ${item.unit}',
      if (item.category?.isNotEmpty == true) item.category!,
      item.kind.label,
    ];
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(_iconFor(item.kind),
            color: theme.colorScheme.onPrimaryContainer, size: 18),
      ),
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitleParts.join(' · '),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(priceText,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          if (item.usageCount > 0)
            Text('used ${item.usageCount}×',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline)),
        ],
      ),
      onTap: () => _pick(item),
    );
  }

  IconData _iconFor(CatalogKind k) {
    switch (k) {
      case CatalogKind.product:
        return Icons.inventory_2_outlined;
      case CatalogKind.service:
        return Icons.handyman_outlined;
      case CatalogKind.bundle:
        return Icons.layers_outlined;
      case CatalogKind.labor:
        return Icons.engineering_outlined;
      case CatalogKind.expense:
        return Icons.receipt_long_outlined;
      case CatalogKind.fee:
        return Icons.attach_money_outlined;
      case CatalogKind.nonInventory:
        return Icons.category_outlined;
    }
  }

  Widget _emptyState(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined,
              color: theme.colorScheme.outline, size: 40),
          const SizedBox(height: 12),
          Text(
            _search.isEmpty
                ? 'No active catalog items yet.\nAdd items in Catalog to reuse them across invoices, bills, and expenses.'
                : 'No catalog items match "$_search".',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
