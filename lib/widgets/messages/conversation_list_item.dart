import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../models/conversation.dart';
import '../../models/user.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/project_terminology.dart';
import 'conversation_actions.dart';
import 'conversation_options_menu.dart';

class ConversationListItem extends StatefulWidget {
  final Conversation conversation;
  final String currentUserId;
  final VoidCallback onTap;
  final bool isSelected;

  const ConversationListItem({
    super.key,
    required this.conversation,
    required this.currentUserId,
    required this.onTap,
    this.isSelected = false,
  });

  @override
  State<ConversationListItem> createState() => _ConversationListItemState();
}

class _ConversationListItemState extends State<ConversationListItem> {
  bool _isHovered = false;

  IconData _scopeIcon(String? scope) {
    switch (scope) {
      case 'project':
        return Icons.folder_outlined;
      case 'vendor':
        return Icons.store_outlined;
      case 'customer':
        return Icons.people_outlined;
      case 'direct':
      default:
        return Icons.person_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final otherParticipantName = widget.conversation.getOtherParticipantName(
      widget.currentUserId,
    );
    final otherParticipantIds = widget.conversation.getOtherParticipantIds(
      widget.currentUserId,
    );
    final unreadCount = widget.conversation.getUnreadCount(
      widget.currentUserId,
    );
    final hasUnread = unreadCount > 0;
    final isArchived = widget.conversation.isArchivedBy(widget.currentUserId);
    final isPinned = widget.conversation.isPinnedBy(widget.currentUserId);
    final isMuted = widget.conversation.isMutedBy(widget.currentUserId);
    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary;
    final rowColor = widget.isSelected
        ? primary.withValues(alpha: 0.08)
        : _isHovered
        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
        : colorScheme.surface;
    final rowBorderColor = widget.isSelected ? primary : AppColors.cardBorder;
    final title = widget.conversation.subject?.trim().isNotEmpty == true
        ? widget.conversation.subject!
        : otherParticipantName;
    final singular = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    );
    final scopeLabel = _scopeLabel(widget.conversation.scope, singular);

    return Slidable(
      key: ValueKey('slide_conv_${widget.conversation.id}'),
      startActionPane: ActionPane(
        motion: const BehindMotion(),
        extentRatio: 0.25,
        children: [
          CustomSlidableAction(
            onPressed: (_) => _toggleArchive(context, isArchived),
            backgroundColor: AppColors.info,
            foregroundColor: Colors.white,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isArchived ? Icons.unarchive : Icons.archive_outlined,
                  size: 24,
                ),
                const SizedBox(height: 4),
                Text(
                  isArchived ? 'Unarchive' : 'Archive',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const BehindMotion(),
        extentRatio: 0.65,
        children: [
          CustomSlidableAction(
            onPressed: (_) => _togglePin(context, isPinned),
            backgroundColor: AppColors.messageAccent,
            foregroundColor: Colors.white,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  size: 22,
                ),
                const SizedBox(height: 4),
                Text(
                  isPinned ? 'Unpin' : 'Pin',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          CustomSlidableAction(
            onPressed: (_) => _toggleMute(context, isMuted),
            backgroundColor: AppColors.warning,
            foregroundColor: Colors.white,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isMuted
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                  size: 22,
                ),
                const SizedBox(height: 4),
                Text(
                  isMuted ? 'Unmute' : 'Mute',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          CustomSlidableAction(
            onPressed: (_) => _confirmDelete(context),
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.delete_outline, size: 22),
                SizedBox(height: 4),
                Text(
                  'Delete',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
          decoration: BoxDecoration(
            color: rowColor,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: rowBorderColor,
              width: widget.isSelected ? 2 : 1,
            ),
          ),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            splashColor: primary.withValues(alpha: 0.1),
            highlightColor: primary.withValues(alpha: 0.06),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(top: 4),
                    width: 3,
                    height: 54,
                    decoration: BoxDecoration(
                      color: (widget.isSelected || hasUnread)
                          ? primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (otherParticipantIds.length <= 1)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.all(1.2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: hasUnread
                              ? primary.withValues(alpha: 0.35)
                              : Colors.transparent,
                        ),
                      ),
                      child: _buildAvatar(context),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: _buildAvatar(context),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              // Conversation rows render on colorScheme.surface,
                              // which is dark in dark-chrome mode. Use onSurface
                              // so the title doesn't disappear.
                              child: Text(
                                title,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: hasUnread
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: hasUnread
                                      ? colorScheme.onSurface
                                      : colorScheme.onSurface.withValues(
                                          alpha: 0.88,
                                        ),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (widget.conversation.lastMessageAt != null)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text(
                                  timeago.format(
                                    widget.conversation.lastMessageAt!,
                                    locale: 'en_short',
                                  ),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: hasUnread
                                        ? primary
                                        : AppColors.textTertiary.withValues(
                                            alpha: 0.85,
                                          ),
                                    fontWeight: hasUnread
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        _buildSubtitleWidget(otherParticipantName, hasUnread, primary),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              _scopeIcon(widget.conversation.scope),
                              size: 13,
                              color: hasUnread
                                  ? primary
                                  : AppColors.textTertiary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              scopeLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: hasUnread
                                    ? primary
                                    : AppColors.textSecondary,
                              ),
                            ),
                            if (isPinned)
                              Padding(
                                padding: const EdgeInsets.only(left: 7),
                                child: Icon(
                                  Icons.push_pin,
                                  size: 12,
                                  color: primary,
                                ),
                              ),
                            if (isMuted)
                              Padding(
                                padding: const EdgeInsets.only(left: 7),
                                child: Icon(
                                  Icons.notifications_off_outlined,
                                  size: 12,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            if (isArchived)
                              Padding(
                                padding: const EdgeInsets.only(left: 7),
                                child: Icon(
                                  Icons.archive_outlined,
                                  size: 12,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            const Spacer(),
                            if (hasUnread)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: primary,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  unreadCount > 99
                                      ? '99+'
                                      : unreadCount.toString(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 140),
                      opacity: (_isHovered || widget.isSelected) ? 1 : 0,
                      child: IgnorePointer(
                        ignoring: !(_isHovered || widget.isSelected),
                        child: ConversationOptionsMenu(
                          conversationId: widget.conversation.id,
                          currentUserId: widget.currentUserId,
                          isArchived: isArchived,
                          isPinned: isPinned,
                          isMuted: isMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _toggleArchive(BuildContext context, bool isArchived) {
    HapticFeedback.lightImpact();
    Slidable.of(context)?.close();
    ConversationActions.toggleArchive(
      context: context,
      conversationId: widget.conversation.id,
      userId: widget.currentUserId,
      isArchived: isArchived,
    );
  }

  void _togglePin(BuildContext context, bool isPinned) {
    HapticFeedback.lightImpact();
    Slidable.of(context)?.close();
    ConversationActions.togglePin(
      context: context,
      conversationId: widget.conversation.id,
      userId: widget.currentUserId,
      isPinned: isPinned,
    );
  }

  void _toggleMute(BuildContext context, bool isMuted) {
    HapticFeedback.lightImpact();
    Slidable.of(context)?.close();
    ConversationActions.toggleMute(
      context: context,
      conversationId: widget.conversation.id,
      userId: widget.currentUserId,
      isMuted: isMuted,
    );
  }

  void _confirmDelete(BuildContext context) {
    HapticFeedback.lightImpact();
    Slidable.of(context)?.close();
    ConversationActions.confirmDelete(
      context: context,
      conversationId: widget.conversation.id,
    );
  }

  Widget _buildSubtitleWidget(
    String otherParticipantName,
    bool hasUnread,
    Color primary,
  ) {
    final raw = _buildSubtitle(otherParticipantName);
    // Conversation rows render on colorScheme.surface (dark in dark-chrome
    // mode), so derive the subtitle color from onSurface instead of the
    // hardcoded light-theme tokens.
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final textColor = hasUnread
        ? onSurface.withValues(alpha: 0.88)
        : onSurface.withValues(alpha: 0.62);
    final textWeight =
        hasUnread ? FontWeight.w500 : FontWeight.normal;
    const textStyle = TextStyle(fontSize: 13, height: 1.3);

    // Strip leading 📎 emoji and render a proper Icon instead
    if (raw.startsWith('📎 ')) {
      final label = raw.substring('📎 '.length);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.attach_file, size: 13, color: textColor),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyle.copyWith(
                color: textColor,
                fontWeight: textWeight,
              ),
            ),
          ),
        ],
      );
    }

    return Text(
      raw,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: textStyle.copyWith(color: textColor, fontWeight: textWeight),
    );
  }

  String _buildSubtitle(String otherParticipantName) {
    final lastMessage = widget.conversation.lastMessage?.trim();
    final safeMessage = (lastMessage != null && lastMessage.isNotEmpty)
        ? lastMessage
        : 'No messages yet';

    if (widget.conversation.type == 'group') {
      return safeMessage;
    }
    if (widget.conversation.subject != null) {
      final senderId = widget.conversation.lastMessageSenderId;
      final senderLabel = (senderId == widget.currentUserId)
          ? 'You'
          : otherParticipantName;
      return '$senderLabel: $safeMessage';
    }
    return safeMessage;
  }

  String _scopeLabel(String? scope, String singular) {
    switch (scope) {
      case 'project':
        return singular;
      case 'vendor':
        return 'Vendor';
      case 'customer':
        return 'Customer';
      case 'direct':
      default:
        return 'Direct';
    }
  }

  Widget _buildAvatar(BuildContext context) {
    final otherParticipantIds = widget.conversation.getOtherParticipantIds(
      widget.currentUserId,
    );
    final participantNames = widget.conversation.participantNames;

    if (otherParticipantIds.isEmpty) {
      return CircleAvatar(
        radius: 20,
        backgroundColor: AppColors.cardBorder,
        child: const Icon(Icons.person, size: 20, color: Colors.white),
      );
    }

    // Single participant - show larger avatar
    if (otherParticipantIds.length == 1) {
      final id = otherParticipantIds[0];
      final name = participantNames[id] ?? 'Unknown';
      return _buildLiveCircleAvatar(id, name, 20);
    }

    // Multiple participants - stacked
    const double avatarSize = 24.0;
    const double overlap = 10.0;
    final visibleIds = otherParticipantIds.take(3).toList();
    final overflow = otherParticipantIds.length - 3;
    final stackWidth =
        avatarSize +
        (visibleIds.length - 1) * overlap +
        (overflow > 0 ? overlap : 0);

    return SizedBox(
      width: stackWidth,
      height: avatarSize,
      child: Stack(
        children: [
          for (int i = 0; i < visibleIds.length; i++)
            Positioned(
              left: i * overlap,
              child: Container(
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 1.5,
                  ),
                ),
                child: _buildLiveCircleAvatar(
                  visibleIds[i],
                  participantNames[visibleIds[i]] ?? 'Unknown',
                  avatarSize / 2,
                ),
              ),
            ),
          if (overflow > 0)
            Positioned(
              left: visibleIds.length * overlap,
              child: Container(
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Text(
                    '+$overflow',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLiveCircleAvatar(String userId, String name, double radius) {
    return StreamBuilder<AppUser?>(
      stream: ServiceLocator.userService.getUserStream(userId),
      builder: (context, snapshot) {
        final liveUser = snapshot.data;
        final displayName = liveUser?.displayName ?? name;
        final photoUrl = liveUser?.profilePictureUrl;
        return _buildCircleAvatar(userId, displayName, photoUrl, radius);
      },
    );
  }

  Widget _buildCircleAvatar(
    String id,
    String name,
    String? photoUrl,
    double radius,
  ) {
    final color = _getColorFromId(id);
    final initials = _getInitials(name);

    if (photoUrl != null && photoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: CachedNetworkImageProvider(photoUrl),
        backgroundColor: color,
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.65,
        ),
      ),
    );
  }

  Color _getColorFromId(String id) {
    final hash = id.hashCode;
    final colors = [
      AppColors.info,
      AppColors.success,
      AppColors.warning,
      AppColors.messageAccent,
      AppColors.financialAccent,
      Colors.pink,
      Colors.indigo,
      Colors.cyan,
    ];
    return colors[hash.abs() % colors.length];
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }
}
