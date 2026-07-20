import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/inventory/inventory_item.dart';

class SupabaseInventoryItemService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final String workspaceId;

  SupabaseInventoryItemService({required this.workspaceId});

  Stream<List<InventoryItem>> watchItems() {
    return _supabase
        .from('inventory_items')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .map((rows) {
          final list = rows.map(InventoryItem.fromRow).toList();
          list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          return list;
        });
  }

  Future<List<InventoryItem>> listItems() async {
    final rows = await _supabase
        .from('inventory_items')
        .select()
        .eq('workspace_id', workspaceId)
        .order('name');
    return (rows as List).map((r) => InventoryItem.fromRow(r as Map<String, dynamic>)).toList();
  }

  Future<InventoryItem?> getItem(String id) async {
    final row = await _supabase
        .from('inventory_items')
        .select()
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : InventoryItem.fromRow(row);
  }

  Future<InventoryItem> create(InventoryItem item) async {
    final user = _supabase.auth.currentUser;
    final data = item.toDb();
    data['created_by'] = user?.id;
    final row = await _supabase
        .from('inventory_items')
        .insert(data)
        .select()
        .single();
    return InventoryItem.fromRow(row);
  }

  Future<void> update(InventoryItem item) async {
    final data = item.toDb()..['updated_at'] = DateTime.now().toIso8601String();
    await _supabase.from('inventory_items').update(data).eq('id', item.id);
  }

  Future<void> delete(String id) async {
    await _supabase.from('inventory_items').delete().eq('id', id);
  }
}
