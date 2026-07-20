import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../models/message_attachment.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../services/attachment_service.dart';
import '../../theme/theme.dart';
import '../../utils/project_terminology.dart';
import '../../utils/slash_commands.dart';
import '../../utils/user_facing_error.dart';
import 'conversation_details_panel.dart';
import 'forward_message_dialog.dart';
import 'mention_autocomplete.dart';
import 'message_bubble.dart';
import 'message_thread_skeleton.dart';
import 'pinned_messages_panel.dart';
import 'messaging_styles.dart';
import 'project_photo_picker_dialog.dart';
import 'reply_preview_bar.dart';
import 'typing_indicator.dart';
import 'unread_separator.dart';

/// Full-featured conversation thread view with message stream, typing
/// indicators, reply-to, reactions, forward, edit, delete, scroll-to-bottom
/// FAB, and an optional details panel.
///
/// Use a [Key] based on [conversationId] at the call site so that switching
/// conversations forces widget recreation and proper stream cleanup.
class ConversationThreadView extends StatefulWidget {
  final String conversationId;
  final String workspaceId;
  final String currentUserId;
  final String currentUserName;

  /// Called when the user taps the close button. When `null` the close button
  /// is hidden (e.g. when embedded inside a project tab).
  final VoidCallback? onClose;

  /// Called when the user taps the expand/collapse button. When `null` no
  /// expand button is shown.
  final VoidCallback? onExpand;

  /// Whether the thread is currently in expanded (full-width) mode. Only used
  /// when [onExpand] is non-null.
  final bool isExpanded;

  /// Whether to show the conversation-details toggle button in the header.
  final bool showDetailsToggle;

  /// Optional project ID for picking project photos as attachments.
  final String? projectId;

  const ConversationThreadView({
    super.key,
    required this.conversationId,
    required this.workspaceId,
    required this.currentUserId,
    required this.currentUserName,
    this.onClose,
    this.onExpand,
    this.isExpanded = false,
    this.showDetailsToggle = true,
    this.projectId,
  });

  @override
  State<ConversationThreadView> createState() => _ConversationThreadViewState();
}

class _ConversationThreadViewState extends State<ConversationThreadView> {
  final AttachmentService _attachmentService = AttachmentService();
  final TextEditingController _replyController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  dynamic get _messageService => ServiceLocator.messageService;

  // Streams stored as fields so they survive setState rebuilds and
  // StreamBuilders never drop + re-subscribe their channels.
  late final Stream<List<Message>> _messagesStream;
  late final Stream<Conversation> _conversationStream;

  // Subject inline editing
  bool _isEditingSubject = false;
  final TextEditingController _subjectEditController = TextEditingController();

  final List<MessageAttachment> _attachments = [];
  bool _isSending = false;
  bool _isUploading = false;
  bool _hasMarkedAsRead = false;
  int _previousMessageCount = 0;
  bool _showScrollToBottom = false;
  Message? _replyToMessage;
  List<String> _typingUserNames = [];
  bool _firstUnreadSet = false;
  String? _firstUnreadMessageId;
  List<Conversation> _allConversations = [];
  bool _showDetailsPanel = false;
  String? _mentionQuery;
  List<Map<String, String>> _participants = [];
  Map<String, String> _participantNames = {};
  String? _derivedProjectId;
  int _newMessagesWhileScrolledUp = 0;
  int _messageDisplayLimit = 50;
  bool _isSearchingMessages = false;
  String _messageSearchQuery = '';

  String get _draftKey => 'draft_${widget.conversationId}';

  @override
  void initState() {
    super.initState();
    _messagesStream = _messageService.getMessages(widget.conversationId)
        as Stream<List<Message>>;
    _conversationStream = _messageService.getConversationStream(
      widget.conversationId,
    ) as Stream<Conversation>;
    _scrollController.addListener(_onScroll);
    _replyController.addListener(_onComposeChanged);
    _restoreDraft();
    _messageService.subscribeToTyping(
      conversationId: widget.conversationId,
      userId: widget.currentUserId,
      onTypingChanged: (List<String> names) {
        if (mounted) setState(() => _typingUserNames = names);
      },
    );
  }

