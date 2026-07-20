import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/conversation.dart';
import '../services/service_locator.dart';
import '../providers/auth_provider.dart';
import '../theme/theme.dart';
import 'messages/compose_conversation_pane.dart';
import 'messages/conversation_filter.dart';
import 'messages/conversation_list_item.dart';
import 'messages/conversation_list_pane.dart';
import 'messages/conversation_thread_view.dart';

// ---------------------------------------------------------------------------
// Controller – drives the desktop content-area overlay
// ---------------------------------------------------------------------------

/// Controls whether the desktop messaging overlay is shown.
///
/// Value semantics:
///   `null`  → hidden
///   `''`    → show inbox (no specific conversation)
///   `'new'` → compose new conversation
///   other   → open that conversation ID
class MessagingOverlayController extends ValueNotifier<String?> {
  MessagingOverlayController() : super(null);

  static final instance = MessagingOverlayController();

  void show({String? conversationId}) => value = conversationId ?? '';
  void hide() => value = null;
  bool get isVisible => value != null;
}

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Shows the messaging inbox.
///
/// On mobile (< 600 px) opens a full-height bottom sheet.
/// On desktop sets the [MessagingOverlayController] which the
/// [AdaptiveNavigation] picks up to render the overlay inside the content area
/// (preserving sidebar + top bar).
void showMessagingPopup(BuildContext context, {String? conversationId}) {
  final isMobile = MediaQuery.of(context).size.width < AppBreakpoints.mobile;

  if (isMobile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _MessagingBottomSheet(initialConversationId: conversationId),
    );
  } else {
    MessagingOverlayController.instance.show(conversationId: conversationId);
  }
}

// ---------------------------------------------------------------------------
// Desktop overlay panel – rendered inside the content-area Stack
// ---------------------------------------------------------------------------

/// The messaging panel shown as an overlay inside the content area on desktop.
/// Rendered by [AdaptiveNavigation] when [MessagingOverlayController] is active.
class MessagingOverlayPanel extends StatefulWidget {
  final String? initialConversationId;
  final VoidCallback onClose;

  /// Called when the user taps the expand/collapse button in the panel header.
  final VoidCallback? onToggleExpand;

  /// Whether the panel is currently expanded to fill the full content area.
  final bool isExpanded;

  const MessagingOverlayPanel({
    super.key,
    this.initialConversationId,
    required this.onClose,
    this.onToggleExpand,
    this.isExpanded = false,
  });

  @override
  State<MessagingOverlayPanel> createState() => _MessagingOverlayPanelState();
}

class _MessagingOverlayPanelState extends State<MessagingOverlayPanel> {
  String? _selectedConversationId;
  ConversationFilter _filter = ConversationFilter.all;
  String? _scopeFilter;
  bool _isExpanded = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _selectedConversationId = widget.initialConversationId;
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final appUser = authProvider.appUser;
    final workspaceId = appUser?.currentWorkspaceId;

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          if (_selectedConversationId != null) {
            // First Escape: close compose/thread, go back to list.
            setState(() {
              _selectedConversationId = null;
              _isExpanded = false;
            });
          } else {
            // Second Escape (already at list): close the whole panel.
            widget.onClose();
          }
        }
      },
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: workspaceId == null || appUser == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.base, vertical: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.1),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.chat_bubble,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Inbox',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                        ),
                        const Spacer(),
                        if (widget.onToggleExpand != null)
                          IconButton(
                            icon: Icon(
                              widget.isExpanded
                                  ? Icons.close_fullscreen
                                  : Icons.open_in_full,
                              size: 18,
                            ),
                            onPressed: widget.onToggleExpand,
                            tooltip:
                                widget.isExpanded ? 'Collapse' : 'Expand',
                          ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: widget.onClose,
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                  ),
                  // Content
                  Expanded(
                    child: _buildContent(workspaceId, appUser.id,
                        appUser.displayName ?? 'Unknown'),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildContent(
      String workspaceId, String currentUserId, String currentUserName) {
    final listPane = ConversationListPane(
      workspaceId: workspaceId,
      currentUserId: currentUserId,
      selectedConversationId: _selectedConversationId,
      filter: _filter,
      scopeFilter: _scopeFilter,
      onFilterChanged: (f) => setState(() => _filter = f),
      onScopeFilterChanged: (s) => setState(() => _scopeFilter = s),
      onSelectConversation: (id) =>
          setState(() {
            _selectedConversationId = id;
            _isExpanded = false;
          }),
    );

    if (_selectedConversationId == null) {
      return listPane;
    }

    Widget detailPane;
    if (_selectedConversationId == 'new') {
      detailPane = ComposeConversationPane(
        workspaceId: workspaceId,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
        onSent: (id) => setState(() {
          _selectedConversationId = id;
          _isExpanded = false;
        }),
      );
    } else {
      detailPane = ConversationThreadView(
        key: ValueKey('popup-thread-${_selectedConversationId!}'),
        conversationId: _selectedConversationId!,
        workspaceId: workspaceId,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
        onClose: () => setState(() {
          _selectedConversationId = null;
          _isExpanded = false;
        }),
        onExpand: () => setState(() => _isExpanded = !_isExpanded),
        isExpanded: _isExpanded,
      );
    }

    if (_isExpanded) return detailPane;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Not enough room for list + thread side-by-side: show thread only.
        if (constraints.maxWidth < AppBreakpoints.mobile) return detailPane;
        return Row(
          children: [
            SizedBox(width: 320, child: listPane),
            const VerticalDivider(width: 1),
            Expanded(child: detailPane),
          ],
        );
      },
    );
  }

}

// ---------------------------------------------------------------------------
// Mobile bottom sheet (unchanged)
// ---------------------------------------------------------------------------

