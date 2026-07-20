import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/supabase_config.dart';
import '../../models/task_comment.dart';
import '../../utils/app_logger.dart';
import 'notification_service.dart';

/// Supabase implementation of TaskCommentService
class SupabaseTaskCommentService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Add a comment to a task
  Future<TaskComment> addComment({
    required String taskId,
    required String content,
    required String senderId,
    required String senderName,
    required String workspaceId,
    List<Map<String, dynamic>> attachments = const [],
    List<String> mentionedUserIds = const [],
  }) async {
    try {
      final now = DateTime.now();

      final commentData = {
        'task_id': taskId,
        'sender_id': senderId,
        'sender_name': senderName,
        'content': content,
        'workspace_id': workspaceId,
        'attachments': attachments,
        'mentioned_user_ids': mentionedUserIds,
        'created_at': now.toIso8601String(),
      };

      final response = await _supabase
          .from('task_comments')
          .insert(commentData)
          .select()
          .single();

      final comment = _toComment(response);

      // Fire-and-forget: send mention notification emails
      if (mentionedUserIds.isNotEmpty) {
        _sendMentionNotifications(
          mentionedUserIds: mentionedUserIds,
          senderName: senderName,
          taskTitle: '', // Will be looked up by caller or edge function
          commentContent: content,
          projectId: '', // Caller can pass if needed
          taskId: taskId,
          workspaceId: workspaceId,
        );

        // Create in-app notifications for mentioned users
        _createMentionNotifications(
          mentionedUserIds: mentionedUserIds,
          senderId: senderId,
          senderName: senderName,
          taskId: taskId,
          workspaceId: workspaceId,
          commentContent: content,
        );
      }

      return comment;
    } catch (e) {
      throw Exception('Error adding comment: $e');
    }
  }

  /// Create in-app notifications for mentioned users (fire-and-forget)
  Future<void> _createMentionNotifications({
    required List<String> mentionedUserIds,
    required String senderId,
    required String senderName,
    required String taskId,
    required String workspaceId,
    required String commentContent,
  }) async {
    try {
      final notificationService = SupabaseNotificationService();

      // Look up task info for the notification
      String taskTitle = 'a task';
      String projectId = '';
      try {
        final task = await _supabase
            .from('tasks')
            .select('title, project_id')
            .eq('id', taskId)
            .maybeSingle();
        if (task != null) {
          taskTitle = task['title'] as String? ?? 'a task';
          projectId = task['project_id'] as String? ?? '';
        }
      } catch (_) {}

      // Truncate comment for notification body
      final truncatedContent = commentContent.length > 200
          ? '${commentContent.substring(0, 200)}...'
          : commentContent;

      for (final userId in mentionedUserIds) {
        if (userId == senderId) continue; // Don't notify the sender
        final deepLink = projectId.isNotEmpty
            ? '/projects/$projectId?tab=tasks&taskId=$taskId'
            : '/notifications';
        notificationService.createNotification(
          userId: userId,
          workspaceId: workspaceId,
          type: 'mention',
          title: '$senderName mentioned you in "$taskTitle"',
          body: truncatedContent,
          metadata: {
            'target_type': 'task',
            'task_id': taskId,
            'project_id': projectId,
            'sender_id': senderId,
            'tab': 'tasks',
            'deeplink_path': deepLink,
          },
        );
      }
    } catch (e) {
      AppLogger.error('Error creating mention notifications', error: e);
    }
  }

  /// Send mention notification emails via edge function (fire-and-forget)
  Future<void> _sendMentionNotifications({
    required List<String> mentionedUserIds,
    required String senderName,
    required String taskTitle,
    required String commentContent,
    required String projectId,
    required String taskId,
    required String workspaceId,
  }) async {
    try {
      final accessToken = _supabase.auth.currentSession?.accessToken;
      if (accessToken == null) return;
      var resolvedProjectId = projectId;

      // Look up task title if not provided
      var title = taskTitle;
      if (title.isEmpty) {
        try {
          final task = await _supabase
              .from('tasks')
              .select('title, project_id')
              .eq('id', taskId)
              .maybeSingle();
          if (task != null) {
            title = task['title'] as String? ?? 'Untitled Task';
            if (resolvedProjectId.isEmpty) {
              resolvedProjectId = task['project_id'] as String? ?? '';
            }
          }
        } catch (_) {
          title = 'Untitled Task';
        }
      }

      final edgeFunctionUrl =
          '${SupabaseConfig.url}/functions/v1/send-mention-notification';

      final response = await http.post(
        Uri.parse(edgeFunctionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
          'apikey': SupabaseConfig.anonKey,
        },
        body: jsonEncode({
          'mentionedUserIds': mentionedUserIds,
          'senderName': senderName,
          'taskTitle': title,
          'commentContent': commentContent,
          'projectId': resolvedProjectId,
          'taskId': taskId,
          'workspaceId': workspaceId,
        }),
      );

      if (response.statusCode == 200) {
        AppLogger.info(
          'Mention notifications sent',
          metadata: {'mentionedCount': mentionedUserIds.length},
        );
      } else {
        AppLogger.warning(
          'Failed to send mention notifications',
          metadata: {
            'statusCode': response.statusCode,
            'response': response.body,
          },
        );
      }
    } catch (e) {
      AppLogger.error('Error sending mention notifications', error: e);
      // Don't rethrow - this is fire-and-forget
    }
  }

  /// Get all comments for a task, ordered by timestamp
  Stream<List<TaskComment>> getComments(String taskId) {
    return _supabase
        .from('task_comments')
        .stream(primaryKey: ['id'])
        .eq('task_id', taskId)
        .order('created_at', ascending: true)
        .map((data) {
          return data.map((row) => _toComment(row)).toList();
        });
  }

  /// Get comments for a task (one-time)
  Future<List<TaskComment>> getCommentsOnce(String taskId) async {
    try {
      final response = await _supabase
          .from('task_comments')
          .select()
          .eq('task_id', taskId)
          .order('created_at', ascending: true);

      return response.map((row) => _toComment(row)).toList();
    } catch (e) {
      throw Exception('Error fetching comments: $e');
    }
  }

  /// Update a comment
  Future<void> updateComment(String commentId, String newContent) async {
    try {
      await _supabase
          .from('task_comments')
          .update({'content': newContent})
          .eq('id', commentId);
    } catch (e) {
      throw Exception('Error updating comment: $e');
    }
  }

  /// Delete a comment
  Future<void> deleteComment(String taskId, String commentId) async {
    try {
      await _supabase.from('task_comments').delete().eq('id', commentId);
    } catch (e) {
      throw Exception('Error deleting comment: $e');
    }
  }

  /// Get comment count for a task
  Future<int> getCommentCount(String taskId) async {
    try {
      final result = await _supabase
          .from('task_comments')
          .select()
          .eq('task_id', taskId)
          .count();
      return result.count;
    } catch (e) {
      return 0;
    }
  }

  /// Get comment counts for many tasks with a single query.
  Future<Map<String, int>> getCommentCounts(List<String> taskIds) async {
    if (taskIds.isEmpty) return const <String, int>{};

    final uniqueTaskIds = taskIds.toSet().toList(growable: false);
    final counts = {for (final taskId in uniqueTaskIds) taskId: 0};

    // Chunk large IN queries. Kept small: each id is a ~36-char UUID, and a
    // batch of 200 produces an ~8KB request URL that can exceed the gateway's
    // header-buffer limit (observed as intermittent 502s).
    const batchSize = 50;
    for (var i = 0; i < uniqueTaskIds.length; i += batchSize) {
      final end = (i + batchSize > uniqueTaskIds.length)
          ? uniqueTaskIds.length
          : i + batchSize;
      final batch = uniqueTaskIds.sublist(i, end);

      try {
        final rows = await _supabase
            .from('task_comments')
            .select('task_id')
            .inFilter('task_id', batch);

        for (final row in rows) {
          final taskId = row['task_id'] as String?;
          if (taskId == null) continue;
          counts[taskId] = (counts[taskId] ?? 0) + 1;
        }
      } catch (_) {
        // Leave defaults if a batch fails.
      }
    }

    return counts;
  }

  /// Get recent comments for a workspace (for activity feed)
  Stream<List<TaskComment>> getRecentWorkspaceComments(
    String workspaceId, {
    int limit = 50,
  }) {
    return _supabase
        .from('task_comments')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .order('created_at', ascending: false)
        .limit(limit)
        .map((data) {
          return data.map((row) => _toComment(row)).toList();
        });
  }

  /// Convert database row to TaskComment
  TaskComment _toComment(Map<String, dynamic> row) {
    return TaskComment(
      id: row['id'],
      taskId: row['task_id'],
      senderId: row['sender_id'],
      senderName: row['sender_name'],
      content: row['content'],
      timestamp: DateTime.parse(row['created_at']),
      workspaceId: row['workspace_id'],
      attachments:
          (row['attachments'] as List<dynamic>?)
              ?.map((a) => Map<String, dynamic>.from(a))
              .toList() ??
          [],
      mentionedUserIds: List<String>.from(row['mentioned_user_ids'] ?? []),
    );
  }
}
