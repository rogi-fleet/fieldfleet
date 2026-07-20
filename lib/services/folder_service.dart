import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/file_folder.dart';
import '../utils/app_logger.dart';

/// Service for managing file folders in projects.
class FolderService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Creates a new folder.
  Future<FileFolder> createFolder({
    required String workspaceId,
    required String projectId,
    required String name,
    String? parentFolderId,
    required String createdBy,
    bool isVirtual = false,
    String? virtualType,
  }) async {
    try {
      final folder = FileFolder(
        id: '',
        workspaceId: workspaceId,
        projectId: projectId,
        name: name,
        parentFolderId: parentFolderId,
        isVirtual: isVirtual,
        virtualType: virtualType,
        createdBy: createdBy,
        createdAt: DateTime.now(),
      );

      final docRef = await _firestore
          .collection('file_folders')
          .add(folder.toJson());

      return folder.copyWith(id: docRef.id);
    } catch (e) {
      AppLogger.error('Failed to create folder', error: e, metadata: {
        'name': name,
        'projectId': projectId,
      });
      throw Exception('Failed to create folder: $e');
    }
  }

  /// Renames a folder.
  Future<void> renameFolder(String folderId, String newName) async {
    try {
      await _firestore
          .collection('file_folders')
          .doc(folderId)
          .update({'name': newName});
    } catch (e) {
      AppLogger.error('Failed to rename folder', error: e, metadata: {
        'folderId': folderId,
        'newName': newName,
      });
      throw Exception('Failed to rename folder: $e');
    }
  }

  /// Deletes a folder. Does not delete child folders or files.
  Future<void> deleteFolder(String folderId) async {
    try {
      await _firestore
          .collection('file_folders')
          .doc(folderId)
          .delete();
    } catch (e) {
      AppLogger.error('Failed to delete folder', error: e, metadata: {
        'folderId': folderId,
      });
      throw Exception('Failed to delete folder: $e');
    }
  }

  /// Gets all folders for a project as a stream.
  Stream<List<FileFolder>> getProjectFolders(String workspaceId, String projectId) {
    return _firestore
        .collection('file_folders')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('projectId', isEqualTo: projectId)
        .orderBy('createdAt')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => FileFolder.fromJson(doc.data(), doc.id))
          .toList();
    });
  }

  /// Gets a single folder by ID.
  Future<FileFolder?> getFolder(String folderId) async {
    try {
      final doc = await _firestore
          .collection('file_folders')
          .doc(folderId)
          .get();

      if (!doc.exists) return null;
      return FileFolder.fromJson(doc.data()!, doc.id);
    } catch (e) {
      AppLogger.error('Failed to get folder', error: e, metadata: {
        'folderId': folderId,
      });
      return null;
    }
  }

  /// Initializes default folders for a project if they don't exist.
  /// Creates: General, Content (with virtual subfolders)
  Future<void> initializeDefaultFolders({
    required String workspaceId,
    required String projectId,
    required String createdBy,
  }) async {
    try {
      // Check if folders already exist
      final existing = await _firestore
          .collection('file_folders')
          .where('workspaceId', isEqualTo: workspaceId)
          .where('projectId', isEqualTo: projectId)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        // Folders already initialized
        return;
      }

      final batch = _firestore.batch();

      // Create General folder
      final generalRef = _firestore.collection('file_folders').doc();
      batch.set(generalRef, FileFolder(
        id: generalRef.id,
        workspaceId: workspaceId,
        projectId: projectId,
        name: 'General',
        createdBy: createdBy,
        createdAt: DateTime.now(),
      ).toJson());

      // Create Content folder
      final contentRef = _firestore.collection('file_folders').doc();
      batch.set(contentRef, FileFolder(
        id: contentRef.id,
        workspaceId: workspaceId,
        projectId: projectId,
        name: 'Content',
        createdBy: createdBy,
        createdAt: DateTime.now(),
      ).toJson());

      // Create Tasks virtual folder (under Content)
      final tasksRef = _firestore.collection('file_folders').doc();
      batch.set(tasksRef, FileFolder(
        id: tasksRef.id,
        workspaceId: workspaceId,
        projectId: projectId,
        name: 'Tasks',
        parentFolderId: contentRef.id,
        isVirtual: true,
        virtualType: 'tasks',
        createdBy: createdBy,
        createdAt: DateTime.now(),
      ).toJson());

      // Create Messages virtual folder (under Content)
      final messagesRef = _firestore.collection('file_folders').doc();
      batch.set(messagesRef, FileFolder(
        id: messagesRef.id,
        workspaceId: workspaceId,
        projectId: projectId,
        name: 'Messages',
        parentFolderId: contentRef.id,
        isVirtual: true,
        virtualType: 'messages',
        createdBy: createdBy,
        createdAt: DateTime.now(),
      ).toJson());

      // Create Forms virtual folder (under Content)
      final formsRef = _firestore.collection('file_folders').doc();
      batch.set(formsRef, FileFolder(
        id: formsRef.id,
        workspaceId: workspaceId,
        projectId: projectId,
        name: 'Forms',
        parentFolderId: contentRef.id,
        isVirtual: true,
        virtualType: 'forms',
        createdBy: createdBy,
        createdAt: DateTime.now(),
      ).toJson());

      // Create Documents virtual folder (under Content)
      final documentsRef = _firestore.collection('file_folders').doc();
      batch.set(documentsRef, FileFolder(
        id: documentsRef.id,
        workspaceId: workspaceId,
        projectId: projectId,
        name: 'Financials',
        parentFolderId: contentRef.id,
        isVirtual: true,
        virtualType: 'documents',
        createdBy: createdBy,
        createdAt: DateTime.now(),
      ).toJson());

      await batch.commit();

      AppLogger.info('Initialized default folders for project', metadata: {
        'projectId': projectId,
      });
    } catch (e) {
      AppLogger.error('Failed to initialize default folders', error: e, metadata: {
        'projectId': projectId,
      });
      throw Exception('Failed to initialize default folders: $e');
    }
  }

  /// Gets child folders of a parent folder.
  List<FileFolder> getChildFolders(List<FileFolder> allFolders, String? parentFolderId) {
    return allFolders
        .where((f) => f.parentFolderId == parentFolderId)
        .toList();
  }

  /// Builds folder tree structure from flat list.
  Map<String?, List<FileFolder>> buildFolderTree(List<FileFolder> folders) {
    final tree = <String?, List<FileFolder>>{};
    for (final folder in folders) {
      tree.putIfAbsent(folder.parentFolderId, () => []);
      tree[folder.parentFolderId]!.add(folder);
    }
    return tree;
  }
}
