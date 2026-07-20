import 'dart:io';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mime/mime.dart';
import '../../models/file_attachment.dart';
import '../../models/file_tag.dart';
import '../../config/supabase_config.dart';
import '../../utils/app_logger.dart';
import '../../utils/image_compress_utils.dart';
import '../../utils/storage_path_utils.dart';

/// Thrown when a workspace exceeds its storage quota.
class StorageQuotaExceededException implements Exception {
  final int usedBytes;
  final int limitBytes;
  final int fileSizeBytes;

  StorageQuotaExceededException({
    required this.usedBytes,
    required this.limitBytes,
    required this.fileSizeBytes,
  });

  String get usedFormatted => _formatBytes(usedBytes);
  String get limitFormatted => _formatBytes(limitBytes);

  static String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  String toString() =>
      'Storage limit reached ($usedFormatted of $limitFormatted used). '
      'Upgrade your plan for more storage.';
}

/// Supabase implementation of StorageService
class SupabaseStorageService {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const String _privateStorageScheme = 'tfstorage://';

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

  /// Storage limits per subscription tier (in bytes).
  static const Map<String, int> _storageLimits = {
    'free': 1 * 1024 * 1024 * 1024, // 1 GB
    'pro': 10 * 1024 * 1024 * 1024, // 10 GB
    'business': 100 * 1024 * 1024 * 1024, // 100 GB
  };

  /// Get the current storage usage for a workspace (in bytes).
  Future<int> getWorkspaceStorageUsage(String workspaceId) async {
    final result = await _supabase.rpc(
      'get_workspace_storage_usage',
      params: {'p_workspace_id': workspaceId},
    );
    return (result as num?)?.toInt() ?? 0;
  }

  /// Check if the workspace has enough storage quota for a new file.
  /// Throws [StorageQuotaExceededException] if the quota would be exceeded.
  Future<void> _checkStorageQuota(String workspaceId, int fileSizeBytes) async {
    // Look up workspace subscription tier
    final workspace = await _supabase
        .from('workspaces')
        .select('subscription_tier')
        .eq('id', workspaceId)
        .maybeSingle();

    final tier = workspace?['subscription_tier'] as String? ?? 'free';
    final limitBytes = _storageLimits[tier] ?? _storageLimits['free']!;
    final usedBytes = await getWorkspaceStorageUsage(workspaceId);

    if (usedBytes + fileSizeBytes > limitBytes) {
      throw StorageQuotaExceededException(
        usedBytes: usedBytes,
        limitBytes: limitBytes,
        fileSizeBytes: fileSizeBytes,
      );
    }
  }

  /// Validate file before upload
  ({bool isValid, String? error}) validateFile(File file, String fileName) {
    // Check file size
    final fileSize = file.lengthSync();
    if (fileSize > maxFileSizeBytes) {
      return (isValid: false, error: 'File size must be less than 10MB');
    }

    // Check file type
    final mimeType = lookupMimeType(fileName) ?? 'application/octet-stream';
    if (!allowedMimeTypes.contains(mimeType)) {
      return (
        isValid: false,
        error:
            'File type not allowed. Supported: JPG, PNG, HEIC, PDF, DOC, XLS',
      );
    }

    return (isValid: true, error: null);
  }

  /// Validate bytes before upload (for web)
  ({bool isValid, String? error}) validateFileBytes(
    Uint8List bytes,
    String fileName,
  ) {
    if (bytes.length > maxFileSizeBytes) {
      return (isValid: false, error: 'File size must be less than 10MB');
    }

    final mimeType = lookupMimeType(fileName) ?? 'application/octet-stream';
    if (!allowedMimeTypes.contains(mimeType)) {
      return (
        isValid: false,
        error:
            'File type not allowed. Supported: JPG, PNG, HEIC, PDF, DOC, XLS',
      );
    }

    return (isValid: true, error: null);
  }

