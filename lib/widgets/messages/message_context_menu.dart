import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/message.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import 'reaction_picker.dart';

enum MessageAction { reply, react, edit, delete, copy, forward, pin, unpin, save, unsave }

class MessageContextMenu extends StatelessWidget {
  final Message message;
  final String currentUserId;
  final bool isDesktop;
  final void Function(MessageAction action)? onAction;
  final void Function(String emoji)? onReact;
  final bool isBookmarked;

  const MessageContextMenu({
    super.key,
    required this.message,
    required this.currentUserId,
    this.isDesktop = false,
    this.onAction,
    this.onReact,
    this.isBookmarked = false,
  });

  bool get _isOwnMessage => message.senderId == currentUserId;
  bool get _isDeleted => message.isDeleted;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Quick reaction bar
          if (!_isDeleted) ...[
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: ['👍', '❤️', '😂', '😮', '😢', '🎉']
                    .map((emoji) => _QuickReaction(
                          emoji: emoji,
                          onTap: () {
                            Navigator.of(context).pop();
                            onReact?.call(emoji);
                          },
                        ))
                    .toList(),
              ),
            ),
            const Divider(height: 1),
          ],
          // Action items
          if (!_isDeleted) ...[
            _MenuItem(
              icon: Icons.reply,
              label: 'Reply',
              onTap: () {
                Navigator.of(context).pop();
                onAction?.call(MessageAction.reply);
              },
            ),
            _MenuItem(
              icon: Icons.emoji_emotions_outlined,
              label: 'React',
              onTap: () async {
                Navigator.of(context).pop();
                final emoji = await showReactionPicker(context);
                if (emoji != null) onReact?.call(emoji);
              },
            ),
            _MenuItem(
              icon: Icons.copy_outlined,
              label: 'Copy',
              onTap: () {
                Navigator.of(context).pop();
                Clipboard.setData(ClipboardData(text: message.content));
                onAction?.call(MessageAction.copy);
              },
            ),
            _MenuItem(
              icon: Icons.forward,
              label: 'Forward',
              onTap: () {
                Navigator.of(context).pop();
                onAction?.call(MessageAction.forward);
              },
            ),
            _MenuItem(
              icon: message.isPinned
                  ? Icons.push_pin
                  : Icons.push_pin_outlined,
              label: message.isPinned ? 'Unpin from conversation' : 'Pin to conversation',
              onTap: () {
                Navigator.of(context).pop();
                onAction?.call(message.isPinned
                    ? MessageAction.unpin
                    : MessageAction.pin);
              },
            ),
            _MenuItem(
              icon: isBookmarked ? Icons.bookmark : Icons.bookmark_border,
              label: isBookmarked ? 'Remove from saved' : 'Save for later',
              onTap: () {
                Navigator.of(context).pop();
                onAction?.call(isBookmarked
                    ? MessageAction.unsave
                    : MessageAction.save);
              },
            ),
          ],
          if (_isOwnMessage && !_isDeleted) ...[
            const Divider(height: 1),
            _MenuItem(
              icon: Icons.edit_outlined,
              label: 'Edit',
              onTap: () {
                Navigator.of(context).pop();
                onAction?.call(MessageAction.edit);
              },
            ),
            _MenuItem(
              icon: Icons.delete_outline,
              label: 'Delete',
              iconColor: AppColors.error,
              labelColor: AppColors.error,
              onTap: () {
                Navigator.of(context).pop();
                onAction?.call(MessageAction.delete);
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickReaction extends StatelessWidget {
  final String emoji;
  final VoidCallback onTap;

  const _QuickReaction({required this.emoji, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        child: Text(emoji, style: const TextStyle(fontSize: 22)),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? labelColor;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: labelColor ?? Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Show message context menu as a modal bottom sheet (mobile) or dialog (desktop)
Future<void> showMessageContextMenu({
  required BuildContext context,
  required Message message,
  required String currentUserId,
  required bool isDesktop,
  void Function(MessageAction)? onAction,
  void Function(String emoji)? onReact,
  bool isBookmarked = false,
}) {
  if (isDesktop) {
    return showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r12)),
        child: MessageContextMenu(
          message: message,
          currentUserId: currentUserId,
          isDesktop: true,
          onAction: onAction,
          onReact: onReact,
          isBookmarked: isBookmarked,
        ),
      ),
    );
  }
  return showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => MessageContextMenu(
      message: message,
      currentUserId: currentUserId,
      onAction: onAction,
      onReact: onReact,
      isBookmarked: isBookmarked,
    ),
  );
}

/// Handle a message action (edit / delete via service)
Future<void> handleMessageAction({
  required BuildContext context,
  required MessageAction action,
  required Message message,
  required String currentUserId,
  void Function()? onEdit, // caller manages edit-mode
}) async {
  final messageService = ServiceLocator.messageService;

  switch (action) {
    case MessageAction.edit:
      onEdit?.call();
      break;

    case MessageAction.delete:
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete message'),
          content: const Text('This message will be shown as deleted to everyone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await messageService.deleteMessage(message.id);
      }
      break;

    case MessageAction.copy:
      // Already handled inline in the menu
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copied to clipboard'),
            duration: Duration(seconds: 1),
          ),
        );
      }
      break;

    case MessageAction.pin:
      try {
        await messageService.pinMessage(
          messageId: message.id,
          userId: currentUserId,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Message pinned'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not pin: $e')),
          );
        }
      }
      break;

    case MessageAction.unpin:
      try {
        await messageService.unpinMessage(message.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Message unpinned'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not unpin: $e')),
          );
        }
      }
      break;

    case MessageAction.save:
      try {
        await messageService.bookmarkMessage(
          messageId: message.id,
          userId: currentUserId,
          workspaceId: message.workspaceId,
          conversationId: message.conversationId,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Saved'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save: $e')),
          );
        }
      }
      break;

    case MessageAction.unsave:
      try {
        await messageService.removeBookmark(
          messageId: message.id,
          userId: currentUserId,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Removed from saved'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not remove: $e')),
          );
        }
      }
      break;

    default:
      break;
  }
}
