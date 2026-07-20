import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/app_notification.dart';
import '../../models/message.dart';
import '../../models/conversation.dart';
import 'notification_service.dart';

/// Supabase implementation of MessageService
class SupabaseMessageService {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _markMessagesAsReadRpcUnavailable = false;

  /// Get or create a direct conversation between two users
  Future<Conversation> getOrCreateDirectConversation({
    required String workspaceId,
    required String currentUserId,
    required String currentUserName,
    required String otherUserId,
    required String otherUserName,
  }) async {
    final participantIds = [currentUserId, otherUserId]..sort();

    // Query for existing conversation
    final response = await _supabase
        .from('conversations')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('type', 'direct')
        .eq('scope', 'direct')
        .contains('participant_ids', participantIds)
        .limit(1)
        .maybeSingle();

    if (response != null) {
      return _toConversation(response);
    }

    // Create new conversation
    final now = DateTime.now();
    final conversationData = {
      'workspace_id': workspaceId,
      'participant_ids': participantIds,
      'participant_names': {
        currentUserId: currentUserName,
        otherUserId: otherUserName,
      },
      'last_message': null,
      'last_message_at': null,
      'type': 'direct',
      'scope': 'direct',
      'scope_reference_id': null,
      'scope_reference_name': null,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'unread_counts': {currentUserId: 0, otherUserId: 0},
      'archived_by': {},
      'pinned_by': {},
      'muted_by': {},
    };

    final newConversation = await _supabase
        .from('conversations')
        .insert(conversationData)
        .select()
        .single();

    return _toConversation(newConversation);
  }

  /// Create a new conversation with subject
  Future<Conversation> createConversation({
    required String workspaceId,
    required String subject,
    required List<String> participantIds,
    required Map<String, String> participantNames,
    required String senderId,
    required String senderName,
    String? initialMessage,
    List<Map<String, dynamic>>? attachments,
    String scope = 'direct',
    String? scopeReferenceId,
    String? scopeReferenceName,
  }) async {
    final now = DateTime.now();
    final type = participantIds.length > 2 ? 'group' : 'direct';

    final unreadCounts = <String, int>{};
    for (final participantId in participantIds) {
      unreadCounts[participantId] = 0;
    }

    final conversationData = {
      'workspace_id': workspaceId,
      'participant_ids': participantIds,
      'participant_names': participantNames,
      'subject': subject,
      'last_message': initialMessage,
      'last_message_at': initialMessage != null ? now.toIso8601String() : null,
      'last_message_sender_id': initialMessage != null ? senderId : null,
      'type': type,
      'scope': scope,
      'scope_reference_id': scopeReferenceId,
      'scope_reference_name': scopeReferenceName,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'unread_counts': unreadCounts,
      'archived_by': {},
      'pinned_by': {},
      'muted_by': {},
    };

    final response = await _supabase
        .from('conversations')
        .insert(conversationData)
        .select()
        .single();

    if (initialMessage != null && initialMessage.trim().isNotEmpty) {
      await sendMessage(
        conversationId: response['id'],
        workspaceId: workspaceId,
        senderId: senderId,
        senderName: senderName,
        content: initialMessage,
        attachments: attachments,
      );
    }

    return _toConversation(response);
  }

  /// Update the subject of an existing conversation
  Future<void> updateConversationSubject({
    required String conversationId,
    required String subject,
  }) async {
    await _supabase
        .from('conversations')
        .update({'subject': subject.trim()})
        .eq('id', conversationId);
  }

  /// Get all conversations for a user in a workspace
  Stream<List<Conversation>> getConversations({
    required String workspaceId,
    required String userId,
  }) {
    if (workspaceId.isEmpty) {
      return Stream.value(const <Conversation>[]);
    }
    return _supabase
        .from('conversations')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .order('last_message_at', ascending: false)
        .map((data) {
          return data
              .where((row) {
                final participantIds =
                    (row['participant_ids'] as List?)?.cast<String>() ?? [];
                return participantIds.contains(userId);
              })
              .map((row) => _toConversation(row))
              .toList()
            ..sort((a, b) {
              // Pinned conversations first
              final aPinned = a.isPinnedBy(userId);
              final bPinned = b.isPinnedBy(userId);
              if (aPinned && !bPinned) return -1;
              if (!aPinned && bPinned) return 1;
              // Then by last message time
              if (a.lastMessageAt == null && b.lastMessageAt == null) return 0;
              if (a.lastMessageAt == null) return 1;
              if (b.lastMessageAt == null) return -1;
              return b.lastMessageAt!.compareTo(a.lastMessageAt!);
            });
        });
  }

