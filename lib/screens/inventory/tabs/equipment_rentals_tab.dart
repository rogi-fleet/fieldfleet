import 'package:flutter/material.dart';

import '../../../models/inventory/equipment_rental.dart';
import '../../../services/service_locator.dart';
import '../../../theme/theme.dart';
import '../../../widgets/common/list_skeleton.dart';
import '../forms/equipment_rental_form.dart';

class EquipmentRentalsTab extends StatelessWidget {
  final String workspaceId;
  const EquipmentRentalsTab({super.key, required this.workspaceId});

  @override
  Widget build(BuildContext context) {
    final service = ServiceLocator.equipmentRentalServiceFor(workspaceId);
    return StreamBuilder<List<EquipmentRental>>(
      stream: service.watchRentals(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const ListSkeleton();
        }
        final rentals = snap.data ?? const <EquipmentRental>[];
        final open = rentals.where((r) => r.isOpen).toList();
        final closed = rentals.where((r) => !r.isOpen).toList();
        return Stack(
          children: [
            if (rentals.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.xxl),
                  child: Text(
                    'No equipment rentals yet. When you deploy a leasable '
                    'asset (air mover, dehu, scrubber) to a job, start a '
                    'rental here so the daily rate is billed back.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              ListView(
                padding: const EdgeInsets.all(AppSpacing.base),
                children: [
                  if (open.isNotEmpty) ...[
                    Text('Open rentals',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    for (final r in open)
                      _RentalRow(rental: r, workspaceId: workspaceId),
                    const SizedBox(height: 24),
                  ],
                  if (closed.isNotEmpty) ...[
                    Text('Closed rentals',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    for (final r in closed)
                      _RentalRow(rental: r, workspaceId: workspaceId),
                  ],
                ],
              ),
            Positioned(
              bottom: 16,
              right: 16,
              child: FloatingActionButton.extended(
                heroTag: 'equipment_rentals_fab',
                icon: const Icon(Icons.add),
                label: const Text('Start rental'),
                onPressed: () => _openForm(context, workspaceId, null),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RentalRow extends StatelessWidget {
  final EquipmentRental rental;
  final String workspaceId;
  const _RentalRow({required this.rental, required this.workspaceId});

  @override
  Widget build(BuildContext context) {
    final billed = rental.billedAmount();
    final days = rental.daysBilled();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: rental.isOpen
              ? AppColors.info.withValues(alpha: 0.15)
              : AppColors.success.withValues(alpha: 0.15),
          child: Icon(
            rental.isOpen ? Icons.air : Icons.check,
            color: rental.isOpen ? AppColors.info : AppColors.success,
          ),
        ),
        title: Text('Rental ${rental.id.substring(0, 6)}'),
        subtitle: Text(
          [
            'Started ${_d(rental.startDate)}',
            if (rental.endDate != null) 'Ended ${_d(rental.endDate!)}',
            '$days day${days == 1 ? '' : 's'}',
            if (billed > 0) '\$${billed.toStringAsFixed(2)}',
            if (rental.isBillable) 'Billable' else 'Non-billable',
          ].join(' · '),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            final svc = ServiceLocator.equipmentRentalServiceFor(workspaceId);
            if (v == 'close' && rental.isOpen) {
              await svc.closeRental(rental);
            } else if (v == 'edit') {
              _openForm(context, workspaceId, rental);
            } else if (v == 'delete') {
              await svc.delete(rental.id);
            }
          },
          itemBuilder: (_) => [
            if (rental.isOpen)
              const PopupMenuItem(value: 'close', child: Text('Close rental')),
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }

  String _d(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

void _openForm(
  BuildContext context,
  String workspaceId,
  EquipmentRental? existing,
) {
  showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: EquipmentRentalForm(
          workspaceId: workspaceId,
          existing: existing,
        ),
      ),
    ),
  );
}
