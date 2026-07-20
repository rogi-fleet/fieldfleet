import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/floorplan/scene.dart';
import '../../utils/app_logger.dart';
import '../floorplan/scene_io.dart';

/// One row per construction_plan in `floorplan_scenes`. Mirrors the shape of
/// [SupabaseFileMarkupService] — single-row-per-parent with upsert semantics.
class SupabaseFloorplanSceneService {
  SupabaseFloorplanSceneService({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const String _table = 'floorplan_scenes';
  static const String _bucket = 'construction-plans';

  /// Returns the persisted scene for [planId], or `null` if none exists yet.
  Future<({Scene scene, int version})?> getScene(String planId) async {
    final row = await _supabase
        .from(_table)
        .select('scene_json, scene_version')
        .eq('plan_id', planId)
        .maybeSingle();
    if (row == null) return null;
    final raw = row['scene_json'];
    final map = raw is Map ? raw.cast<String, dynamic>() : null;
    if (map == null) return null;
    return (
      scene: SceneIO.fromRow(map),
      version: (row['scene_version'] as num?)?.toInt() ?? 1,
    );
  }

  /// Live updates for the scene attached to [planId].
  Stream<({Scene scene, int version})?> streamScene(String planId) {
    return _supabase
        .from(_table)
        .stream(primaryKey: ['id'])
        .eq('plan_id', planId)
        .map((rows) {
          if (rows.isEmpty) return null;
          final raw = rows.first['scene_json'];
          final map = raw is Map ? raw.cast<String, dynamic>() : null;
          if (map == null) return null;
          return (
            scene: SceneIO.fromRow(map),
            version: (rows.first['scene_version'] as num?)?.toInt() ?? 1,
          );
        });
  }

  /// Upsert the head scene for [planId]. Returns the new scene_version.
  ///
  /// [expectedVersion] is the version the client started editing from. If
  /// the server-side version has advanced beyond it, we still write (last-
  /// write-wins) but the returned [conflictDetected] flag is true so the UI
  /// can surface a warning. CRDT/OT is out of scope for v1.
  ///
  /// [scanMetadata] is the raw FloorPlanScanResult JSON when this upsert
  /// is creating (or replacing) a scene that originated from a room
  /// scan. We keep it for future re-processing; runtime never reads it.
  /// Pass null to leave the existing scan_metadata column untouched
  /// (most upserts — every save, every AI edit — fall in this bucket).
  Future<({int version, bool conflictDetected})> upsertScene({
    required String planId,
    required String workspaceId,
    required String projectId,
    required Scene scene,
    String? thumbnailUrl,
    String? lastEditedBy,
    int? expectedVersion,
    Map<String, dynamic>? scanMetadata,
  }) async {
    final existing = await _supabase
        .from(_table)
        .select('scene_version')
        .eq('plan_id', planId)
        .maybeSingle();
    final priorVersion = (existing?['scene_version'] as num?)?.toInt();
    final conflictDetected = priorVersion != null &&
        expectedVersion != null &&
        priorVersion > expectedVersion;
    final nextVersion = (priorVersion ?? 0) + 1;

    final response = await _supabase
        .from(_table)
        .upsert({
          'plan_id': planId,
          'workspace_id': workspaceId,
          'project_id': projectId,
          'scene_json': SceneIO.toRow(scene),
          if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
          if (lastEditedBy != null) 'last_edited_by': lastEditedBy,
          if (scanMetadata != null) 'scan_metadata': scanMetadata,
          'scene_version': nextVersion,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'plan_id')
        .select('scene_version')
        .single();

    return (
      version: (response['scene_version'] as num).toInt(),
      conflictDetected: conflictDetected,
    );
  }

  Future<void> deleteScene(String planId) async {
    await _supabase.from(_table).delete().eq('plan_id', planId);
  }

  /// Upload a thumbnail PNG and return its public URL.
  Future<String> uploadThumbnail({
    required String workspaceId,
    required String projectId,
    required String planId,
    required Uint8List bytes,
  }) async {
    final path = '$workspaceId/$projectId/thumbnails/$planId.png';
    try {
      await _supabase.storage.from(_bucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/png',
              upsert: true,
            ),
          );
    } catch (e) {
      AppLogger.warning(
        'floorplan thumbnail upload failed',
        metadata: {'planId': planId, 'error': e.toString()},
      );
      rethrow;
    }
    return _supabase.storage.from(_bucket).getPublicUrl(path);
  }
}
