import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/conversation.dart';
import '../../../models/project.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/service_locator.dart';
import '../../../theme/theme.dart';
import '../../../widgets/messages/compose_conversation_pane.dart';
import '../../../widgets/messages/conversation_filter.dart';
import '../../../widgets/messages/conversation_list_pane.dart';
import '../../../widgets/messages/conversation_thread_view.dart';

/// Embedded split-pane inbox tab for the project detail screen.
///
/// Desktop (>= 768px): conversation list on the left, thread on the right.
/// Mobile (< 768px): list view that transitions to full-screen thread on tap.
class ProjectMessagesTab extends StatefulWidget {
  final Project project;

  const ProjectMessagesTab({super.key, required this.project});

  @override
  State<ProjectMessagesTab> createState() => _ProjectMessagesTabState();
}

class _ProjectMessagesTabState extends State<ProjectMessagesTab> {
  String? _selectedConversationId;
  ConversationFilter _filter = ConversationFilter.all;
  String? _scopeFilter;
  bool _isExpanded = false;
  bool _autoSelected = false;
  Stream<List<Conversation>>? _conversationsStream;

  @override
  void didUpdateWidget(covariant ProjectMessagesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.project.id != oldWidget.project.id) {
      _selectedConversationId = null;
      _scopeFilter = null;
      _isExpanded = false;
      _autoSelected = false;
      _conversationsStream = null;
    }
  }

  void _ensureStream(String workspaceId, String userId) {
    // Creates the stream once; survives setState rebuilds so the subscription
    // is never dropped and the list updates in real-time.
    _conversationsStream ??= ServiceLocator.messageService
        .getConversationsByScope(
          workspaceId: workspaceId,
          userId: userId,
          scope: 'project',
          scopeReferenceId: widget.project.id,
        );
  }

  void _selectConversation(String id) {
    setState(() {
      _selectedConversationId = id;
      _isExpanded = false;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedConversationId = null;
      _isExpanded = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final appUser = authProvider.appUser;
    final workspaceId = appUser?.currentWorkspaceId;

    if (workspaceId == null || appUser == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 768;

        if (isDesktop) {
          return _buildDesktopLayout(
            workspaceId,
            appUser.id,
            appUser.displayName ?? 'Unknown',
          );
        }
        return _buildMobileLayout(
          workspaceId,
          appUser.id,
          appUser.displayName ?? 'Unknown',
        );
      },
    );
  }

  Widget _buildDesktopLayout(
    String workspaceId,
    String currentUserId,
    String currentUserName,
  ) {
    _ensureStream(workspaceId, currentUserId);
    final stream = _conversationsStream!;

    final listPane = ConversationListPane(
      workspaceId: workspaceId,
      currentUserId: currentUserId,
      selectedConversationId: _selectedConversationId,
      filter: _filter,
      scopeFilter: _scopeFilter,
      onFilterChanged: (f) => setState(() => _filter = f),
      onScopeFilterChanged: (s) => setState(() => _scopeFilter = s),
      onSelectConversation: _selectConversation,
      showScopeFilters: false,
      conversationsStream: stream,
    );

    void onClose() => _clearSelection();
    void onExpand() => setState(() => _isExpanded = !_isExpanded);

    // Auto-select the most recent conversation once the stream loads.
    Widget content = StreamBuilder<List<Conversation>>(
      stream: stream,
      builder: (context, snapshot) {
        if (!_autoSelected &&
            snapshot.hasData &&
            snapshot.data!.isNotEmpty &&
            _selectedConversationId == null) {
          _autoSelected = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _selectConversation(snapshot.data!.first.id);
          });
        }

        if (_isExpanded && _selectedConversationId != null) {
          return _buildRightPane(
            workspaceId,
            currentUserId,
            currentUserName,
            onClose: onClose,
            onExpand: onExpand,
          );
        }

        return Row(
          children: [
            SizedBox(width: 350, child: listPane),
            const VerticalDivider(width: 1),
            Expanded(
              child: _buildRightPane(
                workspaceId,
                currentUserId,
                currentUserName,
                onClose: onClose,
                onExpand: onExpand,
              ),
            ),
          ],
        );
      },
    );

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: content,
    );
  }

  Widget _buildMobileLayout(
    String workspaceId,
    String currentUserId,
    String currentUserName,
  ) {
    // Show thread/compose when a conversation is selected
    if (_selectedConversationId != null) {
      return Column(
        children: [
          // Back button header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    Icons.arrow_back,
                    color: ChromeColors.of(context).scaffoldText,
                  ),
                  onPressed: _clearSelection,
                  tooltip: 'Back to inbox',
                ),
                Text(
                  'Back to inbox',
                  style: TextStyle(
                    fontSize: 14,
                    color: ChromeColors.of(context).scaffoldText,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _buildRightPane(workspaceId, currentUserId, currentUserName),
          ),
        ],
      );
    }

    // Show conversation list
    _ensureStream(workspaceId, currentUserId);
    return ConversationListPane(
      workspaceId: workspaceId,
      currentUserId: currentUserId,
      selectedConversationId: _selectedConversationId,
      filter: _filter,
      scopeFilter: _scopeFilter,
      onFilterChanged: (f) => setState(() => _filter = f),
      onScopeFilterChanged: (s) => setState(() => _scopeFilter = s),
      onSelectConversation: _selectConversation,
      showScopeFilters: false,
      conversationsStream: _conversationsStream,
    );
  }

  Widget _buildRightPane(
    String workspaceId,
    String currentUserId,
    String currentUserName, {
    VoidCallback? onClose,
    VoidCallback? onExpand,
  }) {
    if (_selectedConversationId == null) {
      return _buildEmptyState();
    }

    if (_selectedConversationId == 'new') {
      return ComposeConversationPane(
        workspaceId: workspaceId,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
        defaultScope: 'project',
        defaultScopeReferenceId: widget.project.id,
        defaultScopeReferenceName: widget.project.name,
        projectId: widget.project.id,
        onSent: (id) => _selectConversation(id),
      );
    }

    return ConversationThreadView(
      key: ValueKey('project-thread-${_selectedConversationId!}'),
      conversationId: _selectedConversationId!,
      workspaceId: workspaceId,
      currentUserId: currentUserId,
      currentUserName: currentUserName,
      onClose: onClose,
      onExpand: onExpand,
      isExpanded: _isExpanded,
      projectId: widget.project.id,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.messageAccent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.forum_outlined,
              size: 36,
              color: AppColors.messageAccent,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Select a conversation',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose from the list or start a new message',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
