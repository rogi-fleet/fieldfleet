import 'package:flutter/material.dart';

import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/user_facing_error.dart';

/// Shared archive/pin/mute/delete handlers used by both the
/// kebab popup ([ConversationOptionsMenu]) and the swipe actions on
/// [ConversationListItem]. Centralizes snackbar + error messaging so the
/// two surfaces stay in sync.
class ConversationActions {
  ConversationActions._();

  static Future<void> toggleArchive({
    required BuildContext context,
    required String conversationId,
    required String userId,
    required bool isArchived,
    VoidCallback? onChanged,
  }) {
    final service = ServiceLocator.messageService;
    return _run(
      context: context,
      action: () => isArchived
          ? service.unarchiveConversation(
              conversationId: conversationId,
              userId: userId,
            )
          : service.archiveConversation(
              conversationId: conversationId,
              userId: userId,
            ),
      successMessage: isArchived
          ? 'Conversation unarchived'
          : 'Conversation archived',
      errorAction: 'update conversation',
      onSuccess: onChanged,
    );
  }

  static Future<void> togglePin({
    required BuildContext context,
    required String conversationId,
    required String userId,
    required bool isPinned,
  }) {
    final service = ServiceLocator.messageService;
    return _run(
      context: context,
      action: () => isPinned
          ? service.unpinConversation(
              conversationId: conversationId,
              userId: userId,
            )
          : service.pinConversation(
              conversationId: conversationId,
              userId: userId,
            ),
      successMessage: isPinned
          ? 'Conversation unpinned'
          : 'Conversation pinned',
      errorAction: 'update conversation',
    );
  }

  static Future<void> toggleMute({
    required BuildContext context,
    required String conversationId,
    required String userId,
    required bool isMuted,
  }) {
    final service = ServiceLocator.messageService;
    return _run(
      context: context,
      action: () => isMuted
          ? service.unmuteConversation(
              conversationId: conversationId,
              userId: userId,
            )
          : service.muteConversation(
              conversationId: conversationId,
              userId: userId,
            ),
      successMessage: isMuted ? 'Conversation unmuted' : 'Conversation muted',
      errorAction: 'update conversation',
    );
  }

  static Future<void> confirmDelete({
    required BuildContext context,
    required String conversationId,
    VoidCallback? onDeleted,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: const Text(
          'Are you sure you want to delete this conversation? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    return _run(
      context: context,
      action: () =>
          ServiceLocator.messageService.deleteConversation(conversationId),
      successMessage: 'Conversation deleted',
      errorAction: 'delete conversation',
      onSuccess: onDeleted,
    );
  }

  static Future<void> _run({
    required BuildContext context,
    required Future<void> Function() action,
    required String successMessage,
    required String errorAction,
    VoidCallback? onSuccess,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      onSuccess?.call();
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(successMessage),
            duration: const Duration(seconds: 2),
          ),
        );
    } catch (e) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(UserFacingError.uiMessage(e, action: errorAction)),
            backgroundColor: AppColors.error,
          ),
        );
    }
  }
}
