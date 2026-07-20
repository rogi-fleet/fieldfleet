import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Compresses image files before upload to reduce storage usage.
/// Non-image files are returned unchanged.
class ImageCompressUtils {
  /// JPEG quality for compressed images (0-100).
  static const int quality = 80;

  /// Max dimension (width or height) for compressed images.
  static const int maxDimension = 2048;

  /// Minimum file size to bother compressing (100KB).
  static const int minSizeToCompress = 100 * 1024;

  static final _compressibleTypes = {
    'image/jpeg',
    'image/png',
    'image/heic',
    'image/heif',
    'image/webp',
  };

  /// Whether this MIME type should be compressed.
  static bool shouldCompress(String mimeType) {
    return _compressibleTypes.contains(mimeType.toLowerCase());
  }

  static CompressFormat _formatForMime(String mimeType) {
    switch (mimeType.toLowerCase()) {
      case 'image/png':
        return CompressFormat.png;
      case 'image/heic':
      case 'image/heif':
        return CompressFormat.heic;
      case 'image/webp':
        return CompressFormat.webp;
      default:
        return CompressFormat.jpeg;
    }
  }

  /// Compress image bytes. Returns original bytes if compression isn't
  /// beneficial or the file is too small.
  static Future<Uint8List> compressBytes(
    Uint8List bytes,
    String mimeType,
  ) async {
    if (!shouldCompress(mimeType) || bytes.length < minSizeToCompress) {
      return bytes;
    }

    try {
      final result = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: maxDimension,
        minHeight: maxDimension,
        quality: quality,
        format: _formatForMime(mimeType),
      );

      // Only use compressed version if it's actually smaller
      if (result.length < bytes.length) {
        return result;
      }
      return bytes;
    } catch (_) {
      // If compression fails, return original bytes
      return bytes;
    }
  }

  /// Compress an image file. Returns compressed bytes.
  /// Falls back to reading original bytes on failure.
  static Future<Uint8List> compressFile(File file, String mimeType) async {
    final bytes = await file.readAsBytes();
    if (!shouldCompress(mimeType) || bytes.length < minSizeToCompress) {
      return bytes;
    }

    try {
      final result = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        minWidth: maxDimension,
        minHeight: maxDimension,
        quality: quality,
        format: _formatForMime(mimeType),
      );

      if (result != null && result.length < bytes.length) {
        return result;
      }
      return bytes;
    } catch (_) {
      return bytes;
    }
  }

  /// Thumbnail max dimension.
  static const int thumbDimension = 300;

  /// Thumbnail JPEG quality.
  static const int thumbQuality = 60;

  /// Generate a small JPEG thumbnail from image bytes.
  /// Returns null for non-image types or on failure.
  static Future<Uint8List?> generateThumbnail(
    Uint8List bytes,
    String mimeType,
  ) async {
    if (!shouldCompress(mimeType)) return null;

    try {
      final result = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: thumbDimension,
        minHeight: thumbDimension,
        quality: thumbQuality,
        format: CompressFormat.jpeg,
      );
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Build a thumbnail storage path from the original path.
  /// e.g. `ws/proj/image.jpg` → `ws/proj/thumbs/image.jpg`
  static String thumbPath(String storagePath) {
    final lastSlash = storagePath.lastIndexOf('/');
    if (lastSlash == -1) return 'thumbs/$storagePath';
    return '${storagePath.substring(0, lastSlash)}/thumbs/${storagePath.substring(lastSlash + 1)}';
  }
}