  /// Get conversations filtered by scope
  Stream<List<Conversation>> getConversationsByScope({
    required String workspaceId,
    required String userId,
    required String scope,
    String? scopeReferenceId,
  }) {
    if (workspaceId.isEmpty) {
      return Stream.value(const <Conversation>[]);
    }
    return _supabase
        .from('conversations')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .order('last_message_at', ascending: false)
        .map((data) {
          return data
              .where((row) {
                final participantIds =
                    (row['participant_ids'] as List?)?.cast<String>() ?? [];
                if (!participantIds.contains(userId)) return false;
                if (row['scope'] != scope) return false;
                if (scopeReferenceId != null &&
                    row['scope_reference_id'] != scopeReferenceId) {
                  return false;
                }
                return true;
              })
              .map((row) => _toConversation(row))
              .toList();
        });
  }

  /// Get a single conversation stream
  Stream<Conversation> getConversationStream(String conversationId) {
    return _supabase
        .from('conversations')
        .stream(primaryKey: ['id'])
        .eq('id', conversationId)
        .map((data) {
          if (data.isEmpty) {
            throw Exception('Conversation not found');
          }
          return _toConversation(data.first);
        });
  }

  /// Get messages for a conversation
  Stream<List<Message>> getMessages(String conversationId) {
    return _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('timestamp', ascending: true)
        .map((data) {
          return data.map((row) => _toMessage(row)).toList();
        });
  }

  /// Get a page of messages for a conversation (newest first in query,
  /// returned in ascending timestamp order for display).
  /// Pass [before] to load messages older than a given timestamp.
  Future<List<Message>> getMessagesPage({
    required String conversationId,
    int limit = 50,
    DateTime? before,
  }) async {
    var query = _supabase
        .from('messages')
        .select()
        .eq('conversation_id', conversationId);
    if (before != null) {
      query = query.lt('timestamp', before.toIso8601String());
    }
    final rows = await query
        .order('timestamp', ascending: false)
        .limit(limit);
    final messages = rows.map((row) => _toMessage(row)).toList();
    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return messages;
  }

