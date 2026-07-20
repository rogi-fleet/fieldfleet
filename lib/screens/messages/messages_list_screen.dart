import 'dart:async';
import 'package:flutter/material.dart';
import '../../utils/user_facing_error.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../services/service_locator.dart';
import '../../models/conversation.dart';
import '../../widgets/messages/conversation_list_item.dart';
import '../../widgets/messages/conversation_list_skeleton.dart';
import 'desktop_inbox_layout.dart';
import 'conversation_screen.dart';
import '../../theme/theme.dart';
import '../../widgets/messages/conversation_filter.dart';
import '../../widgets/messages/messaging_styles.dart';

class MessagesListScreen extends StatefulWidget {
  final String? selectedConversationId;

  const MessagesListScreen({super.key, this.selectedConversationId});

  @override
  State<MessagesListScreen> createState() => _MessagesListScreenState();
}

class _MessagesListScreenState extends State<MessagesListScreen> {
  ConversationFilter _filter = ConversationFilter.all;
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
    final workspaceId = context.read<AuthProvider>().appUser?.currentWorkspaceId;
    final userId = context.read<AuthProvider>().appUser?.id;
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

    if (workspaceId == null || appUser == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Use desktop layout for wide screens (>= 768px)
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth >= 768) {
      return DesktopInboxLayout(
        selectedConversationId: widget.selectedConversationId,
      );
    }

    if (widget.selectedConversationId != null) {
      return ConversationScreen(conversationId: widget.selectedConversationId!);
    }

    // Mobile layout for narrow screens
    return _buildMobileLayout(workspaceId, appUser.id);
  }

  Widget _buildMobileLayout(String workspaceId, String currentUserId) {
    final searchHint = MediaQuery.of(context).size.width < AppBreakpoints.mobile
        ? 'Search messages'
        : 'Search conversations and messages';

    return Scaffold(
      appBar: AppBar(
        title: _searchExpanded
            ? TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: _onSearchChanged,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: searchHint,
                  border: InputBorder.none,
                  isDense: true,
                ),
              )
            : Row(
                children: [
                  MessagingStyles.iconBadge(context, Icons.forum_rounded),
                  const SizedBox(width: 10),
                  const Text(
                    'Inbox',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
        actions: [
          if (_searchExpanded)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close search',
              onPressed: _collapseSearch,
            )
          else
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Search',
              onPressed: _expandSearch,
            ),
          PopupMenuButton<ConversationFilter>(
            icon: const Icon(Icons.filter_list),
            onSelected: (filter) {
              setState(() {
                _filter = filter;
              });
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: ConversationFilter.all,
                child: Row(
                  children: [
                    Icon(
                      Icons.all_inbox,
                      size: 20,
                      color: _filter == ConversationFilter.all
                          ? Theme.of(context).colorScheme.primary
                          : AppColors.textPrimary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'All',
                      style: TextStyle(
                        fontWeight: _filter == ConversationFilter.all
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: ConversationFilter.unread,
                child: Row(
                  children: [
                    Icon(
                      Icons.mark_email_unread,
                      size: 20,
                      color: _filter == ConversationFilter.unread
                          ? Theme.of(context).colorScheme.primary
                          : AppColors.textPrimary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Unread',
                      style: TextStyle(
                        fontWeight: _filter == ConversationFilter.unread
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: ConversationFilter.archived,
                child: Row(
                  children: [
                    Icon(
                      Icons.archive,
                      size: 20,
                      color: _filter == ConversationFilter.archived
                          ? Theme.of(context).colorScheme.primary
                          : AppColors.textPrimary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Archived',
                      style: TextStyle(
                        fontWeight: _filter == ConversationFilter.archived
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: StreamBuilder<List<Conversation>>(
        stream: ServiceLocator.messageService.getConversations(
          workspaceId: workspaceId,
          userId: currentUserId,
        ),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: SelectableText(
                UserFacingError.uiMessage(snapshot.error, action: 'load data'),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const ConversationListSkeleton();
          }

          var conversations = snapshot.data ?? [];

          // Apply filter
          switch (_filter) {
            case ConversationFilter.all:
              // Show only non-archived conversations
              conversations = conversations
                  .where((c) => !c.isArchivedBy(currentUserId))
                  .toList();
              break;
            case ConversationFilter.unread:
              // Show only non-archived conversations with unread messages
              conversations = conversations
                  .where(
                    (c) =>
                        !c.isArchivedBy(currentUserId) &&
                        c.getUnreadCount(currentUserId) > 0,
                  )
                  .toList();
              break;
            case ConversationFilter.archived:
              // Show only archived conversations
              conversations = conversations
                  .where((c) => c.isArchivedBy(currentUserId))
                  .toList();
              break;
          }

          // Apply inline search query.
          final activeQuery = _searchQuery.trim().toLowerCase();
          if (activeQuery.isNotEmpty) {
            conversations = conversations.where((c) {
              final name = c
                  .getOtherParticipantName(currentUserId)
                  .toLowerCase();
              return name.contains(activeQuery) ||
                  _messageMatchConversationIds.contains(c.id);
            }).toList();
          }

          if (conversations.isEmpty) {
            if (activeQuery.isNotEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.search_off,
                      size: 48,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No results found',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              );
            }
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  MessagingStyles.emptyStateIcon(
                    context,
                    diameter: 80,
                    iconSize: 36,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _filter == ConversationFilter.unread
                        ? 'All caught up'
                        : _filter == ConversationFilter.archived
                        ? 'No archived conversations'
                        : 'No messages yet',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_filter == ConversationFilter.all)
                    Text(
                      'Start a conversation with a team member',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  if (_filter == ConversationFilter.unread)
                    Text(
                      'No unread messages',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  if (_filter == ConversationFilter.all) ...[
                    const SizedBox(height: 24),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        context.push('/messages/new');
                      },
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('New Message'),
                    ),
                  ],
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
                currentUserId: currentUserId,
                onTap: () {
                  context.push('/messages/${conversation.id}');
                },
              );
            },
          );
        },
      ),
      floatingActionButton: _filter != ConversationFilter.archived
          ? Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom + 78,
              ),
              child: FloatingActionButton(
                onPressed: () {
                  context.push('/messages/new');
                },
                tooltip: 'New Message',
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                child: const Icon(Icons.edit_outlined),
              ),
            )
          : null,
    );
  }
}
