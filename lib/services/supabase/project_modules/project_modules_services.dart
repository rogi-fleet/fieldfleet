import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/project_modules/warranty.dart';
import '../../../models/project_modules/daily_log.dart';
import '../../../models/project_modules/inspection.dart';
import '../../../models/project_modules/punch_list.dart';

/// Project-scoped services for Warranties, Daily Logs, Inspections, and
/// Punch Lists. Each is constructed with both workspaceId (for RLS scoping)
/// and projectId (the parent project). RLS already enforces workspace access.
SupabaseClient get _db => Supabase.instance.client;

// ============================================================================
// Warranties
// ============================================================================
class ProjectWarrantyService {
  final String workspaceId;
  final String projectId;
  ProjectWarrantyService({required this.workspaceId, required this.projectId});

  Stream<List<ProjectWarranty>> watchWarranties() => _db
    .from('project_warranties').stream(primaryKey: ['id'])
    .eq('project_id', projectId)
    .map((rows) {
      final list = rows.map(ProjectWarranty.fromRow).toList();
      list.sort((a, b) {
        final ae = a.endsOn ?? DateTime(9999);
        final be = b.endsOn ?? DateTime(9999);
        return ae.compareTo(be);
      });
      return list;
    });

  Future<ProjectWarranty> createWarranty(ProjectWarranty w) async {
    final row = await _db.from('project_warranties').insert(w.toInsert())
      .select().single();
    return ProjectWarranty.fromRow(row);
  }

  Future<void> updateWarranty(String id, Map<String, dynamic> patch) async {
    patch['updated_at'] = DateTime.now().toIso8601String();
    await _db.from('project_warranties').update(patch).eq('id', id);
  }

  Future<void> deleteWarranty(String id) async {
    await _db.from('project_warranties').delete().eq('id', id);
  }

  // Claims
  Stream<List<ProjectWarrantyClaim>> watchClaims(String warrantyId) => _db
    .from('project_warranty_claims').stream(primaryKey: ['id'])
    .eq('warranty_id', warrantyId)
    .map((rows) => rows.map(ProjectWarrantyClaim.fromRow).toList()
      ..sort((a, b) => b.claimDate.compareTo(a.claimDate)));

  Future<void> createClaim(ProjectWarrantyClaim c) async {
    await _db.from('project_warranty_claims').insert(c.toInsert());
  }

  Future<void> updateClaim(String id, Map<String, dynamic> patch) async {
    await _db.from('project_warranty_claims').update(patch).eq('id', id);
  }

  Future<void> deleteClaim(String id) async {
    await _db.from('project_warranty_claims').delete().eq('id', id);
  }
}

// ============================================================================
// Daily logs
// ============================================================================
class ProjectDailyLogService {
  final String workspaceId;
  final String projectId;
  ProjectDailyLogService({required this.workspaceId, required this.projectId});

  Stream<List<ProjectDailyLog>> watchLogs() => _db
    .from('project_daily_logs').stream(primaryKey: ['id'])
    .eq('project_id', projectId)
    .map((rows) {
      final list = rows.map(ProjectDailyLog.fromRow).toList();
      list.sort((a, b) => b.logDate.compareTo(a.logDate));
      return list;
    });

  Future<ProjectDailyLog> createLog(ProjectDailyLog l) async {
    final row = await _db.from('project_daily_logs').insert(l.toInsert())
      .select().single();
    return ProjectDailyLog.fromRow(row);
  }

  Future<void> updateLog(String id, Map<String, dynamic> patch) async {
    patch['updated_at'] = DateTime.now().toIso8601String();
    await _db.from('project_daily_logs').update(patch).eq('id', id);
  }

  Future<void> submitLog(String id, String userId) =>
    updateLog(id, {
      'status': 'submitted',
      'submitted_by': userId,
      'submitted_at': DateTime.now().toIso8601String(),
    });

  Future<void> approveLog(String id, String userId) =>
    updateLog(id, {
      'status': 'approved',
      'approved_by': userId,
      'approved_at': DateTime.now().toIso8601String(),
    });

  Future<void> deleteLog(String id) async {
    await _db.from('project_daily_logs').delete().eq('id', id);
  }
}

// ============================================================================
// Inspections (header + checklist items)
// ============================================================================
class ProjectInspectionService {
  final String workspaceId;
  final String projectId;
  ProjectInspectionService({required this.workspaceId, required this.projectId});

