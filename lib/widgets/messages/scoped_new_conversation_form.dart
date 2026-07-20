import 'package:flutter/material.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import '../../models/conversation.dart';
import '../../models/user.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../forms/stacked_field.dart';

/// A reusable new-conversation form for project, customer, and vendor scopes.
///
/// Manages its own [TextEditingController]s and participant selection state
/// internally, so parent widgets only need to track which view is active.
class ScopedNewConversationForm extends StatefulWidget {
  final String workspaceId;
  final String currentUserId;
  final String currentUserName;
  final String scope;
  final String scopeReferenceId;
  final String scopeReferenceName;

  /// If provided, only these user IDs are loaded as potential participants
  /// (e.g. project team members). If null, all workspace users are loaded.
  final List<String>? restrictToUserIds;

  final bool compact;
  final VoidCallback onClose;
  final void Function(Conversation) onConversationCreated;

  /// Callback for the expand/collapse button. Shown only when not compact.
  final VoidCallback? onExpandToggle;

  /// Whether the form is currently in expanded mode.
  final bool isExpanded;

  const ScopedNewConversationForm({
    super.key,
    required this.workspaceId,
    required this.currentUserId,
    required this.currentUserName,
    required this.scope,
    required this.scopeReferenceId,
    required this.scopeReferenceName,
    this.restrictToUserIds,
    this.compact = false,
    required this.onClose,
    required this.onConversationCreated,
    this.onExpandToggle,
    this.isExpanded = false,
  });

  @override
  State<ScopedNewConversationForm> createState() =>
      _ScopedNewConversationFormState();
}

class _ScopedNewConversationFormState extends State<ScopedNewConversationForm> {
  final dynamic _messageService = ServiceLocator.messageService;
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  Set<String> _selectedMemberIds = {};
  Map<String, String> _memberNames = {};
  Future<List<AppUser>>? _usersFuture;

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<List<AppUser>> _loadUsers() {
    if (widget.restrictToUserIds != null) {
      return ServiceLocator.userService
          .getUsersByIds(widget.restrictToUserIds!);
    }
    return (ServiceLocator.userService
            .getUsersByWorkspace(widget.workspaceId) as Stream<List<AppUser>>)
        .first;
  }

  Future<void> _submit() async {
    if (_subjectController.text.trim().isEmpty) return;

    try {
      final conversation = await _messageService.createConversation(
        workspaceId: widget.workspaceId,
        subject: _subjectController.text.trim(),
        participantIds: [widget.currentUserId, ..._selectedMemberIds],
        participantNames: {
          widget.currentUserId: widget.currentUserName,
          ..._memberNames,
        },
        senderId: widget.currentUserId,
        senderName: widget.currentUserName,
        initialMessage: _messageController.text.trim().isNotEmpty
            ? _messageController.text.trim()
            : null,
        scope: widget.scope,
        scopeReferenceId: widget.scopeReferenceId,
        scopeReferenceName: widget.scopeReferenceName,
      );

      if (!mounted) return;
      _subjectController.clear();
      _messageController.clear();
      setState(() {
        _selectedMemberIds = {};
        _memberNames = {};
        _usersFuture = null;
      });
      widget.onConversationCreated(conversation);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.uiMessage(
              e,
              action: 'creating conversation',
            ),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _usersFuture ??= _loadUsers();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          StackedField(
            label: 'Subject',
            child: TextField(
              controller: _subjectController,
              decoration: const InputDecoration(
                hintText: 'Enter conversation subject',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          StackedField(
            label: 'Participants',
            child: _buildParticipants(),
          ),
          const SizedBox(height: 16),
          StackedField(
            label: 'Message',
            child: TextField(
              controller: _messageController,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'Enter your message',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.tonalIcon(
            onPressed: _submit,
            icon: const Icon(Icons.send),
            label: const Text('Create Conversation'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        if (widget.compact)
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: widget.onClose,
          ),
        const Expanded(
          child: Text(
            'New Conversation',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
          ),
        ),
        if (!widget.compact) ...[
          if (widget.onExpandToggle != null)
            IconButton(
              icon: Icon(
                widget.isExpanded
                    ? Icons.close_fullscreen
                    : Icons.open_in_full,
                size: 18,
              ),
              onPressed: widget.onExpandToggle,
              tooltip: widget.isExpanded ? 'Collapse' : 'Expand',
            ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: widget.onClose,
          ),
        ],
      ],
    );
  }

  Widget _buildParticipants() {
    return FutureBuilder<List<AppUser>>(
      future: _usersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: LinearProgressIndicator(),
          );
        }
        final allUsers = snapshot.data ?? [];
        final others =
            allUsers.where((u) => u.id != widget.currentUserId).toList();
        if (others.isEmpty) {
          return Text(
            'No other team members found',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          );
        }
        final allSelected = others.every(
          (u) => _selectedMemberIds.contains(u.id),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // "You" + select-all row
            Row(
              children: [
                Chip(
                  avatar: const Icon(Icons.person, size: 16),
                  label: const Text('You'),
                  backgroundColor:
                      Theme.of(context).colorScheme.secondaryContainer,
                  labelStyle: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                ),
                const Spacer(),
                TextButton.icon(
                  icon: Icon(
                    allSelected ? Icons.deselect : Icons.select_all,
                    size: 16,
                  ),
                  label: Text(
                    allSelected ? 'Deselect all' : 'Select all',
                    style: const TextStyle(fontSize: 13),
                  ),
                  onPressed: () {
                    setState(() {
                      if (allSelected) {
                        _selectedMemberIds.clear();
                        _memberNames.clear();
                      } else {
                        for (final u in others) {
                          _selectedMemberIds.add(u.id);
                          _memberNames[u.id] = u.displayName ?? u.email;
                        }
                      }
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Member list with avatar + name + role
            ...others.map((user) {
              final name = user.displayName ?? user.email;
              final role = user.jobTitle ?? '';
              final photoUrl = user.profilePictureUrl ?? '';
              final initials = name.trim().isNotEmpty
                  ? name
                        .trim()
                        .split(' ')
                        .map((w) => w[0])
                        .take(2)
                        .join()
                        .toUpperCase()
                  : '?';
              final selected = _selectedMemberIds.contains(user.id);
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundImage: photoUrl.isNotEmpty
                      ? NetworkImage(photoUrl)
                      : null,
                  backgroundColor: photoUrl.isEmpty
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  child: photoUrl.isEmpty
                      ? Text(
                          initials,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        )
                      : null,
                ),
                title: Text(name, style: const TextStyle(fontSize: 13)),
                subtitle: role.isNotEmpty
                    ? Text(role, style: const TextStyle(fontSize: 11))
                    : null,
                trailing: selected
                    ? Icon(
                        Icons.check_circle,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : Icon(
                        Icons.radio_button_unchecked,
                        size: 18,
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                onTap: () {
                  setState(() {
                    if (selected) {
                      _selectedMemberIds.remove(user.id);
                      _memberNames.remove(user.id);
                    } else {
                      _selectedMemberIds.add(user.id);
                      _memberNames[user.id] = name;
                    }
                  });
                },
              );
            }),
          ],
        );
      },
    );
  }
}
