import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';
import '../../models/app_notification.dart';
import '../../utils/app_logger.dart';

/// Supabase implementation of NotificationService
class SupabaseNotificationService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Get notifications for a user in a workspace (realtime stream)
  Stream<List<AppNotification>> getNotifications({
    required String userId,
    required String workspaceId,
  }) {
    return _supabase
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .map((data) {
          return data
              .where((row) => row['workspace_id'] == workspaceId)
              .take(100)
              .map((row) => AppNotification.fromRow(row))
              .toList();
        });
  }

  /// Get unread notification count (realtime stream)
  Stream<int> getUnreadCount({
    required String userId,
    required String workspaceId,
  }) {
    return getNotifications(
      userId: userId,
      workspaceId: workspaceId,
    ).map((notifications) => notifications.where((n) => !n.isRead).length);
  }

  /// Create a notification.
  ///
  /// Goes through the `create_notification` RPC (SECURITY DEFINER) which
  /// enforces workspace-membership authorization and optional dedup. The
  /// previous direct INSERT relied on an over-broad RLS policy that has
  /// since been removed.
  ///
  /// [dedupeKey] / [dedupeWindowSeconds]: when set, suppresses duplicate
  /// notifications for the same (user, workspace, type, key) within the
  /// window and returns the existing id instead. Pass null to disable.
  Future<String?> createNotification({
    required String userId,
    required String workspaceId,
    required String type,
    required String title,
    String? body,
    Map<String, dynamic>? metadata,
    String? dedupeKey,
    int dedupeWindowSeconds = 300,
    bool dispatchPush = true,
  }) async {
    try {
      final result = await _supabase.rpc(
        'create_notification',
        params: {
          'p_user_id': userId,
          'p_workspace_id': workspaceId,
          'p_type': type,
          'p_title': title,
          'p_body': body,
          'p_metadata': metadata ?? {},
          'p_dedupe_key': dedupeKey,
          'p_dedupe_window_seconds': dedupeWindowSeconds,
        },
      );

      final notificationId = result is String ? result : result?.toString();
      // Always dispatch — push-dispatch is the single source of truth on
      // whether to actually send (per-type preferences, devices, etc.).
      if (dispatchPush && notificationId != null && notificationId.isNotEmpty) {
        _dispatchPush(notificationId);
      }
      return notificationId;
    } catch (e) {
      AppLogger.error('Error creating notification', error: e);
      return null;
    }
  }

  Future<void> _dispatchPush(String notificationId) async {
    try {
      final accessToken = _supabase.auth.currentSession?.accessToken;
      if (accessToken == null || accessToken.isEmpty) {
        AppLogger.debug(
          'Skipping push dispatch due to missing access token',
          metadata: {'notificationId': notificationId},
        );
        return;
      }

      final response = await http.post(
        Uri.parse('${SupabaseConfig.url}/functions/v1/push-dispatch'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
          'apikey': SupabaseConfig.anonKey,
        },
        body: jsonEncode({'notification_id': notificationId}),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        AppLogger.warning(
          'Push dispatch failed',
          metadata: {
            'notificationId': notificationId,
            'status': response.statusCode,
            'response': response.body,
          },
        );
      }
    } catch (e) {
      AppLogger.warning(
        'Push dispatch invocation error',
        metadata: {'notificationId': notificationId, 'error': e.toString()},
      );
    }
  }

  /// Mark a single notification as read
  Future<void> markAsRead(String notificationId) async {
    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notificationId);
    } catch (e) {
      AppLogger.error('Error marking notification as read', error: e);
    }
  }

  /// Mark all notifications as read for a user in a workspace
  Future<void> markAllAsRead({
    required String userId,
    required String workspaceId,
  }) async {
    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('workspace_id', workspaceId)
          .eq('is_read', false);
    } catch (e) {
      AppLogger.error('Error marking all notifications as read', error: e);
    }
  }
}
