import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_logger.dart';

class SettingsAuditEvent {
  final String id;
  final String workspaceId;
  final String actorUserId;
  final String actorDisplayName;
  final String targetType;
  final String targetId;
  final String eventType;
  final Map<String, dynamic>? beforeData;
  final Map<String, dynamic>? afterData;
  final DateTime createdAt;

  SettingsAuditEvent({
    required this.id,
    required this.workspaceId,
    required this.actorUserId,
    required this.actorDisplayName,
    required this.targetType,
    required this.targetId,
    required this.eventType,
    required this.beforeData,
    required this.afterData,
    required this.createdAt,
  });
}

class SettingsAuditPage {
  final List<SettingsAuditEvent> events;
  final String? nextCursor;

  SettingsAuditPage({required this.events, required this.nextCursor});
}

/// Writes settings audit events to the `settings_audit_events` table.
/// This service is intentionally best-effort and should not block feature flows.
class SupabaseSettingsAuditService {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const Set<String> _sensitiveKeys = {
    'password',
    'token',
    'secret',
    'api_key',
    'apikey',
    'authorization',
    'auth',
    'cookie',
    'session',
    'phone',
    'email',
  };

  Future<void> logEvent({
    required String workspaceId,
    required String targetType,
    required String targetId,
    required String eventType,
    Map<String, dynamic>? beforeData,
    Map<String, dynamic>? afterData,
  }) async {
    try {
      final actorUserId = _supabase.auth.currentUser?.id;
      if (actorUserId == null) {
        return;
      }

      await _supabase.from('settings_audit_events').insert({
        'workspace_id': workspaceId,
        'actor_user_id': actorUserId,
        'target_type': targetType,
        'target_id': targetId,
        'event_type': eventType,
        'before_data': _redactMap(beforeData),
        'after_data': _redactMap(afterData),
      });
    } catch (e) {
      AppLogger.warning(
        'Failed to write settings audit event',
        metadata: {
          'workspaceId': workspaceId,
          'targetType': targetType,
          'targetId': targetId,
          'eventType': eventType,
          'error': e.toString(),
        },
      );
    }
  }

  Future<SettingsAuditPage> getEvents({
    required String workspaceId,
    String? actorUserId,
    String? eventType,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? beforeCreatedAt,
    int limit = 50,
  }) async {
    try {
      var query = _supabase
          .from('settings_audit_events')
          .select()
          .eq('workspace_id', workspaceId);

      if (actorUserId != null && actorUserId.isNotEmpty) {
        query = query.eq('actor_user_id', actorUserId);
      }
      if (eventType != null && eventType.isNotEmpty) {
        query = query.eq('event_type', eventType);
      }
      if (dateFrom != null) {
        query = query.gte('created_at', dateFrom.toIso8601String());
      }
      if (dateTo != null) {
        query = query.lte('created_at', dateTo.toIso8601String());
      }
      if (beforeCreatedAt != null && beforeCreatedAt.isNotEmpty) {
        query = query.lt('created_at', beforeCreatedAt);
      }

      final response = await query
          .order('created_at', ascending: false)
          .limit(limit + 1);

      final rows = (response as List).cast<Map<String, dynamic>>();
      final hasMore = rows.length > limit;
      final pageRows = hasMore ? rows.take(limit).toList() : rows;

      final actorIds = pageRows
          .map((row) => row['actor_user_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();

      final actorMap = <String, String>{};
      if (actorIds.isNotEmpty) {
        final usersResponse = await _supabase
            .from('users')
            .select('id, display_name, email')
            .inFilter('id', actorIds);

        for (final user
            in (usersResponse as List).cast<Map<String, dynamic>>()) {
          final id = user['id'] as String?;
          if (id == null) continue;
          final displayName = (user['display_name'] as String?)?.trim();
          final email = (user['email'] as String?)?.trim();
          actorMap[id] = (displayName != null && displayName.isNotEmpty)
              ? displayName
              : (email ?? id);
        }
      }

      final events = pageRows.map((row) {
        final actorId = row['actor_user_id'] as String? ?? '';
        return SettingsAuditEvent(
          id: row['id'] as String,
          workspaceId: row['workspace_id'] as String? ?? workspaceId,
          actorUserId: actorId,
          actorDisplayName: actorMap[actorId] ?? actorId,
          targetType: row['target_type'] as String? ?? 'unknown',
          targetId: row['target_id'] as String? ?? '',
          eventType: row['event_type'] as String? ?? 'unknown',
          beforeData: row['before_data'] != null
              ? Map<String, dynamic>.from(row['before_data'] as Map)
              : null,
          afterData: row['after_data'] != null
              ? Map<String, dynamic>.from(row['after_data'] as Map)
              : null,
          createdAt: DateTime.parse(row['created_at'] as String),
        );
      }).toList();

      final nextCursor = hasMore
          ? pageRows.last['created_at'] as String?
          : null;

      return SettingsAuditPage(events: events, nextCursor: nextCursor);
    } catch (e) {
      AppLogger.error(
        'Failed to load settings audit events',
        error: e,
        metadata: {'workspaceId': workspaceId},
      );
      rethrow;
    }
  }

  Map<String, dynamic>? _redactMap(Map<String, dynamic>? input) {
    if (input == null) {
      return null;
    }
    final output = <String, dynamic>{};
    input.forEach((key, value) {
      output[key] = _redactValue(key, value);
    });
    return output;
  }

  dynamic _redactValue(String key, dynamic value) {
    final normalizedKey = key.toLowerCase();
    if (_sensitiveKeys.any(normalizedKey.contains)) {
      return '[REDACTED]';
    }

    if (value is Map) {
      return value.map(
        (k, v) => MapEntry(k.toString(), _redactValue(k.toString(), v)),
      );
    }
    if (value is List) {
      return value
          .map(
            (item) => item is Map
                ? item.map(
                    (k, v) =>
                        MapEntry(k.toString(), _redactValue(k.toString(), v)),
                  )
                : item,
          )
          .toList();
    }
    return value;
  }
}
