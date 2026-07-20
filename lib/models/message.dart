import 'package:cloud_firestore/cloud_firestore.dart';
import 'message_attachment.dart';

class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final String senderName;
  final String content;
  final DateTime timestamp;
  final List<String> readBy;
  final String workspaceId;
  final List<MessageAttachment> attachments;
  final DateTime? editedAt;
  final Map<String, List<String>> reactions; // emoji -> list of userIds
  final DateTime? deletedAt;
  final String? replyToId;
  final DateTime? pinnedAt;
  final String? pinnedBy;
  final int threadReplyCount;
  final DateTime? lastReplyAt;

  Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.timestamp,
    required this.readBy,
    required this.workspaceId,
    List<MessageAttachment>? attachments,
    this.editedAt,
    Map<String, List<String>>? reactions,
    this.deletedAt,
    this.replyToId,
    this.pinnedAt,
    this.pinnedBy,
    this.threadReplyCount = 0,
    this.lastReplyAt,
  })  : attachments = attachments ?? [],
        reactions = reactions ?? {};

  factory Message.fromJson(Map<String, dynamic> json, String id) {
    final attachmentsList = json['attachments'] as List?;
    final attachments = attachmentsList != null
        ? attachmentsList
            .map((a) => MessageAttachment.fromJson(a as Map<String, dynamic>))
            .toList()
        : <MessageAttachment>[];

    // Parse reactions from JSONB
    Map<String, List<String>> reactions = {};
    if (json['reactions'] != null && json['reactions'] is Map) {
      final reactionsMap = json['reactions'] as Map;
      for (final entry in reactionsMap.entries) {
        final emoji = entry.key as String;
        final userIds = (entry.value as List?)?.cast<String>() ?? <String>[];
        reactions[emoji] = userIds;
      }
    }

    return Message(
      id: id,
      conversationId: json['conversationId'] as String,
      senderId: json['senderId'] as String,
      senderName: json['senderName'] as String,
      content: json['content'] as String,
      timestamp: _parseDateTime(json['timestamp']),
      readBy: List<String>.from(json['readBy'] as List? ?? []),
      workspaceId: json['workspaceId'] as String,
      attachments: attachments,
      editedAt: json['editedAt'] != null ? _parseDateTime(json['editedAt']) : null,
      reactions: reactions,
      deletedAt: json['deletedAt'] != null ? _parseDateTime(json['deletedAt']) : null,
      replyToId: json['replyToId'] as String?,
      pinnedAt: json['pinnedAt'] != null ? _parseDateTime(json['pinnedAt']) : null,
      pinnedBy: json['pinnedBy'] as String?,
      threadReplyCount: (json['threadReplyCount'] as num?)?.toInt() ?? 0,
      lastReplyAt: json['lastReplyAt'] != null
          ? _parseDateTime(json['lastReplyAt'])
          : null,
    );
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }

    // Supports timestamp-like objects from non-Firestore backends.
    try {
      final parsed = (value as dynamic).toDate();
      if (parsed is DateTime) return parsed;
    } catch (_) {
      // Fall through to error below.
    }

    throw ArgumentError('Invalid timestamp value: $value');
  }

  Map<String, dynamic> toJson() {
    return {
      'conversationId': conversationId,
      'senderId': senderId,
      'senderName': senderName,
      'content': content,
      'timestamp': Timestamp.fromDate(timestamp),
      'readBy': readBy,
      'workspaceId': workspaceId,
      'attachments': attachments.map((a) => a.toJson()).toList(),
      if (editedAt != null) 'editedAt': Timestamp.fromDate(editedAt!),
      'reactions': reactions,
      if (deletedAt != null) 'deletedAt': Timestamp.fromDate(deletedAt!),
      if (replyToId != null) 'replyToId': replyToId,
    };
  }

  Message copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? senderName,
    String? content,
    DateTime? timestamp,
    List<String>? readBy,
    String? workspaceId,
    List<MessageAttachment>? attachments,
    DateTime? editedAt,
    Map<String, List<String>>? reactions,
    DateTime? deletedAt,
    String? replyToId,
    DateTime? pinnedAt,
    String? pinnedBy,
    int? threadReplyCount,
    DateTime? lastReplyAt,
  }) {
    return Message(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      readBy: readBy ?? this.readBy,
      workspaceId: workspaceId ?? this.workspaceId,
      attachments: attachments ?? this.attachments,
      editedAt: editedAt ?? this.editedAt,
      reactions: reactions ?? this.reactions,
      deletedAt: deletedAt ?? this.deletedAt,
      replyToId: replyToId ?? this.replyToId,
      pinnedAt: pinnedAt ?? this.pinnedAt,
      pinnedBy: pinnedBy ?? this.pinnedBy,
      threadReplyCount: threadReplyCount ?? this.threadReplyCount,
      lastReplyAt: lastReplyAt ?? this.lastReplyAt,
    );
  }

  // Helper to check if message has been read by a specific user
  bool isReadBy(String userId) {
    return readBy.contains(userId);
  }

  // Helper to check if message has attachments
  bool get hasAttachments {
    return attachments.isNotEmpty;
  }

  bool get isDeleted => deletedAt != null;
  bool get isEdited => editedAt != null;
  bool get isPinned => pinnedAt != null;
  bool get hasThreadReplies => threadReplyCount > 0;
}
