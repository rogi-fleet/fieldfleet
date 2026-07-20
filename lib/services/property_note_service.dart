import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/property_note.dart';
import '../utils/app_logger.dart';

/// Service for managing property notes.
class PropertyNoteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference get _notesCollection =>
      _firestore.collection('property_notes');

  /// Create a new note
  Future<String> createNote(PropertyNote note) async {
    try {
      final docRef = _notesCollection.doc();
      final noteData = note.copyWith(id: docRef.id).toJson();
      await docRef.set(noteData);

      AppLogger.info('Property note created', metadata: {
        'noteId': docRef.id,
        'propertyId': note.propertyId,
      });

      return docRef.id;
    } catch (e) {
      AppLogger.error('Failed to create property note', error: e);
      rethrow;
    }
  }

  /// Delete a note
  Future<void> deleteNote(String noteId) async {
    try {
      await _notesCollection.doc(noteId).delete();

      AppLogger.info('Property note deleted', metadata: {'noteId': noteId});
    } catch (e) {
      AppLogger.error('Failed to delete property note', error: e);
      rethrow;
    }
  }

  /// Get a single note by ID
  Future<PropertyNote?> getNote(String noteId) async {
    try {
      final doc = await _notesCollection.doc(noteId).get();
      if (!doc.exists) return null;
      return PropertyNote.fromJson(doc.data() as Map<String, dynamic>, doc.id);
    } catch (e) {
      AppLogger.error('Failed to get property note', error: e);
      return null;
    }
  }

  /// Get all notes for a property (real-time stream)
  Stream<List<PropertyNote>> getNotesByProperty(String propertyId, {String? workspaceId}) {
    var query = _notesCollection
        .where('propertyId', isEqualTo: propertyId);

    if (workspaceId != null) {
      query = query.where('workspaceId', isEqualTo: workspaceId);
    }

    return query
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) =>
              PropertyNote.fromJson(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    });
  }

  /// Get notes for a specific area (real-time stream)
  Stream<List<PropertyNote>> getNotesByArea(String areaId, {String? workspaceId}) {
    var query = _notesCollection
        .where('areaId', isEqualTo: areaId);

    if (workspaceId != null) {
      query = query.where('workspaceId', isEqualTo: workspaceId);
    }

    return query
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) =>
              PropertyNote.fromJson(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    });
  }

  /// Get notes by tag
  Stream<List<PropertyNote>> getNotesByTag(String propertyId, String tag, {String? workspaceId}) {
    var query = _notesCollection
        .where('propertyId', isEqualTo: propertyId)
        .where('tag', isEqualTo: tag);

    if (workspaceId != null) {
      query = query.where('workspaceId', isEqualTo: workspaceId);
    }

    return query
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) =>
              PropertyNote.fromJson(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    });
  }

  /// Get recent notes (last 10)
  Future<List<PropertyNote>> getRecentNotes(String propertyId, {String? workspaceId}) async {
    try {
      var query = _notesCollection
          .where('propertyId', isEqualTo: propertyId);

      if (workspaceId != null) {
        query = query.where('workspaceId', isEqualTo: workspaceId);
      }

      final snapshot = await query
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();

      return snapshot.docs
          .map((doc) =>
              PropertyNote.fromJson(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    } catch (e) {
      AppLogger.error('Failed to get recent notes', error: e);
      return [];
    }
  }

  /// Count notes for a property
  Future<int> getNoteCount(String propertyId, {String? workspaceId}) async {
    try {
      var query = _notesCollection
          .where('propertyId', isEqualTo: propertyId);

      if (workspaceId != null) {
        query = query.where('workspaceId', isEqualTo: workspaceId);
      }

      final snapshot = await query
          .count()
          .get();

      return snapshot.count ?? 0;
    } catch (e) {
      AppLogger.error('Failed to get note count', error: e);
      return 0;
    }
  }
}
