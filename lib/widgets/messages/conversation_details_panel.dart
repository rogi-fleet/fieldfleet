import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../models/conversation.dart';
import '../../models/user.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import 'media_gallery.dart';

/// A slide-in details panel for a conversation (desktop side panel / mobile full page)
class ConversationDetailsPanel extends StatefulWidget {
  final Conversation conversation;
  final String currentUserId;
  final bool isModal; // true = mobile full page, false = desktop side panel

  const ConversationDetailsPanel({
    super.key,
    required this.conversation,
    required this.currentUserId,
    this.isModal = false,
  });

  @override
  State<ConversationDetailsPanel> createState() => _ConversationDetailsPanelState();
}

class _ConversationDetailsPanelState extends State<ConversationDetailsPanel> {
  bool _showMedia = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final conversation = widget.conversation;
    final isPinned = conversation.isPinnedBy(widget.currentUserId);
    final isMuted = conversation.isMutedBy(widget.currentUserId);
    final isArchived = conversation.isArchivedBy(widget.currentUserId);

    final content = CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              // Title
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Text(
                  conversation.subject ??
                      conversation.getOtherParticipantName(widget.currentUserId),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              // Quick actions
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _QuickAction(
                      icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                      label: isPinned ? 'Unpin' : 'Pin',
                      isActive: isPinned,
                      onTap: () async {
                        final svc = ServiceLocator.messageService;
                        if (isPinned) {
                          await svc.unpinConversation(
                            conversationId: conversation.id,
                            userId: widget.currentUserId,
                          );
                        } else {
                          await svc.pinConversation(
                            conversationId: conversation.id,
                            userId: widget.currentUserId,
                          );
                        }
                      },
                    ),
                    _QuickAction(
                      icon: isMuted
                          ? Icons.notifications
                          : Icons.notifications_off_outlined,
                      label: isMuted ? 'Unmute' : 'Mute',
                      isActive: isMuted,
                      onTap: () async {
                        final svc = ServiceLocator.messageService;
                        if (isMuted) {
                          await svc.unmuteConversation(
                            conversationId: conversation.id,
                            userId: widget.currentUserId,
                          );
                        } else {
                          await svc.muteConversation(
                            conversationId: conversation.id,
                            userId: widget.currentUserId,
                          );
                        }
                      },
                    ),
                    _QuickAction(
                      icon: isArchived ? Icons.unarchive : Icons.archive_outlined,
                      label: isArchived ? 'Unarchive' : 'Archive',
                      onTap: () async {
                        final svc = ServiceLocator.messageService;
                        if (isArchived) {
                          await svc.unarchiveConversation(
                            conversationId: conversation.id,
                            userId: widget.currentUserId,
                          );
                        } else {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Archive conversation?'),
                              content: const Text(
                                'You can unarchive it at any time from the conversation details.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(ctx).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.of(ctx).pop(true),
                                  child: const Text('Archive'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            await svc.archiveConversation(
                              conversationId: conversation.id,
                              userId: widget.currentUserId,
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),

              const Divider(),

              // Participants header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Text(
                      'Participants (${conversation.participantIds.length})',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Participant list
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final id = conversation.participantIds[index];
              final name = conversation.participantNames[id] ?? 'Unknown';
              final isCurrentUser = id == widget.currentUserId;

              return ListTile(
                dense: true,
                leading: _buildParticipantAvatar(colorScheme, id, name),
                title: Text(
                  isCurrentUser ? '$name (you)' : name,
                  style: const TextStyle(fontSize: 13),
                ),
              );
            },
            childCount: conversation.participantIds.length,
          ),
        ),

        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(),

              // Media section
              InkWell(
                onTap: () => setState(() => _showMedia = !_showMedia),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
                  child: Row(
                    children: [
                      const Icon(Icons.image_outlined, size: 20),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Shared media & files',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(
                        _showMedia ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),

              if (_showMedia)
                SizedBox(
                  height: 320,
                  child: MediaGallery(conversationId: conversation.id),
                ),

              const Divider(),

              // Conversation metadata
              Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Created ${timeago.format(conversation.createdAt)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    if (conversation.scope != 'direct') ...[
                      const SizedBox(height: 4),
                      Text(
                        'Scope: ${conversation.scope}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (widget.isModal) {
      return Scaffold(
        appBar: AppBar(title: const Text('Conversation info')),
        body: content,
      );
    }

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          left: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: content,
    );
  }

  Widget _buildParticipantAvatar(
    ColorScheme colorScheme,
    String userId,
    String name,
  ) {
    return StreamBuilder<AppUser?>(
      stream: ServiceLocator.userService.getUserStream(userId),
      builder: (context, snapshot) {
        final liveUser = snapshot.data;
        final photoUrl = liveUser?.profilePictureUrl;
        final initialsSource = liveUser?.displayName ?? name;

        if (photoUrl != null && photoUrl.isNotEmpty) {
          return CircleAvatar(
            radius: 16,
            backgroundImage: CachedNetworkImageProvider(photoUrl),
          );
        }

        return CircleAvatar(
          radius: 16,
          backgroundColor: colorScheme.primaryContainer,
          child: Text(
            initialsSource.isNotEmpty ? initialsSource[0].toUpperCase() : '?',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
        );
      },
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isActive
                  ? colorScheme.primaryContainer
                  : colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 20,
              color: isActive ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isActive ? colorScheme.primary : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