  /// Generate unique filename to prevent collisions
  String _generateUniqueFileName(String originalFileName) {
    return buildUniqueStorageFileName(
      originalFileName,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  String _buildPrivateStorageRef(String bucket, String storagePath) =>
      '$_privateStorageScheme$bucket/$storagePath';

  ({String bucket, String path})? parsePrivateStorageRef(String? rawValue) {
    if (rawValue == null) return null;

    final trimmed = rawValue.trim();
    if (!trimmed.startsWith(_privateStorageScheme)) return null;

    final withoutScheme = trimmed.substring(_privateStorageScheme.length);
    final separatorIndex = withoutScheme.indexOf('/');
    if (separatorIndex <= 0 || separatorIndex == withoutScheme.length - 1) {
      return null;
    }

    return (
      bucket: withoutScheme.substring(0, separatorIndex),
      path: withoutScheme.substring(separatorIndex + 1),
    );
  }

  Future<String?> resolveStorageUrl(
    String? rawValue, {
    int expiresIn = 3600,
  }) async {
    if (rawValue == null || rawValue.trim().isEmpty) return rawValue;

    final parsedRef = parsePrivateStorageRef(rawValue);
    if (parsedRef == null) return rawValue;

    return getSignedUrl(parsedRef.bucket, parsedRef.path, expiresIn: expiresIn);
  }

  /// Determine the bucket based on file type
  String _getBucket(String mimeType) {
    if (mimeType.startsWith('image/')) {
      return 'project-images';
    } else {
      return 'project-documents';
    }
  }

  bool _isBucketNotFound(Object error) {
    if (error is StorageException) {
      final message = error.message.toLowerCase();
      return error.statusCode == '404' || message.contains('bucket not found');
    }
    return false;
  }

  Future<String> _uploadWithBucketFallback({
    required String preferredBucket,
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
  }) async {
    const cacheControl = '31536000';
    try {
      await _supabase.storage
          .from(preferredBucket)
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(
              contentType: contentType,
              cacheControl: cacheControl,
            ),
          );
      return preferredBucket;
    } catch (e) {
      if (preferredBucket == SupabaseConfig.projectFilesBucket ||
          !_isBucketNotFound(e)) {
        rethrow;
      }

      AppLogger.warning(
        'Storage bucket missing, falling back to project-files',
        metadata: {'missingBucket': preferredBucket},
      );

      await _supabase.storage
          .from(SupabaseConfig.projectFilesBucket)
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(
              contentType: contentType,
              cacheControl: cacheControl,
            ),
          );
      return SupabaseConfig.projectFilesBucket;
    }
  }

  /// Upload a thumbnail for an image and return its public URL.
  /// Returns null if the image can't be thumbnailed or upload fails.
  Future<String?> _uploadThumbnail({
    required Uint8List imageBytes,
    required String mimeType,
    required String storagePath,
    required String bucket,
  }) async {
    final thumbBytes = await ImageCompressUtils.generateThumbnail(
      imageBytes,
      mimeType,
    );
    if (thumbBytes == null) return null;

    final thumbStoragePath = ImageCompressUtils.thumbPath(storagePath);
    try {
      final uploadedBucket = await _uploadWithBucketFallback(
        preferredBucket: bucket,
        storagePath: thumbStoragePath,
        bytes: thumbBytes,
        contentType: 'image/jpeg',
      );
      return _supabase.storage
          .from(uploadedBucket)
          .getPublicUrl(thumbStoragePath);
    } catch (e) {
      AppLogger.warning(
        'Failed to upload thumbnail, continuing without it',
        metadata: {'storagePath': thumbStoragePath},
      );
      return null;
    }
  }

  /// Upload file to Supabase Storage
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

      // Check storage quota before uploading
      await _checkStorageQuota(workspaceId, file.lengthSync());

      // Generate unique filename
      final uniqueFileName = _generateUniqueFileName(fileName);
      final mimeType = lookupMimeType(fileName) ?? 'application/octet-stream';
      final bucket = _getBucket(mimeType);

