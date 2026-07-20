import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/conversation.dart';
import '../../services/service_locator.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../utils/project_terminology.dart';
import '../../widgets/messaging_popup.dart';
import '../theme/theme.dart';

/// A widget that displays a summary of messages for a specific project
class ProjectMessagingSummaryWidget extends StatefulWidget {
  final String workspaceId;
  final String projectId;
  final String projectName;

  const ProjectMessagingSummaryWidget({
    super.key,
    required this.workspaceId,
    required this.projectId,
    required this.projectName,
  });

  @override
  State<ProjectMessagingSummaryWidget> createState() =>
      _ProjectMessagingSummaryWidgetState();
}

class _ProjectMessagingSummaryWidgetState
    extends State<ProjectMessagingSummaryWidget> {
  Stream<List<Conversation>>? _conversationsStream;
  String? _streamKey;

  Stream<List<Conversation>>? _ensureStream(String? currentUserId) {
    if (currentUserId == null) {
      _streamKey = null;
      _conversationsStream = null;
      return null;
    }
    final key =
        '${widget.workspaceId}|${widget.projectId}|$currentUserId';
    if (key != _streamKey) {
      _streamKey = key;
      _conversationsStream = ServiceLocator.messageService
          .getConversationsByScope(
            workspaceId: widget.workspaceId,
            userId: currentUserId,
            scope: 'project',
            scopeReferenceId: widget.projectId,
          );
    }
    return _conversationsStream;
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.appUser?.id;
    final projectTerminology = context.watch<WorkspaceProvider>().projectTerminology;
    final singular = singularProjectTerminology(projectTerminology);

    if (currentUserId == null) return const SizedBox.shrink();

    final stream = _ensureStream(currentUserId);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.r12),
        side: BorderSide(color: AppColors.cardBorder),
      ),
      child: InkWell(
        onTap: () => showMessagingPopup(context),
        borderRadius: BorderRadius.circular(AppRadius.r12),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StreamBuilder<List<Conversation>>(
                stream: stream,
                builder: (context, snapshot) {
                  // Calculate total unread count
                  int totalUnread = 0;
                  final conversations = snapshot.data ?? [];
                  for (final conv in conversations) {
                    totalUnread += conv.getUnreadCount(currentUserId);
                  }
                  
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: AppColors.messageAccentLight,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Icon(
                              Icons.message_outlined,
                              color: AppColors.messageAccent,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '$singular Messages',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (totalUnread > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: AppSpacing.xs,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.error,
                                borderRadius: BorderRadius.circular(AppRadius.xl),
                              ),
                              child: Text(
                                '$totalUnread unread',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Message count
                      if (snapshot.connectionState == ConnectionState.waiting)
                        const Center(child: CircularProgressIndicator())
                      else if (conversations.isEmpty)
                        Center(
                          child: Text(
                            'No ${singular.toLowerCase()} messages yet',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      else
                        // Show recent conversations
                        ...conversations.take(3).map((conv) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Icon(
                                    conv.getUnreadCount(currentUserId) > 0
                                        ? Icons.mark_email_unread
                                        : Icons.email_outlined,
                                    size: 16,
                                    color: conv.getUnreadCount(currentUserId) > 0
                                        ? AppColors.info
                                        : AppColors.textTertiary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      conv.subject ?? conv.getOtherParticipantName(currentUserId),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: conv.getUnreadCount(currentUserId) > 0
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )),
                      const SizedBox(height: 8),
                      // View all button
                      if (conversations.isNotEmpty)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => showMessagingPopup(context),
                            child: const Text('View All'),
                          ),
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
}
