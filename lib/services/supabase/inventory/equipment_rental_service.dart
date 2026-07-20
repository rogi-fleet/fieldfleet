import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/inventory/equipment_rental.dart';

/// Tracks per-job deployments of leasable assets (air movers, dehus, etc.)
/// Closing a rental can optionally invoice it to the project's cost_items
/// so the rental revenue lands in the job Financials.
class SupabaseEquipmentRentalService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final String workspaceId;

  SupabaseEquipmentRentalService({required this.workspaceId});

  Stream<List<EquipmentRental>> watchRentals() {
    return _supabase
        .from('equipment_rentals')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .map((rows) {
          final list = rows.map(EquipmentRental.fromRow).toList();
          // Open rentals first, then most recent.
          list.sort((a, b) {
            if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
            return b.startDate.compareTo(a.startDate);
          });
          return list;
        });
  }

  Stream<List<EquipmentRental>> watchRentalsForProject(String projectId) {
    return _supabase
        .from('equipment_rentals')
        .stream(primaryKey: ['id'])
        .eq('project_id', projectId)
        .map((rows) => rows.map(EquipmentRental.fromRow).toList());
  }

  Stream<List<EquipmentRental>> watchOpenRentalsForAsset(String assetId) {
    return _supabase
        .from('equipment_rentals')
        .stream(primaryKey: ['id'])
        .eq('asset_id', assetId)
        .map((rows) => rows
            .map(EquipmentRental.fromRow)
            .where((r) => r.isOpen)
            .toList());
  }

  Future<EquipmentRental> startRental(EquipmentRental rental) async {
    final user = _supabase.auth.currentUser;
    final data = rental.toDb();
    data['created_by'] = user?.id;
    final row = await _supabase
        .from('equipment_rentals')
        .insert(data)
        .select()
        .single();
    return EquipmentRental.fromRow(row);
  }

  Future<void> update(EquipmentRental rental) async {
    final data = rental.toDb()..['updated_at'] = DateTime.now().toIso8601String();
    await _supabase
        .from('equipment_rentals')
        .update(data)
        .eq('id', rental.id);
  }

  Future<void> delete(String id) async {
    await _supabase.from('equipment_rentals').delete().eq('id', id);
  }

  /// Closes (returns) a rental. If billable and there's no existing cost
  /// item, writes one into the project Financials. Cost insert + rental
  /// close happen atomically inside a Postgres function.
  Future<EquipmentRental> closeRental(
    EquipmentRental rental, {
    DateTime? endDate,
    String assetName = 'Equipment rental',
  }) async {
    final close = endDate ?? DateTime.now();
    final closed = rental.copyWith(endDate: close);
    final days = closed.daysBilled();
    final description =
        '$assetName rental ($days day${days == 1 ? '' : 's'})';
    final endDateStr =
        '${close.year.toString().padLeft(4, '0')}-${close.month.toString().padLeft(2, '0')}-${close.day.toString().padLeft(2, '0')}';

    // Days + billed amount are derived server-side from the stored rental
    // rates so the client cannot inflate or duplicate cost lines through
    // concurrent calls. The function locks the row and is idempotent.
    final newCostItemId = await _supabase.rpc('inventory_close_rental', params: {
      'p_rental_id': rental.id,
      'p_end_date': endDateStr,
      'p_description': description,
    });

    return closed.copyWith(
      costItemId: (newCostItemId as String?) ?? closed.costItemId,
    );
  }
}
