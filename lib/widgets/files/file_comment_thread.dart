import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/file_attachment.dart';
import '../../models/file_comment.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../mention_input_field.dart';
import '../mention_text.dart';
import '../user_avatar.dart';

/// Threaded per-file discussion shown inside [FileDetailPanel].
///
/// Renders top-level comments with optional one-level-deep replies. Uses
/// the existing [MentionInputField] + [MentionText] pair for @mention
/// detection, autocomplete, and highlight rendering. The AI assist row
/// on the composer calls `ai-text-ops` via [SupabaseAiCopilotService].
class FileCommentThread extends StatefulWidget {
  final FileAttachment file;

  /// When set, the matching comment tile pulses briefly when rendered for
  /// the first time — used by the mention-notification deep-link flow.
  final String? highlightCommentId;

  const FileCommentThread({
    super.key,
    required this.file,
    this.highlightCommentId,
  });

  @override
  State<FileCommentThread> createState() => _FileCommentThreadState();
}

class _FileCommentThreadState extends State<FileCommentThread> {
  final _commentService = ServiceLocator.fileCommentService;
  final _userService = ServiceLocator.userService;

  List<AppUser> _members = const [];
  String? _replyingToId;
  String? _highlightCommentId;
  bool _highlightFired = false;

  @override
  void initState() {
    super.initState();
    _highlightCommentId = widget.highlightCommentId;
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final stream =
        _userService.getUsersByWorkspace(widget.file.workspaceId);
    final first = await stream.first;
    if (!mounted) return;
    setState(() => _members = List<AppUser>.from(first));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FileComment>>(
      stream: _commentService.streamComments(widget.file.id),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _errorBox('Could not load comments: ${snapshot.error}');
        }
        final comments = snapshot.data ?? const <FileComment>[];
        final topLevel =
            comments.where((c) => c.parentCommentId == null).toList();
        final childrenByParent = <String, List<FileComment>>{};
        for (final c in comments.where((c) => c.parentCommentId != null)) {
          (childrenByParent[c.parentCommentId!] ??= []).add(c);
        }
        // Once we've seen the highlighted comment in the stream, start a
        // one-shot timer to drop the highlight after a few seconds so the
        // pulse doesn't linger through the session.
        if (!_highlightFired &&
            _highlightCommentId != null &&
            comments.any((c) => c.id == _highlightCommentId)) {
          _highlightFired = true;
          Future.delayed(const Duration(seconds: 3), () {
            if (!mounted) return;
            setState(() => _highlightCommentId = null);
          });
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.forum_outlined,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  comments.isEmpty
                      ? 'Comments'
                      : 'Comments (${comments.length})',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (topLevel.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text(
                  'No comments yet. Start the conversation below.',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
              )
            else
              ...topLevel.map(
                (c) => _CommentTile(
                  comment: c,
                  children: childrenByParent[c.id] ?? const [],
                  members: _members,
                  highlightCommentId: _highlightCommentId,
                  onReply: () => setState(() => _replyingToId = c.id),
                  onDelete: (id) => _commentService.deleteComment(id),
                ),
              ),
            const SizedBox(height: 12),
            _Composer(
              key: ValueKey(_replyingToId ?? 'root'),
              file: widget.file,
              members: _members,
              replyingToId: _replyingToId,
              onCancelReply: () => setState(() => _replyingToId = null),
              onSent: () => setState(() => _replyingToId = null),
            ),
          ],
        );
      },
    );
  }

  Widget _errorBox(String msg) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(msg, style: TextStyle(color: AppColors.error, fontSize: 12)),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final FileComment comment;
  final List<FileComment> children;
  final List<AppUser> members;
  final String? highlightCommentId;
  final VoidCallback onReply;
  final ValueChanged<String> onDelete;

  const _CommentTile({
    required this.comment,
    required this.children,
    required this.members,
    required this.highlightCommentId,
    required this.onReply,
    required this.onDelete,
  });

  AppUser? _userById(String id) =>
      members.where((m) => m.id == id).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final author = _userById(comment.authorId);
    final currentUserId =
        context.read<AuthProvider>().appUser?.id;
    final canDelete = currentUserId == comment.authorId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _renderOne(
            comment: comment,
            author: author,
            indent: 0,
            canReply: true,
            canDelete: canDelete,
            onReply: onReply,
            onDelete: onDelete,
            highlighted: highlightCommentId == comment.id,
          ),
          ...children.map(
            (c) => _renderOne(
              comment: c,
              author: _userById(c.authorId),
              indent: 32,
              canReply: false,
              canDelete: currentUserId == c.authorId,
              onReply: () {},
              onDelete: onDelete,
              highlighted: highlightCommentId == c.id,
            ),
          ),
        ],
      ),
    );
  }

  Widget _renderOne({
    required FileComment comment,
    required AppUser? author,
    required double indent,
    required bool canReply,
    required bool canDelete,
    required VoidCallback onReply,
    required ValueChanged<String> onDelete,
    bool highlighted = false,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      margin: EdgeInsets.only(left: indent, bottom: 8),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: highlighted
            ? AppColors.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(user: author, size: AvatarSize.small),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      author?.displayName ?? 'Unknown',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatTime(comment.createdAt),
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                    if (comment.wasEdited) ...[
                      const SizedBox(width: 6),
                      Text(
                        '(edited)',
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                MentionText(
                  text: comment.body,
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (canReply)
                      _MiniAction(label: 'Reply', onTap: onReply),
                    if (canDelete) ...[
                      const SizedBox(width: 12),
                      _MiniAction(
                        label: 'Delete',
                        color: AppColors.error,
                        onTap: () => onDelete(comment.id),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // NOTE: the old Padding wrapper above is replaced by AnimatedContainer;
  // the closing parentheses of the outer widget are the end of _renderOne.

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

class _MiniAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _MiniAction({required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          color: color ?? AppColors.primary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _Composer extends StatefulWidget {
  final FileAttachment file;
  final List<AppUser> members;
  final String? replyingToId;
  final VoidCallback onCancelReply;
  final VoidCallback onSent;

  const _Composer({
    super.key,
    required this.file,
    required this.members,
    required this.replyingToId,
    required this.onCancelReply,
    required this.onSent,
  });

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final TextEditingController _controller = TextEditingController();
  List<String> _mentioned = const [];
  bool _sending = false;
  bool _aiBusy = false;
  String? _aiMessage;
  bool _aiMessageIsError = false;
  Timer? _aiMessageTimer;

  late final _commentService = ServiceLocator.fileCommentService;
  late final _aiService = ServiceLocator.aiCopilotService;

  @override
  void dispose() {
    _controller.dispose();
    _aiMessageTimer?.cancel();
    super.dispose();
  }

  void _setAiMessage(String message, {bool isError = false}) {
    _aiMessageTimer?.cancel();
    setState(() {
      _aiMessage = message;
      _aiMessageIsError = isError;
    });
    _aiMessageTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _aiMessage = null);
    });
  }

  Future<void> _send() async {
    final body = _controller.text.trim();
    if (body.isEmpty) return;
    final auth = context.read<AuthProvider>().appUser;
    if (auth == null) return;
    setState(() => _sending = true);
    try {
      await _commentService.addComment(
        workspaceId: widget.file.workspaceId,
        fileAttachmentId: widget.file.id,
        authorId: auth.id,
        authorDisplayName: auth.displayName ?? auth.email,
        body: body,
        mentionedUserIds: _mentioned,
        parentCommentId: widget.replyingToId,
        fileTitle: widget.file.title ?? widget.file.fileName,
      );
      _controller.clear();
      _mentioned = const [];
      widget.onSent();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not send: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _runAi(String op, {String? style, String? tone}) async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      _setAiMessage('Type a comment first', isError: true);
      return;
    }
    setState(() => _aiBusy = true);
    try {
      String result;
      switch (op) {
        case 'rewrite':
          result = await _aiService.rewriteText(
            workspaceId: widget.file.workspaceId,
            text: text,
            style: style ?? 'clear',
          );
          break;
        case 'expand':
          result = await _aiService.expandText(
            workspaceId: widget.file.workspaceId,
            text: text,
          );
          break;
        case 'tone':
        default:
          result = await _aiService.toneText(
            workspaceId: widget.file.workspaceId,
            text: text,
            tone: tone ?? 'friendly',
          );
          break;
      }
      if (!mounted) return;
      _controller.text = result;
      _setAiMessage('Updated by AI');
    } catch (e) {
      if (!mounted) return;
      _setAiMessage('AI assist unavailable: $e', isError: true);
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.replyingToId != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(
                  Icons.subdirectory_arrow_right,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Replying',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: widget.onCancelReply,
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        MentionInputField(
          controller: _controller,
          members: widget.members,
          hintText: widget.replyingToId == null
              ? 'Add a comment — type @ to mention'
              : 'Reply — type @ to mention',
          minLines: 2,
          maxLines: 6,
          onMentionsChanged: (ids) => _mentioned = ids,
          onSubmit: _send,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _AiChip(
              label: 'Rewrite',
              icon: Icons.auto_fix_high,
              busy: _aiBusy,
              onTap: () => _runAi('rewrite'),
            ),
            const SizedBox(width: 6),
            _AiChip(
              label: 'Expand',
              icon: Icons.unfold_more,
              busy: _aiBusy,
              onTap: () => _runAi('expand'),
            ),
            const SizedBox(width: 6),
            _AiChip(
              label: 'Tone',
              icon: Icons.tune,
              busy: _aiBusy,
              onTap: _pickToneAndRun,
            ),
            const SizedBox(width: 6),
            _SendChip(
              label: widget.replyingToId == null ? 'Send' : 'Reply',
              busy: _sending,
              onTap: _send,
            ),
          ],
        ),
        if (_aiMessage != null) ...[
          const SizedBox(height: 6),
          Text(
            _aiMessage!,
            style: TextStyle(
              fontSize: 11,
              color: _aiMessageIsError
                  ? AppColors.error
                  : AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _pickToneAndRun() async {
    final tone = await showMenu<String>(
      context: context,
      position: const RelativeRect.fromLTRB(0, 0, 0, 0),
      items: const [
        PopupMenuItem(value: 'friendly', child: Text('Friendly')),
        PopupMenuItem(value: 'formal', child: Text('Formal')),
        PopupMenuItem(value: 'direct', child: Text('Direct')),
      ],
    );
    if (tone == null) return;
    await _runAi('tone', tone: tone);
  }
}

class _AiChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback onTap;

  const _AiChip({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: busy
          ? const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: busy ? null : onTap,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Primary-color twin of [_AiChip] — same dimensions and visual density so
/// it doesn't tower over the AI chips in the row.
class _SendChip extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback onTap;

  const _SendChip({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return ActionChip(
      backgroundColor: primary,
      side: BorderSide(color: primary),
      avatar: busy
          ? const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.send, size: 14, color: Colors.white),
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      onPressed: busy ? null : onTap,
      visualDensity: VisualDensity.compact,
    );
  }
}
