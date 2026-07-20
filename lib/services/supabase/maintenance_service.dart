import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/maintenance_log.dart';

/// Entity-agnostic CRUD over the `maintenance_logs` table.
///
/// Both assets and vehicles store their service history here, scoped by
/// `entity_id` + `entity_type`. RLS handles workspace isolation.
class SupabaseMaintenanceService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Live stream of logs for one entity, newest first.
  Stream<List<MaintenanceLog>> streamLogs(String entityId) {
    return _supabase
        .from('maintenance_logs')
        .stream(primaryKey: ['id'])
        .eq('entity_id', entityId)
        .order('date', ascending: false)
        .map((data) => data.map(_toLog).toList());
  }

  /// One-shot fetch — used for per-row indicators on list screens where
  /// streaming every entity's logs would be wasteful.
  Future<List<MaintenanceLog>> getLogsOnce(String entityId) async {
    final response = await _supabase
        .from('maintenance_logs')
        .select()
        .eq('entity_id', entityId)
        .order('date', ascending: false);
    return (response as List).map((row) => _toLog(row)).toList();
  }

  Future<MaintenanceLog> addLog(MaintenanceLog log) async {
    final response = await _supabase
        .from('maintenance_logs')
        .insert(_toRow(log))
        .select()
        .single();
    return _toLog(response);
  }

  Future<void> updateLog(MaintenanceLog log) async {
    await _supabase
        .from('maintenance_logs')
        .update(_toRow(log))
        .eq('id', log.id);
  }

  Future<void> deleteLog(String logId) async {
    await _supabase.from('maintenance_logs').delete().eq('id', logId);
  }

  MaintenanceLog _toLog(Map<String, dynamic> row) {
    return MaintenanceLog(
      id: row['id'],
      workspaceId: row['workspace_id'] ?? '',
      entityId: row['entity_id'] ?? '',
      entityType: row['entity_type'] ?? 'asset',
      date: row['date'] != null
          ? DateTime.parse(row['date'])
          : DateTime.now(),
      type: row['type'] ?? 'other',
      description: row['description'] ?? '',
      cost: (row['cost'] as num?)?.toDouble() ?? 0.0,
      performedBy: row['performed_by'],
      nextMaintenanceDate: row['next_maintenance_date'] != null
          ? DateTime.parse(row['next_maintenance_date'])
          : null,
      nextMaintenanceMileage: row['next_maintenance_mileage'],
    );
  }

  Map<String, dynamic> _toRow(MaintenanceLog log) {
    return {
      'workspace_id': log.workspaceId,
      'entity_id': log.entityId,
      'entity_type': log.entityType,
      'type': log.type,
      'description': log.description,
      'date': log.date.toIso8601String(),
      'cost': log.cost,
      'performed_by': log.performedBy,
      'next_maintenance_date': log.nextMaintenanceDate?.toIso8601String(),
      'next_maintenance_mileage': log.nextMaintenanceMileage,
    };
  }
}
