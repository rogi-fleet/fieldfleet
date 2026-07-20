import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a comment on a task
class TaskComment {
  final String id;
  final String taskId;
  final String senderId;
  final String senderName;
  final String content;
  final DateTime timestamp;
  final String workspaceId;
  final List<Map<String, dynamic>> attachments;
  final List<String> mentionedUserIds;

  TaskComment({
    required this.id,
    required this.taskId,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.timestamp,
    required this.workspaceId,
    this.attachments = const [],
    this.mentionedUserIds = const [],
  });

  factory TaskComment.fromJson(Map<String, dynamic> json, String id) {
    return TaskComment(
      id: id,
      taskId: json['taskId'] as String,
      senderId: json['senderId'] as String,
      senderName: json['senderName'] as String,
      content: json['content'] as String,
      timestamp: (json['timestamp'] as Timestamp).toDate(),
      workspaceId: json['workspaceId'] as String,
      attachments: (json['attachments'] as List<dynamic>?)
          ?.map((a) => Map<String, dynamic>.from(a as Map))
          .toList() ?? [],
      mentionedUserIds: (json['mentionedUserIds'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'taskId': taskId,
      'senderId': senderId,
      'senderName': senderName,
      'content': content,
      'timestamp': Timestamp.fromDate(timestamp),
      'workspaceId': workspaceId,
      'attachments': attachments,
      'mentionedUserIds': mentionedUserIds,
    };
  }

  TaskComment copyWith({
    String? id,
    String? taskId,
    String? senderId,
    String? senderName,
    String? content,
    DateTime? timestamp,
    String? workspaceId,
    List<Map<String, dynamic>>? attachments,
    List<String>? mentionedUserIds,
  }) {
    return TaskComment(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      workspaceId: workspaceId ?? this.workspaceId,
      attachments: attachments ?? this.attachments,
      mentionedUserIds: mentionedUserIds ?? this.mentionedUserIds,
    );
  }

  /// Check if this comment has any attachments
  bool get hasAttachments => attachments.isNotEmpty;
}