  Stream<List<ProjectInspection>> watchInspections() => _db
    .from('project_inspections').stream(primaryKey: ['id'])
    .eq('project_id', projectId)
    .map((rows) {
      final list = rows.map(ProjectInspection.fromRow).toList();
      list.sort((a, b) {
        final ad = a.scheduledFor ?? a.createdAt;
        final bd = b.scheduledFor ?? b.createdAt;
        return bd.compareTo(ad);
      });
      return list;
    });

  Future<ProjectInspection> createInspection(ProjectInspection i) async {
    final row = await _db.from('project_inspections').insert(i.toInsert())
      .select().single();
    return ProjectInspection.fromRow(row);
  }

  Future<void> updateInspection(String id, Map<String, dynamic> patch) async {
    patch['updated_at'] = DateTime.now().toIso8601String();
    await _db.from('project_inspections').update(patch).eq('id', id);
  }

  Future<void> deleteInspection(String id) async {
    await _db.from('project_inspections').delete().eq('id', id);
  }

  // Items
  Stream<List<ProjectInspectionItem>> watchItems(String inspectionId) => _db
    .from('project_inspection_items').stream(primaryKey: ['id'])
    .eq('inspection_id', inspectionId)
    .map((rows) {
      final list = rows.map(ProjectInspectionItem.fromRow).toList();
      list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return list;
    });

  Future<void> addItem(ProjectInspectionItem item) async {
    await _db.from('project_inspection_items').insert(item.toInsert());
  }

  Future<void> addItems(List<ProjectInspectionItem> items) async {
    if (items.isEmpty) return;
    await _db.from('project_inspection_items')
      .insert(items.map((i) => i.toInsert()).toList());
  }

  Future<void> updateItem(String id, Map<String, dynamic> patch) async {
    patch['updated_at'] = DateTime.now().toIso8601String();
    await _db.from('project_inspection_items').update(patch).eq('id', id);
  }

  Future<void> deleteItem(String id) async {
    await _db.from('project_inspection_items').delete().eq('id', id);
  }
}

// ============================================================================
// Punch lists (header + items)
// ============================================================================
class ProjectPunchListService {
  final String workspaceId;
  final String projectId;
  ProjectPunchListService({required this.workspaceId, required this.projectId});

  Stream<List<ProjectPunchList>> watchLists() => _db
    .from('project_punch_lists').stream(primaryKey: ['id'])
    .eq('project_id', projectId)
    .map((rows) {
      final list = rows.map(ProjectPunchList.fromRow).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });

  Future<ProjectPunchList> createList(ProjectPunchList l) async {
    final row = await _db.from('project_punch_lists').insert(l.toInsert())
      .select().single();
    return ProjectPunchList.fromRow(row);
  }

  Future<void> updateList(String id, Map<String, dynamic> patch) async {
    patch['updated_at'] = DateTime.now().toIso8601String();
    await _db.from('project_punch_lists').update(patch).eq('id', id);
  }

  Future<void> deleteList(String id) async {
    await _db.from('project_punch_lists').delete().eq('id', id);
  }

  // Items
  Stream<List<ProjectPunchListItem>> watchItems(String listId) => _db
    .from('project_punch_list_items').stream(primaryKey: ['id'])
    .eq('punch_list_id', listId)
    .map((rows) {
      final list = rows.map(ProjectPunchListItem.fromRow).toList();
      list.sort((a, b) {
        // Open work first, sorted by priority
        const order = {'critical': 0, 'high': 1, 'medium': 2, 'low': 3};
        final pa = order[a.priority] ?? 9;
        final pb = order[b.priority] ?? 9;
        if (pa != pb) return pa.compareTo(pb);
        return a.sortOrder.compareTo(b.sortOrder);
      });
      return list;
    });

  Future<void> addItem(ProjectPunchListItem item) async {
    await _db.from('project_punch_list_items').insert(item.toInsert());
  }

  Future<void> updateItem(String id, Map<String, dynamic> patch) async {
    patch['updated_at'] = DateTime.now().toIso8601String();
    await _db.from('project_punch_list_items').update(patch).eq('id', id);
  }

  Future<void> markComplete(String id, String userId) =>
    updateItem(id, {
      'status': 'completed',
      'completed_by': userId,
      'completed_at': DateTime.now().toIso8601String(),
    });

  Future<void> verifyItem(String id, String userId) =>
    updateItem(id, {
      'status': 'verified',
      'verified_by': userId,
      'verified_at': DateTime.now().toIso8601String(),
    });

  Future<void> deleteItem(String id) async {
    await _db.from('project_punch_list_items').delete().eq('id', id);
  }
}
