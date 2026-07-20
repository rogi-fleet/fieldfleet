import 'package:flutter/material.dart';
import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';

/// Dialog for forwarding a message to a selected conversation
class ForwardMessageDialog extends StatefulWidget {
  final Message message;
  final String currentUserId;
  final String currentUserName;
  final String workspaceId;
  final List<Conversation> conversations;

  const ForwardMessageDialog({
    super.key,
    required this.message,
    required this.currentUserId,
    required this.currentUserName,
    required this.workspaceId,
    required this.conversations,
  });

  @override
  State<ForwardMessageDialog> createState() => _ForwardMessageDialogState();
}

class _ForwardMessageDialogState extends State<ForwardMessageDialog> {
  String _search = '';
  bool _forwarding = false;

  List<Conversation> get _filtered {
    if (_search.isEmpty) return widget.conversations;
    final lower = _search.toLowerCase();
    return widget.conversations.where((c) {
      final name = c.getOtherParticipantName(widget.currentUserId).toLowerCase();
      final subject = (c.subject ?? '').toLowerCase();
      return name.contains(lower) || subject.contains(lower);
    }).toList();
  }

  Future<void> _forward(Conversation target) async {
    setState(() => _forwarding = true);
    try {
      await ServiceLocator.messageService.forwardMessage(
        messageId: widget.message.id,
        targetConversationId: target.id,
        workspaceId: widget.workspaceId,
        senderId: widget.currentUserId,
        senderName: widget.currentUserName,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message forwarded'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to forward: $e'),
            backgroundColor: AppColors.error,
          ),
        );
        setState(() => _forwarding = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Text(
                    'Forward message',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Search
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.xs),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search conversations...',
                  prefixIcon: Icon(Icons.search, size: 20),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            // Message preview
            Container(
              margin: const EdgeInsets.all(AppSpacing.md),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                widget.message.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const Divider(height: 1),
            // Conversation list
            Expanded(
              child: _forwarding
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (context, index) {
                        final conv = _filtered[index];
                        final name = conv.getOtherParticipantName(widget.currentUserId);
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 18,
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                            ),
                          ),
                          title: Text(conv.subject ?? name),
                          subtitle: conv.lastMessage != null
                              ? Text(
                                  conv.lastMessage!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : null,
                          onTap: () => _forward(conv),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Show the forward dialog
Future<bool?> showForwardDialog({
  required BuildContext context,
  required Message message,
  required String currentUserId,
  required String currentUserName,
  required String workspaceId,
  required List<Conversation> conversations,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => ForwardMessageDialog(
      message: message,
      currentUserId: currentUserId,
      currentUserName: currentUserName,
      workspaceId: workspaceId,
      conversations: conversations,
    ),
  );
}
