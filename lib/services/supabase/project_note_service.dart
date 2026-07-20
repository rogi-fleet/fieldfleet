import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/project_note.dart';
import '../../utils/app_logger.dart';

/// Supabase service for managing notes (project, customer, vendor).
class SupabaseProjectNoteService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Create a new note
  Future<String> createNote(ProjectNote note) async {
    try {
      final now = DateTime.now().toIso8601String();
      final noteData = note.toDbRow();
      noteData['created_at'] = now;
      noteData['updated_at'] = now;

      final response = await _supabase
          .from('notes')
          .insert(noteData)
          .select('id')
          .single();

      AppLogger.info('Note created', metadata: {
        'noteId': response['id'],
        'entityType': note.entityType,
        'entityId': note.entityId,
      });

      return response['id'];
    } catch (e) {
      AppLogger.error('Failed to create note', error: e);
      rethrow;
    }
  }

  /// Update an existing note
  Future<void> updateNote({
    required String noteId,
    required String content,
    String? tag,
  }) async {
    try {
      await _supabase.from('notes').update({
        'content': content,
        'tag': tag,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', noteId);

      AppLogger.info('Note updated', metadata: {'noteId': noteId});
    } catch (e) {
      AppLogger.error('Failed to update note', error: e);
      rethrow;
    }
  }

  /// Delete a note
  Future<void> deleteNote(String noteId) async {
    try {
      await _supabase.from('notes').delete().eq('id', noteId);
      AppLogger.info('Note deleted', metadata: {'noteId': noteId});
    } catch (e) {
      AppLogger.error('Failed to delete note', error: e);
      rethrow;
    }
  }

  /// Get all notes for an entity (real-time stream)
  Stream<List<ProjectNote>> getNotesByEntity(String entityType, String entityId,
      {String? workspaceId}) {
    // Supabase stream only supports one .eq() — use entity_id (most selective)
    // and client-side filter by entity_type.
    return _supabase
        .from('notes')
        .stream(primaryKey: ['id'])
        .eq('entity_id', entityId)
        .order('created_at', ascending: false)
        .map((data) {
      var notes = data
          .where((row) => row['entity_type'] == entityType)
          .map((row) => ProjectNote.fromRow(row))
          .toList();
      if (workspaceId != null) {
        notes = notes.where((n) => n.workspaceId == workspaceId).toList();
      }
      return notes;
    });
  }

  /// Convenience: get notes for a project
  Stream<List<ProjectNote>> getNotesByProject(String projectId,
      {String? workspaceId}) {
    return getNotesByEntity('project', projectId, workspaceId: workspaceId);
  }

  /// Convenience: get notes for a customer
  Stream<List<ProjectNote>> getNotesByCustomer(String customerId,
      {String? workspaceId}) {
    return getNotesByEntity('customer', customerId, workspaceId: workspaceId);
  }

  /// Convenience: get notes for a vendor
  Stream<List<ProjectNote>> getNotesByVendor(String vendorId,
      {String? workspaceId}) {
    return getNotesByEntity('vendor', vendorId, workspaceId: workspaceId);
  }

  /// Get recent notes for an entity (one-shot, for overview widgets)
  Future<List<ProjectNote>> getRecentNotes(String entityType, String entityId,
      {String? workspaceId, int limit = 5}) async {
    try {
      var query = _supabase
          .from('notes')
          .select()
          .eq('entity_type', entityType)
          .eq('entity_id', entityId);

      if (workspaceId != null) {
        query = query.eq('workspace_id', workspaceId);
      }

      final response =
          await query.order('created_at', ascending: false).limit(limit);

      return response.map((row) => ProjectNote.fromRow(row)).toList();
    } catch (e) {
      AppLogger.error('Failed to get recent notes', error: e);
      return [];
    }
  }
}
