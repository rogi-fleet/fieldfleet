import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/conversation.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/project_terminology.dart';
import '../../utils/user_facing_error.dart';
import '../common/view_icon_button.dart';
import 'conversation_filter.dart';
import 'conversation_list_item.dart';
import 'conversation_list_skeleton.dart';

/// Reusable conversation list pane with a search icon, scope icon row, a
/// status filter popup menu, and a compose button. Used in the standalone
/// inbox, the messaging popup, and the embedded project messages tab.
class ConversationListPane extends StatefulWidget {
  final String workspaceId;
  final String currentUserId;
  final String? selectedConversationId;
  final ConversationFilter filter;
  final String? scopeFilter;
  final ValueChanged<ConversationFilter> onFilterChanged;
  final ValueChanged<String?> onScopeFilterChanged;
  final ValueChanged<String> onSelectConversation;

  /// Whether to show the scope filter row (All / Direct / Projects / …).
  final bool showScopeFilters;

  /// Whether to show the compose button at the bottom.
  final bool showComposeButton;

  /// Optional override stream. When provided the pane uses this stream instead
  /// of `getConversations()`. Useful for pre-filtering to a project scope.
  final Stream<List<Conversation>>? conversationsStream;

  const ConversationListPane({
    super.key,
    required this.workspaceId,
    required this.currentUserId,
    required this.selectedConversationId,
    required this.filter,
    required this.scopeFilter,
    required this.onFilterChanged,
    required this.onScopeFilterChanged,
    required this.onSelectConversation,
    this.showScopeFilters = true,
    this.showComposeButton = true,
    this.conversationsStream,
  });

  @override
  State<ConversationListPane> createState() => _ConversationListPaneState();
}

class _ConversationListPaneState extends State<ConversationListPane> {
  bool _searchExpanded = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounce;
  String _searchQuery = '';
  Set<String> _messageMatchConversationIds = const {};
  int _searchToken = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _expandSearch() {
    setState(() => _searchExpanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _collapseSearch() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() {
      _searchExpanded = false;
      _searchQuery = '';
      _messageMatchConversationIds = const {};
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _runMessageContentSearch(value);
    });
    setState(() => _searchQuery = value);
  }

