import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/messages/compose_conversation_pane.dart';

class NewConversationScreen extends StatelessWidget {
  const NewConversationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appUser = context.watch<AuthProvider>().appUser;
    if (appUser == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: ComposeConversationPane(
        workspaceId: appUser.currentWorkspaceId,
        currentUserId: appUser.id,
        currentUserName: appUser.displayName ?? 'Unknown',
        onSent: (_) => Navigator.of(context).pop(),
      ),
    );
  }
}