      // Build storage path
      final storagePath = taskId != null
          ? '$workspaceId/$projectId/tasks/$taskId/$uniqueFileName'
          : '$workspaceId/$projectId/$uniqueFileName';

      // Read and compress image bytes (non-images pass through unchanged)
      final bytes = await ImageCompressUtils.compressFile(file, mimeType);

      // Upload to Supabase Storage
      // Note: Supabase doesn't provide progress events like Firebase
      // We'll simulate a simple progress callback
      if (onProgress != null) {
        onProgress(0.0);
      }

      final uploadedBucket = await _uploadWithBucketFallback(
        preferredBucket: bucket,
        storagePath: storagePath,
        bytes: bytes,
        contentType: mimeType,
      );

      if (onProgress != null) {
        onProgress(1.0);
      }

      // Get public URL
      final fileUrl = _supabase.storage
          .from(uploadedBucket)
          .getPublicUrl(storagePath);

      // Generate and upload thumbnail for images
      final thumbnailUrl = await _uploadThumbnail(
        imageBytes: bytes,
        mimeType: mimeType,
        storagePath: storagePath,
        bucket: uploadedBucket,
      );

      // Get file metadata (use compressed bytes length)
      final fileSize = bytes.length;
      final now = DateTime.now();

      // Create FileAttachment record in database
      final attachmentData = {
        'workspace_id': workspaceId,
        'project_id': projectId,
        'task_id': taskId,
        'message_id': messageId,
        'folder_id': folderId,
        'tags': tags ?? [],
        'file_name': fileName,
        'file_url': fileUrl,
        'thumbnail_url': thumbnailUrl,
        'storage_path': storagePath,
        'bucket': uploadedBucket,
        'file_size': fileSize,
        'mime_type': mimeType,
        'uploaded_by': uploadedBy,
        'uploaded_at': now.toIso8601String(),
        'created_at': now.toIso8601String(),
      };

      final response = await _supabase
          .from('file_attachments')
          .insert(attachmentData)
          .select()
          .single();

      // Audit — uploaded. Fire-and-forget inside _recordEvent.
      await _recordEvent(
        response['id'] as String,
        'uploaded',
        payload: {
          'file_name': fileName,
          'size': fileSize,
          'mime_type': mimeType,
          if (taskId != null) 'task_id': taskId,
          if (folderId != null) 'folder_id': folderId,
        },
      );

