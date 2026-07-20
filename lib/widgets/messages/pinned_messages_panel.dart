import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/message.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';

/// A panel listing all pinned messages for a conversation.
class PinnedMessagesPanel extends StatelessWidget {
  final String conversationId;
  final String currentUserId;
  final void Function(Message)? onJumpTo;

  const PinnedMessagesPanel({
    super.key,
    required this.conversationId,
    required this.currentUserId,
    this.onJumpTo,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Message>>(
      stream: ServiceLocator.messageService.streamPinnedMessages(conversationId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final pinned = snap.data ?? const <Message>[];
        if (pinned.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.push_pin_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No pinned messages yet',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Long-press any message and choose "Pin to conversation".',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          itemCount: pinned.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final m = pinned[i];
            return ListTile(
              leading: CircleAvatar(
                child: Text(m.senderName.isNotEmpty ? m.senderName[0] : '?'),
              ),
              title: Text(
                m.senderName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                m.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    DateFormat('MMM d').format(m.timestamp),
                    style: const TextStyle(fontSize: 11),
                  ),
                  IconButton(
                    icon: const Icon(Icons.push_pin, size: 18),
                    tooltip: 'Unpin',
                    onPressed: () =>
                        ServiceLocator.messageService.unpinMessage(m.id),
                  ),
                ],
              ),
              onTap: onJumpTo == null ? null : () => onJumpTo!(m),
            );
          },
        );
      },
    );
  }
}
