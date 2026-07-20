import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';
import '../../models/file_comment.dart';
import '../../utils/app_logger.dart';
import 'notification_service.dart';

/// Supabase CRUD + notification fan-out for comments attached to a single
/// `file_attachments` row. Mirrors [SupabaseTaskCommentService] but trimmed:
/// we only do in-app notifications for @mentions — email delivery can be
/// added later by pointing at a new Edge Function.
class SupabaseFileCommentService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Stream<List<FileComment>> streamComments(String fileAttachmentId) {
    return _supabase
        .from('file_comments')
        .stream(primaryKey: ['id'])
        .eq('file_attachment_id', fileAttachmentId)
        .order('created_at', ascending: true)
        .map((rows) => rows.map(FileComment.fromSupabase).toList());
  }

  Future<FileComment> addComment({
    required String workspaceId,
    required String fileAttachmentId,
    required String authorId,
    required String authorDisplayName,
    required String body,
    String? parentCommentId,
    List<String> mentionedUserIds = const [],
    List<String> attachmentIds = const [],
    String? fileTitle,
  }) async {
    final now = DateTime.now();
    final data = <String, dynamic>{
      'workspace_id': workspaceId,
      'file_attachment_id': fileAttachmentId,
      'author_id': authorId,
      'body': body,
      'mentioned_user_ids': mentionedUserIds,
      'attachment_ids': attachmentIds,
      'created_at': now.toIso8601String(),
      if (parentCommentId != null) 'parent_comment_id': parentCommentId,
    };

    final response = await _supabase
        .from('file_comments')
        .insert(data)
        .select()
        .single();
    final comment = FileComment.fromSupabase(response);

    // file_events 'commented' — fire-and-forget audit.
    _supabase.rpc('record_file_event', params: {
      'p_file_attachment_id': fileAttachmentId,
      'p_action': 'commented',
      'p_payload': {
        'comment_id': comment.id,
        'excerpt': body.length > 200 ? '${body.substring(0, 200)}…' : body,
      },
    }).catchError((e) {
      AppLogger.warning(
        'record_file_event(commented) failed',
        metadata: {'error': e.toString()},
      );
    });

    if (mentionedUserIds.isNotEmpty) {
      _fanOutMentionNotifications(
        senderId: authorId,
        senderName: authorDisplayName,
        mentionedUserIds: mentionedUserIds,
        workspaceId: workspaceId,
        fileAttachmentId: fileAttachmentId,
        commentId: comment.id,
        body: body,
        fileTitle: fileTitle,
      );
      _sendMentionEmails(
        senderName: authorDisplayName,
        mentionedUserIds: mentionedUserIds,
        workspaceId: workspaceId,
        fileAttachmentId: fileAttachmentId,
        commentId: comment.id,
        body: body,
        fileTitle: fileTitle,
      );
    }

    return comment;
  }

  Future<void> editComment({
    required String commentId,
    required String body,
    List<String> mentionedUserIds = const [],
    List<String> attachmentIds = const [],
  }) async {
    await _supabase.from('file_comments').update({
      'body': body,
      'mentioned_user_ids': mentionedUserIds,
      'attachment_ids': attachmentIds,
      'edited_at': DateTime.now().toIso8601String(),
    }).eq('id', commentId);
  }

  Future<void> deleteComment(String commentId) async {
    await _supabase.from('file_comments').delete().eq('id', commentId);
  }

  /// Fire-and-forget email dispatch via the send-file-mention-notification
  /// Edge Function. In-app notifications handle the primary path; email is
  /// a second channel for users who are offline. Silently no-ops if the
  /// function isn't deployed or Resend isn't configured — the in-app
  /// notification still fires regardless.
  Future<void> _sendMentionEmails({
    required String senderName,
    required List<String> mentionedUserIds,
    required String workspaceId,
    required String fileAttachmentId,
    required String commentId,
    required String body,
    String? fileTitle,
  }) async {
    try {
      final accessToken = _supabase.auth.currentSession?.accessToken;
      if (accessToken == null) return;

      final displayFile = fileTitle?.trim().isNotEmpty == true
          ? fileTitle!.trim()
          : 'a file';
      final url =
          '${SupabaseConfig.url}/functions/v1/send-file-mention-notification';

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
          'apikey': SupabaseConfig.anonKey,
        },
        body: jsonEncode({
          'mentionedUserIds': mentionedUserIds,
          'senderName': senderName,
          'fileTitle': displayFile,
          'commentContent': body,
          'fileAttachmentId': fileAttachmentId,
          'commentId': commentId,
          'workspaceId': workspaceId,
        }),
      );

      if (response.statusCode != 200) {
        AppLogger.warning(
          'File mention email dispatch failed',
          metadata: {
            'statusCode': response.statusCode,
            'response': response.body.substring(
              0,
              response.body.length > 200 ? 200 : response.body.length,
            ),
          },
        );
      }
    } catch (e) {
      AppLogger.warning(
        'File mention email dispatch errored',
        metadata: {'error': e.toString()},
      );
    }
  }

  void _fanOutMentionNotifications({
    required String senderId,
    required String senderName,
    required List<String> mentionedUserIds,
    required String workspaceId,
    required String fileAttachmentId,
    required String commentId,
    required String body,
    String? fileTitle,
  }) {
    final excerpt =
        body.length > 200 ? '${body.substring(0, 200)}…' : body;
    final displayFile = fileTitle?.trim().isNotEmpty == true
        ? fileTitle!.trim()
        : 'a file';
    final deeplink = '/files?fileId=$fileAttachmentId&commentId=$commentId';
    final notificationService = SupabaseNotificationService();

    for (final userId in mentionedUserIds) {
      if (userId == senderId) continue;
      notificationService.createNotification(
        userId: userId,
        workspaceId: workspaceId,
        type: 'mention',
        title: '$senderName mentioned you in "$displayFile"',
        body: excerpt,
        metadata: {
          'target_type': 'file',
          'file_attachment_id': fileAttachmentId,
          'comment_id': commentId,
          'sender_id': senderId,
          'deeplink_path': deeplink,
        },
      );
    }
  }
}
