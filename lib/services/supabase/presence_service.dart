import 'package:supabase_flutter/supabase_flutter.dart';

/// Tracks online/offline status for workspace members via Supabase Realtime Presence
class PresenceService {
  final SupabaseClient _supabase = Supabase.instance.client;
  RealtimeChannel? _channel;
  final Map<String, bool> _onlineStatus = {};
  final List<void Function(Map<String, bool>)> _listeners = [];

  /// Start tracking presence for a workspace channel
  Future<void> startPresence({
    required String workspaceId,
    required String userId,
    required String userName,
  }) async {
    _channel?.unsubscribe();

    _channel = _supabase.channel('presence:$workspaceId');

    _channel!
        .onPresenceSync((payload) {
          _updateOnlineStatus();
        })
        .onPresenceJoin((payload) {
          _updateOnlineStatus();
        })
        .onPresenceLeave((payload) {
          _updateOnlineStatus();
        })
        .subscribe((status, error) async {
          if (status == RealtimeSubscribeStatus.subscribed) {
            await _channel!.track({
              'user_id': userId,
              'user_name': userName,
              'online_at': DateTime.now().toIso8601String(),
            });
          }
        });
  }

  void _updateOnlineStatus() {
    if (_channel == null) return;
    final state = _channel!.presenceState();
    _onlineStatus.clear();
    for (final entry in state) {
      for (final presence in entry.presences) {
        final uid = presence.payload['user_id'] as String?;
        if (uid != null) {
          _onlineStatus[uid] = true;
        }
      }
    }
    for (final listener in _listeners) {
      listener(Map<String, bool>.from(_onlineStatus));
    }
  }

  bool isOnline(String userId) => _onlineStatus[userId] ?? false;

  Map<String, bool> get onlineStatus => Map<String, bool>.unmodifiable(_onlineStatus);

  void addListener(void Function(Map<String, bool>) listener) {
    _listeners.add(listener);
  }

  void removeListener(void Function(Map<String, bool>) listener) {
    _listeners.remove(listener);
  }

  Future<void> dispose() async {
    await _channel?.unsubscribe();
    _channel = null;
    _onlineStatus.clear();
    _listeners.clear();
  }
}
