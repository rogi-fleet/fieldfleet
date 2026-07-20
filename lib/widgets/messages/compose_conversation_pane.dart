import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/message_attachment.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../services/attachment_service.dart';
import '../../theme/theme.dart';
import '../../utils/project_terminology.dart';
import 'messaging_styles.dart';
import 'project_photo_picker_dialog.dart';

/// Full compose-new-conversation pane with recipient search, optional project
/// scoping, subject, message body, and file attachments.
///
/// Used in the standalone inbox (desktop + mobile).
class ComposeConversationPane extends StatefulWidget {
  final String workspaceId;
  final String currentUserId;
  final String currentUserName;
  final void Function(String conversationId)? onSent;

  /// Pre-set scope for the conversation (e.g. 'project').
  /// When set the project picker row is hidden.
  final String? defaultScope;

  /// Pre-set scope reference ID (e.g. project ID).
  final String? defaultScopeReferenceId;

  /// Pre-set scope reference name (e.g. project name).
  final String? defaultScopeReferenceName;

  /// Optional project ID for picking project photos as attachments.
  final String? projectId;

  const ComposeConversationPane({
    super.key,
    required this.workspaceId,
    required this.currentUserId,
    required this.currentUserName,
    this.onSent,
    this.defaultScope,
    this.defaultScopeReferenceId,
    this.defaultScopeReferenceName,
    this.projectId,
  });

  @override
  State<ComposeConversationPane> createState() =>
      _ComposeConversationPaneState();
}

class _ComposeConversationPaneState extends State<ComposeConversationPane> {
  // ── Controllers & focus ─────────────────────────────────────────────────
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final TextEditingController _projectSearchController =
      TextEditingController();
  final FocusNode _projectSearchFocusNode = FocusNode();
  final AttachmentService _attachmentService = AttachmentService();

  dynamic get _messageService => ServiceLocator.messageService;

  // ── Recipients ───────────────────────────────────────────────────────────
  final List<Map<String, String>> _selectedRecipients = [];
  List<Map<String, String>> _allUsers = [];
  List<Map<String, String>> _filteredUsers = [];
  bool _isLoadingUsers = true;
  bool _showUserDropdown = false;

  // ── Projects ─────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _allProjects = [];
  List<Map<String, dynamic>> _filteredProjects = [];
  Map<String, dynamic>? _selectedProject;
  bool _isLoadingProjects = true;
  bool _showProjectDropdown = false;

  // ── Team suggestions ─────────────────────────────────────────────────────
  List<Map<String, String>> _teamSuggestions = [];
  Map<String, String>? _customerRecipient; // customer workspace user, if found
  Set<String> _autoAddedRecipientIds = {}; // tracks project auto-adds for undo
  String? _autoFilledSubject; // tracks what was auto-filled so clear only undoes that

  // ── Mutable scope state ──────────────────────────────────────────────────
  late String _scope;
  late String? _scopeReferenceId;
  late String? _scopeReferenceName;