  Future<void> _runMessageContentSearch(String query) async {
    final trimmed = query.trim();
    final token = ++_searchToken;
    if (trimmed.isEmpty) {
      if (!mounted) return;
      setState(() => _messageMatchConversationIds = const {});
      return;
    }
    final messages = await ServiceLocator.messageService.searchMessages(
      workspaceId: widget.workspaceId,
      userId: widget.currentUserId,
      query: trimmed,
    );
    if (!mounted || token != _searchToken) return;
    setState(() {
      _messageMatchConversationIds = {
        for (final m in messages) m.conversationId,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final messageService = ServiceLocator.messageService;
    final projectTerminology =
        context.watch<WorkspaceProvider>().projectTerminology;
    final singular = singularProjectTerminology(projectTerminology);

    return StreamBuilder<List<Conversation>>(
      stream: widget.conversationsStream ??
          messageService.getConversations(
            workspaceId: widget.workspaceId,
            userId: widget.currentUserId,
          ),
      builder: (context, snapshot) {
        final allConversations = snapshot.data ?? const <Conversation>[];

        // Scope-filtered set: drives both the body list and the inline
        // search so results stay within the active scope (or the
        // pre-filtered conversationsStream when one is provided).
        final scopedConversations = widget.scopeFilter == null
            ? allConversations
            : allConversations
                .where((c) => c.scope == widget.scopeFilter)
                .toList();

        final hasSearchableConversations = scopedConversations.isNotEmpty;
        final searchHint = MediaQuery.of(context).size.width < AppBreakpoints.mobile
            ? 'Search messages'
            : 'Search conversations and messages';

        return Column(
          children: [
            // Header with search, scope icons, and filter menu
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Row(
                children: _searchExpanded
                    ? _buildExpandedSearchRow(context, searchHint)
                    : _buildCollapsedHeaderRow(
                        context,
                        projectTerminology,
                        hasSearchableConversations,
                      ),
              ),
            ),

            // Conversation List
            Expanded(
              child: Builder(
                builder: (context) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const ConversationListSkeleton();
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: SelectableText(
                        UserFacingError.uiMessage(
                          snapshot.error,
                          action: 'load data',
                        ),
                      ),
                    );
                  }

                  // Apply archive/unread filter on top of the already
                  // scope-filtered set.
                  List<Conversation> conversations;
                  switch (widget.filter) {
                    case ConversationFilter.all:
                      conversations = scopedConversations
                          .where((c) => !c.isArchivedBy(widget.currentUserId))
                          .toList();
                      break;
                    case ConversationFilter.unread:
                      conversations = scopedConversations
                          .where(
                            (c) =>
                                !c.isArchivedBy(widget.currentUserId) &&
                                c.getUnreadCount(widget.currentUserId) > 0,
                          )
                          .toList();
                      break;
                    case ConversationFilter.archived:
                      conversations = scopedConversations
                          .where((c) => c.isArchivedBy(widget.currentUserId))
                          .toList();
                      break;
                  }

                  // Apply inline search query on top of the filter result.
                  final activeQuery = _searchQuery.trim().toLowerCase();
                  if (activeQuery.isNotEmpty) {
                    conversations = conversations.where((c) {
                      final name = c
                          .getOtherParticipantName(widget.currentUserId)
                          .toLowerCase();
                      return name.contains(activeQuery) ||
                          _messageMatchConversationIds.contains(c.id);
                    }).toList();
                  }

                  if (conversations.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            activeQuery.isNotEmpty
                                ? Icons.search_off
                                : Icons.chat_bubble_outline,
                            size: 48,
                            color: ChromeColors.of(context)
                                .scaffoldTextSecondary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            activeQuery.isNotEmpty
                                ? 'No results found'
                                : _getEmptyMessage(singular),
                            style: TextStyle(
                              color: ChromeColors.of(context)
                                  .scaffoldTextSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: conversations.length,
                    itemBuilder: (context, index) {
                      final conversation = conversations[index];
                      final isSelected =
                          conversation.id == widget.selectedConversationId;

                      return ConversationListItem(
                        conversation: conversation,
                        currentUserId: widget.currentUserId,
                        isSelected: isSelected,
                        onTap: () =>
                            widget.onSelectConversation(conversation.id),
                      );
                    },
                  );
                },
              ),
            ),

            // New Message Button
            if (widget.showComposeButton &&
                widget.filter != ConversationFilter.archived)
              Container(
                padding: EdgeInsets.fromLTRB(
                  12,
                  12,
                  12,
                  12 + MediaQuery.of(context).padding.bottom,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () => widget.onSelectConversation('new'),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('New Message'),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  List<Widget> _buildCollapsedHeaderRow(
    BuildContext context,
    String projectTerminology,
    bool hasSearchableConversations,
  ) {
    return [
      IgnorePointer(
        ignoring: !hasSearchableConversations,
        child: Opacity(
          opacity: hasSearchableConversations ? 1 : 0.5,
          child: ViewIconButton(
            icon: Icons.search,
            tooltip: 'Search',
            isSelected: false,
            onTap: _expandSearch,
          ),
        ),
      ),
      if (widget.showScopeFilters) ...[
        const SizedBox(width: 4),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildScopeIconButton(
                  context,
                  null,
                  'All conversations',
                  Icons.all_inbox,
                ),
                _buildScopeIconButton(
                  context,
                  'direct',
                  'Direct messages',
                  Icons.person,
                ),
                _buildScopeIconButton(
                  context,
                  'project',
                  projectTerminology,
                  Icons.folder,
                ),
                _buildScopeIconButton(
                  context,
                  'vendor',
                  'Vendors',
                  Icons.store,
                ),
                _buildScopeIconButton(
                  context,
                  'customer',
                  'Customers',
                  Icons.people,
                ),
              ],
            ),
          ),
        ),
      ] else
        const Spacer(),
      _buildFilterMenuButton(context),
    ];
  }

  List<Widget> _buildExpandedSearchRow(
    BuildContext context,
    String searchHint,
  ) {
    final chrome = ChromeColors.of(context);
    return [
      Expanded(
        child: SizedBox(
          height: 36,
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            onChanged: _onSearchChanged,
            style: TextStyle(fontSize: 14, color: chrome.textActive),
            decoration: InputDecoration(
              hintText: searchHint,
              hintStyle: TextStyle(color: chrome.sectionLabel),
              prefixIcon: Icon(
                Icons.search,
                size: 20,
                color: chrome.text,
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 36,
              ),
              suffixIcon: IconButton(
                icon: Icon(Icons.close, size: 18, color: chrome.text),
                onPressed: _collapseSearch,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
              ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 36,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(color: chrome.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(color: chrome.divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(
                  color: chrome.isDark
                      ? AppColors.primaryLight
                      : AppColors.primary,
                  width: 2,
                ),
              ),
              filled: true,
              fillColor: chrome.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.base,
                vertical: AppSpacing.sm,
              ),
              isDense: true,
            ),
          ),
        ),
      ),
      const SizedBox(width: 10),
      _buildFilterMenuButton(context),
    ];
  }

  String _getEmptyMessage(String singular) {
    if (widget.filter == ConversationFilter.unread) {
      return 'No unread messages';
    }
    if (widget.filter == ConversationFilter.archived) {
      return 'No archived conversations';
    }
    if (widget.scopeFilter == 'direct') {
      return 'No direct messages';
    }
    if (widget.scopeFilter == 'project') {
      return 'No ${singular.toLowerCase()} conversations';
    }
    if (widget.scopeFilter == 'vendor') {
      return 'No vendor conversations';
    }
    if (widget.scopeFilter == 'customer') {
      return 'No customer conversations';
    }
    return 'No messages yet';
  }

  Widget _buildScopeIconButton(
    BuildContext context,
    String? scope,
    String label,
    IconData icon,
  ) {
    final isSelected = widget.scopeFilter == scope;
    return ViewIconButton(
      icon: icon,
      tooltip: label,
      isSelected: isSelected,
      onTap: () => widget.onScopeFilterChanged(isSelected ? null : scope),
    );
  }

  Widget _buildFilterMenuButton(BuildContext context) {
    final hasActive = widget.filter != ConversationFilter.all;
    final chrome = ChromeColors.of(context);

    return PopupMenuButton<ConversationFilter>(
      tooltip: 'Filters',
      position: PopupMenuPosition.under,
      onSelected: widget.onFilterChanged,
      itemBuilder: (context) => [
        _buildFilterMenuItem(
          ConversationFilter.all,
          'All',
          Icons.all_inbox_outlined,
        ),
        _buildFilterMenuItem(
          ConversationFilter.unread,
          'Unread',
          Icons.mark_email_unread_outlined,
        ),
        _buildFilterMenuItem(
          ConversationFilter.archived,
          'Archived',
          Icons.archive_outlined,
        ),
      ],
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: Icon(
              hasActive ? Icons.filter_alt : Icons.filter_alt_outlined,
              size: 20,
              color: hasActive ? AppColors.secondary : chrome.text,
            ),
          ),
          if (hasActive)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.secondary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }

  PopupMenuItem<ConversationFilter> _buildFilterMenuItem(
    ConversationFilter value,
    String label,
    IconData icon,
  ) {
    final isSelected = widget.filter == value;
    return PopupMenuItem<ConversationFilter>(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: isSelected ? AppColors.secondary : null,
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected ? AppColors.secondary : null,
            ),
          ),
        ],
      ),
    );
  }
}
