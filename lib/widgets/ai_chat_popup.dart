import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/workspace_provider.dart';
import 'ai_chat_widget.dart';
import 'ai_persona_picker.dart';
import '../theme/theme.dart';

/// Shows the AI chat as a popup overlay
void showAiChatPopup(BuildContext context, {String? initialQuery, String? projectId}) {
  final isMobile = MediaQuery.of(context).size.width < AppBreakpoints.mobile;

  if (isMobile) {
    // Show as bottom sheet on mobile
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AiChatBottomSheet(initialQuery: initialQuery, projectId: projectId),
    );
  } else {
    // Show as dialog on desktop
    showDialog(
      context: context,
      builder: (context) => _AiChatDialog(initialQuery: initialQuery, projectId: projectId),
    );
  }
}

/// Bottom sheet wrapper for mobile
class _AiChatBottomSheet extends StatelessWidget {
  final String? initialQuery;
  final String? projectId;

  const _AiChatBottomSheet({this.initialQuery, this.projectId});

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WorkspaceProvider>().activeWorkspace;
    final personaEmoji = kPersonaAvatarEmojis[ws?.aiPersonaAvatar ?? 'hard_hat'] ?? '🤖';
    final personaName = ws?.aiPersonaName?.isNotEmpty == true ? ws!.aiPersonaName! : 'AI Assistant';

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Text(personaEmoji, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Text(
                      personaName,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Chat widget
              Expanded(child: AiChatWidget(initialQuery: initialQuery, projectId: projectId)),
            ],
          ),
        );
      },
    );
  }
}

/// Dialog wrapper for desktop
class _AiChatDialog extends StatelessWidget {
  final String? initialQuery;
  final String? projectId;

  const _AiChatDialog({this.initialQuery, this.projectId});

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WorkspaceProvider>().activeWorkspace;
    final personaEmoji = kPersonaAvatarEmojis[ws?.aiPersonaAvatar ?? 'hard_hat'] ?? '🤖';
    final personaName = ws?.aiPersonaName?.isNotEmpty == true ? ws!.aiPersonaName! : 'AI Assistant';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r16)),
      child: Container(
        width: 600,
        height: 700,
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(AppSpacing.base),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Text(personaEmoji, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Text(
                    personaName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Chat widget
            Expanded(child: AiChatWidget(initialQuery: initialQuery, projectId: projectId)),
          ],
        ),
      ),
    );
  }
}