class _MessagingBottomSheet extends StatefulWidget {
  final String? initialConversationId;

  const _MessagingBottomSheet({this.initialConversationId});

  @override
  State<_MessagingBottomSheet> createState() => _MessagingBottomSheetState();
}

class _MessagingBottomSheetState extends State<_MessagingBottomSheet> {
  String? _selectedConversationId;
  bool _searchExpanded = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounce;
  String _searchQuery = '';
  Set<String> _messageMatchConversationIds = const {};
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    _selectedConversationId = widget.initialConversationId;
  }

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
    final auth = context.read<AuthProvider>();
    final workspaceId = auth.appUser?.currentWorkspaceId;
    final userId = auth.appUser?.id;
    if (trimmed.isEmpty || workspaceId == null || userId == null) {
      if (!mounted) return;
      setState(() => _messageMatchConversationIds = const {});
      return;
    }
    final messages = await ServiceLocator.messageService.searchMessages(
      workspaceId: workspaceId,
      userId: userId,
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
    final authProvider = context.watch<AuthProvider>();
    final appUser = authProvider.appUser;
    final workspaceId = appUser?.currentWorkspaceId;

    return DraggableScrollableSheet(
      initialChildSize: 1.0,
      minChildSize: 0.5,
      maxChildSize: 1.0,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            children: [
              SizedBox(height: MediaQuery.of(context).padding.top),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: _searchExpanded
                      ? [
                          Expanded(
                            child: SizedBox(
                              height: 36,
                              child: TextField(
                                controller: _searchController,
                                focusNode: _searchFocusNode,
                                onChanged: _onSearchChanged,
                                decoration: InputDecoration(
                                  hintText: 'Search messages',
                                  prefixIcon:
                                      const Icon(Icons.search, size: 20),
                                  prefixIconConstraints: const BoxConstraints(
                                    minWidth: 36,
                                    minHeight: 36,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: _collapseSearch,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 36,
                                      minHeight: 36,
                                    ),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.md),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.base,
                                    vertical: AppSpacing.sm,
                                  ),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ),
                        ]
                      : [
                          if (_selectedConversationId != null)
                            IconButton(
                              icon: const Icon(Icons.arrow_back),
                              onPressed: () {
                                setState(() {
                                  _selectedConversationId = null;
                                });
                              },
                            ),
                          Icon(
                            Icons.chat_bubble,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Inbox',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const Spacer(),
                          if (_selectedConversationId == null &&
                              workspaceId != null &&
                              appUser != null)
                            IconButton(
                              icon: const Icon(Icons.search),
                              tooltip: 'Search messages',
                              onPressed: _expandSearch,
                            ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                ),
              ),
              const Divider(height: 1),
              // Content
              Expanded(
                child: _selectedConversationId == null
                    ? _MobileConversationList(
                        searchQuery: _searchQuery,
                        messageMatchConversationIds:
                            _messageMatchConversationIds,
                        onSelectConversation: (id) {
                          setState(() {
                            _selectedConversationId = id;
                          });
                        },
                      )
                    : _selectedConversationId == 'new'
                        ? (workspaceId == null || appUser == null)
                            ? const Center(child: CircularProgressIndicator())
                            : ComposeConversationPane(
                                workspaceId: workspaceId,
                                currentUserId: appUser.id,
                                currentUserName:
                                    appUser.displayName ?? 'Unknown',
                                onSent: (id) {
                                  setState(() {
                                    _selectedConversationId = id;
                                  });
                                },
                              )
                        : (workspaceId == null || appUser == null)
                            ? const Center(child: CircularProgressIndicator())
                            : ConversationThreadView(
                                key: ValueKey(
                                  'thread-${_selectedConversationId!}',
                                ),
                                conversationId: _selectedConversationId!,
                                workspaceId: workspaceId,
                                currentUserId: appUser.id,
                                currentUserName:
                                    appUser.displayName ?? 'Unknown',
                                onClose: () {
                                  setState(() {
                                    _selectedConversationId = null;
                                  });
                                },
                              ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Mobile conversation list widget
class _MobileConversationList extends StatelessWidget {
  final ValueChanged<String> onSelectConversation;
  final String searchQuery;
  final Set<String> messageMatchConversationIds;

  const _MobileConversationList({
    required this.onSelectConversation,
    this.searchQuery = '',
    this.messageMatchConversationIds = const {},
  });

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final appUser = authProvider.appUser;
    final workspaceId = appUser?.currentWorkspaceId;

    if (workspaceId == null || appUser == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final messageService = ServiceLocator.messageService;

    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<Conversation>>(
            stream: messageService.getConversations(
              workspaceId: workspaceId,
              userId: appUser.id,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              var conversations = snapshot.data ?? [];
              conversations = conversations
                  .where((c) => !c.isArchivedBy(appUser.id))
                  .toList();

              final activeQuery = searchQuery.trim().toLowerCase();
              if (activeQuery.isNotEmpty) {
                conversations = conversations.where((c) {
                  final name = c
                      .getOtherParticipantName(appUser.id)
                      .toLowerCase();
                  return name.contains(activeQuery) ||
                      messageMatchConversationIds.contains(c.id);
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
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        activeQuery.isNotEmpty
                            ? 'No results found'
                            : 'No messages yet',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                itemCount: conversations.length,
                itemBuilder: (context, index) {
                  final conversation = conversations[index];
                  return ConversationListItem(
                    conversation: conversation,
                    currentUserId: appUser.id,
                    onTap: () => onSelectConversation(conversation.id),
                  );
                },
              );
            },
          ),
        ),
        // New message button
        Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => onSelectConversation('new'),
              icon: const Icon(Icons.add),
              label: const Text('New Message'),
            ),
          ),
        ),
      ],
    );
  }
}
