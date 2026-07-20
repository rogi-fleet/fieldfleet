import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/module_header.dart';
import '../../widgets/messages/compose_conversation_pane.dart';
import '../../widgets/messages/conversation_filter.dart';
import '../../widgets/messages/conversation_list_pane.dart';
import '../../widgets/messages/conversation_thread_view.dart';

/// Outlook-style desktop inbox layout with split panes
class DesktopInboxLayout extends StatefulWidget {
  final String? selectedConversationId;

  const DesktopInboxLayout({super.key, this.selectedConversationId});

  @override
  State<DesktopInboxLayout> createState() => _DesktopInboxLayoutState();
}

class _DesktopInboxLayoutState extends State<DesktopInboxLayout> {
  ConversationFilter _filter = ConversationFilter.all;
  String? _scopeFilter;
  String? _selectedConversationId;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _selectedConversationId = widget.selectedConversationId;
  }

  @override
  void didUpdateWidget(DesktopInboxLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedConversationId != _selectedConversationId) {
      setState(() {
        _selectedConversationId = widget.selectedConversationId;
      });
    }
  }

  void _selectConversation(String conversationId) {
    setState(() {
      _selectedConversationId = conversationId;
      _isExpanded = false;
    });
    // Update URL
    context.go('/messages/$conversationId');
  }

  void _closeConversation() {
    setState(() {
      _selectedConversationId = null;
      _isExpanded = false;
    });
    context.go('/messages');
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final appUser = authProvider.appUser;
    final workspaceId = appUser?.currentWorkspaceId;

    if (workspaceId == null || appUser == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final listPane = ConversationListPane(
      workspaceId: workspaceId,
      currentUserId: appUser.id,
      selectedConversationId: _selectedConversationId,
      filter: _filter,
      scopeFilter: _scopeFilter,
      onFilterChanged: (f) => setState(() => _filter = f),
      onScopeFilterChanged: (s) => setState(() => _scopeFilter = s),
      onSelectConversation: (id) {
        if (id == 'new') {
          setState(() {
            _selectedConversationId = 'new';
            _isExpanded = false;
          });
        } else {
          _selectConversation(id);
        }
      },
    );

    Widget body;
    if (_selectedConversationId == null) {
      // No selection: full-width list
      body = listPane;
    } else if (_isExpanded) {
      // Expanded: full-width thread/compose
      body = _selectedConversationId == 'new'
          ? _buildComposePane(
              workspaceId,
              appUser.id,
              appUser.displayName ?? 'Unknown',
            )
          : _buildConversationPane(
              _selectedConversationId!,
              workspaceId,
              appUser.id,
              appUser.displayName ?? 'Unknown',
            );
    } else {
      // Split: list on left, thread on right
      body = Row(
        children: [
          SizedBox(width: 350, child: listPane),
          const VerticalDivider(width: 1),
          Expanded(
            child: _selectedConversationId == 'new'
                ? _buildComposePane(
                    workspaceId,
                    appUser.id,
                    appUser.displayName ?? 'Unknown',
                  )
                : _buildConversationPane(
                    _selectedConversationId!,
                    workspaceId,
                    appUser.id,
                    appUser.displayName ?? 'Unknown',
                  ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Column(
        children: [
          const ModuleHeader(
            icon: Icons.forum_outlined,
            title: 'Messages',
            description:
                'Conversations with teammates, customers and vendors.',
          ),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _buildConversationPane(
    String conversationId,
    String workspaceId,
    String currentUserId,
    String currentUserName,
  ) {
    return ConversationThreadView(
      key: ValueKey('thread-$conversationId'),
      conversationId: conversationId,
      workspaceId: workspaceId,
      currentUserId: currentUserId,
      currentUserName: currentUserName,
      onClose: _closeConversation,
      onExpand: () => setState(() => _isExpanded = !_isExpanded),
      isExpanded: _isExpanded,
    );
  }

  Widget _buildComposePane(
    String workspaceId,
    String currentUserId,
    String currentUserName,
  ) {
    return ComposeConversationPane(
      workspaceId: workspaceId,
      currentUserId: currentUserId,
      currentUserName: currentUserName,
      onSent: (id) => _selectConversation(id),
    );
  }
}

