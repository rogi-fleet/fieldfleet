import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/asset_event.dart';
import '../../utils/app_logger.dart';

/// Read + record helper for the asset_events audit log.
///
/// Writes go through the `record_asset_event` RPC so that the actor and
/// workspace can't be forged. Failures from the RPC are logged but
/// never raised — losing an audit row should never block a real user
/// action like updating an asset.
class SupabaseAssetEventService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Live timeline for one asset, newest first.
  Stream<List<AssetEvent>> streamEvents(String assetId) {
    return _supabase
        .from('asset_events')
        .stream(primaryKey: ['id'])
        .eq('asset_id', assetId)
        .order('created_at', ascending: false)
        .map((data) => data.map(_toEvent).toList());
  }

  /// Fire-and-forget audit write. Never throws — we'd rather lose a
  /// timeline row than break the user's update flow.
  Future<void> record(
    String assetId,
    String action, {
    Map<String, dynamic>? payload,
  }) async {
    try {
      await _supabase.rpc('record_asset_event', params: {
        'p_asset_id': assetId,
        'p_action': action,
        'p_payload': payload ?? const <String, dynamic>{},
      });
    } catch (e) {
      AppLogger.warning(
        'record_asset_event failed',
        metadata: {'assetId': assetId, 'action': action, 'error': e.toString()},
      );
    }
  }

  AssetEvent _toEvent(Map<String, dynamic> row) {
    return AssetEvent(
      id: row['id'] as String,
      workspaceId: row['workspace_id'] as String,
      assetId: row['asset_id'] as String,
      actorId: row['actor_id'] as String?,
      action: row['action'] as String? ?? 'updated',
      payload: (row['payload'] as Map<String, dynamic>?) ?? const {},
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}
