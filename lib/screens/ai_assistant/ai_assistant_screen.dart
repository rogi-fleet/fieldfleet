import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/workspace_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/ai_chat_widget.dart';
import '../../widgets/ai_persona_picker.dart';
import '../../widgets/common/module_header.dart';

class AiAssistantScreen extends StatelessWidget {
  const AiAssistantScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WorkspaceProvider>().activeWorkspace;
    final emoji = kPersonaAvatarEmojis[ws?.aiPersonaAvatar ?? 'hard_hat'] ?? '🤖';
    final name = ws?.aiPersonaName?.isNotEmpty == true ? ws!.aiPersonaName! : 'AI Assistant';

    return Scaffold(
      // Content surface — without this the chat renders on the dark chrome
      // background, making the empty-state heading and input bar invisible.
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          ModuleHeader(
            leading: Text(emoji, style: const TextStyle(fontSize: 24)),
            title: name,
            description:
                'Ask anything about your jobs, customers, schedule and data.',
          ),
          const Expanded(child: AiChatWidget()),
        ],
      ),
    );
  }
}
