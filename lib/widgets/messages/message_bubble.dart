import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/message.dart';
import '../../models/user.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import 'message_context_menu.dart';
import 'message_markdown.dart';

class MessageBubble extends StatefulWidget {
  final Message message;
  final bool isMe;
  final bool showSenderName;
  final bool isFirstInGroup;
  final bool isLastInGroup;
  final double? maxWidth;
  final String? currentUserId;
  /// Called when the user taps Reply in the context menu
  final void Function(Message)? onReply;
  /// Called when the user taps Forward in the context menu
  final void Function(Message)? onForward;
  /// Snapshot of the quoted/replied-to message (optional)
  final Message? replyToMessage;

  /// Map of userId → display name, used for read receipt tooltips.
  final Map<String, String> participantNames;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.showSenderName = false,
    this.isFirstInGroup = true,
    this.isLastInGroup = true,
    this.maxWidth,
    this.currentUserId,
    this.onReply,
    this.onForward,
    this.replyToMessage,
    this.participantNames = const {},
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _isEditing = false;
  late final TextEditingController _editController;
  bool _isBookmarked = false;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController(text: widget.message.content);
    _refreshBookmark();
  }

  Future<void> _refreshBookmark() async {
    final uid = widget.currentUserId;
    if (uid == null) return;
    final saved = await ServiceLocator.messageService
        .isBookmarked(messageId: widget.message.id, userId: uid);
    if (mounted) setState(() => _isBookmarked = saved);
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  Future<void> _saveEdit() async {
    final newContent = _editController.text.trim();
    if (newContent.isEmpty || newContent == widget.message.content) {
      setState(() => _isEditing = false);
      return;
    }
    try {
      await ServiceLocator.messageService.editMessage(
        messageId: widget.message.id,
        newContent: newContent,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save edit: $e')),
        );
      }
    }
    if (mounted) setState(() => _isEditing = false);
  }

  Future<void> _toggleReaction(String emoji) async {
    final userId = widget.currentUserId;
    if (userId == null) return;
    final service = ServiceLocator.messageService;
    final existingUsers = widget.message.reactions[emoji] ?? [];
    if (existingUsers.contains(userId)) {
      await service.removeReaction(
        messageId: widget.message.id,
        emoji: emoji,
        userId: userId,
      );
    } else {
      await service.addReaction(
        messageId: widget.message.id,
        emoji: emoji,
        userId: userId,
      );
    }
  }

  InlineSpan _readReceiptTooltip() {
    final readers = widget.message.readBy
        .where((id) => id != widget.currentUserId)
        .map((id) => widget.participantNames[id] ?? id)
        .toList();
    if (readers.isEmpty) {
      return const TextSpan(text: 'Sent — not yet read');
    }
    return TextSpan(
      text: 'Read by ${readers.join(', ')}',
    );
  }

  void _showImageViewer(BuildContext context, String url, String fileName) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        barrierDismissible: true,
        pageBuilder: (_, __, ___) => Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            title: Text(fileName, style: const TextStyle(fontSize: 14)),
            actions: [
              IconButton(
                icon: const Icon(Icons.download_rounded),
                onPressed: () => launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.externalApplication,
                ),
                tooltip: 'Download',
              ),
            ],
          ),
          body: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  progressIndicatorBuilder: (_, __, progress) => Center(
                    child: CircularProgressIndicator(
                      value: progress.progress,
                      color: Colors.white,
                    ),
                  ),
                  errorWidget: (_, __, ___) => const Icon(
                    Icons.broken_image,
                    size: 64,
                    color: Colors.white54,
                  ),
                ),
              ),
            ),
          ),
        ),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  void _showContextMenu() {
    final userId = widget.currentUserId ?? '';
    showMessageContextMenu(
      context: context,
      message: widget.message,
      currentUserId: userId,
      isDesktop: MediaQuery.of(context).size.width >= 768,
      onReact: _toggleReaction,
      isBookmarked: _isBookmarked,
      onAction: (action) async {
        if (action == MessageAction.edit) {
          setState(() => _isEditing = true);
        } else if (action == MessageAction.reply) {
          widget.onReply?.call(widget.message);
        } else if (action == MessageAction.forward) {
          widget.onForward?.call(widget.message);
        } else {
          await handleMessageAction(
            context: context,
            action: action,
            message: widget.message,
            currentUserId: userId,
          );
          if (action == MessageAction.save || action == MessageAction.unsave) {
            _refreshBookmark();
          }
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Deleted message placeholder
    if (widget.message.isDeleted) {
      return _DeletedMessagePlaceholder(
        isMe: widget.isMe,
        timestamp: widget.message.timestamp,
      );
    }

    // Tighter spacing for grouped messages
    final verticalPadding = widget.isFirstInGroup ? 4.0 : 1.0;

    // Adaptive bubble radius based on position in group
    final topLeft = !widget.isMe && !widget.isFirstInGroup
        ? const Radius.circular(6)
        : const Radius.circular(18);
    final topRight = widget.isMe && !widget.isFirstInGroup
        ? const Radius.circular(6)
        : const Radius.circular(18);
    final bottomLeft = !widget.isMe && !widget.isLastInGroup
        ? const Radius.circular(6)
        : widget.isMe
            ? const Radius.circular(18)
            : const Radius.circular(4);
    final bottomRight = widget.isMe && !widget.isLastInGroup
        ? const Radius.circular(6)
        : widget.isMe
            ? const Radius.circular(4)
            : const Radius.circular(18);

    final hasReactions = widget.message.reactions.isNotEmpty &&
        widget.message.reactions.values.any((v) => v.isNotEmpty);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: verticalPadding,
        bottom: verticalPadding,
      ),
      child: Row(
        mainAxisAlignment: widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!widget.isMe) ...[
            if (widget.isLastInGroup)
              _buildSenderAvatar(colorScheme)
            else
              const SizedBox(width: 28),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: _showContextMenu,
              onSecondaryTap: _showContextMenu, // right-click on desktop
              child: Column(
                crossAxisAlignment:
                    widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (widget.showSenderName && !widget.isMe)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 4),
                      child: Text(
                        widget.message.senderName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  Container(
                    constraints: BoxConstraints(
                      maxWidth: widget.maxWidth ?? MediaQuery.of(context).size.width * 0.7,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: widget.isMe
                          ? colorScheme.primary
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.only(
                        topLeft: topLeft,
                        topRight: topRight,
                        bottomLeft: bottomLeft,
                        bottomRight: bottomRight,
                      ),
                      boxShadow: widget.isMe
                          ? [
                              BoxShadow(
                                color: colorScheme.primary.withValues(alpha: 0.2),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                    ),
                    child: Column(
                      crossAxisAlignment: widget.isMe
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        // Quoted reply preview
                        if (widget.replyToMessage != null)
                          _QuotedMessage(
                            message: widget.replyToMessage!,
                            isMe: widget.isMe,
                          ),

                        // Show attachments if any
                        if (widget.message.hasAttachments) ...[
                          ...widget.message.attachments.map((attachment) {
                            if (attachment.isImage) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(AppRadius.sm),
                                  child: GestureDetector(
                                    onTap: () => _showImageViewer(
                                      context,
                                      attachment.fileUrl,
                                      attachment.fileName,
                                    ),
                                    child: CachedNetworkImage(
                                      imageUrl: attachment.thumbnailUrl ?? attachment.fileUrl,
                                      fit: BoxFit.cover,
                                      width: 200,
                                      progressIndicatorBuilder: (context, url, progress) =>
                                          SizedBox(
                                            width: 200,
                                            height: 150,
                                            child: Center(
                                              child: CircularProgressIndicator(value: progress.progress),
                                            ),
                                          ),
                                      errorWidget: (context, url, error) => Container(
                                        width: 200,
                                        height: 150,
                                        color: AppColors.cardBorder,
                                        child: const Icon(Icons.broken_image, size: 48),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            } else {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: widget.isMe
                                        ? Colors.white.withValues(alpha: 0.15)
                                        : AppColors.surfaceAlt,
                                    borderRadius: BorderRadius.circular(AppRadius.md),
                                    border: Border(
                                      left: BorderSide(
                                        width: 3,
                                        color: widget.isMe
                                            ? Colors.white.withValues(alpha: 0.5)
                                            : colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: widget.isMe
                                              ? Colors.white.withValues(alpha: 0.2)
                                              : colorScheme.primary.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(AppRadius.sm),
                                        ),
                                        child: Icon(
                                          attachment.isPdf
                                              ? Icons.picture_as_pdf_rounded
                                              : Icons.insert_drive_file_rounded,
                                          color: widget.isMe
                                              ? Colors.white
                                              : colorScheme.primary,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Flexible(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              attachment.fileName,
                                              style: TextStyle(
                                                color: widget.isMe
                                                    ? Colors.white
                                                    : AppColors.textPrimary,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              attachment.formattedSize,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: widget.isMe
                                                    ? Colors.white70
                                                    : AppColors.textTertiary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      IconButton(
                                        icon: Icon(
                                          Icons.download_rounded,
                                          color: widget.isMe
                                              ? Colors.white
                                              : colorScheme.primary,
                                          size: 20,
                                        ),
                                        onPressed: () => launchUrl(
                                          Uri.parse(attachment.fileUrl),
                                          mode: LaunchMode.externalApplication,
                                        ),
                                        splashRadius: 18,
                                        constraints: const BoxConstraints(
                                          minWidth: 32,
                                          minHeight: 32,
                                        ),
                                        padding: EdgeInsets.zero,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }
                          }),
                        ],

                        // Inline edit mode
                        if (_isEditing)
                          _InlineEdit(
                            controller: _editController,
                            isMe: widget.isMe,
                            onSave: _saveEdit,
                            onCancel: () => setState(() => _isEditing = false),
                          )
                        else ...[
                          if (widget.message.content.isNotEmpty)
                            MessageMarkdown(
                              content: widget.message.content,
                              textColor: widget.isMe
                                  ? colorScheme.onPrimary
                                  : colorScheme.onSurfaceVariant,
                              codeBackground: widget.isMe
                                  ? Colors.white.withValues(alpha: 0.18)
                                  : colorScheme.surface,
                              codeForeground: widget.isMe
                                  ? Colors.white
                                  : colorScheme.onSurface,
                              linkColor: widget.isMe
                                  ? Colors.white
                                  : colorScheme.primary,
                              mentionBackground: widget.isMe
                                  ? Colors.white.withValues(alpha: 0.2)
                                  : colorScheme.primary.withValues(alpha: 0.12),
                              mentionForeground: widget.isMe
                                  ? Colors.white
                                  : colorScheme.primary,
                            ),
                        ],
                        if (widget.message.isPinned ||
                            widget.message.hasThreadReplies) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            children: [
                              if (widget.message.isPinned)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.push_pin,
                                      size: 12,
                                      color: widget.isMe
                                          ? Colors.white.withValues(alpha: 0.85)
                                          : colorScheme.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Pinned',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: widget.isMe
                                            ? Colors.white.withValues(alpha: 0.85)
                                            : colorScheme.primary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              if (widget.message.hasThreadReplies)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.forum_outlined,
                                      size: 12,
                                      color: widget.isMe
                                          ? Colors.white.withValues(alpha: 0.85)
                                          : colorScheme.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${widget.message.threadReplyCount} '
                                      '${widget.message.threadReplyCount == 1 ? "reply" : "replies"}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: widget.isMe
                                            ? Colors.white.withValues(alpha: 0.85)
                                            : colorScheme.primary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 4),
                        // Timestamp + edited label + read indicator
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.message.isEdited)
                              Text(
                                'edited · ',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontStyle: FontStyle.italic,
                                  color: widget.isMe
                                      ? colorScheme.onPrimary.withValues(alpha: 0.6)
                                      : colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.6),
                                ),
                              ),
                            Text(
                              DateFormat('h:mm a').format(widget.message.timestamp),
                              style: TextStyle(
                                fontSize: 10,
                                color: widget.isMe
                                    ? colorScheme.onPrimary.withValues(alpha: 0.7)
                                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                              ),
                            ),
                            if (widget.isMe) ...[
                              const SizedBox(width: 4),
                              Tooltip(
                                richMessage: _readReceiptTooltip(),
                                child: Icon(
                                  Icons.done_all,
                                  size: 12,
                                  color: widget.message.readBy.length > 1
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Reaction chips below bubble
                  if (hasReactions)
                    _ReactionChips(
                      reactions: widget.message.reactions,
                      currentUserId: widget.currentUserId ?? '',
                      onToggle: _toggleReaction,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSenderAvatar(ColorScheme colorScheme) {
    return StreamBuilder<AppUser?>(
      stream: ServiceLocator.userService.getUserStream(widget.message.senderId),
      builder: (context, snapshot) {
        final photoUrl = snapshot.data?.profilePictureUrl;
        if (photoUrl != null && photoUrl.isNotEmpty) {
          return CircleAvatar(
            radius: 14,
            backgroundImage: CachedNetworkImageProvider(photoUrl),
          );
        }

        return CircleAvatar(
          radius: 14,
          backgroundColor: colorScheme.primaryContainer,
          child: Text(
            widget.message.senderName.substring(0, 1).toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Inline edit widget
// ---------------------------------------------------------------------------
class _InlineEdit extends StatelessWidget {
  final TextEditingController controller;
  final bool isMe;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  const _InlineEdit({
    required this.controller,
    required this.isMe,
    required this.onSave,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 6,
          style: TextStyle(
            color: isMe ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
            fontSize: 16,
          ),
          decoration: InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
            hintStyle: TextStyle(
              color: (isMe ? colorScheme.onPrimary : colorScheme.onSurfaceVariant)
                  .withValues(alpha: 0.5),
            ),
          ),
          onSubmitted: (_) => onSave(),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                minimumSize: Size.zero,
                foregroundColor: isMe
                    ? colorScheme.onPrimary.withValues(alpha: 0.7)
                    : colorScheme.onSurfaceVariant,
              ),
              child: const Text('Cancel', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: onSave,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                minimumSize: Size.zero,
                backgroundColor: isMe
                    ? Colors.white.withValues(alpha: 0.25)
                    : null,
                foregroundColor: isMe ? colorScheme.onPrimary : null,
              ),
              child: const Text('Save', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Quoted/reply message preview inside bubble
// ---------------------------------------------------------------------------
class _QuotedMessage extends StatelessWidget {
  final Message message;
  final bool isMe;

  const _QuotedMessage({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseColor = isMe ? colorScheme.onPrimary : colorScheme.onSurfaceVariant;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: baseColor.withValues(alpha: 0.5),
            width: 3,
          ),
        ),
        color: baseColor.withValues(alpha: 0.08),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(6),
          bottomRight: Radius.circular(6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.senderName,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: baseColor.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            message.isDeleted ? 'This message was deleted' : message.content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: baseColor.withValues(alpha: 0.7),
              fontStyle: message.isDeleted ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reaction chips
// ---------------------------------------------------------------------------
class _ReactionChips extends StatelessWidget {
  final Map<String, List<String>> reactions;
  final String currentUserId;
  final void Function(String emoji) onToggle;

  const _ReactionChips({
    required this.reactions,
    required this.currentUserId,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final chips = <Widget>[];

    for (final entry in reactions.entries) {
      final emoji = entry.key;
      final users = entry.value;
      if (users.isEmpty) continue;
      final iReacted = users.contains(currentUserId);

      chips.add(
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onToggle(emoji),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                color: iReacted
                    ? colorScheme.primary.withValues(alpha: 0.1)
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(
                  color: iReacted
                      ? colorScheme.primary
                      : colorScheme.outline.withValues(alpha: 0.2),
                  width: 1.5,
                ),
              ),
              child: Text(
                '$emoji ${users.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: iReacted ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(spacing: 4, runSpacing: 4, children: chips),
    );
  }
}

// ---------------------------------------------------------------------------
// Deleted message placeholder
// ---------------------------------------------------------------------------
class _DeletedMessagePlaceholder extends StatelessWidget {
  final bool isMe;
  final DateTime timestamp;

  const _DeletedMessagePlaceholder({required this.isMe, required this.timestamp});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: 2),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppRadius.r16),
              border: Border.all(
                color: colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.block,
                  size: 14,
                  color: colorScheme.onSurface.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 6),
                Text(
                  'This message was deleted',
                  style: TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
