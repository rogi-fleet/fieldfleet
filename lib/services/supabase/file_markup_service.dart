import 'dart:ui' show Rect;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/file_markup.dart';
import '../../utils/app_logger.dart';

/// Supabase CRUD for [MarkupLayer]s. One-per-file semantics enforced by the
/// UNIQUE index on `file_markup_layers.file_attachment_id` — upsert writes
/// the head, delete is the "Revert to Original" path.
class SupabaseFileMarkupService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<MarkupLayer?> getLayer(String fileAttachmentId) async {
    final row = await _supabase
        .from('file_markup_layers')
        .select()
        .eq('file_attachment_id', fileAttachmentId)
        .maybeSingle();
    if (row == null) return null;
    return MarkupLayer.fromSupabase(row);
  }

  Stream<MarkupLayer?> streamLayer(String fileAttachmentId) {
    return _supabase
        .from('file_markup_layers')
        .stream(primaryKey: ['id'])
        .eq('file_attachment_id', fileAttachmentId)
        .map((rows) => rows.isEmpty ? null : MarkupLayer.fromSupabase(rows.first));
  }

  /// Upsert the shape list for a file's layer. Returns the resulting row.
  Future<MarkupLayer> upsertLayer({
    required String workspaceId,
    required String fileAttachmentId,
    required List<MarkupShape> shapes,
    int rotation = 0,
    bool flipHorizontal = false,
    bool flipVertical = false,
    Rect cropRect = const Rect.fromLTWH(0, 0, 1, 1),
    String? authorId,
  }) async {
    final serialized = shapes.map((s) => s.toJson()).toList();
    final hasCrop = cropRect.left > 0 ||
        cropRect.top > 0 ||
        cropRect.width < 1 ||
        cropRect.height < 1;
    final response = await _supabase
        .from('file_markup_layers')
        .upsert(
          {
            'workspace_id': workspaceId,
            'file_attachment_id': fileAttachmentId,
            'shapes': serialized,
            'rotation': rotation,
            'flip_horizontal': flipHorizontal,
            'flip_vertical': flipVertical,
            'crop_x': cropRect.left,
            'crop_y': cropRect.top,
            'crop_width': cropRect.width,
            'crop_height': cropRect.height,
            if (authorId != null) 'author_id': authorId,
            'updated_at': DateTime.now().toIso8601String(),
          },
          onConflict: 'file_attachment_id',
        )
        .select()
        .single();

    _recordEvent(fileAttachmentId, 'marked_up', payload: {
      'shape_count': shapes.length,
      if (rotation != 0) 'rotation': rotation,
      if (flipHorizontal) 'flip_horizontal': true,
      if (flipVertical) 'flip_vertical': true,
      if (hasCrop) 'crop_applied': true,
    });

    return MarkupLayer.fromSupabase(response);
  }

  /// Revert to Original — deletes the entire layer. Underlying file bytes
  /// are untouched; markup simply disappears.
  Future<void> deleteLayer(String fileAttachmentId) async {
    // Fetch shape count before delete for the audit payload.
    int? priorCount;
    try {
      final row = await _supabase
          .from('file_markup_layers')
          .select('shapes')
          .eq('file_attachment_id', fileAttachmentId)
          .maybeSingle();
      if (row != null) {
        final raw = row['shapes'];
        if (raw is List) priorCount = raw.length;
      }
    } catch (_) {}

    await _supabase
        .from('file_markup_layers')
        .delete()
        .eq('file_attachment_id', fileAttachmentId);

    _recordEvent(
      fileAttachmentId,
      'reverted_markup',
      payload: {if (priorCount != null) 'prior_shape_count': priorCount},
    );
  }

  void _recordEvent(String fileId, String action, {Map<String, dynamic>? payload}) {
    _supabase.rpc('record_file_event', params: {
      'p_file_attachment_id': fileId,
      'p_action': action,
      'p_payload': payload ?? const <String, dynamic>{},
    }).catchError((e) {
      AppLogger.warning(
        'record_file_event failed',
        metadata: {'fileId': fileId, 'action': action, 'error': e.toString()},
      );
    });
  }
}
