import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/workspace_provider.dart';
import '../services/ai_service.dart';
import '../services/service_locator.dart';
import '../theme/theme.dart';
import '../utils/project_terminology.dart';
import 'ai_persona_picker.dart';

/// A simple AI chat widget with a text input bar
class AiChatWidget extends StatefulWidget {
  final String? initialQuery;
  final String? projectId;

  const AiChatWidget({super.key, this.initialQuery, this.projectId});

  @override
  State<AiChatWidget> createState() => _AiChatWidgetState();
}

class _AiChatWidgetState extends State<AiChatWidget> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AiService _aiService = AiService();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  String _statusText = 'AI is thinking...';
  int? _activeAssistantMessageIndex;
  String? _projectContext;

  AiPersonaContext? get _persona =>
      context.read<WorkspaceProvider>().aiPersonaContext;

  String get _personaAvatarPath {
    final ws = context.read<WorkspaceProvider>().activeWorkspace;
    final slug = ws?.aiPersonaAvatar ?? 'hard_hat';
    return kPersonaAvatars[slug] ?? 'assets/images/avatars/robot.png';
  }

  String get _personaName {
    final ws = context.read<WorkspaceProvider>().activeWorkspace;
    return ws?.aiPersonaName?.isNotEmpty == true
        ? ws!.aiPersonaName!
        : 'AI Assistant';
  }

  @override
  void initState() {
    super.initState();
    if (widget.projectId != null) {
      _loadProjectContext(widget.projectId!);
    }
    // Auto-submit initial query if provided
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _controller.text = widget.initialQuery!;
        _handleSubmit();
      });
    }
  }

  Future<void> _loadProjectContext(String projectId) async {
    try {
      final workspaceId =
          context.read<AuthProvider>().appUser?.currentWorkspaceId;
      if (workspaceId == null) return;

      final projectFuture = (ServiceLocator.projectService.getProject(projectId)
          as Future<dynamic>);
      final tasksFuture = (ServiceLocator.taskService
          .getTasks(projectId, workspaceId: workspaceId)
          .first as Future<dynamic>);
      final budgetFuture = (ServiceLocator.budgetService
          .calculateBudgetSummary(projectId, workspaceId) as Future<dynamic>);

      final results = await Future.wait<dynamic>(
          [projectFuture, tasksFuture, budgetFuture]);

      final project = results[0];
      final tasks = results[1] as List;
      final budget = results[2];

      if (!mounted) return;

      final overdue = tasks.where((t) {
        final due = t.dueDate;
        return due != null &&
            due.isBefore(DateTime.now()) &&
            t.status != 'done';
      }).length;
      final open = tasks.where((t) => t.status != 'done').length;

      final projectName = project?.name ?? 'Unknown';
      final projectStatus = project?.status ?? 'unknown';
      final estimated = (budget as dynamic).totalApprovedPrice as double;
      final actual = budget.totalActualCost as double;
      final margin = budget.overallMargin as double;
      final pct =
          estimated > 0 ? (actual / estimated * 100).toStringAsFixed(1) : '0.0';

      final singular = singularProjectTerminology(
          context.read<WorkspaceProvider>().projectTerminology);
      setState(() {
        _projectContext = '$singular: $projectName ($projectStatus)\n'
            'Tasks: ${tasks.length} total, $open open, $overdue overdue\n'
            'Budget: \$${estimated.toStringAsFixed(0)} estimated, '
            '\$${actual.toStringAsFixed(0)} actual ($pct%), '
            'margin ${margin.toStringAsFixed(1)}%';
      });
    } catch (_) {
      // Project context is optional — silently ignore errors
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (_isLoading) return;

    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final now = DateTime.now();
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true, timestamp: now));
      _messages.add(ChatMessage(text: '', isUser: false, timestamp: now));
      _isLoading = true;
      _statusText = 'AI is thinking...';
      _activeAssistantMessageIndex = _messages.length - 1;
    });

    _controller.clear();
    _scrollToBottom();

    // Build history from prior messages (all except the two just added)
    final priorMessages = _messages.length > 2
        ? _messages.sublist(0, _messages.length - 2)
        : <ChatMessage>[];
    final history = priorMessages.isEmpty
        ? null
        : priorMessages
            .where((m) => m.text.isNotEmpty)
            .map((m) =>
                {'role': m.isUser ? 'user' : 'assistant', 'content': m.text})
            .toList();
    // Cap at last 10 messages
    final cappedHistory = history != null && history.length > 10
        ? history.sublist(history.length - 10)
        : history;

    try {
      final response = await _aiService.askQuestion(
        question: text,
        context: _projectContext,
        persona: _persona,
        conversationHistory: cappedHistory,
        onProgress: (providerName, status) {
          if (!mounted) return;
          setState(() {
            _statusText = '$providerName: $status';
          });
        },
        onStream: (providerName, delta, accumulated) {
          if (!mounted) return;
          final idx = _activeAssistantMessageIndex;
          if (idx == null || idx < 0 || idx >= _messages.length) return;
          setState(() {
            _messages[idx] = ChatMessage(
              text: accumulated,
              isUser: false,
              timestamp: _messages[idx].timestamp,
            );
          });
          _scrollToBottom();
        },
      );

      if (!mounted) return;
      final idx = _activeAssistantMessageIndex;
      if (idx != null && idx >= 0 && idx < _messages.length) {
        setState(() {
          _messages[idx] = ChatMessage(
            text: _messages[idx].text.trim().isNotEmpty
                ? _messages[idx].text
                : response,
            isUser: false,
            timestamp: _messages[idx].timestamp,
          );
          _statusText = 'Complete';
          _isLoading = false;
          _activeAssistantMessageIndex = null;
        });
      }
    } catch (e) {
      if (mounted) {
        final idx = _activeAssistantMessageIndex;
        if (idx != null && idx >= 0 && idx < _messages.length) {
          _messages[idx] = ChatMessage(
            text:
                'I could not process that request right now. Please try again.',
            isUser: false,
            timestamp: _messages[idx].timestamp,
          );
        }
        setState(() {
          _statusText = 'Failed';
          _isLoading = false;
          _activeAssistantMessageIndex = null;
        });
      }
    } finally {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Messages list
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        _personaAvatarPath,
                        width: 80,
                        height: 80,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _personaName,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        getPersonaGreeting(
                          context
                              .read<WorkspaceProvider>()
                              .activeWorkspace
                              ?.aiPersonaName,
                        ),
                        style: TextStyle(color: AppColors.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(AppSpacing.base),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    return _MessageBubble(message: message);
                  },
                ),
        ),

        // Loading indicator
        if (_isLoading)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: [
                const SizedBox(width: 16),
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _statusText,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

        // Input bar
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor, width: 1),
            ),
          ),
          // Extra bottom padding clears the global bottom nav bar (the shell
          // uses extendBody:true, which inflates MediaQuery padding.bottom).
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  // Theme.colorScheme.surface (the container background here)
                  // is a dark navy on FieldFleet's dark theme — the default
                  // hint color renders as dark blue on dark blue, which is
                  // illegible. Force a contrasting hint + a filled white
                  // input so the placeholder reads cleanly.
                  style: const TextStyle(color: Colors.black87),
                  decoration: InputDecoration(
                    hintText: 'Ask $_personaName...',
                    hintStyle:
                        TextStyle(color: Colors.black.withValues(alpha: 0.55)),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                  ),
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _handleSubmit(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _isLoading ? null : _handleSubmit,
                icon: const Icon(Icons.send),
                color: Theme.of(context).colorScheme.primary,
                iconSize: 28,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final ws = context.read<WorkspaceProvider>().activeWorkspace;
    final avatarSlug = ws?.aiPersonaAvatar ?? 'hard_hat';
    final assetPath =
        kPersonaAvatars[avatarSlug] ?? 'assets/images/avatars/robot.png';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.1),
              child: ClipOval(
                child: Image.asset(
                  assetPath,
                  width: 24,
                  height: 24,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base, vertical: 10),
              decoration: BoxDecoration(
                color: message.isUser
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.r16),
              ),
              child: Text(
                message.text,
                style: TextStyle(
                  color: message.isUser
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.onSurface,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          if (message.isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Icon(
                Icons.person,
                size: 18,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}
