import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/conversation.dart';
import '../../services/service_locator.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/messaging_popup.dart';
import '../../theme/theme.dart';

class MessagingSummaryWidget extends StatelessWidget {
  final String workspaceId;

  const MessagingSummaryWidget({
    super.key,
    required this.workspaceId,
  });

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.appUser?.id;
    final messageService = ServiceLocator.messageService;

    if (currentUserId == null) return const SizedBox.shrink();

    return Card(
      child: InkWell(
        onTap: () => showMessagingPopup(context),
        borderRadius: AppRadius.cardRadius,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StreamBuilder<List<Conversation>>(
                stream: messageService.getConversations(
                  workspaceId: workspaceId,
                  userId: currentUserId,
                ),
                builder: (context, snapshot) {
                  // Calculate total unread count
                  int totalUnread = 0;
                  if (snapshot.hasData) {
                    for (final conv in snapshot.data!) {
                      totalUnread += conv.getUnreadCount(currentUserId);
                    }
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.messageAccentLight,
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                            ),
                            child: const Icon(
                              Icons.message_outlined,
                              color: AppColors.messageAccent,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.iconGap),
                          const Expanded(
                            child: Text(
                              'Inbox',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (totalUnread > 0)
                            Flexible(
                              child: Container(
                                margin: const EdgeInsets.only(right: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.xs),
                                decoration: BoxDecoration(
                                  color: AppColors.messageAccent,
                                  borderRadius: BorderRadius.circular(AppRadius.full),
                                ),
                                child: Text(
                                  '$totalUnread unread',
                                  style: const TextStyle(
                                    color: AppColors.textOnPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => showMessagingPopup(context),
                            child: const Text('View All'),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.base),

                      // Conversations list
                      _buildConversationsList(
                        context,
                        snapshot,
                        currentUserId,
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConversationsList(
    BuildContext context,
    AsyncSnapshot<List<Conversation>> snapshot,
    String currentUserId,
  ) {
    if (snapshot.hasError) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: const Text(
          'Unable to load messages',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    if (!snapshot.hasData) {
      return const SizedBox(
        height: 60,
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final conversations = snapshot.data!;
    if (conversations.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sectionGap),
        child: Center(
          child: Column(
            children: [
              const Icon(
                Icons.inbox_outlined,
                size: 40,
                color: AppColors.cardBorder,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'No messages yet',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Take top 3 conversations
    final displayConversations = conversations.take(3).toList();

    return Column(
      children: displayConversations.map((conversation) {
        final unreadCount = conversation.getUnreadCount(currentUserId);
        final otherName = conversation.getOtherParticipantName(currentUserId);
        final hasUnread = unreadCount > 0;

        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          padding: const EdgeInsets.all(AppSpacing.iconGap),
          decoration: BoxDecoration(
            color: hasUnread ? AppColors.messageAccentLight : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: hasUnread ? AppColors.messageAccent.withValues(alpha: 0.3) : AppColors.cardBorder,
            ),
          ),
          child: Row(
            children: [
              // Unread indicator dot
              if (hasUnread) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.messageAccent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
              ],

              // Avatar placeholder
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.messageAccentLight,
                child: Text(
                  otherName.isNotEmpty ? otherName[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: AppColors.messageAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.iconGap),

              // Name and last message
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      otherName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
                        color: hasUnread ? AppColors.messageAccentDark : AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (conversation.lastMessage != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        conversation.lastMessage!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              // Unread badge or chevron
              if (unreadCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: AppColors.messageAccent,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: Text(
                    unreadCount.toString(),
                    style: const TextStyle(
                      color: AppColors.textOnPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                )
              else
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: AppColors.textTertiary,
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
