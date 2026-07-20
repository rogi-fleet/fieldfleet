import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/theme.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/task_comment.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../services/service_locator.dart';
import 'mention_input_field.dart';
import 'mention_text.dart';
import 'user_avatar.dart';

/// Widget for displaying and adding task comments
class TaskCommentsWidget extends StatefulWidget {
  final String taskId;
  final String workspaceId;

  const TaskCommentsWidget({
    super.key,
    required this.taskId,
    required this.workspaceId,
  });

  @override
  State<TaskCommentsWidget> createState() => _TaskCommentsWidgetState();
}

class _TaskCommentsWidgetState extends State<TaskCommentsWidget> {
  final dynamic _commentService = ServiceLocator.taskCommentService;
  final dynamic _userService = ServiceLocator.userService;
  final dynamic _memberService = ServiceLocator.workspaceMemberService;
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<MentionInputFieldState> _mentionInputKey = GlobalKey();
  bool _isSending = false;
  final Map<String, AppUser?> _usersCache = {};
  List<AppUser> _workspaceMembers = [];
  List<String> _currentMentionedUserIds = [];
  
  // Cache the stream to prevent re-subscription on rebuilds
  late Stream<List<TaskComment>> _commentsStream;

  @override
  void initState() {
    super.initState();
    _commentsStream = _commentService.getComments(widget.taskId);
    _loadWorkspaceMembers();
  }
  
  Future<void> _loadWorkspaceMembers() async {
    // Listen to workspace members stream and load user details
    _memberService.getWorkspaceMembers(widget.workspaceId).listen((members) async {
      final users = <AppUser>[];
      for (final member in members) {
        final user = await _getUser(member.userId);
        if (user != null) {
          users.add(user);
        }
      }
      if (mounted) {
        setState(() {
          _workspaceMembers = users;
        });
      }
    });
  }
  
  @override
  void didUpdateWidget(TaskCommentsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only recreate stream if taskId changes
    if (oldWidget.taskId != widget.taskId) {
      _commentsStream = _commentService.getComments(widget.taskId);
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<AppUser?> _getUser(String userId) async {
    if (_usersCache.containsKey(userId)) {
      return _usersCache[userId];
    }
    final user = await _userService.getUserById(userId);
    _usersCache[userId] = user;
    return user;
  }

  Future<void> _sendComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty) return;

    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.appUser;
    if (currentUser == null) return;

    setState(() => _isSending = true);

    try {
      await _commentService.addComment(
        taskId: widget.taskId,
        content: content,
        senderId: currentUser.id,
        senderName: currentUser.displayName ?? currentUser.email,
        workspaceId: widget.workspaceId,
        mentionedUserIds: _currentMentionedUserIds,
      );

      _commentController.clear();
      _mentionInputKey.currentState?.clearMentions();
      _currentMentionedUserIds = [];
      
      // Scroll to bottom after adding comment
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add comment: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${timestamp.month}/${timestamp.day}/${timestamp.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Icon(Icons.comment_outlined, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Text(
              'Comments',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Comments list
        Container(
          constraints: const BoxConstraints(maxHeight: 300),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.r12),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            children: [
              // Comments
              Expanded(
                child: StreamBuilder<List<TaskComment>>(
                  stream: _commentsStream,
                  builder: (context, snapshot) {
                    debugPrint('TaskCommentsWidget: taskId=${widget.taskId}, connectionState=${snapshot.connectionState}, hasData=${snapshot.hasData}, hasError=${snapshot.hasError}');
                    if (snapshot.hasError) {
                      debugPrint('TaskCommentsWidget error: ${snapshot.error}');
                    }
                    if (snapshot.hasData) {
                      debugPrint('TaskCommentsWidget: ${snapshot.data!.length} comments found');
                    }
                    
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(AppSpacing.base),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }

                    final comments = snapshot.data ?? [];

                    if (comments.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.chat_bubble_outline,
                                  size: 32, color: AppColors.textTertiary),
                              const SizedBox(height: 8),
                              Text(
                                'No comments yet',
                                style: TextStyle(
                                  color: AppColors.textTertiary,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Add a comment to start the conversation',
                                style: TextStyle(
                                  color: AppColors.textTertiary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      itemCount: comments.length,
                      itemBuilder: (context, index) {
                        final comment = comments[index];
                        return _buildCommentItem(comment);
                      },
                    );
                  },
                ),
              ),

              // Divider
              const Divider(height: 1),

              // Input field
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: MentionInputField(
                        key: _mentionInputKey,
                        controller: _commentController,
                        members: _workspaceMembers,
                        hintText: 'Add a comment... (type @ to mention)',
                        onSubmit: _sendComment,
                        onMentionsChanged: (mentionedIds) {
                          _currentMentionedUserIds = mentionedIds;
                        },
                        enabled: !_isSending,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _isSending ? null : _sendComment,
                      icon: _isSending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              Icons.send,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      tooltip: 'Send',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCommentItem(TaskComment comment) {
    final authProvider = context.read<AuthProvider>();
    final isOwnComment = comment.senderId == authProvider.appUser?.id;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          FutureBuilder<AppUser?>(
            future: _getUser(comment.senderId),
            builder: (context, snapshot) {
              return UserAvatar(
                user: snapshot.data,
                userId: comment.senderId,
                size: AvatarSize.small,
                onTap: null,
              );
            },
          ),
          const SizedBox(width: 10),

          // Comment content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      comment.senderName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    if (isOwnComment) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                        child: const Text(
                          'You',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.info,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Text(
                      _formatTimestamp(comment.timestamp),
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: isOwnComment
                        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.r12),
                    border: Border.all(
                      color: isOwnComment
                          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
                          : AppColors.cardBorder,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MentionText(
                        text: comment.content,
                        style: const TextStyle(fontSize: 13),
                      ),
                      // Display attachments if any
                      if (comment.hasAttachments) ...[
                        const SizedBox(height: 8),
                        _buildAttachmentsList(comment.attachments),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentsList(List<Map<String, dynamic>> attachments) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: attachments.map((attachment) {
        final fileName = attachment['fileName'] as String? ?? 'File';
        final fileUrl = attachment['fileUrl'] as String? ?? '';
        final mimeType = attachment['mimeType'] as String? ?? '';
        final isImage = mimeType.startsWith('image/');
        final thumbnailUrl = attachment['thumbnailUrl'] as String?;

        return InkWell(
          onTap: () => _openAttachment(fileUrl),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 200),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: isImage
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: CachedNetworkImage(
                          imageUrl: thumbnailUrl ?? fileUrl,
                          height: 100,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            height: 60,
                            color: AppColors.cardBorder,
                            child: Center(
                              child: Icon(Icons.broken_image, color: AppColors.textTertiary),
                            ),
                          ),
                          progressIndicatorBuilder: (context, url, progress) => Container(
                            height: 60,
                            color: AppColors.cardBorder,
                            child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        fileName,
                        style: const TextStyle(fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getFileIcon(mimeType),
                        size: 20,
                        color: AppColors.infoDark,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          fileName,
                          style: const TextStyle(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
          ),
        );
      }).toList(),
    );
  }

  IconData _getFileIcon(String mimeType) {
    if (mimeType.startsWith('image/')) return Icons.image;
    if (mimeType == 'application/pdf') return Icons.picture_as_pdf;
    if (mimeType.contains('word') || mimeType.contains('document')) {
      return Icons.description;
    }
    return Icons.insert_drive_file;
  }

  Future<void> _openAttachment(String url) async {
    if (url.isEmpty) return;
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error opening attachment: $e');
    }
  }
}