      return FileAttachment(
        id: response['id'],
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
        uploadedAt: now,
        thumbnailUrl: thumbnailUrl,
      );
    } catch (e) {
      AppLogger.error(
        'Failed to upload file',
        error: e,
        metadata: {
          'fileName': fileName,
          'projectId': projectId,
          'taskId': taskId,
        },
      );
      throw Exception('Failed to upload file: $e');
    }
  }

  /// Upload file bytes to Supabase Storage (for web)
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

      // Check storage quota before uploading
      await _checkStorageQuota(workspaceId, bytes.length);

      // Generate unique filename
      final uniqueFileName = _generateUniqueFileName(fileName);
      final mimeType = lookupMimeType(fileName) ?? 'application/octet-stream';
      final bucket = _getBucket(mimeType);

      // Build storage path
      final storagePath = taskId != null
          ? '$workspaceId/$projectId/tasks/$taskId/$uniqueFileName'
          : '$workspaceId/$projectId/$uniqueFileName';

      // Compress images before upload
      final uploadBytes = await ImageCompressUtils.compressBytes(
        bytes,
        mimeType,
      );

      if (onProgress != null) {
        onProgress(0.0);
      }

      // Upload to Supabase Storage
      final uploadedBucket = await _uploadWithBucketFallback(
        preferredBucket: bucket,
        storagePath: storagePath,
        bytes: uploadBytes,
        contentType: mimeType,
      );

      if (onProgress != null) {
        onProgress(1.0);
      }

      // Get public URL
      final fileUrl = _supabase.storage
          .from(uploadedBucket)
          .getPublicUrl(storagePath);

      // Generate and upload thumbnail for images
      final thumbnailUrl = await _uploadThumbnail(
        imageBytes: uploadBytes,
        mimeType: mimeType,
        storagePath: storagePath,
        bucket: uploadedBucket,
      );

      // Get file metadata (use compressed bytes length)
      final fileSize = uploadBytes.length;
      final now = DateTime.now();

      // Create FileAttachment record in database
      final attachmentData = {
        'workspace_id': workspaceId,
        'project_id': projectId,
        'task_id': taskId,
        'message_id': messageId,
        'folder_id': folderId,
        'tags': tags ?? [],
        'file_name': fileName,
        'file_url': fileUrl,
        'thumbnail_url': thumbnailUrl,
        'storage_path': storagePath,
        'bucket': uploadedBucket,
        'file_size': fileSize,
        'mime_type': mimeType,
        'uploaded_by': uploadedBy,
        'uploaded_at': now.toIso8601String(),
        'created_at': now.toIso8601String(),
      };

      final response = await _supabase
          .from('file_attachments')
          .insert(attachmentData)
          .select()
          .single();

      // Audit — uploaded. Fire-and-forget inside _recordEvent.
      await _recordEvent(
        response['id'] as String,
        'uploaded',
        payload: {
          'file_name': fileName,
          'size': fileSize,
          'mime_type': mimeType,
          if (taskId != null) 'task_id': taskId,
          if (folderId != null) 'folder_id': folderId,
        },
      );

      return FileAttachment(
        id: response['id'],
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
        uploadedAt: now,
        thumbnailUrl: thumbnailUrl,
      );
    } catch (e) {
      AppLogger.error(
        'Failed to upload file bytes',
        error: e,
        metadata: {
          'fileName': fileName,
          'projectId': projectId,
          'taskId': taskId,
        },
      );
      throw Exception('Failed to upload file: $e');
    }
  }

  /// Delete file from Storage and database
  Future<void> deleteFile(FileAttachment fileAttachment) async {
    try {
      // Get storage path and bucket from database record
      final record = await _supabase
          .from('file_attachments')
          .select('storage_path, bucket')
          .eq('id', fileAttachment.id)
          .maybeSingle();

      // Record the delete event BEFORE the row is gone. Safe to lose this
      // via fire-and-forget — file_events survives the deletion itself
      // thanks to ON DELETE SET NULL (migration 20260420140000).
      await _recordEvent(
        fileAttachment.id,
        'deleted',
        payload: {
          'file_name': fileAttachment.fileName,
          'size': fileAttachment.fileSize,
          'mime_type': fileAttachment.mimeType,
        },
      );

      if (record != null) {
        final storagePath = record['storage_path'] as String?;
        final bucket = record['bucket'] as String?;

        if (storagePath != null && bucket != null) {
          // Delete main file and thumbnail from Storage
          final thumbStoragePath = ImageCompressUtils.thumbPath(storagePath);
          await _supabase.storage.from(bucket).remove([
            storagePath,
            thumbStoragePath,
          ]);
        }
      }

      // Delete metadata from database
      await _supabase
          .from('file_attachments')
          .delete()
          .eq('id', fileAttachment.id);
    } catch (e) {
      AppLogger.error(
        'Failed to delete file',
        error: e,
        metadata: {
          'fileId': fileAttachment.id,
          'fileName': fileAttachment.fileName,
        },
      );
      throw Exception('Failed to delete file: $e');
    }
  }

  /// Get all files for a project (realtime stream)
  Stream<List<FileAttachment>> getProjectFiles(
    String workspaceId,
    String projectId,
  ) {
    return _supabase
        .from('file_attachments')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .map((data) {
          final filtered = data
              .where((row) => row['project_id'] == projectId)
              .map((row) => _toFileAttachment(row))
              .toList();
          filtered.sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
          return filtered;
        });
  }

  /// Get files for a task
  Stream<List<FileAttachment>> getTaskFiles(String workspaceId, String taskId) {
    return _supabase
        .from('file_attachments')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .map((data) {
          final filtered = data
              .where((row) => row['task_id'] == taskId)
              .map((row) => _toFileAttachment(row))
              .toList();
          filtered.sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
          return filtered;
        });
  }

  /// Get files in a specific folder
  Stream<List<FileAttachment>> getFolderFiles(
    String workspaceId,
    String projectId,
    String folderId,
  ) {
    return _supabase
        .from('file_attachments')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .map((data) {
          final filtered = data
              .where(
                (row) =>
                    row['project_id'] == projectId &&
                    row['folder_id'] == folderId,
              )
              .map((row) => _toFileAttachment(row))
              .toList();
          filtered.sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
          return filtered;
        });
  }

  /// Get all task files for a project (for virtual Tasks folder)
  Stream<List<FileAttachment>> getAllProjectTaskFiles(
    String workspaceId,
    String projectId,
  ) {
    return _supabase
        .from('file_attachments')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .map((data) {
          final filtered = data
              .where(
                (row) =>
                    row['project_id'] == projectId && row['task_id'] != null,
              )
              .map((row) => _toFileAttachment(row))
              .toList();
          filtered.sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
          return filtered;
        });
  }

  /// Get all message files for a project (for virtual Messages folder)
  Stream<List<FileAttachment>> getAllProjectMessageFiles(
    String workspaceId,
    String projectId,
  ) {
    return _supabase
        .from('file_attachments')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .map((data) {
          final filtered = data
              .where(
                (row) =>
                    row['project_id'] == projectId && row['message_id'] != null,
              )
              .map((row) => _toFileAttachment(row))
              .toList();
          filtered.sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
          return filtered;
        });
  }

  /// Get files without a folder (root files)
  Stream<List<FileAttachment>> getRootFiles(
    String workspaceId,
    String projectId,
  ) {
    return _supabase
        .from('file_attachments')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .map((data) {
          final filtered = data
              .where(
                (row) =>
                    row['project_id'] == projectId &&
                    row['folder_id'] == null &&
                    row['task_id'] == null &&
                    row['message_id'] == null,
              )
              .map((row) => _toFileAttachment(row))
              .toList();
          filtered.sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
          return filtered;
        });
  }

  /// Update file's folder
  Future<void> moveFileToFolder(String fileId, String? folderId) async {
    try {
      await _supabase
          .from('file_attachments')
          .update({'folder_id': folderId})
          .eq('id', fileId);
    } catch (e) {
      AppLogger.error(
        'Failed to move file',
        error: e,
        metadata: {'fileId': fileId, 'folderId': folderId},
      );
      throw Exception('Failed to move file: $e');
    }
  }

  /// Update file tags
  Future<void> updateFileTags(String fileId, List<String> tags) async {
    try {
      await _supabase
          .from('file_attachments')
          .update({'tags': tags})
          .eq('id', fileId);
    } catch (e) {
      AppLogger.error(
        'Failed to update file tags',
        error: e,
        metadata: {'fileId': fileId, 'tags': tags},
      );
      throw Exception('Failed to update file tags: $e');
    }
  }

  /// Generate a signed URL for temporary access (for private buckets)
  Future<String> getSignedUrl(
    String bucket,
    String path, {
    int expiresIn = 3600,
  }) async {
    try {
      final response = await _supabase.storage
          .from(bucket)
          .createSignedUrl(path, expiresIn);
      return response;
    } catch (e) {
      throw Exception('Failed to generate signed URL: $e');
    }
  }

  /// Build a shareable link for a file that works for unauthenticated
  /// recipients. Looks up the file's bucket + storage_path and returns a
  /// signed URL; defaults to 7 days so links pasted into emails/chats
  /// remain valid for the typical review window. Pass `forceDownload: true`
  /// to make the link trigger a save-to-disk via Content-Disposition
  /// instead of inline display.
  Future<String> createShareableLink(
    String fileId, {
    Duration expiresIn = const Duration(days: 7),
    bool forceDownload = false,
  }) async {
    final row = await _supabase
        .from('file_attachments')
        .select('bucket, storage_path, file_name')
        .eq('id', fileId)
        .maybeSingle();
    if (row == null) {
      throw Exception('File not found');
    }
    final bucket = row['bucket'] as String?;
    final path = row['storage_path'] as String?;
    if (bucket == null || bucket.isEmpty || path == null || path.isEmpty) {
      throw Exception('File has no storage path — cannot share');
    }
    final signed = await _supabase.storage
        .from(bucket)
        .createSignedUrl(path, expiresIn.inSeconds);
    if (!forceDownload) return signed;
    final fileName = row['file_name'] as String? ?? 'file';
    final uri = Uri.parse(signed);
    return uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        'download': fileName,
      },
    ).toString();
  }

  /// Fire-and-forget append to the file_events audit trail.
  ///
  /// Uses the server-side `record_file_event` RPC (SECURITY DEFINER) so
  /// clients can't forge history. Failures are logged but never raised —
  /// an audit-log hiccup should not break a user's upload/edit flow.
  Future<void> _recordEvent(
    String fileId,
    String action, {
    Map<String, dynamic>? payload,
  }) async {
    try {
      await _supabase.rpc('record_file_event', params: {
        'p_file_attachment_id': fileId,
        'p_action': action,
        'p_payload': payload ?? const <String, dynamic>{},
      });
    } catch (e) {
      AppLogger.warning(
        'record_file_event failed',
        metadata: {'fileId': fileId, 'action': action, 'error': e.toString()},
      );
    }
  }

  /// Convert database row to FileAttachment.
  ///
  /// When the query selects `file_attachment_tags(file_tags(*))` the embedded
  /// rows are hydrated into [FileAttachment.resolvedTags]. Callers that don't
  /// need tag chips can skip the join for lighter queries — the model falls
  /// back to the legacy `tags` TEXT[] column.
  FileAttachment _toFileAttachment(Map<String, dynamic> row) {
    final joinRows = row['file_attachment_tags'] as List<dynamic>?;
    final resolved = joinRows == null
        ? const <FileTag>[]
        : joinRows
            .map((r) {
              final tag = (r as Map<String, dynamic>)['file_tags'];
              return tag is Map<String, dynamic>
                  ? FileTag.fromSupabase(tag)
                  : null;
            })
            .whereType<FileTag>()
            .toList();

    return FileAttachment(
      id: row['id'],
      workspaceId: row['workspace_id'],
      projectId: row['project_id'],
      taskId: row['task_id'],
      messageId: row['message_id'],
      folderId: row['folder_id'],
      tags: (row['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      resolvedTags: resolved,
      title: row['title'] as String?,
      description: row['description'] as String?,
      fileName: row['file_name'],
      fileUrl: row['file_url'],
      fileSize: row['file_size'],
      mimeType: row['mime_type'],
      uploadedBy: row['uploaded_by'],
      uploadedAt: DateTime.parse(row['uploaded_at']),
      thumbnailUrl: row['thumbnail_url'] as String?,
    );
  }

  /// Update editable file metadata (title / description / folder / tag set).
  ///
  /// Any parameter left null is unchanged. `tagIds` replaces the file's entire
  /// tag set when provided (pass an empty list to clear). Does NOT touch
  /// storage quota or underlying bytes.
  Future<void> updateFileMetadata({
    required String fileId,
    String? title,
    String? description,
    String? folderId,
    bool clearFolder = false,
    List<String>? tagIds,
  }) async {
    try {
      // Snapshot the row + joined tag ids before mutating so we can emit
      // granular audit events (renamed / described / moved / tagged_*).
      final before = await _supabase
          .from('file_attachments')
          .select('title, description, folder_id')
          .eq('id', fileId)
          .maybeSingle();

      Set<String> beforeTagIds = const <String>{};
      if (tagIds != null) {
        final rows = await _supabase
            .from('file_attachment_tags')
            .select('file_tag_id')
            .eq('file_attachment_id', fileId);
        beforeTagIds =
            (rows as List).map((r) => r['file_tag_id'] as String).toSet();
      }

      final updates = <String, dynamic>{};
      if (title != null) updates['title'] = title.isEmpty ? null : title;
      if (description != null) {
        updates['description'] = description.isEmpty ? null : description;
      }
      if (folderId != null || clearFolder) {
        updates['folder_id'] = clearFolder ? null : folderId;
      }

      if (updates.isNotEmpty) {
        await _supabase
            .from('file_attachments')
            .update(updates)
            .eq('id', fileId);
      }

      if (tagIds != null) {
        await _setFileTagJoinRows(fileId, tagIds);
        // Mirror the canonical tag names onto the legacy `tags` TEXT[] so
        // stream-backed views (grid/list) pick up the change without a full
        // reload. This column is scheduled for removal in a follow-up, at
        // which point this mirror goes away too.
        await _mirrorTagNamesToLegacyColumn(fileId);
      }

      // Audit — only emit events for dimensions that actually changed.
      if (before != null) {
        final beforeTitle = before['title'] as String?;
        final beforeDesc = before['description'] as String?;
        final beforeFolder = before['folder_id'] as String?;

        if (title != null && (title.isEmpty ? null : title) != beforeTitle) {
          await _recordEvent(fileId, 'renamed', payload: {
            'from': beforeTitle,
            'to': title.isEmpty ? null : title,
          });
        }
        if (description != null &&
            (description.isEmpty ? null : description) != beforeDesc) {
          await _recordEvent(fileId, 'described', payload: {
            'length': description.length,
          });
        }
        if ((folderId != null || clearFolder) &&
            (clearFolder ? null : folderId) != beforeFolder) {
          await _recordEvent(fileId, 'moved', payload: {
            'from_folder_id': beforeFolder,
            'to_folder_id': clearFolder ? null : folderId,
          });
        }
      }

      if (tagIds != null) {
        final desired = tagIds.toSet();
        final added = desired.difference(beforeTagIds);
        final removed = beforeTagIds.difference(desired);
        for (final id in added) {
          await _recordEvent(fileId, 'tagged_added', payload: {'tag_id': id});
        }
        for (final id in removed) {
          await _recordEvent(fileId, 'tagged_removed',
              payload: {'tag_id': id});
        }
      }
    } catch (e) {
      AppLogger.error(
        'Failed to update file metadata',
        error: e,
        metadata: {'fileId': fileId},
      );
      throw Exception('Failed to update file: $e');
    }
  }

  /// Diff-apply tag ids on a file. Mirrors SupabaseFileTagService.setFileTags
  /// but is colocated here so upload/update flows don't need a second service.
  Future<void> _setFileTagJoinRows(String fileId, List<String> tagIds) async {
    final currentRows = await _supabase
        .from('file_attachment_tags')
        .select('file_tag_id')
        .eq('file_attachment_id', fileId);

    final current = (currentRows as List)
        .map((r) => r['file_tag_id'] as String)
        .toSet();
    final desired = tagIds.toSet();

    final toAdd = desired.difference(current);
    final toRemove = current.difference(desired);

    if (toAdd.isNotEmpty) {
      await _supabase.from('file_attachment_tags').upsert(
        toAdd
            .map((tagId) => {
                  'file_attachment_id': fileId,
                  'file_tag_id': tagId,
                })
            .toList(),
        onConflict: 'file_attachment_id,file_tag_id',
        ignoreDuplicates: true,
      );
    }

    if (toRemove.isNotEmpty) {
      await _supabase
          .from('file_attachment_tags')
          .delete()
          .eq('file_attachment_id', fileId)
          .inFilter('file_tag_id', toRemove.toList());
    }
  }

  /// Copy the names of whatever tags are currently joined to this file into
  /// the legacy `file_attachments.tags TEXT[]` column. Keeps streamed views
  /// (which don't include the join) in sync with panel edits.
  Future<void> _mirrorTagNamesToLegacyColumn(String fileId) async {
    final rows = await _supabase
        .from('file_attachment_tags')
        .select('file_tags(name)')
        .eq('file_attachment_id', fileId);

    final names = (rows as List)
        .map((r) => (r['file_tags'] as Map<String, dynamic>?)?['name'])
        .whereType<String>()
        .toList()
      ..sort();

    await _supabase
        .from('file_attachments')
        .update({'tags': names})
        .eq('id', fileId);
  }

  /// Live stream of every file in a workspace, newest first. Used by the
  /// global Files screen for cross-job browsing; the caller applies any
  /// additional scope filter (customer, tag) client-side.
  ///
  /// Note: Supabase streams can't do joins, so [FileAttachment.resolvedTags]
  /// is always empty here. Callers that need tag filtering should read
  /// [FileAttachment.tags] (the legacy TEXT[] column, kept in sync by
  /// [updateFileMetadata]).
  Stream<List<FileAttachment>> streamWorkspaceFiles(String workspaceId) {
    return _supabase
        .from('file_attachments')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .map((data) {
          final files =
              data.map((row) => _toFileAttachment(row)).toList();
          files.sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
          return files;
        });
  }

  /// Fetch a single file with its resolved tags hydrated.
  Future<FileAttachment?> getFileWithTags(String fileId) async {
    final row = await _supabase
        .from('file_attachments')
        .select('*, file_attachment_tags(file_tags(*))')
        .eq('id', fileId)
        .maybeSingle();
    if (row == null) return null;
    return _toFileAttachment(row);
  }

  /// Upload a signature image to Supabase Storage
  /// Returns the public URL of the uploaded signature
  Future<String> uploadPaymentAttachment({
    required Uint8List bytes,
    required String fileName,
    required String workspaceId,
    required String documentId,
  }) async {
    try {
      final validation = validateFileBytes(bytes, fileName);
      if (!validation.isValid) {
        throw Exception(validation.error);
      }

      await _checkStorageQuota(workspaceId, bytes.length);

      final uniqueName = _generateUniqueFileName('${documentId}_$fileName');
      final storagePath = '$workspaceId/payment-attachments/$uniqueName';
      final mimeType = lookupMimeType(fileName) ?? 'application/octet-stream';
      const bucket = SupabaseConfig.projectFilesBucket;
      final uploadBytes = await ImageCompressUtils.compressBytes(
        bytes,
        mimeType,
      );

      final uploadedBucket = await _uploadWithBucketFallback(
        preferredBucket: bucket,
        storagePath: storagePath,
        bytes: uploadBytes,
        contentType: mimeType,
      );

      return _buildPrivateStorageRef(uploadedBucket, storagePath);
    } catch (e) {
      AppLogger.error(
        'Failed to upload payment attachment',
        error: e,
        metadata: {'workspaceId': workspaceId, 'documentId': documentId},
      );
      throw Exception('Failed to upload payment attachment: $e');
    }
  }

  Future<String> uploadSignature({
    required Uint8List signatureBytes,
    required String workspaceId,
    required String documentId,
  }) async {
    try {
      await _checkStorageQuota(workspaceId, signatureBytes.length);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${documentId}_$timestamp.png';
      final storagePath = '$workspaceId/signatures/$fileName';
      const bucket = SupabaseConfig.projectFilesBucket;

      final uploadedBucket = await _uploadWithBucketFallback(
        preferredBucket: bucket,
        storagePath: storagePath,
        bytes: signatureBytes,
        contentType: 'image/png',
      );

      return _buildPrivateStorageRef(uploadedBucket, storagePath);
    } catch (e) {
      AppLogger.error(
        'Failed to upload signature',
        error: e,
        metadata: {'workspaceId': workspaceId, 'documentId': documentId},
      );
      throw Exception('Failed to upload signature: $e');
    }
  }
}
