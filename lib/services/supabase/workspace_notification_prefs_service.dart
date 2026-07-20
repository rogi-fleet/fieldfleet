import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/app_logger.dart';

/// Per-workspace notification preferences (per user).
///
/// Backed by the `workspace_notification_preferences` table introduced in
/// migration 20260503160100. Resolution of the effective preference for a
/// given key is owned server-side by `effective_notification_pref()` so the
/// client only needs to read/write.
class WorkspaceNotificationPrefsService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Stream of `muted_until` for the user's prefs in [workspaceId]. Emits
  /// `null` when no row exists or no mute is set; emits a future timestamp
  /// when an active mute is in effect.
  Stream<DateTime?> watchMutedUntil({
    required String userId,
    required String workspaceId,
  }) {
    return _supabase
        .from('workspace_notification_preferences')
        .stream(primaryKey: ['user_id', 'workspace_id'])
        .eq('user_id', userId)
        .map((rows) {
          final match = rows.firstWhere(
            (r) => r['workspace_id'] == workspaceId,
            orElse: () => <String, dynamic>{},
          );
          final raw = match['muted_until'] as String?;
          if (raw == null) return null;
          final dt = DateTime.tryParse(raw);
          if (dt == null) return null;
          if (dt.isBefore(DateTime.now())) return null;
          return dt;
        });
  }

  /// Mute notifications for [workspaceId] until [until]. Pass null to clear.
  Future<void> setMutedUntil({
    required String userId,
    required String workspaceId,
    required DateTime? until,
  }) async {
    try {
      await _supabase.from('workspace_notification_preferences').upsert({
        'user_id': userId,
        'workspace_id': workspaceId,
        'muted_until': until?.toUtc().toIso8601String(),
      }, onConflict: 'user_id,workspace_id');
    } catch (e) {
      AppLogger.error('Error setting workspace mute', error: e);
      rethrow;
    }
  }
}
