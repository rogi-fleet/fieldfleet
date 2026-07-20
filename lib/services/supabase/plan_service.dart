import 'dart:io';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/construction_plan.dart';
import '../../models/plan_discipline.dart';
import '../../utils/app_logger.dart';
import '../../utils/storage_path_utils.dart';

/// Supabase implementation of PlanService
class SupabasePlanService {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const String _bucket = 'construction-plans';

  /// Rename a plan in place — used by the editor's inline title field.
  Future<void> renamePlan({
    required String planId,
    required String workspaceId,
    required String name,
  }) async {
    await _supabase
        .from('plans')
        .update({
          'name': name,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', planId)
        .eq('workspace_id', workspaceId);
  }

  /// Create a new editor-only plan (no PDF). The accompanying scene is
  /// created separately via [SupabaseFloorplanSceneService.upsertScene].
  Future<ConstructionPlan> createEditorPlan({
    required String projectId,
    required String workspaceId,
    String? propertyId,
    required String name,
    PlanDiscipline discipline = PlanDiscipline.architectural,
    String? sheetNumber,
    String? notes,
    required String createdBy,
  }) async {
    final now = DateTime.now();
    final response = await _supabase
        .from('plans')
        .insert({
          'workspace_id': workspaceId,
          'project_id': projectId,
          'property_id': propertyId,
          'name': name,
          'discipline': discipline.toString(),
          'sheet_number': sheetNumber,
          'is_current_version': true,
          'file_url': null,
          'file_name': null,
          'file_size': null,
          'storage_path': null,
          'uploaded_by': createdBy,
          'uploaded_at': now.toIso8601String(),
          'notes': notes,
          'linked_task_ids': const <String>[],
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        })
        .select()
        .single();
    return _toPlan(response);
  }

  /// Get all plans for a project
  Stream<List<ConstructionPlan>> getPlans(
    String projectId,
    String workspaceId,
  ) {
    return _supabase
        .from('plans')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .map((data) {
          final filtered = data
              .where((row) => row['project_id'] == projectId)
              .map((row) => _toPlan(row))
              .toList();
          // Sort by discipline, then sheet_number, then uploaded_at desc
          filtered.sort((a, b) {
            final discCompare = a.discipline.toString().compareTo(
              b.discipline.toString(),
            );
            if (discCompare != 0) return discCompare;
            final sheetCompare = (a.sheetNumber ?? '').compareTo(
              b.sheetNumber ?? '',
            );
            if (sheetCompare != 0) return sheetCompare;
            return b.uploadedAt.compareTo(a.uploadedAt);
          });
          return filtered;
        });
  }

  /// Get a single plan by ID
  Future<ConstructionPlan?> getPlan(String planId, String workspaceId) async {
    try {
      final response = await _supabase
          .from('plans')
          .select()
          .eq('id', planId)
          .eq('workspace_id', workspaceId)
          .maybeSingle();

      if (response == null) return null;
      return _toPlan(response);
    } catch (e) {
      throw Exception('Error fetching plan: $e');
    }
  }

  /// Get a single plan stream by ID
  Stream<ConstructionPlan?> getPlanStream(String planId, String workspaceId) {
    return _supabase
        .from('plans')
        .stream(primaryKey: ['id'])
        .eq('id', planId)
        .map((data) {
          if (data.isEmpty) return null;
          final row = data.first;
          if (row['workspace_id'] != workspaceId) return null;
          return _toPlan(row);
        });
  }

  /// Get only current version plans
  Stream<List<ConstructionPlan>> getCurrentPlans(
    String projectId,
    String workspaceId,
  ) {
    return _supabase
        .from('plans')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .map((data) {
          final filtered = data
              .where(
                (row) =>
                    row['project_id'] == projectId &&
                    row['is_current_version'] == true,
              )
              .map((row) => _toPlan(row))
              .toList();
          filtered.sort((a, b) {
            final discCompare = a.discipline.toString().compareTo(
              b.discipline.toString(),
            );
            if (discCompare != 0) return discCompare;
            return (a.sheetNumber ?? '').compareTo(b.sheetNumber ?? '');
          });
          return filtered;
        });
  }

  /// Get all versions of a specific sheet
  Stream<List<ConstructionPlan>> getPlanVersions(
    String projectId,
    String workspaceId,
    String sheetNumber,
  ) {
    return _supabase
        .from('plans')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .map((data) {
          final filtered = data
              .where(
                (row) =>
                    row['project_id'] == projectId &&
                    row['sheet_number'] == sheetNumber,
              )
              .map((row) => _toPlan(row))
              .toList();
          filtered.sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
          return filtered;
        });
  }

  /// Get version history for a plan
  Future<List<ConstructionPlan>> getVersionHistory(
    String projectId,
    String workspaceId,
    String name,
    String? sheetNumber,
  ) async {
    try {
      var query = _supabase
          .from('plans')
          .select()
          .eq('project_id', projectId)
          .eq('workspace_id', workspaceId)
          .eq('name', name);

      if (sheetNumber != null) {
        query = query.eq('sheet_number', sheetNumber);
      }

      final response = await query.order('uploaded_at', ascending: false);
      return response.map((row) => _toPlan(row)).toList();
    } catch (e) {
      throw Exception('Error fetching version history: $e');
    }
  }

  /// Get plans by discipline
  Stream<List<ConstructionPlan>> getPlansByDiscipline(
    String projectId,
    String workspaceId,
    PlanDiscipline discipline,
  ) {
    return _supabase
        .from('plans')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .map((data) {
          final filtered = data
              .where(
                (row) =>
                    row['project_id'] == projectId &&
                    row['discipline'] == discipline.toString(),
              )
              .map((row) => _toPlan(row))
              .toList();
          filtered.sort((a, b) {
            final sheetCompare = (a.sheetNumber ?? '').compareTo(
              b.sheetNumber ?? '',
            );
            if (sheetCompare != 0) return sheetCompare;
            return b.uploadedAt.compareTo(a.uploadedAt);
          });
          return filtered;
        });
  }

  /// Upload a new plan from file
  Future<ConstructionPlan> uploadPlan({
    required File pdfFile,
    required String projectId,
    required String workspaceId,
    String? propertyId,
    required String name,
    required PlanDiscipline discipline,
    String? sheetNumber,
    String? version,
    DateTime? drawingDate,
    bool isCurrentVersion = true,
    String? notes,
    required String uploadedBy,
  }) async {
    try {
      // Validate PDF file
      if (!pdfFile.path.toLowerCase().endsWith('.pdf')) {
        throw Exception('File must be a PDF');
      }

      final fileSize = await pdfFile.length();
      if (fileSize > 50 * 1024 * 1024) {
        throw Exception('File size must be less than 50MB');
      }

      final now = DateTime.now();
      final fileName = buildUniqueStorageFileName(
        pdfFile.path.split('/').last,
        timestampMs: now.millisecondsSinceEpoch,
      );
      final storagePath = '$workspaceId/$projectId/$fileName';

      // Read file bytes
      final bytes = await pdfFile.readAsBytes();

      // Upload to Supabase Storage
      await _supabase.storage
          .from(_bucket)
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions: const FileOptions(contentType: 'application/pdf'),
          );

      // Get public URL
      final fileUrl = _supabase.storage.from(_bucket).getPublicUrl(storagePath);

      // If this is set as current version, update other plans
      if (isCurrentVersion && sheetNumber != null) {
        await _setOtherVersionsAsNonCurrent(
          projectId,
          workspaceId,
          sheetNumber,
          null,
        );
      }

      // Create plan document
      final planData = {
        'workspace_id': workspaceId,
        'project_id': projectId,
        'property_id': propertyId,
        'name': name,
        'discipline': discipline.toString(),
        'sheet_number': sheetNumber,
        'version': version,
        'is_current_version': isCurrentVersion,
        'drawing_date': drawingDate?.toIso8601String(),
        'file_url': fileUrl,
        'storage_path': storagePath,
        'file_name': pdfFile.path.split('/').last,
        'file_size': fileSize,
        'uploaded_by': uploadedBy,
        'uploaded_at': now.toIso8601String(),
        'notes': notes,
        'linked_task_ids': [],
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      final response = await _supabase
          .from('plans')
          .insert(planData)
          .select()
          .single();

      return _toPlan(response);
    } catch (e) {
      throw Exception('Error uploading plan: $e');
    }
  }

  /// Upload a new plan from bytes (for web)
  Future<ConstructionPlan> uploadPlanBytes({
    required Uint8List bytes,
    required String fileName,
    required String projectId,
    required String workspaceId,
    String? propertyId,
    required String name,
    required PlanDiscipline discipline,
    String? sheetNumber,
    String? version,
    DateTime? drawingDate,
    bool isCurrentVersion = true,
    String? notes,
    required String uploadedBy,
  }) async {
    try {
      // Validate PDF
      if (!fileName.toLowerCase().endsWith('.pdf')) {
        throw Exception('File must be a PDF');
      }

      if (bytes.length > 50 * 1024 * 1024) {
        throw Exception('File size must be less than 50MB');
      }

      final now = DateTime.now();
      final uniqueFileName = buildUniqueStorageFileName(
        fileName,
        timestampMs: now.millisecondsSinceEpoch,
      );
      final storagePath = '$workspaceId/$projectId/$uniqueFileName';

      // Upload to Supabase Storage
      await _supabase.storage
          .from(_bucket)
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions: const FileOptions(contentType: 'application/pdf'),
          );

      // Get public URL
      final fileUrl = _supabase.storage.from(_bucket).getPublicUrl(storagePath);

      // If this is set as current version, update other plans
      if (isCurrentVersion && sheetNumber != null) {
        await _setOtherVersionsAsNonCurrent(
          projectId,
          workspaceId,
          sheetNumber,
          null,
        );
      }

      // Create plan document
      final planData = {
        'workspace_id': workspaceId,
        'project_id': projectId,
        'property_id': propertyId,
        'name': name,
        'discipline': discipline.toString(),
        'sheet_number': sheetNumber,
        'version': version,
        'is_current_version': isCurrentVersion,
        'drawing_date': drawingDate?.toIso8601String(),
        'file_url': fileUrl,
        'storage_path': storagePath,
        'file_name': fileName,
        'file_size': bytes.length,
        'uploaded_by': uploadedBy,
        'uploaded_at': now.toIso8601String(),
        'notes': notes,
        'linked_task_ids': [],
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      final response = await _supabase
          .from('plans')
          .insert(planData)
          .select()
          .single();

      return _toPlan(response);
    } catch (e) {
      throw Exception('Error uploading plan: $e');
    }
  }

  /// Set a plan as the current version
  Future<void> setCurrentVersion(
    String planId,
    String projectId,
    String workspaceId,
    String name,
    String? sheetNumber,
  ) async {
    try {
      final plan = await getPlan(planId, workspaceId);
      if (plan == null) {
        throw Exception('Plan not found');
      }

      final effectiveSheetNumber = sheetNumber ?? plan.sheetNumber;
      if (effectiveSheetNumber == null) {
        throw Exception('Sheet number is required to set current version');
      }

      // Set other versions to non-current
      await _setOtherVersionsAsNonCurrent(
        plan.projectId,
        plan.workspaceId,
        effectiveSheetNumber,
        planId,
      );

      // Set this plan as current
      await _supabase
          .from('plans')
          .update({
            'is_current_version': true,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', planId);
    } catch (e) {
      throw Exception('Error setting current version: $e');
    }
  }

  /// Helper to set other versions as non-current
  Future<void> _setOtherVersionsAsNonCurrent(
    String projectId,
    String workspaceId,
    String sheetNumber,
    String? excludePlanId,
  ) async {
    var query = _supabase
        .from('plans')
        .select('id')
        .eq('workspace_id', workspaceId)
        .eq('project_id', projectId)
        .eq('sheet_number', sheetNumber);

    if (excludePlanId != null) {
      query = query.neq('id', excludePlanId);
    }

    final plans = await query;

    for (final plan in plans) {
      await _supabase
          .from('plans')
          .update({
            'is_current_version': false,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', plan['id']);
    }
  }

  /// Stream plans scoped to a single property (drawings of one structure).
  Stream<List<ConstructionPlan>> getPlansForProperty(
    String workspaceId,
    String propertyId,
  ) {
    return _supabase
        .from('plans')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .map((data) {
          final filtered = data
              .where((row) => row['property_id'] == propertyId)
              .map((row) => _toPlan(row))
              .toList();
          filtered.sort((a, b) {
            final discCompare = a.discipline.toString().compareTo(
              b.discipline.toString(),
            );
            if (discCompare != 0) return discCompare;
            return (a.sheetNumber ?? '').compareTo(b.sheetNumber ?? '');
          });
          return filtered;
        });
  }

  /// Bulk: re-scope plans to a property (or clear it).
  /// Pass [propertyId] = null to make plans project-wide again.
  Future<void> bulkSetProperty(
    List<String> planIds,
    String workspaceId,
    String? propertyId,
  ) async {
    if (planIds.isEmpty) return;
    await _supabase
        .from('plans')
        .update({
          'property_id': propertyId,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .inFilter('id', planIds)
        .eq('workspace_id', workspaceId);
  }

  /// Bulk: change discipline on selected plans.
  Future<void> bulkSetDiscipline(
    List<String> planIds,
    String workspaceId,
    PlanDiscipline discipline,
  ) async {
    if (planIds.isEmpty) return;
    await _supabase
        .from('plans')
        .update({
          'discipline': discipline.toString(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .inFilter('id', planIds)
        .eq('workspace_id', workspaceId);
  }

  /// Bulk delete. Storage objects are best-effort; storage_path may be null
  /// for editor-only plans.
  Future<void> bulkDeletePlans(
    List<String> planIds,
    String workspaceId,
  ) async {
    if (planIds.isEmpty) return;
    final rows = await _supabase
        .from('plans')
        .select('id, storage_path')
        .inFilter('id', planIds)
        .eq('workspace_id', workspaceId);
    final paths = rows
        .map((r) => r['storage_path'] as String?)
        .whereType<String>()
        .toList();
    if (paths.isNotEmpty) {
      try {
        await _supabase.storage.from(_bucket).remove(paths);
      } catch (e) {
        AppLogger.warning(
          'Could not bulk-delete plan files from storage',
          metadata: {'count': paths.length, 'error': e.toString()},
        );
      }
    }
    await _supabase
        .from('plans')
        .delete()
        .inFilter('id', planIds)
        .eq('workspace_id', workspaceId);
  }

  /// Delete a plan
  Future<void> deletePlan(
    String planId,
    String workspaceId, {
    bool force = false,
  }) async {
    try {
      final plan = await getPlan(planId, workspaceId);
      if (plan == null) {
        throw Exception('Plan not found');
      }

      if (plan.isCurrentVersion && !force) {
        throw Exception(
          'Cannot delete current version. Set another version as current first, or use force=true.',
        );
      }

      // Get storage path from database
      final record = await _supabase
          .from('plans')
          .select('storage_path')
          .eq('id', planId)
          .single();

      final storagePath = record['storage_path'] as String?;

      // Delete from Storage
      if (storagePath != null) {
        try {
          await _supabase.storage.from(_bucket).remove([storagePath]);
        } catch (e) {
          AppLogger.warning(
            'Could not delete plan file from storage',
            metadata: {'planId': planId, 'error': e.toString()},
          );
        }
      }

      // Delete from database
      await _supabase.from('plans').delete().eq('id', planId);
    } catch (e) {
      throw Exception('Error deleting plan: $e');
    }
  }

  /// Link plan to task
  Future<void> linkPlanToTask(String planId, String taskId) async {
    try {
      final plan = await _supabase
          .from('plans')
          .select('linked_task_ids')
          .eq('id', planId)
          .single();

      final linkedTaskIds = List<String>.from(plan['linked_task_ids'] ?? []);
      if (!linkedTaskIds.contains(taskId)) {
        linkedTaskIds.add(taskId);
      }

      await _supabase
          .from('plans')
          .update({
            'linked_task_ids': linkedTaskIds,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', planId);
    } catch (e) {
      throw Exception('Error linking plan to task: $e');
    }
  }

  /// Unlink plan from task
  Future<void> unlinkPlanFromTask(String planId, String taskId) async {
    try {
      final plan = await _supabase
          .from('plans')
          .select('linked_task_ids')
          .eq('id', planId)
          .single();

      final linkedTaskIds = List<String>.from(plan['linked_task_ids'] ?? []);
      linkedTaskIds.remove(taskId);

      await _supabase
          .from('plans')
          .update({
            'linked_task_ids': linkedTaskIds,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', planId);
    } catch (e) {
      throw Exception('Error unlinking plan from task: $e');
    }
  }

  /// Get all plans linked to a task
  Future<List<ConstructionPlan>> getTaskPlans(
    String taskId,
    String workspaceId,
  ) async {
    try {
      final response = await _supabase
          .from('plans')
          .select()
          .eq('workspace_id', workspaceId)
          .contains('linked_task_ids', [taskId]);

      return response.map((row) => _toPlan(row)).toList();
    } catch (e) {
      throw Exception('Error fetching task plans: $e');
    }
  }

  /// Search plans
  Future<List<ConstructionPlan>> searchPlans(
    String projectId,
    String workspaceId,
    String query,
  ) async {
    try {
      final response = await _supabase
          .from('plans')
          .select()
          .eq('workspace_id', workspaceId)
          .eq('project_id', projectId);

      final queryLower = query.toLowerCase();
      return response.map((row) => _toPlan(row)).where((plan) {
        return plan.name.toLowerCase().contains(queryLower) ||
            (plan.sheetNumber?.toLowerCase().contains(queryLower) ?? false) ||
            (plan.version?.toLowerCase().contains(queryLower) ?? false) ||
            (plan.notes?.toLowerCase().contains(queryLower) ?? false);
      }).toList();
    } catch (e) {
      throw Exception('Error searching plans: $e');
    }
  }

  /// Convert database row to ConstructionPlan
  ConstructionPlan _toPlan(Map<String, dynamic> row) {
    return ConstructionPlan(
      id: row['id'],
      workspaceId: row['workspace_id'],
      projectId: row['project_id'],
      propertyId: row['property_id'] as String?,
      name: row['name'],
      discipline: PlanDiscipline.values.firstWhere(
        (e) => e.toString() == row['discipline'],
        orElse: () => PlanDiscipline.architectural,
      ),
      sheetNumber: row['sheet_number'],
      version: row['version'],
      isCurrentVersion: row['is_current_version'] ?? true,
      drawingDate: row['drawing_date'] != null
          ? DateTime.parse(row['drawing_date'])
          : null,
      fileUrl: row['file_url'],
      fileName: row['file_name'],
      fileSize: row['file_size'],
      uploadedBy: row['uploaded_by'],
      uploadedAt: DateTime.parse(row['uploaded_at']),
      notes: row['notes'],
      linkedTaskIds: List<String>.from(row['linked_task_ids'] ?? []),
      createdAt: DateTime.parse(row['created_at']),
      updatedAt: DateTime.parse(row['updated_at']),
    );
  }
}