  Future<void> _restoreDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final draft = prefs.getString(_draftKey);
    if (draft != null && draft.isNotEmpty && mounted) {
      _replyController.text = draft;
      _replyController.selection = TextSelection.collapsed(
        offset: draft.length,
      );
    }
  }

  Future<void> _saveDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final text = _replyController.text;
    if (text.isEmpty) {
      prefs.remove(_draftKey);
    } else {
      prefs.setString(_draftKey, text);
    }
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.remove(_draftKey);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final distanceFromBottom =
        _scrollController.position.maxScrollExtent -
        _scrollController.position.pixels;
    final show = distanceFromBottom > 200;
    if (show != _showScrollToBottom) {
      setState(() => _showScrollToBottom = show);
    }
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_scrollController.hasClients) return;
    if (animated) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  Future<void> _markAsRead() async {
    try {
      await _messageService.markMessagesAsRead(
        conversationId: widget.conversationId,
        userId: widget.currentUserId,
      );
    } catch (e) {
      // Reset the flag so the next message-stream emission retries.
      // Without this, a transient failure would leave the badge stale
      // until the user navigates away and back.
      _hasMarkedAsRead = false;
      debugPrint('Failed to mark messages as read: $e');
    }
  }

  Future<void> _saveSubject() async {
    final newSubject = _subjectEditController.text.trim();
    setState(() => _isEditingSubject = false);
    if (newSubject.isEmpty) return;
    try {
      await _messageService.updateConversationSubject(
        conversationId: widget.conversationId,
        subject: newSubject,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update subject: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showParticipantsDialog(BuildContext context, Conversation conversation) {
    final others = conversation.participantNames.entries
        .where((e) => e.key != widget.currentUserId)
        .toList();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '${conversation.participantIds.length} Participants',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Current user first
              ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor:
                      Theme.of(ctx).colorScheme.secondaryContainer,
                  child: Text(
                    'Y',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color:
                          Theme.of(ctx).colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                title: Text(
                  widget.currentUserName,
                  style: const TextStyle(fontSize: 13),
                ),
                trailing: Text(
                  'You',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
              ...others.map((e) {
                final name = e.value;
                final initials = name.trim().isNotEmpty
                    ? name
                          .trim()
                          .split(' ')
                          .map((w) => w[0])
                          .take(2)
                          .join()
                          .toUpperCase()
                    : '?';
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor:
                        Theme.of(ctx).colorScheme.primaryContainer,
                    child: Text(
                      initials,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color:
                            Theme.of(ctx).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  title: Text(name, style: const TextStyle(fontSize: 13)),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void _onComposeChanged() {
    final cursor = _replyController.selection.baseOffset;
    if (cursor < 0) return;
    final query = detectMentionQuery(_replyController.text, cursor);
    if (query != _mentionQuery) setState(() => _mentionQuery = query);
    _saveDraft();
  }

  @override
  void dispose() {
    _replyController.removeListener(_onComposeChanged);
    _replyController.dispose();
    _subjectEditController.dispose();
    _scrollController.dispose();
    _messageService.disposeTyping();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _isUploading = true;
        });

        for (final file in result.files) {
          try {
            final attachment = await _attachmentService.uploadFile(
              file: file.bytes ?? file.path!,
              fileName: file.name,
              mimeType: _getMimeType(file.extension ?? ''),
              conversationId: widget.conversationId,
              workspaceId: widget.workspaceId,
            );

            setState(() {
              _attachments.add(attachment);
            });
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Failed to upload ${file.name}: $e'),
                  backgroundColor: AppColors.error,
                ),
              );
            }
          }
        }

        setState(() {
          _isUploading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isUploading = false;
      });
    }
  }

  String _getMimeType(String extension) {
    switch (extension.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }

  String? get _effectiveProjectId => widget.projectId ?? _derivedProjectId;

  /// Execute a server-side slash command (/topic, /rename, /leave).
  Future<void> _runChannelSlashCommand(SlashCommandResult parsed) async {
    final cmd = parsed.command!;
    final svc = ServiceLocator.messageService;
    try {
      switch (cmd.name) {
        case 'topic':
          await svc.updateChannelTopic(
            conversationId: widget.conversationId,
            topic: parsed.argument,
          );
          _replyController.value = TextEditingValue.empty;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Channel topic updated'),
                  duration: Duration(seconds: 1)),
            );
          }
          break;
        case 'rename':
          if (parsed.argument.trim().isEmpty) throw 'Provide a new channel name';
          await svc.renameChannel(
            conversationId: widget.conversationId,
            newName: parsed.argument,
          );
          _replyController.value = TextEditingValue.empty;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Channel renamed'),
                  duration: Duration(seconds: 1)),
            );
          }
          break;
        case 'leave':
          await svc.leaveChannel(
            conversationId: widget.conversationId,
            userId: widget.currentUserId,
          );
          _replyController.value = TextEditingValue.empty;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('You left the channel'),
                  duration: Duration(seconds: 1)),
            );
            Navigator.of(context).maybePop();
          }
          break;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Slash command failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _pickProjectPhotos() async {
    final projectId = _effectiveProjectId;
    if (projectId == null) return;
    final existingIds = _attachments.map((a) => a.id).toSet();
    final results = await showProjectPhotoPicker(
      context: context,
      workspaceId: widget.workspaceId,
      projectId: projectId,
      alreadyAttachedIds: existingIds,
    );
    if (!mounted) return;
    if (results != null && results.isNotEmpty) {
      final newOnly = results.where((r) => !existingIds.contains(r.id)).toList();
      if (newOnly.isNotEmpty) {
        setState(() => _attachments.addAll(newOnly));
      }
    }
  }

  Future<void> _sendReply() async {
    final rawContent = _replyController.text.trim();
    if (rawContent.isEmpty && _attachments.isEmpty) return;

    // Slash command parsing — text-substitution commands rewrite the body,
    // channelAction commands are dispatched to the service and short-circuit.
    final parsed = parseSlashCommand(rawContent);
    if (parsed.isAction) {
      await _runChannelSlashCommand(parsed);
      return;
    }
    final content = parsed.transformedText;
    if (content.isEmpty && _attachments.isEmpty) return;

    setState(() {
      _isSending = true;
    });

    final replyId = _replyToMessage?.id;

    try {
      await _messageService.sendMessage(
        conversationId: widget.conversationId,
        workspaceId: widget.workspaceId,
        senderId: widget.currentUserId,
        senderName: widget.currentUserName,
        content: content,
        attachments: _attachments.map((a) => a.toJson()).toList(),
        replyToId: replyId,
      );

      _replyController.value = TextEditingValue.empty;
      _clearDraft();
      setState(() {
        _attachments.clear();
        _replyToMessage = null;
        _mentionQuery = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Header with conversation info and close button
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: StreamBuilder<Conversation>(
            stream: _conversationStream,
            builder: (context, snapshot) {
              final conversation = snapshot.data;
              // Keep participants list and derived project ID up to date
              if (conversation != null) {
                final updated = conversation.participantNames.entries
                    .where((e) => e.key != widget.currentUserId)
                    .map((e) => {'id': e.key, 'name': e.value})
                    .toList();
                final newProjectId =
                    conversation.scope == 'project' &&
                            conversation.scopeReferenceId != null
                        ? conversation.scopeReferenceId
                        : null;
                final newNames = conversation.participantNames;
                final participantsChanged =
                    updated.length != _participants.length;
                final projectIdChanged = newProjectId != _derivedProjectId;
                final namesChanged = newNames.length != _participantNames.length;
                if (participantsChanged || projectIdChanged || namesChanged) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        if (participantsChanged) _participants = updated;
                        if (namesChanged) _participantNames = newNames;
                        if (projectIdChanged) _derivedProjectId = newProjectId;
                      });
                    }
                  });
                }
              }
              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Subject (inline editable) ──────────────────
                        if (_isEditingSubject)
                          SizedBox(
                            height: 32,
                            child: TextField(
                              controller: _subjectEditController,
                              autofocus: true,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                  vertical: 6,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                suffixIcon: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.check, size: 16),
                                      padding: EdgeInsets.zero,
                                      tooltip: 'Save',
                                      onPressed: () => _saveSubject(),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close, size: 16),
                                      padding: EdgeInsets.zero,
                                      tooltip: 'Cancel',
                                      onPressed: () => setState(
                                        () => _isEditingSubject = false,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              onSubmitted: (_) => _saveSubject(),
                              onTapOutside: (_) => _saveSubject(),
                            ),
                          )
                        else
                          GestureDetector(
                            onTap: () {
                              final current = conversation?.subject ??
                                  conversation?.getOtherParticipantName(
                                    widget.currentUserId,
                                  ) ??
                                  '';
                              _subjectEditController.text = current;
                              setState(() => _isEditingSubject = true);
                            },
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    conversation?.subject ??
                                        conversation?.getOtherParticipantName(
                                          widget.currentUserId,
                                        ) ??
                                        'Conversation',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.edit_outlined,
                                  size: 13,
                                  color: AppColors.textTertiary,
                                ),
                              ],
                            ),
                          ),
                        // ── Participants subtitle ──────────────────────
                        if (conversation != null) ...[
                          Builder(builder: (context) {
                            final isGroup =
                                conversation.participantIds.length > 2;
                            final parts = <String>[];
                            if (isGroup) {
                              parts.add(
                                '${conversation.participantIds.length} participants',
                              );
                            } else if (conversation.subject != null) {
                              final other =
                                  conversation.getOtherParticipantName(
                                    widget.currentUserId,
                                  );
                              if (other.isNotEmpty) parts.add(other);
                            }
                            if (conversation.scope != 'direct' &&
                                conversation.scopeReferenceName != null) {
                              parts.add(conversation.scopeReferenceName!);
                            }
                            final subtitle = parts.join(' · ');
                            if (subtitle.isEmpty) return const SizedBox.shrink();
                            // Participant count is tappable to show details
                            final Widget subtitleWidget = isGroup
                                ? GestureDetector(
                                    onTap: () => _showParticipantsDialog(
                                      context,
                                      conversation,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          subtitle,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            decoration:
                                                TextDecoration.underline,
                                            decorationColor: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : Text(
                                    subtitle,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  );
                            return Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: subtitleWidget,
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.push_pin_outlined, size: 20),
                    tooltip: 'Pinned messages',
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        shape: const RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(16)),
                        ),
                        builder: (_) => DraggableScrollableSheet(
                          initialChildSize: 0.6,
                          minChildSize: 0.3,
                          maxChildSize: 0.9,
                          expand: false,
                          builder: (_, controller) => Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(AppSpacing.base),
                                child: Row(
                                  children: [
                                    const Icon(Icons.push_pin, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Pinned messages',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      icon: const Icon(Icons.close),
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                              Expanded(
                                child: PinnedMessagesPanel(
                                  conversationId: widget.conversationId,
                                  currentUserId: widget.currentUserId,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    style: IconButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _isSearchingMessages
                          ? Icons.search_off
                          : Icons.search,
                      size: 20,
                    ),
                    onPressed: () => setState(() {
                      _isSearchingMessages = !_isSearchingMessages;
                      if (!_isSearchingMessages) _messageSearchQuery = '';
                    }),
                    tooltip: _isSearchingMessages
                        ? 'Close search'
                        : 'Search in conversation',
                    style: IconButton.styleFrom(
                      foregroundColor: _isSearchingMessages
                          ? Theme.of(context).colorScheme.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                  if (widget.showDetailsToggle)
                    IconButton(
                      icon: Icon(
                        _showDetailsPanel ? Icons.info : Icons.info_outline,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _showDetailsPanel = !_showDetailsPanel),
                      tooltip: 'Conversation info',
                      style: IconButton.styleFrom(
                        foregroundColor: _showDetailsPanel
                            ? Theme.of(context).colorScheme.primary
                            : AppColors.textSecondary,
                      ),
                    ),
                  if (widget.onExpand != null)
                    IconButton(
                      icon: Icon(
                        widget.isExpanded
                            ? Icons.close_fullscreen
                            : Icons.open_in_full,
                        size: 18,
                      ),
                      onPressed: widget.onExpand,
                      tooltip: widget.isExpanded ? 'Collapse' : 'Expand',
                      style: IconButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                      ),
                    ),
                  if (widget.onClose != null)
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: widget.onClose,
                      tooltip: 'Close',
                      style: IconButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                      ),
                    ),
                ],
              );
            },
          ),
        ),

        // In-conversation search bar
        if (_isSearchingMessages)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: TextField(
              autofocus: true,
              scrollPadding: EdgeInsets.zero,
              decoration: InputDecoration(
                hintText: 'Search messages...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _messageSearchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () =>
                            setState(() => _messageSearchQuery = ''),
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              onChanged: (value) =>
                  setState(() => _messageSearchQuery = value),
            ),
          ),

        // Chat message list + optional details panel
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    StreamBuilder<List<Message>>(
                      stream: _messagesStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const MessageThreadSkeleton();
                        }
                        if (snapshot.hasError) {
                          return Center(
                            child: SelectableText(
                              UserFacingError.uiMessage(
                                snapshot.error,
                                action: 'load data',
                              ),
                            ),
                          );
                        }

                        // Deduplicate by ID — Supabase realtime can emit the
                        // same row via both the initial fetch and a change
                        // event when a new conversation is first opened.
                        final seen = <String>{};
                        var allMessages = (snapshot.data ?? [])
                            .where((m) => seen.add(m.id))
                            .toList();

                        // Apply search filter if active. Skip deleted
                        // messages — their bubble renders as "This message
                        // was deleted" but the original content is still on
                        // the model, so without this guard search would
                        // surface matches the user can't actually read.
                        if (_isSearchingMessages &&
                            _messageSearchQuery.isNotEmpty) {
                          final q = _messageSearchQuery.toLowerCase();
                          allMessages = allMessages
                              .where(
                                (m) =>
                                    !m.isDeleted &&
                                    (m.content.toLowerCase().contains(q) ||
                                        m.senderName
                                            .toLowerCase()
                                            .contains(q)),
                              )
                              .toList();
                        }

                        // Limit display for performance; show "Load earlier" when truncated
                        final hasEarlier =
                            !_isSearchingMessages &&
                            allMessages.length > _messageDisplayLimit;
                        final messages = hasEarlier
                            ? allMessages.sublist(
                                allMessages.length - _messageDisplayLimit,
                              )
                            : allMessages;

                        // Identify first unread message once
                        if (!_firstUnreadSet && messages.isNotEmpty) {
                          _firstUnreadSet = true;
                          final firstUnread = messages
                              .where(
                                (m) => !m.readBy.contains(widget.currentUserId),
                              )
                              .firstOrNull;
                          _firstUnreadMessageId = firstUnread?.id;
                        }

                        // Mark as read / track new messages while scrolled up
                        if (!_hasMarkedAsRead ||
                            messages.length > _previousMessageCount) {
                          final isNewMessages = _hasMarkedAsRead &&
                              messages.length > _previousMessageCount;
                          final delta =
                              messages.length - _previousMessageCount;
                          _hasMarkedAsRead = true;
                          _previousMessageCount = messages.length;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            _markAsRead();
                            if (!_showScrollToBottom) {
                              _scrollToBottom(animated: false);
                            } else if (isNewMessages && delta > 0) {
                              setState(
                                () => _newMessagesWhileScrolledUp += delta,
                              );
                            }
                          });
                        }

                        if (messages.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.chat_bubble_outline,
                                  size: 48,
                                  color: AppColors.textTertiary,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No messages yet',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Start the conversation below',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        // Build items with date separators + unread separator
                        final items = <Widget>[];
                        if (hasEarlier) {
                          final remaining =
                              allMessages.length - _messageDisplayLimit;
                          items.add(
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.md,
                                ),
                                child: TextButton.icon(
                                  onPressed: () => setState(
                                    () => _messageDisplayLimit += 50,
                                  ),
                                  icon: const Icon(
                                    Icons.expand_less,
                                    size: 18,
                                  ),
                                  label: Text(
                                    'Load $remaining earlier message${remaining == 1 ? '' : 's'}',
                                  ),
                                ),
                              ),
                            ),
                          );
                        }
                        for (int i = 0; i < messages.length; i++) {
                          final message = messages[i];
                          final isMe = message.senderId == widget.currentUserId;

                          // Unread separator before first unread
                          if (message.id == _firstUnreadMessageId &&
                              !message.readBy.contains(widget.currentUserId)) {
                            items.add(const UnreadSeparator());
                          }

                          final showDate =
                              i == 0 ||
                              !_isSameDay(
                                messages[i - 1].timestamp,
                                message.timestamp,
                              );
                          if (showDate) {
                            items.add(
                              _DateSeparator(date: message.timestamp),
                            );
                          }

                          final isFirstInGroup =
                              i == 0 ||
                              messages[i - 1].senderId != message.senderId ||
                              showDate;
                          final isLastInGroup =
                              i == messages.length - 1 ||
                              messages[i + 1].senderId != message.senderId ||
                              (i < messages.length - 1 &&
                                  !_isSameDay(
                                    message.timestamp,
                                    messages[i + 1].timestamp,
                                  ));

                          // Look up reply-to message in list
                          Message? replyTo;
                          if (message.replyToId != null) {
                            try {
                              replyTo = messages.firstWhere(
                                (m) => m.id == message.replyToId,
                              );
                            } catch (_) {}
                          }

                          items.add(
                            MessageBubble(
                              message: message,
                              isMe: isMe,
                              showSenderName: !isMe && isFirstInGroup,
                              isFirstInGroup: isFirstInGroup,
                              isLastInGroup: isLastInGroup,
                              maxWidth: 560,
                              currentUserId: widget.currentUserId,
                              participantNames: _participantNames,
                              replyToMessage: replyTo,
                              onReply: (msg) =>
                                  setState(() => _replyToMessage = msg),
                              onForward: (msg) async {
                                if (_allConversations.isEmpty) {
                                  try {
                                    _allConversations = await _messageService
                                        .getConversations(
                                          workspaceId: widget.workspaceId,
                                          userId: widget.currentUserId,
                                        )
                                        .first;
                                  } catch (_) {}
                                }
                                if (!context.mounted) return;
                                await showForwardDialog(
                                  context: context,
                                  message: msg,
                                  currentUserId: widget.currentUserId,
                                  currentUserName: widget.currentUserName,
                                  workspaceId: widget.workspaceId,
                                  conversations: _allConversations,
                                );
                              },
                            ),
                          );
                        }

                        return ListView(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                          children: items,
                        );
                      },
                    ),
                    // Jump to latest FAB
                    if (_showScrollToBottom)
                      Positioned(
                        bottom: 12,
                        right: _showDetailsPanel ? 296 : 16,
                        child: Badge(
                          isLabelVisible: _newMessagesWhileScrolledUp > 0,
                          label: Text('$_newMessagesWhileScrolledUp'),
                          child: FloatingActionButton.small(
                            onPressed: () {
                              _scrollToBottom();
                              setState(
                                () => _newMessagesWhileScrolledUp = 0,
                              );
                            },
                            tooltip: _newMessagesWhileScrolledUp > 0
                                ? '$_newMessagesWhileScrolledUp new message${_newMessagesWhileScrolledUp == 1 ? '' : 's'}'
                                : 'Jump to latest',
                            child: const Icon(Icons.keyboard_arrow_down),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Details panel (slide in from right)
              if (_showDetailsPanel)
                StreamBuilder<Conversation>(
                  stream: _conversationStream,
                  builder: (ctx, snap) {
                    if (!snap.hasData) return const SizedBox.shrink();
                    return ConversationDetailsPanel(
                      conversation: snap.data!,
                      currentUserId: widget.currentUserId,
                    );
                  },
                ),
            ],
          ),
        ),

        // Typing indicator
        TypingIndicator(typingUserNames: _typingUserNames),

        // Reply preview bar
        if (_replyToMessage != null)
          ReplyPreviewBar(
            message: _replyToMessage!,
            onCancel: () => setState(() => _replyToMessage = null),
          ),

        // Compose area
        Container(
          padding: EdgeInsets.fromLTRB(
            12,
            12,
            12,
            12 + MediaQuery.of(context).padding.bottom,
          ),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 5,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Attachments preview
              if (_attachments.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _attachments.asMap().entries.map((entry) {
                      final index = entry.key;
                      final attachment = entry.value;
                      return Chip(
                        avatar: Icon(
                          attachment.isImage
                              ? Icons.image
                              : Icons.insert_drive_file,
                          size: 16,
                        ),
                        label: Text(
                          attachment.fileName,
                          style: const TextStyle(fontSize: 12),
                        ),
                        deleteIcon: const Icon(Icons.close, size: 14),
                        onDeleted: () {
                          setState(() {
                            _attachments.removeAt(index);
                          });
                        },
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                ),

              // @mention autocomplete overlay
              if (_mentionQuery != null)
                MentionAutocomplete(
                  participants: [
                    if (_participants.length > 1)
                      const {'id': '__everyone__', 'name': 'everyone'},
                    ..._participants,
                  ],
                  query: _mentionQuery!,
                  onSelected: (participant) {
                    final cursor = _replyController.selection.baseOffset;
                    final newText = applyMention(
                      _replyController.text,
                      cursor < 0 ? _replyController.text.length : cursor,
                      participant['name']!,
                    );
                    _replyController.value = TextEditingValue(
                      text: newText,
                      selection: TextSelection.collapsed(
                        offset: newText.length,
                      ),
                    );
                    setState(() => _mentionQuery = null);
                  },
                ),

              // Compose row
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    icon: _isUploading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.attach_file, size: 20),
                    onPressed: (_isSending || _isUploading) ? null : _pickFiles,
                    tooltip: 'Attach files',
                    style: IconButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                    ),
                  ),
                  if (_effectiveProjectId != null)
                    IconButton(
                      icon: const Icon(Icons.photo_library_outlined, size: 20),
                      onPressed: (_isSending || _isUploading)
                          ? null
                          : _pickProjectPhotos,
                      tooltip: 'Attach ${singularProjectTerminology(context.watch<WorkspaceProvider>().projectTerminology).toLowerCase()} photos',
                      style: IconButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                      ),
                    ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: _replyController,
                      scrollPadding: EdgeInsets.zero,
                      decoration: MessagingStyles.roundedComposeDecoration(
                        context,
                        hintText: 'Write a reply...',
                        hintStyle: TextStyle(color: AppColors.textTertiary),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: 10,
                        ),
                        borderRadius: 24,
                        enabled: !_isSending && !_isUploading,
                      ),
                      maxLines: 4,
                      minLines: 1,
                      textInputAction: TextInputAction.send,
                      enabled: !_isSending && !_isUploading,
                      onSubmitted: (_) => _sendReply(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send, size: 18),
                    onPressed: (_isSending || _isUploading) ? null : _sendReply,
                    tooltip: 'Send',
                    style: IconButton.styleFrom(
                      minimumSize: const Size(40, 40),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DateSeparator extends StatelessWidget {
  final DateTime date;
  const _DateSeparator({required this.date});

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(date.year, date.month, date.day);
    final diff = today.difference(messageDay).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat('EEEE').format(date);
    if (date.year == now.year) return DateFormat('MMM d').format(date);
    return DateFormat('MMM d, yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
            child: Text(
              _formatDate(date),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}
