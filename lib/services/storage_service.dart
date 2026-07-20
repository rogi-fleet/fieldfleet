import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mime/mime.dart';
import '../models/file_attachment.dart';
import '../utils/app_logger.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const int maxFileSizeBytes = 10 * 1024 * 1024; // 10MB

  static const List<String> allowedMimeTypes = [
    'image/jpeg',
    'image/png',
    'image/heic',
    'image/heif',
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  ];

  // Validate file before upload
  ({bool isValid, String? error}) validateFile(File file, String fileName) {
    // Check file size
    final fileSize = file.lengthSync();
    if (fileSize > maxFileSizeBytes) {
      return (
        isValid: false,
        error: 'File size must be less than 10MB'
      );
    }

    // Check file type
    final mimeType = lookupMimeType(fileName) ?? 'application/octet-stream';
    if (!allowedMimeTypes.contains(mimeType)) {
      return (
        isValid: false,
        error: 'File type not allowed. Supported: JPG, PNG, HEIC, PDF, DOC, XLS'
      );
    }

    return (isValid: true, error: null);
  }

  // Validate bytes before upload (for web)
  ({bool isValid, String? error}) validateFileBytes(Uint8List bytes, String fileName) {
    // Check file size
    if (bytes.length > maxFileSizeBytes) {
      return (
        isValid: false,
        error: 'File size must be less than 10MB'
      );
    }

    // Check file type
    final mimeType = lookupMimeType(fileName) ?? 'application/octet-stream';
    if (!allowedMimeTypes.contains(mimeType)) {
      return (
        isValid: false,
        error: 'File type not allowed. Supported: JPG, PNG, HEIC, PDF, DOC, XLS'
      );
    }

    return (isValid: true, error: null);
  }

  // Generate unique filename to prevent collisions
  String _generateUniqueFileName(String originalFileName) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final extension = originalFileName.split('.').last;
    final nameWithoutExt = originalFileName.substring(
      0,
      originalFileName.length - extension.length - 1,
    );
    return '${nameWithoutExt}_$timestamp.$extension';
  }

  // Upload file to Firebase Storage
  Future<FileAttachment> uploadFile({
    required File file,
    required String fileName,
    required String workspaceId,
    required String projectId,
    String? taskId,
    String? messageId,
    String? folderId,
    List<String>? tags,
    required String uploadedBy,
    Function(double)? onProgress,
  }) async {
    try {
      // Validate file
      final validation = validateFile(file, fileName);
      if (!validation.isValid) {
        throw Exception(validation.error);
      }

      // Generate unique filename
      final uniqueFileName = _generateUniqueFileName(fileName);

      // Build storage path
      final storagePath = taskId != null
          ? 'workspaces/$workspaceId/projects/$projectId/tasks/$taskId/$uniqueFileName'
          : 'workspaces/$workspaceId/projects/$projectId/$uniqueFileName';

      // Upload file
      final ref = _storage.ref().child(storagePath);
      final uploadTask = ref.putFile(file);

      // Track progress
      if (onProgress != null) {
        uploadTask.snapshotEvents.listen((snapshot) {
          final progress = snapshot.bytesTransferred / snapshot.totalBytes;
          onProgress(progress);
        });
      }

      // Wait for upload to complete
      await uploadTask;

      // Get download URL
      final fileUrl = await ref.getDownloadURL();

      // Get file metadata
      final fileSize = file.lengthSync();
      final mimeType = lookupMimeType(fileName) ?? 'application/octet-stream';

      // Create FileAttachment document
      final fileAttachment = FileAttachment(
        id: '', // Will be set by Firestore
        workspaceId: workspaceId,
        projectId: projectId,
        taskId: taskId,
        messageId: messageId,
        folderId: folderId,
        tags: tags ?? [],
        fileName: fileName,
        fileUrl: fileUrl,
        fileSize: fileSize,
        mimeType: mimeType,
        uploadedBy: uploadedBy,
        uploadedAt: DateTime.now(),
      );

      // Save metadata to Firestore
      final docRef = await _firestore
          .collection('file_attachments')
          .add(fileAttachment.toJson());

      return FileAttachment(
        id: docRef.id,
        workspaceId: workspaceId,
        projectId: projectId,
        taskId: taskId,
        messageId: messageId,
        folderId: folderId,
        tags: tags ?? [],
        fileName: fileName,
        fileUrl: fileUrl,
        fileSize: fileSize,
        mimeType: mimeType,
        uploadedBy: uploadedBy,
        uploadedAt: fileAttachment.uploadedAt,
      );
    } catch (e) {
      AppLogger.error('Failed to upload file', error: e, metadata: {
        'fileName': fileName,
        'projectId': projectId,
        'taskId': taskId,
      });
      throw Exception('Failed to upload file: $e');
    }
  }

  // Upload file bytes to Firebase Storage (for web)
  Future<FileAttachment> uploadFileBytes({
    required Uint8List bytes,
    required String fileName,
    required String workspaceId,
    required String projectId,
    String? taskId,
    String? messageId,
    String? folderId,
    List<String>? tags,
    required String uploadedBy,
    Function(double)? onProgress,
  }) async {
    try {
      // Validate file
      final validation = validateFileBytes(bytes, fileName);
      if (!validation.isValid) {
        throw Exception(validation.error);
      }

      // Generate unique filename
      final uniqueFileName = _generateUniqueFileName(fileName);

      // Build storage path
      final storagePath = taskId != null
          ? 'workspaces/$workspaceId/projects/$projectId/tasks/$taskId/$uniqueFileName'
          : 'workspaces/$workspaceId/projects/$projectId/$uniqueFileName';

      // Upload bytes
      final ref = _storage.ref().child(storagePath);
      final mimeType = lookupMimeType(fileName) ?? 'application/octet-stream';
      final metadata = SettableMetadata(
        contentType: mimeType,
      );
      final uploadTask = ref.putData(bytes, metadata);

      // Track progress
      if (onProgress != null) {
        uploadTask.snapshotEvents.listen((snapshot) {
          final progress = snapshot.bytesTransferred / snapshot.totalBytes;
          onProgress(progress);
        });
      }

      // Wait for upload to complete
      await uploadTask;

      // Get download URL
      final fileUrl = await ref.getDownloadURL();

      // Get file metadata
      final fileSize = bytes.length;

      // Create FileAttachment document
      final fileAttachment = FileAttachment(
        id: '', // Will be set by Firestore
        workspaceId: workspaceId,
        projectId: projectId,
        taskId: taskId,
        messageId: messageId,
        folderId: folderId,
        tags: tags ?? [],
        fileName: fileName,
        fileUrl: fileUrl,
        fileSize: fileSize,
        mimeType: mimeType,
        uploadedBy: uploadedBy,
        uploadedAt: DateTime.now(),
      );

      // Save metadata to Firestore
      final docRef = await _firestore
          .collection('file_attachments')
          .add(fileAttachment.toJson());

      return FileAttachment(
        id: docRef.id,
        workspaceId: workspaceId,
        projectId: projectId,
        taskId: taskId,
        messageId: messageId,
        folderId: folderId,
        tags: tags ?? [],
        fileName: fileName,
        fileUrl: fileUrl,
        fileSize: fileSize,
        mimeType: mimeType,
        uploadedBy: uploadedBy,
        uploadedAt: fileAttachment.uploadedAt,
      );
    } catch (e) {
      AppLogger.error('Failed to upload file bytes', error: e, metadata: {
        'fileName': fileName,
        'projectId': projectId,
        'taskId': taskId,
      });
      throw Exception('Failed to upload file: $e');
    }
  }

  // Delete file from Storage and Firestore
  Future<void> deleteFile(FileAttachment fileAttachment) async {
    try {
      // Delete from Storage
      final ref = _storage.refFromURL(fileAttachment.fileUrl);
      await ref.delete();

      // Delete metadata from Firestore
      await _firestore
          .collection('file_attachments')
          .doc(fileAttachment.id)
          .delete();
    } catch (e) {
      AppLogger.error('Failed to delete file', error: e, metadata: {
        'fileId': fileAttachment.id,
        'fileName': fileAttachment.fileName,
      });
      throw Exception('Failed to delete file: $e');
    }
  }

  // Get all files for a project (for "All Files" view)
  Stream<List<FileAttachment>> getProjectFiles(
    String workspaceId,
    String projectId,
  ) {
    return _firestore
        .collection('file_attachments')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('projectId', isEqualTo: projectId)
        .orderBy('uploadedAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => FileAttachment.fromJson(doc.data(), doc.id))
          .toList();
    });
  }

  // Get files for a task
  Stream<List<FileAttachment>> getTaskFiles(
    String workspaceId,
    String taskId,
  ) {
    return _firestore
        .collection('file_attachments')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('taskId', isEqualTo: taskId)
        .orderBy('uploadedAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => FileAttachment.fromJson(doc.data(), doc.id))
          .toList();
    });
  }

  // Get files in a specific folder
  Stream<List<FileAttachment>> getFolderFiles(
    String workspaceId,
    String projectId,
    String folderId,
  ) {
    return _firestore
        .collection('file_attachments')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('projectId', isEqualTo: projectId)
        .where('folderId', isEqualTo: folderId)
        .orderBy('uploadedAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => FileAttachment.fromJson(doc.data(), doc.id))
          .toList();
    });
  }

  // Get all task files for a project (for virtual Tasks folder)
  Stream<List<FileAttachment>> getAllProjectTaskFiles(
    String workspaceId,
    String projectId,
  ) {
    return _firestore
        .collection('file_attachments')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('projectId', isEqualTo: projectId)
        .orderBy('uploadedAt', descending: true)
        .snapshots()
        .map((snapshot) {
      // Filter in memory to get only files with taskId set
      return snapshot.docs
          .map((doc) => FileAttachment.fromJson(doc.data(), doc.id))
          .where((file) => file.taskId != null)
          .toList();
    });
  }

  // Get all message files for a project (for virtual Messages folder)
  Stream<List<FileAttachment>> getAllProjectMessageFiles(
    String workspaceId,
    String projectId,
  ) {
    return _firestore
        .collection('file_attachments')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('projectId', isEqualTo: projectId)
        .orderBy('uploadedAt', descending: true)
        .snapshots()
        .map((snapshot) {
      // Filter in memory to get only files with messageId set
      return snapshot.docs
          .map((doc) => FileAttachment.fromJson(doc.data(), doc.id))
          .where((file) => file.messageId != null)
          .toList();
    });
  }

  // Get files without a folder (root files)
  Stream<List<FileAttachment>> getRootFiles(
    String workspaceId,
    String projectId,
  ) {
    return _firestore
        .collection('file_attachments')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('projectId', isEqualTo: projectId)
        .where('folderId', isNull: true)
        .where('taskId', isNull: true)
        .where('messageId', isNull: true)
        .orderBy('uploadedAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => FileAttachment.fromJson(doc.data(), doc.id))
          .toList();
    });
  }

  // Update file's folder
  Future<void> moveFileToFolder(String fileId, String? folderId) async {
    try {
      await _firestore
          .collection('file_attachments')
          .doc(fileId)
          .update({'folderId': folderId});
    } catch (e) {
      AppLogger.error('Failed to move file', error: e, metadata: {
        'fileId': fileId,
        'folderId': folderId,
      });
      throw Exception('Failed to move file: $e');
    }
  }

  // Update file tags
  Future<void> updateFileTags(String fileId, List<String> tags) async {
    try {
      await _firestore
          .collection('file_attachments')
          .doc(fileId)
          .update({'tags': tags});
    } catch (e) {
      AppLogger.error('Failed to update file tags', error: e, metadata: {
        'fileId': fileId,
        'tags': tags,
      });
      throw Exception('Failed to update file tags: $e');
    }
  }

  /// Upload a signature image to Firebase Storage
  /// Returns the public URL of the uploaded signature
  Future<String> uploadSignature({
    required Uint8List signatureBytes,
    required String workspaceId,
    required String documentId,
  }) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'workspaces/$workspaceId/signatures/${documentId}_$timestamp.png';
      final ref = _storage.ref().child(fileName);

      final uploadTask = await ref.putData(
        signatureBytes,
        SettableMetadata(contentType: 'image/png'),
      );

      return await uploadTask.ref.getDownloadURL();
    } catch (e) {
      AppLogger.error('Failed to upload signature', error: e, metadata: {
        'workspaceId': workspaceId,
        'documentId': documentId,
      });
      throw Exception('Failed to upload signature: $e');
    }
  }
}
