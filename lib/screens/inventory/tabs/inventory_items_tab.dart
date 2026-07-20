import 'package:flutter/material.dart';

import '../../../models/inventory/inventory_item.dart';
import '../../../services/service_locator.dart';
import '../../../theme/theme.dart';
import '../../../widgets/common/list_skeleton.dart';
import '../forms/inventory_item_form.dart';

/// Stock tab — lists every consumable / supply tracked in the workspace
/// with on-hand qty, unit, reorder threshold, and a per-row action menu
/// for edit / delete / record movement.
class InventoryItemsTab extends StatelessWidget {
  final String workspaceId;
  const InventoryItemsTab({super.key, required this.workspaceId});

  @override
  Widget build(BuildContext context) {
    final service = ServiceLocator.inventoryItemServiceFor(workspaceId);
    return StreamBuilder<List<InventoryItem>>(
      stream: service.watchItems(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const ListSkeleton();
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        final items = snap.data ?? const <InventoryItem>[];
        return Stack(
          children: [
            if (items.isEmpty)
              const _EmptyState(
                icon: Icons.inventory,
                title: 'No inventory items yet',
                subtitle:
                    'Add the consumables and supplies your crews use on jobs '
                    '— drywall mud, plastic sheeting, antimicrobial, etc.',
              )
            else
              ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.base),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _ItemRow(
                  item: items[i],
                  workspaceId: workspaceId,
                ),
              ),
            Positioned(
              bottom: 16,
              right: 16,
              child: FloatingActionButton.extended(
                heroTag: 'inventory_items_fab',
                icon: const Icon(Icons.add),
                label: const Text('New item'),
                onPressed: () => _openForm(context, workspaceId, null),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ItemRow extends StatelessWidget {
  final InventoryItem item;
  final String workspaceId;
  const _ItemRow({required this.item, required this.workspaceId});

  @override
  Widget build(BuildContext context) {
    final low = item.reorderPoint > 0 && item.onHandQty <= item.reorderPoint;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: low
              ? AppColors.warning.withValues(alpha: 0.15)
              : Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.10),
          child: Icon(
            low ? Icons.warning_amber : Icons.inventory_2,
            color: low
                ? AppColors.warning
                : Theme.of(context).colorScheme.primary,
          ),
        ),
        title: Text(item.name),
        subtitle: Text(
          [
            _categoryLabel(item.category),
            if (item.sku != null && item.sku!.isNotEmpty) 'SKU ${item.sku}',
            if (low) 'Below reorder',
          ].join(' · '),
        ),
        trailing: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${item.onHandQty.toStringAsFixed(item.onHandQty.truncateToDouble() == item.onHandQty ? 0 : 2)} ${item.unitOfMeasure}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '\$${item.unitCost.toStringAsFixed(2)} / ${item.unitOfMeasure}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'edit') {
                  _openForm(context, workspaceId, item);
                } else if (v == 'delete') {
                  await ServiceLocator.inventoryItemServiceFor(workspaceId)
                      .delete(item.id);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _categoryLabel(String key) {
  switch (key) {
    case 'antimicrobial':
      return 'Antimicrobial';
    case 'ppe':
      return 'PPE';
    case 'plastic_sheeting':
      return 'Plastic sheeting';
    case 'drywall':
      return 'Drywall';
    case 'lumber':
      return 'Lumber';
    case 'fasteners':
      return 'Fasteners';
    case 'cleaning':
      return 'Cleaning';
    case 'tools_consumable':
      return 'Tools (consumable)';
    default:
      return 'Other';
  }
}

const inventoryCategoryOptions = <MapEntry<String, String>>[
  MapEntry('antimicrobial', 'Antimicrobial'),
  MapEntry('ppe', 'PPE'),
  MapEntry('plastic_sheeting', 'Plastic sheeting'),
  MapEntry('drywall', 'Drywall'),
  MapEntry('lumber', 'Lumber'),
  MapEntry('fasteners', 'Fasteners'),
  MapEntry('cleaning', 'Cleaning'),
  MapEntry('tools_consumable', 'Tools (consumable)'),
  MapEntry('other', 'Other'),
];

void _openForm(BuildContext context, String workspaceId, InventoryItem? item) {
  showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: InventoryItemForm(workspaceId: workspaceId, existing: item),
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.black26),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
