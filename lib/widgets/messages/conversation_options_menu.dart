import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'conversation_actions.dart';

class ConversationOptionsMenu extends StatelessWidget {
  final String conversationId;
  final String currentUserId;
  final bool isArchived;
  final bool isPinned;
  final bool isMuted;
  final VoidCallback? onArchiveToggle;
  final VoidCallback? onDelete;

  const ConversationOptionsMenu({
    super.key,
    required this.conversationId,
    required this.currentUserId,
    required this.isArchived,
    this.isPinned = false,
    this.isMuted = false,
    this.onArchiveToggle,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (value) {
        switch (value) {
          case 'pin':
            ConversationActions.togglePin(
              context: context,
              conversationId: conversationId,
              userId: currentUserId,
              isPinned: isPinned,
            );
            break;
          case 'mute':
            ConversationActions.toggleMute(
              context: context,
              conversationId: conversationId,
              userId: currentUserId,
              isMuted: isMuted,
            );
            break;
          case 'archive':
            ConversationActions.toggleArchive(
              context: context,
              conversationId: conversationId,
              userId: currentUserId,
              isArchived: isArchived,
              onChanged: onArchiveToggle,
            );
            break;
          case 'delete':
            ConversationActions.confirmDelete(
              context: context,
              conversationId: conversationId,
              onDeleted: onDelete,
            );
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'pin',
          child: Row(
            children: [
              Icon(
                isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                size: 20,
                color: AppColors.textPrimary,
              ),
              const SizedBox(width: 12),
              Text(isPinned ? 'Unpin' : 'Pin'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'mute',
          child: Row(
            children: [
              Icon(
                isMuted
                    ? Icons.notifications
                    : Icons.notifications_off_outlined,
                size: 20,
                color: AppColors.textPrimary,
              ),
              const SizedBox(width: 12),
              Text(isMuted ? 'Unmute' : 'Mute'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'archive',
          child: Row(
            children: [
              Icon(
                isArchived ? Icons.unarchive : Icons.archive,
                size: 20,
                color: AppColors.textPrimary,
              ),
              const SizedBox(width: 12),
              Text(isArchived ? 'Unarchive' : 'Archive'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, size: 20, color: AppColors.errorDark),
              const SizedBox(width: 12),
              Text('Delete', style: TextStyle(color: AppColors.errorDark)),
            ],
          ),
        ),
      ],
    );
  }
}
