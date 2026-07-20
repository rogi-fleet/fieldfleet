import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/inventory/inventory_supplier.dart';

/// CRUD for [InventorySupplier]. RLS scopes everything to the caller's
/// workspace, but we still pass the workspaceId on insert.
class SupabaseInventorySupplierService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final String workspaceId;

  SupabaseInventorySupplierService({required this.workspaceId});

  Stream<List<InventorySupplier>> watchSuppliers() {
    return _supabase
        .from('inventory_suppliers')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .map((rows) {
          final list = rows.map(InventorySupplier.fromRow).toList();
          list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          return list;
        });
  }

  Future<List<InventorySupplier>> listSuppliers() async {
    final rows = await _supabase
        .from('inventory_suppliers')
        .select()
        .eq('workspace_id', workspaceId)
        .order('name');
    return (rows as List).map((r) => InventorySupplier.fromRow(r as Map<String, dynamic>)).toList();
  }

  Future<InventorySupplier> create(InventorySupplier supplier) async {
    final user = _supabase.auth.currentUser;
    final data = supplier.toDb();
    data['created_by'] = user?.id;
    final row = await _supabase
        .from('inventory_suppliers')
        .insert(data)
        .select()
        .single();
    return InventorySupplier.fromRow(row);
  }

  Future<void> update(InventorySupplier supplier) async {
    final data = supplier.toDb()..['updated_at'] = DateTime.now().toIso8601String();
    await _supabase
        .from('inventory_suppliers')
        .update(data)
        .eq('id', supplier.id);
  }

  Future<void> delete(String id) async {
    await _supabase.from('inventory_suppliers').delete().eq('id', id);
  }
}
