import 'package:cloud_firestore/cloud_firestore.dart';

class Conversation {
  final String id;
  final String workspaceId;
  final List<String> participantIds;
  final Map<String, String> participantNames;
  final String? subject; // Email-style subject line
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final String? lastMessageSenderId;
  final String type; // 'direct' or 'group'
  final String scope; // 'direct' | 'project' | 'vendor' | 'customer'
  final String? scopeReferenceId; // projectId, vendorId, or customerId
  final String? scopeReferenceName; // For display (project name, etc.)
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, int> unreadCounts; // Cached unread count per user
  final Map<String, bool> archivedBy; // Which users have archived this conversation
  final Map<String, bool> pinnedBy; // Which users have pinned this conversation
  final Map<String, bool> mutedBy; // Which users have muted this conversation
  // Slack-like channel metadata (only set when isChannel is true)
  final bool isChannel;
  final String? channelName;
  final String? channelTopic;
  final String? channelPurpose;
  final bool isPrivate;
  final String? createdBy;

  Conversation({
    required this.id,
    required this.workspaceId,
    required this.participantIds,
    required this.participantNames,
    this.subject,
    this.lastMessage,
    this.lastMessageAt,
    this.lastMessageSenderId,
    required this.type,
    this.scope = 'direct',
    this.scopeReferenceId,
    this.scopeReferenceName,
    required this.createdAt,
    required this.updatedAt,
    Map<String, int>? unreadCounts,
    Map<String, bool>? archivedBy,
    Map<String, bool>? pinnedBy,
    Map<String, bool>? mutedBy,
    this.isChannel = false,
    this.channelName,
    this.channelTopic,
    this.channelPurpose,
    this.isPrivate = false,
    this.createdBy,
  })  : unreadCounts = unreadCounts ?? {},
        archivedBy = archivedBy ?? {},
        pinnedBy = pinnedBy ?? {},
        mutedBy = mutedBy ?? {};

  factory Conversation.fromJson(Map<String, dynamic> json, String id) {
    return Conversation(
      id: id,
      workspaceId: json['workspaceId'] as String,
      participantIds: List<String>.from(json['participantIds'] as List),
      participantNames: Map<String, String>.from(json['participantNames'] as Map),
      subject: json['subject'] as String?,
      lastMessage: json['lastMessage'] as String?,
      lastMessageAt: json['lastMessageAt'] != null
          ? _parseDateTime(json['lastMessageAt'])
          : null,
      lastMessageSenderId: json['lastMessageSenderId'] as String?,
      type: json['type'] as String? ?? 'direct',
      scope: json['scope'] as String? ?? 'direct',
      scopeReferenceId: json['scopeReferenceId'] as String?,
      scopeReferenceName: json['scopeReferenceName'] as String?,
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
      unreadCounts: json['unreadCounts'] != null
          ? Map<String, int>.from(json['unreadCounts'] as Map)
          : null,
      archivedBy: json['archivedBy'] != null
          ? Map<String, bool>.from(json['archivedBy'] as Map)
          : null,
      pinnedBy: json['pinnedBy'] != null
          ? Map<String, bool>.from(json['pinnedBy'] as Map)
          : null,
      mutedBy: json['mutedBy'] != null
          ? Map<String, bool>.from(json['mutedBy'] as Map)
          : null,
      isChannel: json['isChannel'] as bool? ?? false,
      channelName: json['channelName'] as String?,
      channelTopic: json['channelTopic'] as String?,
      channelPurpose: json['channelPurpose'] as String?,
      isPrivate: json['isPrivate'] as bool? ?? false,
      createdBy: json['createdBy'] as String?,
    );
  }

  /// Display title — channel name (with #) for channels; falls back to subject.
  String get displayTitle {
    if (isChannel && channelName != null && channelName!.isNotEmpty) {
      return '#${channelName!}';
    }
    return subject ?? '';
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
      'workspaceId': workspaceId,
      'participantIds': participantIds,
      'participantNames': participantNames,
      'subject': subject,
      'lastMessage': lastMessage,
      'lastMessageAt': lastMessageAt != null
          ? Timestamp.fromDate(lastMessageAt!)
          : null,
      'lastMessageSenderId': lastMessageSenderId,
      'type': type,
      'scope': scope,
      'scopeReferenceId': scopeReferenceId,
      'scopeReferenceName': scopeReferenceName,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'unreadCounts': unreadCounts,
      'archivedBy': archivedBy,
      'pinnedBy': pinnedBy,
      'mutedBy': mutedBy,
    };
  }

  Conversation copyWith({
    String? id,
    String? workspaceId,
    List<String>? participantIds,
    Map<String, String>? participantNames,
    String? subject,
    String? lastMessage,
    DateTime? lastMessageAt,
    String? lastMessageSenderId,
    String? type,
    String? scope,
    String? scopeReferenceId,
    String? scopeReferenceName,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, int>? unreadCounts,
    Map<String, bool>? archivedBy,
    Map<String, bool>? pinnedBy,
    Map<String, bool>? mutedBy,
    bool? isChannel,
    String? channelName,
    String? channelTopic,
    String? channelPurpose,
    bool? isPrivate,
    String? createdBy,
  }) {
    return Conversation(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      participantIds: participantIds ?? this.participantIds,
      participantNames: participantNames ?? this.participantNames,
      subject: subject ?? this.subject,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      type: type ?? this.type,
      scope: scope ?? this.scope,
      scopeReferenceId: scopeReferenceId ?? this.scopeReferenceId,
      scopeReferenceName: scopeReferenceName ?? this.scopeReferenceName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      unreadCounts: unreadCounts ?? this.unreadCounts,
      archivedBy: archivedBy ?? this.archivedBy,
      pinnedBy: pinnedBy ?? this.pinnedBy,
      mutedBy: mutedBy ?? this.mutedBy,
      isChannel: isChannel ?? this.isChannel,
      channelName: channelName ?? this.channelName,
      channelTopic: channelTopic ?? this.channelTopic,
      channelPurpose: channelPurpose ?? this.channelPurpose,
      isPrivate: isPrivate ?? this.isPrivate,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  // Helper to get the other participant's name in a direct conversation
  String getOtherParticipantName(String currentUserId) {
    final otherParticipantId = participantIds.firstWhere(
      (id) => id != currentUserId,
      orElse: () => '',
    );
    return participantNames[otherParticipantId] ?? 'Unknown';
  }

  // Helper to get the other participant's ID in a direct conversation
  String? getOtherParticipantId(String currentUserId) {
    try {
      return participantIds.firstWhere((id) => id != currentUserId);
    } catch (e) {
      return null;
    }
  }

  // Helper to get all other participant IDs (excluding current user)
  List<String> getOtherParticipantIds(String currentUserId) {
    return participantIds.where((id) => id != currentUserId).toList();
  }

  // Helper to check if a user is a participant
  bool isParticipant(String userId) {
    return participantIds.contains(userId);
  }

  // Get cached unread count for a user
  int getUnreadCount(String userId) {
    return unreadCounts[userId] ?? 0;
  }

  // Check if conversation is archived by a user
  bool isArchivedBy(String userId) {
    return archivedBy[userId] ?? false;
  }

  // Check if conversation is pinned by a user
  bool isPinnedBy(String userId) {
    return pinnedBy[userId] ?? false;
  }

  // Check if conversation is muted by a user
  bool isMutedBy(String userId) {
    return mutedBy[userId] ?? false;
  }
}