  /// Search messages within a single conversation (server-side ILIKE).
  Future<List<Message>> searchMessagesInConversation({
    required String conversationId,
    required String query,
  }) async {
    if (query.trim().isEmpty) return [];
    try {
      final rows = await _supabase
          .from('messages')
          .select()
          .eq('conversation_id', conversationId)
          .ilike('content', '%$query%')
          .isFilter('deleted_at', null)
          .order('timestamp', ascending: true)
          .limit(100);
      return rows.map((row) => _toMessage(row)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Get a single message by ID
  Future<Message?> getMessageById(String messageId) async {
    try {
      final row = await _supabase
          .from('messages')
          .select()
          .eq('id', messageId)
          .maybeSingle();
      if (row == null) return null;
      return _toMessage(row);
    } catch (_) {
      return null;
    }
  }

  /// Send a message
  Future<void> sendMessage({
    required String conversationId,
    required String workspaceId,
    required String senderId,
    required String senderName,
    required String content,
    List<Map<String, dynamic>>? attachments,
    String? replyToId,
  }) async {
    final now = DateTime.now();

    final conversationResponse = await _supabase
        .from('conversations')
        .select()
        .eq('id', conversationId)
        .single();

    final conversation = _toConversation(conversationResponse);

    final messageData = {
      'conversation_id': conversationId,
      'workspace_id': workspaceId,
      'sender_id': senderId,
      'sender_name': senderName,
      'content': content,
      'timestamp': now.toIso8601String(),
      'read_by': [senderId],
      'attachments': attachments ?? [],
      'reactions': {},
      if (replyToId != null) 'reply_to_id': replyToId,
    };

    await _supabase.from('messages').insert(messageData);

    final updatedUnreadCounts = Map<String, dynamic>.from(
      conversation.unreadCounts,
    );
    final notifyUserIds = <String>[];
    for (final participantId in conversation.participantIds) {
      if (participantId == senderId) continue;
      if (conversation.isMutedBy(participantId)) continue;

      final previousUnread =
          (updatedUnreadCounts[participantId] as int?) ?? 0;
      updatedUnreadCounts[participantId] = previousUnread + 1;
      // Only notify when the recipient's unread was 0 — collapses bursts
      // into one notification per "session" until they read the conversation.
      if (previousUnread == 0) {
        notifyUserIds.add(participantId);
      }
    }

    String lastMessagePreview = content;
    if (attachments != null && attachments.isNotEmpty) {
      if (content.isEmpty) {
        if (attachments.length == 1) {
          final name = (attachments.first['fileName'] as String?)?.trim() ?? '';
          lastMessagePreview = name.isNotEmpty ? '📎 $name' : '📎 Attachment';
        } else {
          lastMessagePreview = '📎 ${attachments.length} Attachments';
        }
      } else {
        // text + attachments: prefix with clip so recipient knows there's a file
        lastMessagePreview = '📎 $content';
      }
    }

    await _supabase
        .from('conversations')
        .update({
          'last_message': lastMessagePreview,
          'last_message_at': now.toIso8601String(),
          'last_message_sender_id': senderId,
          'updated_at': now.toIso8601String(),
          'unread_counts': updatedUnreadCounts,
        })
        .eq('id', conversationId);

    if (notifyUserIds.isNotEmpty) {
      _notifyMessageRecipients(
        recipientIds: notifyUserIds,
        workspaceId: workspaceId,
        conversationId: conversationId,
        senderName: senderName,
        preview: lastMessagePreview,
        conversationSubject: conversation.subject,
        conversationType: conversation.type,
        scope: conversation.scope,
        scopeReferenceId: conversation.scopeReferenceId,
        scopeReferenceName: conversation.scopeReferenceName,
      );
    }
  }

  /// Fire-and-forget: create in-app + push notifications for each recipient.
  Future<void> _notifyMessageRecipients({
    required List<String> recipientIds,
    required String workspaceId,
    required String conversationId,
    required String senderName,
    required String preview,
    String? conversationSubject,
    required String conversationType,
    required String scope,
    String? scopeReferenceId,
    String? scopeReferenceName,
  }) async {
    final notificationService = SupabaseNotificationService();
    final isGroup = conversationType == 'group';
    final title = isGroup && conversationSubject != null && conversationSubject.isNotEmpty
        ? '$senderName in $conversationSubject'
        : senderName;
    final metadata = <String, dynamic>{
      'conversation_id': conversationId,
      'sender_name': senderName,
      'deeplink_path': '/messages/$conversationId',
      'scope': scope,
      if (scopeReferenceId != null) 'scope_reference_id': scopeReferenceId,
      if (scopeReferenceName != null)
        'scope_reference_name': scopeReferenceName,
    };
    for (final userId in recipientIds) {
      notificationService.createNotification(
        userId: userId,
        workspaceId: workspaceId,
        type: AppNotificationTypes.messageReceived,
        title: title,
        body: preview,
        metadata: metadata,
      );
    }
  }

  /// Edit a message
  Future<void> editMessage({
    required String messageId,
    required String newContent,
  }) async {
    await _supabase
        .from('messages')
        .update({
          'content': newContent,
          'edited_at': DateTime.now().toIso8601String(),
        })
        .eq('id', messageId);
  }

  /// Soft-delete a message
  Future<void> deleteMessage(String messageId) async {
    await _supabase
        .from('messages')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', messageId);
  }

  /// Add a reaction to a message
  Future<void> addReaction({
    required String messageId,
    required String emoji,
    required String userId,
  }) async {
    final row = await _supabase
        .from('messages')
        .select('reactions')
        .eq('id', messageId)
        .single();

    final reactions = Map<String, dynamic>.from(row['reactions'] ?? {});
    final userIds = List<String>.from(reactions[emoji] ?? []);
    if (!userIds.contains(userId)) {
      userIds.add(userId);
    }
    reactions[emoji] = userIds;

    await _supabase
        .from('messages')
        .update({'reactions': reactions})
        .eq('id', messageId);
  }

  /// Remove a reaction from a message
  Future<void> removeReaction({
    required String messageId,
    required String emoji,
    required String userId,
  }) async {
    final row = await _supabase
        .from('messages')
        .select('reactions')
        .eq('id', messageId)
        .single();

    final reactions = Map<String, dynamic>.from(row['reactions'] ?? {});
    final userIds = List<String>.from(reactions[emoji] ?? []);
    userIds.remove(userId);
    if (userIds.isEmpty) {
      reactions.remove(emoji);
    } else {
      reactions[emoji] = userIds;
    }

    await _supabase
        .from('messages')
        .update({'reactions': reactions})
        .eq('id', messageId);
  }

  /// Mark all messages in a conversation as read by the current user
  Future<void> markMessagesAsRead({
    required String conversationId,
    required String userId,
  }) async {
    if (!_markMessagesAsReadRpcUnavailable) {
      try {
        await _supabase.rpc(
          'mark_messages_as_read',
          params: {'p_conversation_id': conversationId, 'p_user_id': userId},
        );
        return;
      } on PostgrestException catch (e) {
        final message = e.message.toLowerCase();
        final isMissingRpc =
            e.code == 'PGRST202' ||
            message.contains('mark_messages_as_read') ||
            message.contains('could not find') ||
            message.contains('not found');
        if (isMissingRpc) {
          _markMessagesAsReadRpcUnavailable = true;
        }
      } catch (_) {
        // Fall back to client-side updates when RPC is unavailable locally.
      }
    }

    final conversation = await _supabase
        .from('conversations')
        .select('unread_counts')
        .eq('id', conversationId)
        .maybeSingle();

    if (conversation != null) {
      final unreadCounts = Map<String, dynamic>.from(
        conversation['unread_counts'] ?? {},
      );
      unreadCounts[userId] = 0;
      await _supabase
          .from('conversations')
          .update({'unread_counts': unreadCounts})
          .eq('id', conversationId);
    }

    final messages = await _supabase
        .from('messages')
        .select('id, read_by')
        .eq('conversation_id', conversationId);

    for (final row in messages) {
      final message = Map<String, dynamic>.from(row);
      final messageId = message['id'] as String?;
      if (messageId == null || messageId.isEmpty) continue;

      final readBy = List<String>.from(message['read_by'] ?? []);
      if (readBy.contains(userId)) continue;

      readBy.add(userId);
      await _supabase
          .from('messages')
          .update({'read_by': readBy})
          .eq('id', messageId);
    }
  }

  /// Get unread message count for a conversation
  Future<int> getUnreadCount({
    required String conversationId,
    required String userId,
  }) async {
    try {
      final conversationResponse = await _supabase
          .from('conversations')
          .select('unread_counts')
          .eq('id', conversationId)
          .maybeSingle();

      if (conversationResponse != null) {
        final unreadCounts = Map<String, dynamic>.from(
          conversationResponse['unread_counts'] ?? {},
        );
        return (unreadCounts[userId] as int?) ?? 0;
      }
    } catch (_) {
      // Fall back to counting messages
    }

    // Fallback: count unread messages
    final messagesResponse = await _supabase
        .from('messages')
        .select()
        .eq('conversation_id', conversationId);

    int unreadCount = 0;
    for (final row in messagesResponse) {
      final readBy = List<String>.from(row['read_by'] ?? []);
      if (!readBy.contains(userId)) {
        unreadCount++;
      }
    }

    return unreadCount;
  }

  /// Get total unread message count across all conversations
  Stream<int> getTotalUnreadCount({
    required String workspaceId,
    required String userId,
  }) {
    if (workspaceId.isEmpty) {
      return Stream.value(0);
    }
    return _supabase
        .from('conversations')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .map((data) {
          int totalUnread = 0;
          for (final row in data) {
            final participantIds =
                (row['participant_ids'] as List?)?.cast<String>() ?? [];
            if (participantIds.contains(userId)) {
              final unreadCounts = Map<String, dynamic>.from(
                row['unread_counts'] ?? {},
              );
              totalUnread += (unreadCounts[userId] as int?) ?? 0;
            }
          }
          return totalUnread;
        });
  }

  /// Archive a conversation for a specific user
  Future<void> archiveConversation({
    required String conversationId,
    required String userId,
  }) async {
    final response = await _supabase
        .from('conversations')
        .select('archived_by')
        .eq('id', conversationId)
        .single();

    final archivedBy = Map<String, dynamic>.from(response['archived_by'] ?? {});
    archivedBy[userId] = true;

    await _supabase
        .from('conversations')
        .update({'archived_by': archivedBy})
        .eq('id', conversationId);
  }

  /// Unarchive a conversation for a specific user
  Future<void> unarchiveConversation({
    required String conversationId,
    required String userId,
  }) async {
    final response = await _supabase
        .from('conversations')
        .select('archived_by')
        .eq('id', conversationId)
        .single();

    final archivedBy = Map<String, dynamic>.from(response['archived_by'] ?? {});
    archivedBy[userId] = false;

    await _supabase
        .from('conversations')
        .update({'archived_by': archivedBy})
        .eq('id', conversationId);
  }

  /// Pin a conversation for a specific user
  Future<void> pinConversation({
    required String conversationId,
    required String userId,
  }) async {
    final response = await _supabase
        .from('conversations')
        .select('pinned_by')
        .eq('id', conversationId)
        .single();

    final pinnedBy = Map<String, dynamic>.from(response['pinned_by'] ?? {});
    pinnedBy[userId] = true;

    await _supabase
        .from('conversations')
        .update({'pinned_by': pinnedBy})
        .eq('id', conversationId);
  }

  /// Unpin a conversation for a specific user
  Future<void> unpinConversation({
    required String conversationId,
    required String userId,
  }) async {
    final response = await _supabase
        .from('conversations')
        .select('pinned_by')
        .eq('id', conversationId)
        .single();

    final pinnedBy = Map<String, dynamic>.from(response['pinned_by'] ?? {});
    pinnedBy[userId] = false;

    await _supabase
        .from('conversations')
        .update({'pinned_by': pinnedBy})
        .eq('id', conversationId);
  }

  /// Mute a conversation for a specific user
  Future<void> muteConversation({
    required String conversationId,
    required String userId,
  }) async {
    final response = await _supabase
        .from('conversations')
        .select('muted_by')
        .eq('id', conversationId)
        .single();

    final mutedBy = Map<String, dynamic>.from(response['muted_by'] ?? {});
    mutedBy[userId] = true;

    await _supabase
        .from('conversations')
        .update({'muted_by': mutedBy})
        .eq('id', conversationId);
  }

  /// Unmute a conversation for a specific user
  Future<void> unmuteConversation({
    required String conversationId,
    required String userId,
  }) async {
    final response = await _supabase
        .from('conversations')
        .select('muted_by')
        .eq('id', conversationId)
        .single();

    final mutedBy = Map<String, dynamic>.from(response['muted_by'] ?? {});
    mutedBy[userId] = false;

    await _supabase
        .from('conversations')
        .update({'muted_by': mutedBy})
        .eq('id', conversationId);
  }

  /// Forward a message to another conversation
  Future<void> forwardMessage({
    required String messageId,
    required String targetConversationId,
    required String workspaceId,
    required String senderId,
    required String senderName,
  }) async {
    final original = await getMessageById(messageId);
    if (original == null) return;

    await sendMessage(
      conversationId: targetConversationId,
      workspaceId: workspaceId,
      senderId: senderId,
      senderName: senderName,
      content: original.content,
      attachments: original.attachments.map((a) => a.toJson()).toList(),
    );
  }

  /// Search messages across conversations
  Future<List<Message>> searchMessages({
    required String workspaceId,
    required String userId,
    required String query,
  }) async {
    if (query.trim().isEmpty) return [];

    try {
      final rows = await _supabase
          .from('messages')
          .select()
          .eq('workspace_id', workspaceId)
          .ilike('content', '%$query%')
          .isFilter('deleted_at', null)
          .order('timestamp', ascending: false)
          .limit(50);

      return rows.map((row) => _toMessage(row)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Delete a conversation
  Future<void> deleteConversation(String conversationId) async {
    // Delete all messages in the conversation
    await _supabase
        .from('messages')
        .delete()
        .eq('conversation_id', conversationId);

    // Delete the conversation
    await _supabase.from('conversations').delete().eq('id', conversationId);
  }

  // ---------------------------------------------------------------------------
  // Typing indicators via Realtime Presence
  // ---------------------------------------------------------------------------

  RealtimeChannel? _typingChannel;
  final Map<String, Function(List<String>)> _typingListeners = {};

  /// Start tracking typing status for a conversation
  void subscribeToTyping({
    required String conversationId,
    required String userId,
    required Function(List<String> typingUserNames) onTypingChanged,
  }) {
    _typingChannel?.unsubscribe();
    _typingListeners.clear();

    _typingChannel = _supabase.channel('typing:$conversationId');
    _typingListeners[conversationId] = onTypingChanged;

    _typingChannel!.onPresenceSync((payload) {
      final state = _typingChannel!.presenceState();
      final typingNames = <String>[];
      for (final entry in state) {
        for (final presence in entry.presences) {
          final data = presence.payload;
          if (data['user_id'] != userId && data['is_typing'] == true) {
            typingNames.add(data['user_name'] as String? ?? 'Someone');
          }
        }
      }
      onTypingChanged(typingNames);
    }).subscribe();
  }

  /// Broadcast typing status
  Future<void> setTyping({
    required String userId,
    required String userName,
    required bool isTyping,
  }) async {
    if (_typingChannel == null) return;
    await _typingChannel!.track({
      'user_id': userId,
      'user_name': userName,
      'is_typing': isTyping,
    });
  }

  /// Stop tracking typing for a conversation
  void disposeTyping() {
    _typingChannel?.unsubscribe();
    _typingChannel = null;
    _typingListeners.clear();
  }

  // ---------------------------------------------------------------------------
  // Data conversion helpers
  // ---------------------------------------------------------------------------

  /// Convert database row to Conversation
  Conversation _toConversation(Map<String, dynamic> row) {
    return Conversation.fromJson(
      _toConversationFirestoreFormat(row),
      row['id'],
    );
  }

  /// Convert database row to Message
  Message _toMessage(Map<String, dynamic> row) {
    return Message.fromJson(_toMessageFirestoreFormat(row), row['id']);
  }

  /// Convert Supabase snake_case to Firestore camelCase format for conversations
  Map<String, dynamic> _toConversationFirestoreFormat(
    Map<String, dynamic> row,
  ) {
    return {
      'workspaceId': row['workspace_id'],
      'participantIds': row['participant_ids'],
      'participantNames': row['participant_names'],
      'subject': row['subject'],
      'lastMessage': row['last_message'],
      'lastMessageAt': row['last_message_at'] != null
          ? _FakeTimestamp(DateTime.parse(row['last_message_at']))
          : null,
      'lastMessageSenderId': row['last_message_sender_id'],
      'type': row['type'],
      'scope': row['scope'],
      'scopeReferenceId': row['scope_reference_id'],
      'scopeReferenceName': row['scope_reference_name'],
      'createdAt': row['created_at'] != null
          ? _FakeTimestamp(DateTime.parse(row['created_at']))
          : _FakeTimestamp(DateTime.now()),
      'updatedAt': row['updated_at'] != null
          ? _FakeTimestamp(DateTime.parse(row['updated_at']))
          : _FakeTimestamp(DateTime.now()),
      'unreadCounts': row['unread_counts'],
      'archivedBy': row['archived_by'],
      'pinnedBy': row['pinned_by'],
      'mutedBy': row['muted_by'],
      'isChannel': row['is_channel'] ?? false,
      'channelName': row['channel_name'],
      'channelTopic': row['channel_topic'],
      'channelPurpose': row['channel_purpose'],
      'isPrivate': row['is_private'] ?? false,
      'createdBy': row['created_by'],
    };
  }

  /// Convert Supabase snake_case to Firestore camelCase format for messages
  Map<String, dynamic> _toMessageFirestoreFormat(Map<String, dynamic> row) {
    return {
      'conversationId': row['conversation_id'],
      'workspaceId': row['workspace_id'],
      'senderId': row['sender_id'],
      'senderName': row['sender_name'],
      'content': row['content'],
      'timestamp': row['timestamp'] != null
          ? _FakeTimestamp(DateTime.parse(row['timestamp']))
          : _FakeTimestamp(DateTime.now()),
      'readBy': row['read_by'],
      'attachments': row['attachments'],
      'editedAt': row['edited_at'] != null
          ? _FakeTimestamp(DateTime.parse(row['edited_at']))
          : null,
      'reactions': row['reactions'],
      'deletedAt': row['deleted_at'] != null
          ? _FakeTimestamp(DateTime.parse(row['deleted_at']))
          : null,
      'replyToId': row['reply_to_id'],
      'pinnedAt': row['pinned_at'] != null
          ? _FakeTimestamp(DateTime.parse(row['pinned_at']))
          : null,
      'pinnedBy': row['pinned_by'],
      'threadReplyCount': row['thread_reply_count'] ?? 0,
      'lastReplyAt': row['last_reply_at'] != null
          ? _FakeTimestamp(DateTime.parse(row['last_reply_at']))
          : null,
    };
  }

  // ---------------------------------------------------------------------------
  // Slack-like extras: pinned messages, bookmarks, channels, slash commands
  // ---------------------------------------------------------------------------

  /// Pin a message (visible to all participants).
  /// Uses a SECURITY DEFINER RPC because base RLS only allows the original
  /// sender to update a message, but pinning is a shared-conversation action.
  Future<void> pinMessage({
    required String messageId,
    required String userId,
  }) async {
    await _supabase.rpc('pin_message', params: {'p_message_id': messageId});
  }

  /// Unpin a message (any conversation participant).
  Future<void> unpinMessage(String messageId) async {
    await _supabase.rpc('unpin_message', params: {'p_message_id': messageId});
  }

  /// Stream pinned messages for a conversation (newest pin first).
  Stream<List<Message>> streamPinnedMessages(String conversationId) {
    return _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .map((rows) {
          final pinned = rows
              .where((r) => r['pinned_at'] != null && r['deleted_at'] == null)
              .map((r) => _toMessage(r))
              .toList()
            ..sort((a, b) => (b.pinnedAt ?? b.timestamp)
                .compareTo(a.pinnedAt ?? a.timestamp));
          return pinned;
        });
  }

  /// Save (bookmark) a message for the current user.
  Future<void> bookmarkMessage({
    required String messageId,
    required String userId,
    required String workspaceId,
    required String conversationId,
    String? note,
  }) async {
    await _supabase.from('message_bookmarks').upsert({
      'user_id': userId,
      'workspace_id': workspaceId,
      'message_id': messageId,
      'conversation_id': conversationId,
      if (note != null) 'note': note,
    }, onConflict: 'user_id,message_id');
  }

  Future<void> removeBookmark({
    required String messageId,
    required String userId,
  }) async {
    await _supabase
        .from('message_bookmarks')
        .delete()
        .eq('user_id', userId)
        .eq('message_id', messageId);
  }

  Future<bool> isBookmarked({
    required String messageId,
    required String userId,
  }) async {
    try {
      final r = await _supabase
          .from('message_bookmarks')
          .select('id')
          .eq('user_id', userId)
          .eq('message_id', messageId)
          .maybeSingle();
      return r != null;
    } catch (_) {
      return false;
    }
  }

  /// Stream of saved messages (with the underlying message hydrated).
  Stream<List<SavedMessage>> streamSavedMessages({
    required String userId,
    required String workspaceId,
  }) {
    return _supabase
        .from('message_bookmarks')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .asyncMap((rows) async {
          final filtered =
              rows.where((r) => r['workspace_id'] == workspaceId).toList();
          if (filtered.isEmpty) return <SavedMessage>[];
          final messageIds = filtered
              .map((r) => r['message_id'] as String)
              .toSet()
              .toList();
          final msgRows = await _supabase
              .from('messages')
              .select()
              .inFilter('id', messageIds);
          final byId = {
            for (final m in msgRows) (m['id'] as String): _toMessage(m),
          };
          final saved = <SavedMessage>[];
          for (final r in filtered) {
            final mid = r['message_id'] as String;
            final msg = byId[mid];
            if (msg == null) continue;
            saved.add(SavedMessage(
              bookmarkId: r['id'] as String,
              conversationId: r['conversation_id'] as String,
              note: r['note'] as String?,
              savedAt: DateTime.parse(r['created_at'] as String),
              message: msg,
            ));
          }
          return saved;
        });
  }

  /// Create a Slack-style channel conversation.
  Future<Conversation> createChannel({
    required String workspaceId,
    required String channelName,
    required String creatorId,
    required String creatorName,
    String? topic,
    String? purpose,
    bool isPrivate = false,
    List<String> initialMemberIds = const [],
    Map<String, String> initialMemberNames = const {},
  }) async {
    final normalized = channelName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'[^a-z0-9_\-]'), '');
    if (normalized.isEmpty) {
      throw ArgumentError('Channel name cannot be empty');
    }

    final now = DateTime.now();
    final allMemberIds = <String>{creatorId, ...initialMemberIds}.toList();
    final allMemberNames = {
      creatorId: creatorName,
      ...initialMemberNames,
    };
    final unread = {for (final id in allMemberIds) id: 0};

    final inserted = await _supabase
        .from('conversations')
        .insert({
          'workspace_id': workspaceId,
          'participant_ids': allMemberIds,
          'participant_names': allMemberNames,
          'subject': '#$normalized',
          'type': allMemberIds.length > 2 ? 'group' : 'direct',
          'scope': 'direct',
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
          'unread_counts': unread,
          'archived_by': {},
          'pinned_by': {},
          'muted_by': {},
          'is_channel': true,
          'channel_name': normalized,
          'channel_topic': topic,
          'channel_purpose': purpose,
          'is_private': isPrivate,
          'created_by': creatorId,
        })
        .select()
        .single();
    return _toConversation(inserted);
  }

  /// Update a channel's topic.
  Future<void> updateChannelTopic({
    required String conversationId,
    required String topic,
  }) async {
    await _supabase
        .from('conversations')
        .update({'channel_topic': topic.trim()})
        .eq('id', conversationId);
  }

  /// Rename a channel.
  Future<void> renameChannel({
    required String conversationId,
    required String newName,
  }) async {
    final normalized = newName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'[^a-z0-9_\-]'), '');
    if (normalized.isEmpty) {
      throw ArgumentError('Channel name cannot be empty');
    }
    await _supabase.from('conversations').update({
      'channel_name': normalized,
      'subject': '#$normalized',
    }).eq('id', conversationId);
  }

  /// Public (non-private) channels in the workspace, fetched once via RPC.
  /// Base RLS hides conversations the user isn't a participant of, so we use
  /// a SECURITY DEFINER function that gates on workspace membership.
  Future<List<Conversation>> listPublicChannels(String workspaceId) async {
    final rows = await _supabase
        .rpc('list_public_channels', params: {'p_workspace': workspaceId});
    final list = (rows as List?) ?? const [];
    return list
        .map((r) => _toConversation(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Stream variant — polls the RPC every 10s for simple channel discovery.
  Stream<List<Conversation>> streamPublicChannels(String workspaceId) async* {
    while (true) {
      try {
        yield await listPublicChannels(workspaceId);
      } catch (_) {
        yield const <Conversation>[];
      }
      await Future<void>.delayed(const Duration(seconds: 10));
    }
  }

  /// Join a public channel (workspace-membership gated, RLS-safe).
  Future<void> joinChannel({
    required String conversationId,
    required String userId,
    required String userName,
  }) async {
    await _supabase.rpc('join_channel', params: {
      'p_conversation': conversationId,
      'p_user_name': userName,
    });
  }

  /// Leave a channel.
  Future<void> leaveChannel({
    required String conversationId,
    required String userId,
  }) async {
    await _supabase
        .rpc('leave_channel', params: {'p_conversation': conversationId});
  }
}

/// A bookmarked/saved message with its hydrated [Message].
class SavedMessage {
  final String bookmarkId;
  final String conversationId;
  final String? note;
  final DateTime savedAt;
  final Message message;

  SavedMessage({
    required this.bookmarkId,
    required this.conversationId,
    required this.message,
    required this.savedAt,
    this.note,
  });
}

class _FakeTimestamp {
  final DateTime _dateTime;
  _FakeTimestamp(this._dateTime);
  DateTime toDate() => _dateTime;
}
