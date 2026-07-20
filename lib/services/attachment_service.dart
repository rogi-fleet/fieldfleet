import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../config/backend_config.dart';
import '../config/supabase_config.dart';
import '../models/message_attachment.dart';
import '../utils/image_compress_utils.dart';
import '../utils/storage_path_utils.dart';

class AttachmentService {
  final Uuid _uuid = const Uuid();
  final bool _useSupabaseStorage =
      BackendConfig.useSupabaseMessaging || BackendConfig.useSupabaseStorage;
  late final FirebaseStorage _firebaseStorage = FirebaseStorage.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Upload a file to Firebase Storage
  /// Returns a MessageAttachment with the download URL
  Future<MessageAttachment> uploadFile({
    required dynamic file, // Can be File (mobile/desktop) or Uint8List (web)
    required String fileName,
    required String mimeType,
    required String conversationId,
    required String workspaceId,
    Function(double)? onProgress,
  }) async {
    try {
      final fileId = _uuid.v4();
      final safeFileName = sanitizeStoragePathSegment(fileName);
      // Path must start with {workspace_id}/ so the project-files bucket
      // RLS policy (get_workspace_from_storage_path) passes.
      final filePath =
          '$workspaceId/conversations/$conversationId/$fileId-$safeFileName';
      final ({String downloadUrl, int fileSize}) uploadResult =
          _useSupabaseStorage
          ? await _uploadToSupabase(
              file: file,
              filePath: filePath,
              mimeType: mimeType,
              onProgress: onProgress,
            )
          : await _uploadToFirebase(
              file: file,
              filePath: filePath,
              mimeType: mimeType,
              onProgress: onProgress,
            );
      final downloadUrl = uploadResult.downloadUrl;
      final fileSize = uploadResult.fileSize;

      // Generate thumbnail for images
      String? thumbnailUrl;
      if (mimeType.startsWith('image/')) {
        thumbnailUrl = await _generateThumbnail(
          file: file,
          conversationId: conversationId,
          workspaceId: workspaceId,
          fileId: fileId,
          mimeType: mimeType,
        );
      }

      return MessageAttachment(
        id: fileId,
        fileName: fileName,
        fileUrl: downloadUrl,
        fileSize: fileSize,
        mimeType: mimeType,
        thumbnailUrl: thumbnailUrl,
      );
    } catch (e) {
      debugPrint('Error uploading file: $e');
      rethrow;
    }
  }

  Future<({String downloadUrl, int fileSize})> _uploadToFirebase({
    required dynamic file,
    required String filePath,
    required String mimeType,
    Function(double)? onProgress,
  }) async {
    final ref = _firebaseStorage.ref().child(filePath);
    UploadTask uploadTask;
    int fileSize = 0;

    if (file is File) {
      fileSize = await file.length();
      uploadTask = ref.putFile(file, SettableMetadata(contentType: mimeType));
    } else if (file is Uint8List) {
      fileSize = file.length;
      uploadTask = ref.putData(file, SettableMetadata(contentType: mimeType));
    } else {
      throw Exception('Unsupported file type');
    }

    if (onProgress != null) {
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        onProgress(progress);
      });
    }

    final snapshot = await uploadTask;
    final downloadUrl = await snapshot.ref.getDownloadURL();
    return (downloadUrl: downloadUrl, fileSize: fileSize);
  }

  Future<({String downloadUrl, int fileSize})> _uploadToSupabase({
    required dynamic file,
    required String filePath,
    required String mimeType,
    Function(double)? onProgress,
  }) async {
    final rawBytes = switch (file) {
      File f => await f.readAsBytes(),
      Uint8List data => data,
      _ => throw Exception('Unsupported file type'),
    };

    // Compress images before upload
    final bytes = await ImageCompressUtils.compressBytes(rawBytes, mimeType);

    if (onProgress != null) onProgress(0);

    await _supabase.storage
        .from(SupabaseConfig.projectFilesBucket)
        .uploadBinary(
          filePath,
          bytes,
          fileOptions: FileOptions(
            contentType: mimeType,
            cacheControl: '31536000',
          ),
        );

    if (onProgress != null) onProgress(1);

    final downloadUrl = _supabase.storage
        .from(SupabaseConfig.projectFilesBucket)
        .getPublicUrl(filePath);
    return (downloadUrl: downloadUrl, fileSize: bytes.length);
  }

  /// Generate and upload a thumbnail for images.
  Future<String?> _generateThumbnail({
    required dynamic file,
    required String conversationId,
    required String workspaceId,
    required String fileId,
    required String mimeType,
  }) async {
    try {
      final rawBytes = switch (file) {
        File f => await f.readAsBytes(),
        Uint8List data => data,
        _ => null,
      };
      if (rawBytes == null) return null;

      final thumbBytes = await ImageCompressUtils.generateThumbnail(
        rawBytes,
        mimeType,
      );
      if (thumbBytes == null) return null;

      final thumbPath =
          '$workspaceId/conversations/$conversationId/thumbs/$fileId.jpg';

      if (_useSupabaseStorage) {
        await _supabase.storage
            .from(SupabaseConfig.projectFilesBucket)
            .uploadBinary(
              thumbPath,
              thumbBytes,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                cacheControl: '31536000',
              ),
            );
        return _supabase.storage
            .from(SupabaseConfig.projectFilesBucket)
            .getPublicUrl(thumbPath);
      } else {
        final ref = _firebaseStorage.ref().child(thumbPath);
        await ref.putData(
          thumbBytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        return await ref.getDownloadURL();
      }
    } catch (e) {
      // Thumbnail is non-critical — continue without it
      return null;
    }
  }

  /// Delete a file from Firebase Storage
  Future<void> deleteFile(String fileUrl) async {
    try {
      if (_useSupabaseStorage) {
        final supabaseRef = _extractSupabaseStorageRef(fileUrl);
        if (supabaseRef != null) {
          await _supabase.storage.from(supabaseRef.bucket).remove([
            supabaseRef.path,
          ]);
          return;
        }
      }

      final ref = _firebaseStorage.refFromURL(fileUrl);
      await ref.delete();
    } catch (e) {
      debugPrint('Error deleting file: $e');
      // Don't rethrow - file might already be deleted
    }
  }

  /// Delete multiple files
  Future<void> deleteFiles(List<String> fileUrls) async {
    await Future.wait(fileUrls.map((url) => deleteFile(url)));
  }

  _SupabaseStorageRef? _extractSupabaseStorageRef(String fileUrl) {
    final uri = Uri.tryParse(fileUrl);
    if (uri == null) return null;

    final segments = uri.pathSegments;
    for (var i = 0; i <= segments.length - 5; i++) {
      if (segments[i] == 'storage' &&
          segments[i + 1] == 'v1' &&
          segments[i + 2] == 'object' &&
          segments[i + 3] == 'public') {
        final bucket = segments[i + 4];
        if (bucket.isEmpty || segments.length <= i + 5) return null;
        final path = Uri.decodeComponent(segments.skip(i + 5).join('/'));
        if (path.isEmpty) return null;
        return _SupabaseStorageRef(bucket: bucket, path: path);
      }
    }
    return null;
  }
}

class _SupabaseStorageRef {
  final String bucket;
  final String path;

  const _SupabaseStorageRef({required this.bucket, required this.path});
}
