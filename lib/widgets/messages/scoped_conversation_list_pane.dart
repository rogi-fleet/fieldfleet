import 'dart:async';
import 'package:flutter/material.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import '../../models/conversation.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import 'conversation_list_item.dart';
import 'conversation_list_skeleton.dart';

/// Renders a scoped conversation list with a header, stream-driven list,
/// and empty/loading/error states. Shared across project, customer, and
/// vendor message tabs.
class ScopedConversationListPane extends StatefulWidget {
  final String workspaceId;
  final String currentUserId;
  final String scope;
  final String scopeReferenceId;
  final String title;
  final Conversation? selectedConversation;
  final ValueChanged<Conversation> onSelectConversation;
  final VoidCallback onNewConversation;
  final bool compact;

  const ScopedConversationListPane({
    super.key,
    required this.workspaceId,
    required this.currentUserId,
    required this.scope,
    required this.scopeReferenceId,
    required this.title,
    required this.selectedConversation,
    required this.onSelectConversation,
    required this.onNewConversation,
    this.compact = false,
  });

  @override
  State<ScopedConversationListPane> createState() =>
      _ScopedConversationListPaneState();
}

class _ScopedConversationListPaneState
    extends State<ScopedConversationListPane> {
  // Fires once per widget lifecycle on the first non-empty emission so
  // the desktop split view has something selected by default. Without
  // this guard the post-frame callback would re-fire on every stream
  // tick and fight with explicit deselection from the parent.
  bool _didAutoSelect = false;

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
    final chrome = ChromeColors.of(context);

    return StreamBuilder<List<Conversation>>(
      stream: messageService.getConversationsByScope(
        workspaceId: widget.workspaceId,
        userId: widget.currentUserId,
        scope: widget.scope,
        scopeReferenceId: widget.scopeReferenceId,
      ),
      builder: (context, snapshot) {
        final conversations = snapshot.data ?? const <Conversation>[];

        // Auto-select the most recent conversation on desktop, exactly
        // once per widget lifecycle.
        if (!_didAutoSelect &&
            !widget.compact &&
            widget.selectedConversation == null &&
            conversations.isNotEmpty) {
          _didAutoSelect = true;
          final first = conversations.first;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            widget.onSelectConversation(first);
          });
        }

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.base),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: chrome.scaffoldDivider),
                ),
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
                              style: TextStyle(
                                fontSize: 14,
                                color: chrome.textActive,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Search messages',
                                hintStyle:
                                    TextStyle(color: chrome.sectionLabel),
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
                                  icon: Icon(
                                    Icons.close,
                                    size: 18,
                                    color: chrome.text,
                                  ),
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
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.md),
                                  borderSide:
                                      BorderSide(color: chrome.divider),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.md),
                                  borderSide:
                                      BorderSide(color: chrome.divider),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.md),
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
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(Icons.add, color: chrome.scaffoldText),
                          tooltip: 'New Conversation',
                          onPressed: widget.onNewConversation,
                        ),
                      ]
                    : [
                        Icon(Icons.message,
                            size: 20, color: chrome.scaffoldText),
                        const SizedBox(width: 8),
                        Text(
                          widget.compact ? 'Inbox' : widget.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: chrome.scaffoldText,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(Icons.search,
                              color: chrome.scaffoldText),
                          tooltip: 'Search',
                          onPressed:
                              conversations.isEmpty ? null : _expandSearch,
                        ),
                        IconButton(
                          icon: Icon(Icons.add, color: chrome.scaffoldText),
                          tooltip: 'New Conversation',
                          onPressed: widget.onNewConversation,
                        ),
                      ],
              ),
            ),
            Expanded(
              child: Builder(
                builder: (context) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const ConversationListSkeleton();
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Text(
                          UserFacingError.uiMessage(
                            snapshot.error,
                            action: 'load data',
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  final activeQuery = _searchQuery.trim().toLowerCase();
                  final filtered = activeQuery.isEmpty
                      ? conversations
                      : conversations.where((c) {
                          final name = c
                              .getOtherParticipantName(widget.currentUserId)
                              .toLowerCase();
                          return name.contains(activeQuery) ||
                              _messageMatchConversationIds.contains(c.id);
                        }).toList();

                  if (filtered.isEmpty) {
                    if (activeQuery.isNotEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
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
                                style: TextStyle(
                                    color: AppColors.textSecondary),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 48,
                              color: AppColors.textTertiary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No conversations yet',
                              style:
                                  TextStyle(color: AppColors.textSecondary),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            FilledButton.tonalIcon(
                              onPressed: widget.onNewConversation,
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const Text('Start a conversation'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final conversation = filtered[index];
                      return ConversationListItem(
                        conversation: conversation,
                        currentUserId: widget.currentUserId,
                        isSelected: widget.selectedConversation?.id ==
                            conversation.id,
                        onTap: () => widget.onSelectConversation(conversation),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