  // ── Attachments & send state ─────────────────────────────────────────────
  final List<MessageAttachment> _attachments = [];
  bool _isSending = false;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_handleFieldFocusChange);
    _projectSearchFocusNode.addListener(_handleFieldFocusChange);
    _scope = widget.defaultScope ?? 'direct';
    _scopeReferenceId = widget.defaultScopeReferenceId;
    _scopeReferenceName = widget.defaultScopeReferenceName;
    _loadUsers();
    _loadProjects();
    _restoreComposeDraft();
    _messageController.addListener(_saveComposeDraft);
  }

  String get _composeDraftKey => 'compose_draft_${widget.workspaceId}';

  Future<void> _restoreComposeDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final draft = prefs.getString(_composeDraftKey);
    if (draft != null && draft.isNotEmpty && mounted) {
      _messageController.text = draft;
    }
  }

  void _saveComposeDraft() {
    SharedPreferences.getInstance().then((prefs) {
      final text = _messageController.text;
      if (text.isEmpty) {
        prefs.remove(_composeDraftKey);
      } else {
        prefs.setString(_composeDraftKey, text);
      }
    });
  }

  Future<void> _clearComposeDraft() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.remove(_composeDraftKey);
  }

  @override
  void dispose() {
    _messageController.removeListener(_saveComposeDraft);
    _subjectController.dispose();
    _messageController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _projectSearchController.dispose();
    _projectSearchFocusNode.dispose();
    super.dispose();
  }

  void _handleFieldFocusChange() {
    // Dropdowns are dismissed via TapRegion.onTapOutside (see _buildToRow /
    // _buildProjectRow) so that scrolling the suggestion list on mobile does
    // not accidentally collapse it.  This listener only triggers a repaint so
    // the focus-ring highlight on the field frame stays in sync.
    if (mounted) setState(() {});
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadUsers() async {
    try {
      final workspaceMemberService = ServiceLocator.workspaceMemberService;
      final userService = ServiceLocator.userService;
      final members =
          await workspaceMemberService.getWorkspaceMembers(widget.workspaceId).first;
      final users = <Map<String, String>>[];
      for (final member in members) {
        try {
          final user = await userService.getUserById(member.userId);
          if (user != null && user.id != widget.currentUserId) {
            final roleLabel = member.roleTemplateName?.isNotEmpty == true
                ? member.roleTemplateName!
                : (user.jobTitle?.isNotEmpty == true ? user.jobTitle! : '');
            users.add({
              'id': user.id,
              'name': user.displayName ?? user.email,
              'email': user.email,
              'photoUrl': user.profilePictureUrl ?? '',
              'role': roleLabel,
              'roleTemplateId': member.roleTemplateId ?? '',
            });
          }
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _allUsers = users;
          _filteredUsers = users;
          _isLoadingUsers = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingUsers = false);
    }
  }

  Future<void> _loadProjects() async {
    // Skip loading projects if scope is already pre-set (pane is pre-configured)
    if (widget.defaultScope != null) {
      if (mounted) setState(() => _isLoadingProjects = false);
      return;
    }
    try {
      final projects =
          await ServiceLocator.projectService.getProjectsOnce(widget.workspaceId);
      if (mounted) {
        setState(() {
          _allProjects = projects
              .map((p) => <String, dynamic>{
                    'id': p.id,
                    'name': p.name,
                    'serialNumber': p.serialNumber,
                    'teamMemberIds': List<String>.from(p.teamMemberIds),
                    'customerName': p.customerName,
                    'primaryContactEmail': p.primaryContactEmail,
                  })
              .toList();
          _filteredProjects = _allProjects;
          _isLoadingProjects = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingProjects = false);
    }
  }

  // ── Recipients ────────────────────────────────────────────────────────────

  void _filterUsers(String query) {
    setState(() {
      _filteredUsers = query.isEmpty
          ? _allUsers
          : _allUsers.where((u) {
              final name = (u['name'] ?? '').toLowerCase();
              final email = (u['email'] ?? '').toLowerCase();
              final q = query.toLowerCase();
              return name.contains(q) || email.contains(q);
            }).toList();
    });
  }

  void _addRecipient(Map<String, String> user) {
    if (!_selectedRecipients.any((u) => u['id'] == user['id'])) {
      setState(() {
        _selectedRecipients.add(user);
        _searchController.clear();
        _showUserDropdown = false;
        _filteredUsers = _allUsers;
      });
    }
  }

  void _removeRecipient(Map<String, String> user) {
    setState(() => _selectedRecipients.remove(user));
  }

  void _addAllTeamMembers() {
    setState(() {
      for (final member in _teamSuggestions) {
        if (!_selectedRecipients.any((u) => u['id'] == member['id'])) {
          _selectedRecipients.add(member);
        }
      }
      _showUserDropdown = false;
    });
  }

  void _addAllWorkspaceUsers() {
    setState(() {
      for (final user in _allUsers) {
        if (!_selectedRecipients.any((u) => u['id'] == user['id'])) {
          _selectedRecipients.add(user);
        }
      }
      _showUserDropdown = false;
    });
  }

  /// Users eligible for role expansion given the current scope. In project
  /// scope we restrict to the project team; otherwise the whole workspace.
  List<Map<String, String>> get _roleScopeUsers =>
      _selectedProject != null ? _teamSuggestions : _allUsers;

  /// Groups users by role template. Returns entries sorted by name with the
  /// user list alongside so the caller can show counts and bulk-add.
  List<({String roleId, String roleName, List<Map<String, String>> users})>
      get _roleGroups {
    final map = <String, List<Map<String, String>>>{};
    final names = <String, String>{};
    for (final user in _roleScopeUsers) {
      final roleId = user['roleTemplateId'] ?? '';
      final roleName = user['role'] ?? '';
      if (roleId.isEmpty || roleName.isEmpty) continue;
      map.putIfAbsent(roleId, () => []).add(user);
      names[roleId] = roleName;
    }
    final groups = map.entries
        .map((e) => (
              roleId: e.key,
              roleName: names[e.key]!,
              users: e.value,
            ))
        .toList();
    groups.sort((a, b) => a.roleName.compareTo(b.roleName));
    return groups;
  }

  void _addAllWithRole(List<Map<String, String>> users) {
    setState(() {
      for (final user in users) {
        if (!_selectedRecipients.any((u) => u['id'] == user['id'])) {
          _selectedRecipients.add(user);
        }
      }
      _showUserDropdown = false;
    });
  }

  // ── Projects ──────────────────────────────────────────────────────────────

  void _filterProjects(String query) {
    final q = query.toLowerCase();
    setState(() {
      _filteredProjects = query.isEmpty
          ? _allProjects
          : _allProjects.where((p) {
              final name = (p['name'] as String? ?? '').toLowerCase();
              final id = (p['id'] as String? ?? '').toLowerCase();
              final serial = (p['serialNumber'] as String? ?? '').toLowerCase();
              return name.contains(q) ||
                  id.contains(q) ||
                  serial.contains(q);
            }).toList();
    });
  }

  void _selectProject(Map<String, dynamic> project) {
    final teamIds = List<String>.from(project['teamMemberIds'] as List? ?? []);
    final teamMembers = _allUsers
        .where((u) => teamIds.contains(u['id']))
        .toList();

    final projectName = project['name'] as String;

    // Find customer in workspace users by primary contact email
    Map<String, String>? customer;
    final contactEmail = project['primaryContactEmail'] as String?;
    if (contactEmail != null && contactEmail.isNotEmpty) {
      final match = _allUsers.where(
        (u) => (u['email'] ?? '').toLowerCase() == contactEmail.toLowerCase(),
      );
      if (match.isNotEmpty) customer = match.first;
    }

    setState(() {
      _selectedProject = project;
      _scope = 'project';
      _scopeReferenceId = project['id'] as String;
      _scopeReferenceName = projectName;
      _teamSuggestions = teamMembers;
      _customerRecipient = customer;
      _projectSearchController.clear();
      _showProjectDropdown = false;
      _filteredProjects = _allProjects;
      // Pre-fill subject with project name if still empty
      if (_subjectController.text.isEmpty) {
        _subjectController.text = projectName;
        _autoFilledSubject = projectName;
      }
      // Auto-add all project team members as recipients
      _autoAddedRecipientIds = {};
      for (final member in teamMembers) {
        if (!_selectedRecipients.any((u) => u['id'] == member['id'])) {
          _selectedRecipients.add(member);
          _autoAddedRecipientIds.add(member['id']!);
        }
      }
    });
  }

  void _clearProject() {
    setState(() {
      _selectedProject = null;
      _scope = 'direct';
      _scopeReferenceId = null;
      _scopeReferenceName = null;
      _teamSuggestions = [];
      _customerRecipient = null;
      _projectSearchController.clear();
      // Remove recipients that were auto-added by project selection
      _selectedRecipients.removeWhere(
        (u) => _autoAddedRecipientIds.contains(u['id']),
      );
      _autoAddedRecipientIds = {};
      // Only undo the auto-fill if the user hasn't manually changed the subject
      if (_autoFilledSubject != null &&
          _subjectController.text == _autoFilledSubject) {
        _subjectController.clear();
      }
      _autoFilledSubject = null;
    });
  }

  // ── Attachments ───────────────────────────────────────────────────────────

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );
      if (result != null && result.files.isNotEmpty) {
        setState(() => _isUploading = true);
        for (final file in result.files) {
          try {
            final tempConvId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
            final attachment = await _attachmentService.uploadFile(
              file: file.bytes ?? file.path!,
              fileName: file.name,
              mimeType: _getMimeType(file.extension ?? ''),
              conversationId: tempConvId,
              workspaceId: widget.workspaceId,
            );
            setState(() => _attachments.add(attachment));
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Failed to upload ${file.name}: $e'),
                  backgroundColor: AppColors.error,
                ),
              );
            }
          }
        }
        setState(() => _isUploading = false);
      }
    } catch (_) {
      setState(() => _isUploading = false);
    }
  }

  String? get _effectiveProjectId =>
      widget.projectId ?? (_selectedProject?['id'] as String?);

  Future<void> _pickProjectPhotos() async {
    final projectId = _effectiveProjectId;
    if (projectId == null) return;
    final existingIds = _attachments.map((a) => a.id).toSet();
    final results = await showProjectPhotoPicker(
      context: context,
      workspaceId: widget.workspaceId,
      projectId: projectId,
      alreadyAttachedIds: existingIds,
    );
    if (!mounted) return;
    if (results != null && results.isNotEmpty) {
      final newOnly = results.where((r) => !existingIds.contains(r.id)).toList();
      if (newOnly.isNotEmpty) setState(() => _attachments.addAll(newOnly));
    }
  }

  String _getMimeType(String extension) {
    switch (extension.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }

  // ── Send ──────────────────────────────────────────────────────────────────

  Future<void> _send() async {
    final message = _messageController.text.trim();

    if (_selectedRecipients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one recipient')),
      );
      return;
    }
    if (message.isEmpty && _attachments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a message or attach a file')),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      final recipientIds = _selectedRecipients.map((u) => u['id']!).toList();
      final participantIds = [widget.currentUserId, ...recipientIds];
      final participantNames = <String, String>{
        widget.currentUserId: widget.currentUserName,
        for (final r in _selectedRecipients) r['id']!: r['name']!,
      };

      final subject = _subjectController.text.trim().isNotEmpty
          ? _subjectController.text.trim()
          : '(No Subject)';

      final conversation = await _messageService.createConversation(
        workspaceId: widget.workspaceId,
        subject: subject,
        participantIds: participantIds,
        participantNames: participantNames,
        senderId: widget.currentUserId,
        senderName: widget.currentUserName,
        initialMessage: message.isNotEmpty ? message : null,
        attachments: _attachments.map((a) => a.toJson()).toList(),
        scope: _scope,
        scopeReferenceId: _scopeReferenceId,
        scopeReferenceName: _scopeReferenceName,
      );

      _clearComposeDraft();
      if (mounted) {
        widget.onSent?.call(conversation.id);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isReady = !_isLoadingUsers && !_isLoadingProjects;
    if (!isReady) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  Icons.edit_square,
                  color: Theme.of(context).colorScheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'New Message',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: Column(
            children: [
              // ── Form fields card ──────────────────────────────────────
              Container(
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: AppRadius.cardRadius,
                  border: Border.all(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                  ),
                  boxShadow: AppShadows.sm,
                ),
                child: Column(
                  children: [
                    // Project: row first (hidden when scope is pre-set)
                    if (widget.defaultScope == null) ...[
                      _buildProjectRow(),
                      Divider(
                        height: 1,
                        color:
                            Theme.of(context).dividerColor.withValues(alpha: 0.3),
                      ),
                    ],
                    // To: row (auto-filled when project is selected)
                    _buildToRow(),
                    Divider(
                      height: 1,
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                    ),
                    // Subject: row (auto-filled when project is selected)
                    _buildSubjectRow(),
                  ],
                ),
              ),

              // ── Message area ──────────────────────────────────────────
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(
                    children: [
                      // Attachments preview
                      if (_attachments.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.only(bottom: 12),
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _attachments.asMap().entries.map((entry) {
                              final index = entry.key;
                              final attachment = entry.value;
                              return Chip(
                                avatar: Icon(
                                  attachment.isImage
                                      ? Icons.image
                                      : Icons.insert_drive_file,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                label: Text(
                                  attachment.fileName,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                deleteIcon: const Icon(Icons.close, size: 14),
                                onDeleted: () =>
                                    setState(() => _attachments.removeAt(index)),
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                                side: BorderSide.none,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              );
                            }).toList(),
                          ),
                        ),

                      // Message text field
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: MessagingStyles.roundedComposeDecoration(
                            context,
                            hintText: 'Type your message...',
                            hintStyle: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 15,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: 18,
                            ),
                            borderRadius: 24,
                            enabled: !_isSending && !_isUploading,
                            isDense: false,
                          ),
                          style: const TextStyle(fontSize: 15, height: 1.4),
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          enabled: !_isSending && !_isUploading,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Bottom actions ────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.base,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context)
                          .dividerColor
                          .withValues(alpha: 0.3),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      icon: _isUploading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.attach_file, size: 20),
                      onPressed: (_isSending || _isUploading) ? null : _pickFiles,
                      tooltip: 'Attach files',
                    ),
                    if (_effectiveProjectId != null) ...[
                      const SizedBox(width: 4),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.photo_library_outlined, size: 20),
                        onPressed: (_isSending || _isUploading)
                            ? null
                            : _pickProjectPhotos,
                        tooltip:
                            'Attach ${singularProjectTerminology(context.watch<WorkspaceProvider>().projectTerminology).toLowerCase()} photos',
                      ),
                    ],
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _isSending ? null : _send,
                      icon: _isSending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 18),
                      label: const Text(
                        'Send Message',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xl,
                          vertical: AppSpacing.md,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.r12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Form row builders ─────────────────────────────────────────────────────

  Widget _buildToRow() {
    return TapRegion(
      onTapOutside: (_) {
        if (_showUserDropdown) setState(() => _showUserDropdown = false);
      },
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: 65,
                  child: Text(
                    'To:',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: MessagingStyles.composeFieldFrame(
                  context,
                  isFocused: _searchFocusNode.hasFocus,
                  enabled: !_isSending,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                    vertical: AppSpacing.md,
                  ),
                  borderRadius: const BorderRadius.all(Radius.circular(24)),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      ..._selectedRecipients.map((user) {
                        return Chip(
                          label: Text(
                            user['name']!,
                            style: const TextStyle(fontSize: 12),
                          ),
                          deleteIcon: const Icon(Icons.close, size: 14),
                          onDeleted: () => _removeRecipient(user),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        );
                      }),
                      SizedBox(
                        width: 200,
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          decoration:
                              MessagingStyles.composeFieldDecoration(
                            hintText: 'Search people...',
                          ),
                          style: const TextStyle(fontSize: 14),
                          onChanged: (value) {
                            _filterUsers(value);
                            setState(
                              () => _showUserDropdown = value.isNotEmpty,
                            );
                          },
                          onTap: () =>
                              setState(() => _showUserDropdown = true),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (!_isLoadingUsers && _allUsers.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 65, top: 4),
              child: Text(
                'No other members in this workspace',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          Builder(builder: (context) {
            final selectedIds =
                _selectedRecipients.map((u) => u['id']!).toSet();
            final hasProjectTeam = _selectedProject != null &&
                _teamSuggestions.any((u) => !selectedIds.contains(u['id']));
            final hasUnaddedUsers =
                _allUsers.any((u) => !selectedIds.contains(u['id']));
            final customerNotAdded = _customerRecipient != null &&
                !selectedIds.contains(_customerRecipient!['id']);
            // Roles with at least one member not yet selected.
            final roleGroups = _roleGroups
                .map((g) => (
                      roleId: g.roleId,
                      roleName: g.roleName,
                      users: g.users,
                      unadded:
                          g.users.where((u) => !selectedIds.contains(u['id'])).toList(),
                    ))
                .where((g) => g.users.length > 1 && g.unadded.isNotEmpty)
                .toList();
            final hasRoleGroups = roleGroups.isNotEmpty;
            final hasQuickAdds = hasProjectTeam ||
                hasUnaddedUsers ||
                customerNotAdded ||
                hasRoleGroups;

            if (!_showUserDropdown ||
                (!hasQuickAdds && _filteredUsers.isEmpty)) {
              return const SizedBox.shrink();
            }

            return Container(
              margin: const EdgeInsets.only(left: 65, top: 4),
              constraints: const BoxConstraints(maxHeight: 280),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(AppRadius.md),
                color: Theme.of(context).colorScheme.surface,
                boxShadow: AppShadows.lg,
              ),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  if (hasQuickAdds) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: Text(
                        'Quick add',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textTertiary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    if (hasProjectTeam)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.group_add,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(
                          'Add all from ${_selectedProject!['name']}',
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: _addAllTeamMembers,
                      ),
                    if (hasUnaddedUsers)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.people,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: const Text(
                          'Add your team',
                          style: TextStyle(fontSize: 13),
                        ),
                        onTap: _addAllWorkspaceUsers,
                      ),
                    if (customerNotAdded)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.person_outline,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(
                          'Add ${_customerRecipient!['name']}',
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: const Text(
                          'Customer',
                          style: TextStyle(fontSize: 11),
                        ),
                        onTap: () => _addRecipient(_customerRecipient!),
                      ),
                    ...roleGroups.map(
                      (g) => ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.badge_outlined,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(
                          _selectedProject != null
                              ? 'All ${g.roleName} on ${_selectedProject!['name']}'
                              : 'All ${g.roleName}',
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${g.unadded.length} of ${g.users.length} not added',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onTap: () => _addAllWithRole(g.unadded),
                      ),
                    ),
                    if (_filteredUsers.isNotEmpty) const Divider(height: 1),
                  ],
                  ..._filteredUsers.map((user) {
                    final isSelected =
                        _selectedRecipients.any((u) => u['id'] == user['id']);
                    final photoUrl = user['photoUrl'] ?? '';
                    final role = user['role'] ?? '';
                    final name = user['name']!;
                    final initials = name.trim().isNotEmpty
                        ? name.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase()
                        : '?';
                    return ListTile(
                      dense: true,
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
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                ),
                              )
                            : null,
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        role.isNotEmpty ? role : user['email']!,
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: isSelected
                          ? const Icon(
                              Icons.check,
                              size: 16,
                              color: AppColors.primary,
                            )
                          : null,
                      onTap: () => _addRecipient(user),
                    );
                  }),
                ],
              ),
            );
          }),
        ],
      ),
      ),
    );
  }

  Widget _buildProjectRow() {
    // Visible suggestions = team members not already selected as recipients
    final selectedIds =
        _selectedRecipients.map((u) => u['id']!).toSet();
    final visibleSuggestions =
        _teamSuggestions.where((u) => !selectedIds.contains(u['id'])).toList();

    return TapRegion(
      onTapOutside: (_) {
        if (_showProjectDropdown) setState(() => _showProjectDropdown = false);
      },
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: 65,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Project:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        'optional',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _selectedProject != null
                    ? MessagingStyles.composeFieldFrame(
                        context,
                        isFocused: false,
                        enabled: !_isSending,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.base,
                          vertical: AppSpacing.md,
                        ),
                        borderRadius:
                            const BorderRadius.all(Radius.circular(24)),
                        child: Chip(
                          label: Text(
                            _selectedProject!['name'] as String,
                            style: const TextStyle(fontSize: 12),
                          ),
                          deleteIcon: const Icon(Icons.close, size: 14),
                          onDeleted: _clearProject,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                    : MessagingStyles.composeFieldFrame(
                        context,
                        isFocused: _projectSearchFocusNode.hasFocus,
                        enabled: !_isSending,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.base,
                          vertical: AppSpacing.md,
                        ),
                        borderRadius:
                            const BorderRadius.all(Radius.circular(24)),
                        child: TextField(
                          controller: _projectSearchController,
                          focusNode: _projectSearchFocusNode,
                          decoration:
                              MessagingStyles.composeFieldDecoration(
                            hintText:
                                'Search ${context.watch<WorkspaceProvider>().projectTerminology.toLowerCase()}...',
                          ),
                          style: const TextStyle(fontSize: 14),
                          onChanged: (value) {
                            _filterProjects(value);
                            setState(
                              () => _showProjectDropdown = value.isNotEmpty,
                            );
                          },
                          onTap: () =>
                              setState(() => _showProjectDropdown = true),
                        ),
                      ),
              ),
            ],
          ),
          // Project search dropdown
          if (_showProjectDropdown &&
              _selectedProject == null &&
              _filteredProjects.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(left: 65, top: 4),
              constraints: const BoxConstraints(maxHeight: 150),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(AppRadius.md),
                color: Theme.of(context).colorScheme.surface,
                boxShadow: AppShadows.lg,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _filteredProjects.length,
                itemBuilder: (context, index) {
                  final project = _filteredProjects[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.folder_outlined, size: 16),
                    title: Text(
                      project['name'] as String,
                      style: const TextStyle(fontSize: 13),
                    ),
                    onTap: () => _selectProject(project),
                  );
                },
              ),
            ),
          // Team status + re-add chips for removed members
          if (_selectedProject != null && _teamSuggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 65),
              child: visibleSuggestions.isEmpty
                  ? Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 14,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${_teamSuggestions.length} team member${_teamSuggestions.length == 1 ? '' : 's'} added',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Removed from team — tap to re-add:',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: visibleSuggestions.map((user) {
                            return ActionChip(
                              avatar: Icon(
                                Icons.add,
                                size: 14,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              label: Text(
                                user['name']!,
                                style: const TextStyle(fontSize: 12),
                              ),
                              onPressed: () => _addRecipient(user),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            );
                          }).toList(),
                        ),
                      ],
                    ),
            ),
          ],
        ],
      ),
      ),
    );
  }

  Widget _buildSubjectRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 65,
            child: Text(
              'Subject:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _subjectController,
              decoration: MessagingStyles.composeFieldDecoration(
                hintText: 'Add a subject...',
              ),
              style: const TextStyle(fontSize: 14),
              enabled: !_isSending,
            ),
          ),
        ],
      ),
    );
  }
}
