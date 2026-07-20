import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/conversation.dart';
import '../../models/vendor.dart';
import '../../providers/auth_provider.dart';
import '../messages/conversation_empty_state.dart';
import '../messages/conversation_thread_view.dart';
import '../messages/scoped_conversation_list_pane.dart';
import '../messages/scoped_new_conversation_form.dart';

class VendorMessagesTab extends StatefulWidget {
  final Vendor vendor;

  const VendorMessagesTab({super.key, required this.vendor});

  @override
  State<VendorMessagesTab> createState() => _VendorMessagesTabState();
}

class _VendorMessagesTabState extends State<VendorMessagesTab> {
  Conversation? _selectedConversation;
  bool _isCreatingNew = false;
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final userId = authProvider.appUser?.id;
    final userName = authProvider.appUser?.displayName ?? 'Unknown';
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    if (userId == null || workspaceId == null) {
      return const Center(child: Text('Please log in to view messages'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 840;

        if (isCompact) {
          if (_isCreatingNew) {
            return _buildForm(workspaceId, userId, userName, compact: true);
          }
          if (_selectedConversation != null) {
            return _buildThread(workspaceId, userId, userName, compact: true);
          }
          return _buildList(workspaceId, userId, compact: true);
        }

        final hasDetail = _selectedConversation != null || _isCreatingNew;

        Widget detailPane;
        if (_isCreatingNew) {
          detailPane = _buildForm(workspaceId, userId, userName, compact: false);
        } else if (_selectedConversation != null) {
          detailPane =
              _buildThread(workspaceId, userId, userName, compact: false);
        } else {
          detailPane = const ConversationEmptyState();
        }

        Widget body;
        if (_isExpanded && hasDetail) {
          body = detailPane;
        } else {
          body = Row(
            children: [
              SizedBox(
                width: 320,
                child: _buildList(workspaceId, userId, compact: false),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: detailPane),
            ],
          );
        }

        return Material(
          color: Theme.of(context).colorScheme.surface,
          child: body,
        );
      },
    );
  }

  Widget _buildList(String workspaceId, String userId,
      {required bool compact}) {
    return ScopedConversationListPane(
      workspaceId: workspaceId,
      currentUserId: userId,
      scope: 'vendor',
      scopeReferenceId: widget.vendor.id,
      title: 'Vendor Inbox',
      compact: compact,
      selectedConversation: _selectedConversation,
      onSelectConversation: (conversation) {
        setState(() {
          _selectedConversation = conversation;
          _isCreatingNew = false;
          _isExpanded = false;
        });
      },
      onNewConversation: () {
        setState(() {
          _isCreatingNew = true;
          _selectedConversation = null;
          _isExpanded = false;
        });
      },
    );
  }

  Widget _buildForm(String workspaceId, String userId, String userName,
      {required bool compact}) {
    return ScopedNewConversationForm(
      key: const ValueKey('vendor-new-conv'),
      workspaceId: workspaceId,
      currentUserId: userId,
      currentUserName: userName,
      scope: 'vendor',
      scopeReferenceId: widget.vendor.id,
      scopeReferenceName: widget.vendor.companyName,
      compact: compact,
      onClose: () {
        setState(() {
          _isCreatingNew = false;
          _isExpanded = false;
        });
      },
      onConversationCreated: (conversation) {
        setState(() {
          _selectedConversation = conversation;
          _isCreatingNew = false;
        });
      },
      onExpandToggle: !compact ? () => setState(() => _isExpanded = !_isExpanded) : null,
      isExpanded: _isExpanded,
    );
  }

  Widget _buildThread(String workspaceId, String userId, String userName,
      {required bool compact}) {
    return ConversationThreadView(
      key: ValueKey('thread-${_selectedConversation!.id}'),
      conversationId: _selectedConversation!.id,
      workspaceId: workspaceId,
      currentUserId: userId,
      currentUserName: userName,
      showDetailsToggle: !compact,
      onClose: compact
          ? () => setState(() => _selectedConversation = null)
          : () => setState(() {
                _selectedConversation = null;
                _isExpanded = false;
              }),
      onExpand:
          !compact ? () => setState(() => _isExpanded = !_isExpanded) : null,
      isExpanded: _isExpanded,
    );
  }
}
