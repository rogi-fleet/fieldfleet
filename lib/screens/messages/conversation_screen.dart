import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/messages/conversation_thread_view.dart';

class ConversationScreen extends StatelessWidget {
  final String conversationId;

  const ConversationScreen({super.key, required this.conversationId});

  @override
  Widget build(BuildContext context) {
    final appUser = context.watch<AuthProvider>().appUser;

    if (appUser == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: ConversationThreadView(
        key: ValueKey('mobile-$conversationId'),
        conversationId: conversationId,
        workspaceId: appUser.currentWorkspaceId,
        currentUserId: appUser.id,
        currentUserName: appUser.displayName ?? 'Unknown',
        showDetailsToggle: false,
        onClose: () => context.pop(),
      ),
    );
  }
}
