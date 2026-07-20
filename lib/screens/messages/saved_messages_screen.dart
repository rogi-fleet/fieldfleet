import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/service_locator.dart';
import '../../services/supabase/message_service.dart';
import '../../theme/theme.dart';

/// "Saved" inbox view showing all messages bookmarked by the current user.
class SavedMessagesScreen extends StatelessWidget {
  const SavedMessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final userId = auth.currentUserId;
    final workspaceId = auth.appUser?.currentWorkspaceId;

    if (userId == null || workspaceId == null || workspaceId.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Sign in to see saved messages.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Saved messages')),
      body: StreamBuilder<List<SavedMessage>>(
        stream: ServiceLocator.messageService.streamSavedMessages(
          userId: userId,
          workspaceId: workspaceId,
        ),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const <SavedMessage>[];
          if (items.isEmpty) {
            return _EmptyState();
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final s = items[i];
              return ListTile(
                leading: CircleAvatar(
                  child: Text(
                    s.message.senderName.isNotEmpty
                        ? s.message.senderName[0]
                        : '?',
                  ),
                ),
                title: Text(
                  s.message.senderName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.message.content,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (s.note != null && s.note!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Note: ${s.note!}',
                          style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Saved ${DateFormat.yMMMd().add_jm().format(s.savedAt)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.bookmark, size: 20),
                  tooltip: 'Remove from saved',
                  onPressed: () {
                    ServiceLocator.messageService.removeBookmark(
                      messageId: s.message.id,
                      userId: userId,
                    );
                  },
                ),
                onTap: () {
                  context.push('/messages/${s.conversationId}');
                },
                isThreeLine: true,
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark_border,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No saved messages',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Long-press any message and choose "Save for later" '
              'to keep it here for quick reference.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
