import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/property_note.dart';
import '../../utils/app_logger.dart';

/// Supabase service for managing property notes.
class SupabasePropertyNoteService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Create a new note
  Future<String> createNote(PropertyNote note) async {
    try {
      final now = DateTime.now().toIso8601String();
      final noteData = _toDbFormat(note);
      noteData['created_at'] = now;
      noteData['updated_at'] = now;

      final response = await _supabase
          .from('property_notes')
          .insert(noteData)
          .select('id')
          .single();

      AppLogger.info('Property note created', metadata: {
        'noteId': response['id'],
        'propertyId': note.propertyId,
      });

      return response['id'];
    } catch (e) {
      AppLogger.error('Failed to create property note', error: e);
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
      await _supabase.from('property_notes').update({
        'content': content,
        'tag': tag,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', noteId);

      AppLogger.info('Property note updated', metadata: {'noteId': noteId});
    } catch (e) {
      AppLogger.error('Failed to update property note', error: e);
      rethrow;
    }
  }

  /// Delete a note
  Future<void> deleteNote(String noteId) async {
    try {
      await _supabase.from('property_notes').delete().eq('id', noteId);

      AppLogger.info('Property note deleted', metadata: {'noteId': noteId});
    } catch (e) {
      AppLogger.error('Failed to delete property note', error: e);
      rethrow;
    }
  }

  /// Get a single note by ID
  Future<PropertyNote?> getNote(String noteId) async {
    try {
      final response = await _supabase
          .from('property_notes')
          .select()
          .eq('id', noteId)
          .maybeSingle();

      if (response == null) return null;
      return _toPropertyNote(response);
    } catch (e) {
      AppLogger.error('Failed to get property note', error: e);
      return null;
    }
  }

  /// Get all notes for a property (real-time stream)
  Stream<List<PropertyNote>> getNotesByProperty(String propertyId,
      {String? workspaceId}) {
    return _supabase
        .from('property_notes')
        .stream(primaryKey: ['id'])
        .eq('property_id', propertyId)
        .order('created_at', ascending: false)
        .map((data) {
          var notes = data.map((row) => _toPropertyNote(row)).toList();
          if (workspaceId != null) {
            notes = notes.where((n) => n.workspaceId == workspaceId).toList();
          }
          return notes;
        });
  }

  /// Get notes for a specific area (real-time stream)
  Stream<List<PropertyNote>> getNotesByArea(String areaId,
      {String? workspaceId}) {
    return _supabase
        .from('property_notes')
        .stream(primaryKey: ['id'])
        .eq('area_id', areaId)
        .order('created_at', ascending: false)
        .map((data) {
          var notes = data.map((row) => _toPropertyNote(row)).toList();
          if (workspaceId != null) {
            notes = notes.where((n) => n.workspaceId == workspaceId).toList();
          }
          return notes;
        });
  }

  /// Get notes by tag
  Stream<List<PropertyNote>> getNotesByTag(String propertyId, String tag,
      {String? workspaceId}) {
    return _supabase
        .from('property_notes')
        .stream(primaryKey: ['id'])
        .eq('property_id', propertyId)
        .order('created_at', ascending: false)
        .map((data) {
          var notes = data
              .where((row) => row['tag'] == tag)
              .map((row) => _toPropertyNote(row))
              .toList();
          if (workspaceId != null) {
            notes = notes.where((n) => n.workspaceId == workspaceId).toList();
          }
          return notes;
        });
  }

  /// Get recent notes (last 10)
  Future<List<PropertyNote>> getRecentNotes(String propertyId,
      {String? workspaceId}) async {
    try {
      var query = _supabase
          .from('property_notes')
          .select()
          .eq('property_id', propertyId);

      if (workspaceId != null) {
        query = query.eq('workspace_id', workspaceId);
      }

      final response = await query
          .order('created_at', ascending: false)
          .limit(10);

      return response.map((row) => _toPropertyNote(row)).toList();
    } catch (e) {
      AppLogger.error('Failed to get recent notes', error: e);
      return [];
    }
  }

  /// Count notes for a property
  Future<int> getNoteCount(String propertyId, {String? workspaceId}) async {
    try {
      var query = _supabase
          .from('property_notes')
          .select('id')
          .eq('property_id', propertyId);

      if (workspaceId != null) {
        query = query.eq('workspace_id', workspaceId);
      }

      final response = await query;

      return response.length;
    } catch (e) {
      AppLogger.error('Failed to get note count', error: e);
      return 0;
    }
  }

  /// Convert database row to PropertyNote
  PropertyNote _toPropertyNote(Map<String, dynamic> row) {
    return PropertyNote.fromJson(_toFirestoreFormat(row), row['id']);
  }

  /// Convert Supabase snake_case to Firestore camelCase format
  Map<String, dynamic> _toFirestoreFormat(Map<String, dynamic> row) {
    return {
      'projectId': row['project_id'],
      'workspaceId': row['workspace_id'],
      'propertyId': row['property_id'],
      'areaId': row['area_id'],
      'content': row['content'],
      'tag': row['tag'],
      'authorId': row['author_id'],
      'authorName': row['author_name'],
      'createdAt': row['created_at'] != null
          ? _FakeTimestamp(DateTime.parse(row['created_at']))
          : _FakeTimestamp(DateTime.now()),
      'updatedAt': row['updated_at'] != null
          ? _FakeTimestamp(DateTime.parse(row['updated_at']))
          : null,
    };
  }

  /// Convert PropertyNote to database format (snake_case)
  Map<String, dynamic> _toDbFormat(PropertyNote note) {
    final json = note.toJson();
    return {
      'project_id': json['projectId'],
      'workspace_id': json['workspaceId'],
      'property_id': json['propertyId'],
      'area_id': json['areaId'],
      'content': json['content'],
      'tag': json['tag'],
      'author_id': json['authorId'],
      'author_name': json['authorName'],
    };
  }
}

/// Wrapper class to mimic Firestore Timestamp for model compatibility
class _FakeTimestamp {
  final DateTime _dateTime;
  _FakeTimestamp(this._dateTime);
  DateTime toDate() => _dateTime;
}
