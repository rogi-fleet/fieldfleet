import 'package:flutter/material.dart';

import '../../../models/inventory/inventory_supplier.dart';
import '../../../services/service_locator.dart';
import '../../../widgets/common/list_skeleton.dart';
import '../forms/inventory_supplier_form.dart';
import '../../../theme/theme.dart';

class InventorySuppliersTab extends StatelessWidget {
  final String workspaceId;
  const InventorySuppliersTab({super.key, required this.workspaceId});

  @override
  Widget build(BuildContext context) {
    final service = ServiceLocator.inventorySupplierServiceFor(workspaceId);
    return StreamBuilder<List<InventorySupplier>>(
      stream: service.watchSuppliers(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const ListSkeleton();
        }
        final suppliers = snap.data ?? const <InventorySupplier>[];
        return Stack(
          children: [
            if (suppliers.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.xxl),
                  child: Text(
                    'No suppliers yet. Add the vendors you order materials '
                    'and rentals from (Home Depot, Sherwin-Williams, etc.).',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.base),
                itemCount: suppliers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final s = suppliers[i];
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.store)),
                      title: Text(s.name),
                      subtitle: Text(
                        [
                          if (s.contactName != null) s.contactName!,
                          if (s.phone != null) s.phone!,
                          if (s.email != null) s.email!,
                        ].where((e) => e.isNotEmpty).join(' · '),
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'edit') {
                            _openForm(context, workspaceId, s);
                          } else if (v == 'delete') {
                            await service.delete(s.id);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ),
                  );
                },
              ),
            Positioned(
              bottom: 16,
              right: 16,
              child: FloatingActionButton.extended(
                heroTag: 'inventory_suppliers_fab',
                icon: const Icon(Icons.add),
                label: const Text('New supplier'),
                onPressed: () => _openForm(context, workspaceId, null),
              ),
            ),
          ],
        );
      },
    );
  }
}

void _openForm(
  BuildContext context,
  String workspaceId,
  InventorySupplier? existing,
) {
  showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: InventorySupplierForm(
          workspaceId: workspaceId,
          existing: existing,
        ),
      ),
    ),
  );
}
