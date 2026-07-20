import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/workspace_provider.dart';
import '../services/supabase/search_service.dart';
import '../services/ai_service.dart';
import '../services/service_locator.dart';
import '../models/project.dart';
import '../theme/theme.dart';
import '../utils/address_formatter.dart';
import 'ai_persona_picker.dart';

String _aiPersonaAvatarPath(BuildContext context) {
  final ws = context.read<WorkspaceProvider>().activeWorkspace;
  final slug = ws?.aiPersonaAvatar ?? 'hard_hat';
  return kPersonaAvatars[slug] ?? 'assets/images/avatars/robot.png';
}

String _aiPersonaName(BuildContext context) {
  final ws = context.read<WorkspaceProvider>().activeWorkspace;
  return ws?.aiPersonaName?.isNotEmpty == true
      ? ws!.aiPersonaName!
      : 'AI Assistant';
}

String _askPersonaLabel(BuildContext context) =>
    'Ask ${_aiPersonaName(context)}';

Widget _aiPersonaAvatar(
  BuildContext context, {
  double size = 18,
  Color? backgroundColor,
}) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: backgroundColor ?? Colors.transparent,
    ),
    child: ClipOval(
      child: Image.asset(_aiPersonaAvatarPath(context), fit: BoxFit.cover),
    ),
  );
}

/// A smart search bar with AI awareness and multi-entity search
class SmartSearchBar extends StatefulWidget {
  final String workspaceId;
  final String? projectId; // If provided, prioritizes project-specific results
  final bool expanded; // If true, shows as expanded search bar
  final Function(SearchResult)? onResultSelected;
  final VoidCallback? onAiQuerySubmitted;

  const SmartSearchBar({
    super.key,
    required this.workspaceId,
    this.projectId,
    this.expanded = false,
    this.onResultSelected,
    this.onAiQuerySubmitted,
  });

  @override
  State<SmartSearchBar> createState() => _SmartSearchBarState();
}

class _SmartSearchBarState extends State<SmartSearchBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _searchService = ServiceLocator.searchService;
  final _layerLink = LayerLink();

  OverlayEntry? _overlayEntry;
  List<SearchResult> _results = [];
  List<SearchResult> _aiSuggestions = [];
  SearchIntent? _currentIntent;
  bool _isLoading = false;
  bool _isAiProcessing = false;
  Timer? _debounceTimer;
  int _selectedIndex = -1;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _debounceTimer?.cancel();
    _removeOverlay();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      if (_controller.text.isNotEmpty) {
        _showOverlay();
      }
    } else {
      // Delay removal to allow click on results
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!_focusNode.hasFocus) {
          _removeOverlay();
        }
      });
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();

    if (query.isEmpty) {
      setState(() {
        _results = [];
        _aiSuggestions = [];
        _currentIntent = null;
      });
      _removeOverlay();
      return;
    }

    // Detect intent immediately
    final intent = _searchService.detectIntent(query);
    setState(() {
      _currentIntent = intent;
      _aiSuggestions = _searchService.getAiSuggestions(query, intent,
          projectTerminology:
              context.read<WorkspaceProvider>().projectTerminology);
    });
    // Show the overlay right away so the user sees immediate feedback
    // (AI suggestions, intent hints, or the "no matches yet" placeholder
    // while the debounced search query is still in flight). Previously
    // the overlay only appeared after _performSearch returned, which on
    // an empty workspace meant typing produced no visible feedback at all.
    _showOverlay();

    // Debounce the actual search
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final results = await _searchService.search(
        query,
        widget.workspaceId,
        limit: 15,
      );

      if (mounted) {
        setState(() {
          _results = results;
          _isLoading = false;
          _selectedIndex = -1;
        });
        _showOverlay();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showOverlay() {
    _removeOverlay();

    // Always show the overlay when there's a query and we're done debouncing:
    // even with no matches, render a "No matches — ask the AI Assistant"
    // empty state. Suppressing it on empty results made the search bar feel
    // broken on workspaces with no data (you'd type and nothing happened).
    if (_controller.text.trim().isEmpty) {
      return;
    }

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: 400,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 45),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(AppRadius.r12),
            child: _buildResultsList(),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final totalItems = _aiSuggestions.length + _results.length;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (totalItems == 0) return;
      setState(() {
        _selectedIndex = (_selectedIndex + 1) % totalItems;
      });
      _showOverlay();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (totalItems == 0) return;
      setState(() {
        _selectedIndex = (_selectedIndex - 1 + totalItems) % totalItems;
      });
      _showOverlay();
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      _submitCurrentQuery();
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      _focusNode.unfocus();
      _removeOverlay();
    }
  }

  void _submitCurrentQuery() {
    if (_controller.text.trim().isEmpty) return;

    _removeOverlay(); // Always remove overlay on Enter

    if (_selectedIndex >= 0) {
      if (_selectedIndex < _aiSuggestions.length) {
        _handleAiSuggestion(_aiSuggestions[_selectedIndex]);
      } else {
        _handleResultSelected(_results[_selectedIndex - _aiSuggestions.length]);
      }
      return;
    }

    if (_currentIntent?.type == SearchIntentType.question || _results.isEmpty) {
      _handleAiQuery();
    }
  }

  void _handleResultSelected(SearchResult result) {
    _removeOverlay();
    _controller.clear();
    _focusNode.unfocus();

    if (widget.onResultSelected != null) {
      widget.onResultSelected!(result);
    } else if (result.route.isNotEmpty) {
      context.go(result.route);
    }
  }

  void _handleAiSuggestion(SearchResult suggestion) {
    final action = suggestion.metadata?['action'] as String?;

    switch (action) {
      case 'ask_ai':
        _handleAiQuery();
        break;
      case 'create_task':
        _removeOverlay();
        _controller.clear();
        _focusNode.unfocus();
        context.go('/projects'); // Navigate to projects to create task
        break;
      case 'create_project':
        _removeOverlay();
        _controller.clear();
        _focusNode.unfocus();
        context.go('/projects/new');
        break;
      case 'analytics':
        _removeOverlay();
        _controller.clear();
        _focusNode.unfocus();
        context.go('/reports');
        break;
      case 'show_overdue':
        _removeOverlay();
        _controller.clear();
        _focusNode.unfocus();
        context.go('/tasks?overdue=true');
        break;
      default:
        _handleAiQuery();
    }
  }

  Future<void> _handleAiQuery() async {
    final query = _controller.text;
    if (query.isEmpty) return;

    // Remove overlay and clear state BEFORE showing dialog
    _removeOverlay();
    _controller.clear();
    _focusNode.unfocus();

    setState(() {
      _isAiProcessing = false;
      _results = [];
      _aiSuggestions = [];
      _currentIntent = null;
    });

    // Show AI response dialog
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => _AiResponseDialog(
          query: query,
          workspaceId: widget.workspaceId,
          projectId: widget.projectId,
        ),
      );
    }
  }

  Widget _buildResultsList() {
    final allItems = [..._aiSuggestions, ..._results];

    if (allItems.isEmpty && !_isLoading) {
      // Question-intent: prompt the user to send the query to the AI.
      if (_currentIntent?.type == SearchIntentType.question) {
        return Container(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _aiPersonaAvatar(
                context,
                size: 32,
                backgroundColor: AppColors.infoLight,
              ),
              const SizedBox(height: 8),
              Text('Press Enter to ${_askPersonaLabel(context)}'),
              const SizedBox(height: 4),
              Text(
                'or keep typing to search',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        );
      }
      // Non-question empty: show a friendly "no matches" + AI fallback
      // instead of nothing (otherwise the search bar feels broken on
      // workspaces with no data, since the overlay just doesn't appear).
      return Container(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'No matches for "${_controller.text.trim()}"',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Try a different keyword, or press Enter to '
              '${_askPersonaLabel(context).toLowerCase()}.',
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
          ],
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 400),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isLoading) const LinearProgressIndicator(minHeight: 2),

          // AI Suggestions section
          if (_aiSuggestions.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Row(
                children: [
                  _aiPersonaAvatar(
                    context,
                    size: 14,
                    backgroundColor: AppColors.infoLight,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'AI Suggestions',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.info,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            ..._aiSuggestions.asMap().entries.map((entry) {
              final index = entry.key;
              final result = entry.value;
              return _buildResultTile(result, index, isAiSuggestion: true);
            }),
            if (_results.isNotEmpty)
              Divider(height: 1, color: AppColors.cardBorder),
          ],

          // Regular results section
          if (_results.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Text(
                'Results',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  return _buildResultTile(
                    _results[index],
                    index + _aiSuggestions.length,
                  );
                },
              ),
            ),
          ],

          // Hint for AI query
          if (_currentIntent?.type == SearchIntentType.question) ...[
            Divider(height: 1, color: AppColors.cardBorder),
            InkWell(
              onTap: _handleAiQuery,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                color: AppColors.infoLight,
                child: Row(
                  children: [
                    _aiPersonaAvatar(
                      context,
                      size: 18,
                      backgroundColor: AppColors.infoLight,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_askPersonaLabel(context)}: "${_controller.text}"',
                        style: TextStyle(color: AppColors.infoDark),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      'Enter',
                      style: TextStyle(fontSize: 11, color: AppColors.info),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultTile(
    SearchResult result,
    int index, {
    bool isAiSuggestion = false,
  }) {
    final isSelected = index == _selectedIndex;

    return InkWell(
      onTap: () {
        if (isAiSuggestion) {
          _handleAiSuggestion(result);
        } else {
          _handleResultSelected(result);
        }
      },
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
        color: isSelected ? AppColors.surfaceAlt : null,
        child: Row(
          children: [
            _buildTypeIcon(result.type, isAiSuggestion: isAiSuggestion),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _displayTitleForResult(context, result),
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: isAiSuggestion ? AppColors.infoDark : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (result.subtitle != null || result.parentName != null)
                    Text(
                      result.parentName != null
                          ? '${result.parentName} - ${result.subtitle ?? ""}'
                          : result.subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            _buildTypeBadge(result.type),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeIcon(SearchResultType type, {bool isAiSuggestion = false}) {
    if (isAiSuggestion) {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.infoLight,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: _aiPersonaAvatar(
            context,
            size: 18,
            backgroundColor: AppColors.infoLight,
          ),
        ),
      );
    }

    IconData icon;
    Color color;

    switch (type) {
      case SearchResultType.project:
        icon = Icons.folder_outlined;
        color = AppColors.info;
        break;
      case SearchResultType.task:
        icon = Icons.task_alt;
        color = AppColors.success;
        break;
      case SearchResultType.customer:
        icon = Icons.person_outline;
        color = AppColors.warning;
        break;
      case SearchResultType.vendor:
        icon = Icons.store_outlined;
        color = AppColors.financialAccent;
        break;
      case SearchResultType.document:
        icon = Icons.description_outlined;
        color = AppColors.invoiceAccent;
        break;
      case SearchResultType.opportunity:
        icon = Icons.trending_up;
        color = AppColors.secondary;
        break;
      case SearchResultType.asset:
        icon = Icons.handyman_outlined;
        color = AppColors.planAccent;
        break;
      case SearchResultType.catalogItem:
        icon = Icons.inventory_2_outlined;
        color = AppColors.secondaryDark;
        break;
      case SearchResultType.teamMember:
        icon = Icons.badge_outlined;
        color = AppColors.messageAccent;
        break;
      case SearchResultType.aiSuggestion:
        icon = Icons.search;
        color = AppColors.info;
        break;
    }

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, size: 16, color: color),
    );
  }

  Widget _buildTypeBadge(SearchResultType type) {
    if (type == SearchResultType.aiSuggestion) {
      return const SizedBox.shrink();
    }

    String label;
    Color color;

    switch (type) {
      case SearchResultType.project:
        label = 'Project';
        color = AppColors.info;
        break;
      case SearchResultType.task:
        label = 'Task';
        color = AppColors.success;
        break;
      case SearchResultType.customer:
        label = 'Customer';
        color = AppColors.warning;
        break;
      case SearchResultType.vendor:
        label = 'Vendor';
        color = AppColors.financialAccent;
        break;
      case SearchResultType.document:
        label = 'Doc';
        color = AppColors.invoiceAccent;
        break;
      case SearchResultType.opportunity:
        label = 'Opportunity';
        color = AppColors.secondary;
        break;
      case SearchResultType.asset:
        label = 'Equipment';
        color = AppColors.planAccent;
        break;
      case SearchResultType.catalogItem:
        label = 'Catalog';
        color = AppColors.secondaryDark;
        break;
      case SearchResultType.teamMember:
        label = 'Team';
        color = AppColors.messageAccent;
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  String _displayTitleForResult(BuildContext context, SearchResult result) {
    if (result.type == SearchResultType.aiSuggestion &&
        result.title.startsWith('Ask AI:')) {
      return result.title.replaceFirst('Ask AI', _askPersonaLabel(context));
    }
    return result.title;
  }

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeColors.of(context);
    return CompositedTransformTarget(
      link: _layerLink,
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: _handleKeyEvent,
        child: SizedBox(
          width: widget.expanded ? 350 : 200,
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            onChanged: _onSearchChanged,
            onSubmitted: (_) => _submitCurrentQuery(),
            decoration: InputDecoration(
              hintText: 'Search or ask ${_aiPersonaName(context)}...',
              hintStyle: chrome.isDark
                  ? const TextStyle(color: AppColors.textTertiary)
                  : null,
              prefixIcon: _isAiProcessing
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : (_currentIntent?.type == SearchIntentType.question
                      ? Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: _aiPersonaAvatar(
                            context,
                            size: 20,
                            backgroundColor: AppColors.infoLight,
                          ),
                        )
                      : Icon(
                          Icons.search,
                          size: 20,
                          color: chrome.isDark ? AppColors.textTertiary : null,
                        )),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _controller.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: chrome.isDark
                  ? AppColors.surface
                  : Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.3),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 0,
                horizontal: AppSpacing.md,
              ),
              isDense: true,
            ),
          ),
        ),
      ),
    );
  }
}

enum _AiScopeType { workspace, project, customer, task }

class _AiScopeResolution {
  final _AiScopeType type;
  final SearchResult? result;
  final List<SearchResult> options;
  final String source;

  const _AiScopeResolution._({
    required this.type,
    required this.source,
    this.result,
    this.options = const [],
  });

  factory _AiScopeResolution.workspace({String source = 'workspace'}) {
    return _AiScopeResolution._(
      type: _AiScopeType.workspace,
      source: source,
    );
  }

  factory _AiScopeResolution.resolved(
    SearchResult result, {
    required String source,
  }) {
    return _AiScopeResolution._(
      type: _scopeTypeForResult(result.type),
      result: result,
      source: source,
    );
  }

  factory _AiScopeResolution.ambiguous(
    List<SearchResult> options, {
    String source = 'ambiguous',
  }) {
    return _AiScopeResolution._(
      type: _AiScopeType.workspace,
      options: options,
      source: source,
    );
  }

  bool get isAmbiguous => options.isNotEmpty;

  String get displayLabel {
    return switch (type) {
      _AiScopeType.project => 'Project: ${result?.title ?? ''}'.trim(),
      _AiScopeType.customer => 'Customer: ${result?.title ?? ''}'.trim(),
      _AiScopeType.task => 'Task: ${result?.title ?? ''}'.trim(),
      _AiScopeType.workspace => 'Workspace overview',
    };
  }
}

class _ScoredSearchResult {
  final SearchResult result;
  final double score;

  const _ScoredSearchResult(this.result, this.score);
}

class _AiEntityClassification {
  final String entityType;
  final String? entityHint;
  final double confidence;

  const _AiEntityClassification({
    required this.entityType,
    this.entityHint,
    this.confidence = 0,
  });

  bool get isResolvable =>
      entityType == 'project' ||
      entityType == 'customer' ||
      entityType == 'task' ||
      entityType == 'workspace';

  factory _AiEntityClassification.fromJson(Map<String, dynamic> json) {
    final rawType = (json['entityType'] ?? json['entity_type'] ?? 'unknown')
        .toString()
        .trim()
        .toLowerCase();
    final normalizedType = switch (rawType) {
      'client' => 'customer',
      'job' => 'project',
      'item' => 'task',
      _ => rawType,
    };
    final rawConfidence = json['confidence'];
    final confidence = rawConfidence is num
        ? rawConfidence.toDouble()
        : double.tryParse(rawConfidence?.toString() ?? '') ?? 0;
    final hint = json['entityHint'] ?? json['entity_hint'];

    return _AiEntityClassification(
      entityType: normalizedType,
      entityHint: hint?.toString().trim().isEmpty ?? true
          ? null
          : hint.toString().trim(),
      confidence: confidence.clamp(0, 1).toDouble(),
    );
  }
}

_AiScopeType _scopeTypeForResult(SearchResultType type) {
  return switch (type) {
    SearchResultType.project => _AiScopeType.project,
    SearchResultType.customer => _AiScopeType.customer,
    SearchResultType.task => _AiScopeType.task,
    _ => _AiScopeType.workspace,
  };
}

String _searchResultTypeLabel(SearchResultType type) {
  return switch (type) {
    SearchResultType.project => 'Project',
    SearchResultType.task => 'Task',
    SearchResultType.customer => 'Customer',
    SearchResultType.vendor => 'Vendor',
    SearchResultType.document => 'Document',
    SearchResultType.opportunity => 'Opportunity',
    SearchResultType.asset => 'Equipment',
    SearchResultType.catalogItem => 'Catalog',
    SearchResultType.teamMember => 'Team',
    SearchResultType.aiSuggestion => 'AI',
  };
}

IconData _searchResultTypeIcon(SearchResultType type) {
  return switch (type) {
    SearchResultType.project => Icons.folder_outlined,
    SearchResultType.task => Icons.task_alt,
    SearchResultType.customer => Icons.person_outline,
    SearchResultType.vendor => Icons.store_outlined,
    SearchResultType.document => Icons.description_outlined,
    SearchResultType.opportunity => Icons.trending_up,
    SearchResultType.asset => Icons.handyman_outlined,
    SearchResultType.catalogItem => Icons.inventory_2_outlined,
    SearchResultType.teamMember => Icons.badge_outlined,
    SearchResultType.aiSuggestion => Icons.auto_awesome_outlined,
  };
}

/// Dialog for AI responses
class _AiResponseDialog extends StatefulWidget {
  final String query;
  final String workspaceId;
  final String? projectId;

  const _AiResponseDialog({
    required this.query,
    required this.workspaceId,
    this.projectId,
  });

  @override
  State<_AiResponseDialog> createState() => _AiResponseDialogState();
}

class _AiResponseDialogState extends State<_AiResponseDialog> {
  final _aiService = AiService();
  final _searchService = ServiceLocator.searchService;
  final _projectService = ServiceLocator.projectService;
  final _taskService = ServiceLocator.taskService;
  final _budgetService = ServiceLocator.budgetService;
  dynamic get _customerService => ServiceLocator.customerService;

  bool _isLoading = true;
  String _response = '';
  String? _error;
  String _currentStatus = 'Gathering data...';
  String _streamedText = '';
  String _pendingStreamedText = '';
  String? _resolvedScopeLabel;
  List<SearchResult> _disambiguationOptions = [];
  Timer? _streamUpdateTimer;

  @override
  void initState() {
    super.initState();
    _gatherDataAndAsk();
  }

  @override
  void dispose() {
    _streamUpdateTimer?.cancel();
    super.dispose();
  }

  void _handleStreamUpdate(
    String providerName,
    String delta,
    String accumulated,
  ) {
    if (!mounted) return;
    _pendingStreamedText = accumulated;
    if (_streamUpdateTimer != null) return;
    _streamUpdateTimer = Timer(const Duration(milliseconds: 120), () {
      _streamUpdateTimer = null;
      if (!mounted) return;
      setState(() {
        _streamedText = _pendingStreamedText;
      });
    });
  }

  Future<void> _gatherDataAndAsk() async {
    try {
      setState(() {
        _currentStatus = 'Resolving context...';
        _streamedText = '';
        _pendingStreamedText = '';
        _disambiguationOptions = [];
      });

      final scope = await _resolveQueryScope();
      if (!mounted) return;

      if (scope.isAmbiguous) {
        setState(() {
          _disambiguationOptions = scope.options;
          _currentStatus = 'Choose a match';
          _isLoading = false;
        });
        return;
      }

      await _askQuestionWithScope(scope);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to get AI response: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _askQuestionWithScope(_AiScopeResolution scope) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _response = '';
      _streamedText = '';
      _pendingStreamedText = '';
      _disambiguationOptions = [];
      _resolvedScopeLabel = scope.displayLabel;
      _currentStatus = 'Gathering your data...';
    });

    final context = await _buildDataContext(scope);
    if (!mounted) return;

    setState(() => _currentStatus = 'Connecting to AI...');

    final response = await _aiService.askQuestion(
      question: widget.query,
      context: context,
      onProgress: (providerName, status) {
        if (mounted) {
          setState(() {
            _currentStatus = status;
          });
        }
      },
      onStream: _handleStreamUpdate,
    );

    if (mounted) {
      setState(() {
        _response = response;
        _streamedText = _pendingStreamedText;
        _isLoading = false;
      });
    }
  }

  Future<_AiScopeResolution> _resolveQueryScope() async {
    final queryLower = widget.query.toLowerCase();
    final initial = await _resolveWithSearch(
      widget.query,
      preferredType: _preferredTypeFromQuery(queryLower),
    );
    if (_isClearlyResolved(initial)) {
      return _AiScopeResolution.resolved(initial.first.result,
          source: 'search');
    }

    final activeProjectName = await _activeProjectName();
    final classification = await _classifyQueryWithAi(
      query: widget.query,
      activeProjectName: activeProjectName,
      candidateLabels: initial
          .take(5)
          .map((entry) => _candidateLabel(entry.result))
          .toList(),
      onProgress: (providerName, status) {
        if (mounted) {
          setState(() {
            _currentStatus = status;
          });
        }
      },
    );

    if (classification != null && classification.isResolvable) {
      if (classification.entityType == 'workspace') {
        return _AiScopeResolution.workspace(source: 'ai');
      }

      final resolvedByAi = await _resolveWithSearch(
        classification.entityHint?.trim().isNotEmpty == true
            ? classification.entityHint!
            : widget.query,
        preferredType: _searchTypeForEntity(classification.entityType),
      );

      if (_isClearlyResolved(
        resolvedByAi,
        minimumScore: classification.confidence >= 0.75 ? 42 : 52,
      )) {
        return _AiScopeResolution.resolved(resolvedByAi.first.result,
            source: 'ai');
      }

      if (_isMeaningfullyAmbiguous(resolvedByAi)) {
        return _AiScopeResolution.ambiguous(
          resolvedByAi.take(3).map((entry) => entry.result).toList(),
          source: 'ai',
        );
      }
    }

    if (_isMeaningfullyAmbiguous(initial)) {
      return _AiScopeResolution.ambiguous(
        initial.take(3).map((entry) => entry.result).toList(),
        source: 'search',
      );
    }

    if (widget.projectId != null &&
        !_mentionsSpecificEntity(queryLower) &&
        activeProjectName != null &&
        activeProjectName.isNotEmpty) {
      return _AiScopeResolution.resolved(
        SearchResult(
          id: widget.projectId!,
          title: activeProjectName,
          type: SearchResultType.project,
        ),
        source: 'active_project',
      );
    }

    return _AiScopeResolution.workspace(source: 'workspace');
  }

  Future<List<_ScoredSearchResult>> _resolveWithSearch(
    String query, {
    SearchResultType? preferredType,
  }) async {
    final results = await _searchService.search(
      query,
      widget.workspaceId,
      limit: 10,
      types: preferredType == null
          ? [
              SearchResultType.project,
              SearchResultType.customer,
              SearchResultType.task,
            ]
          : [preferredType],
    );

    final queryLower = query.toLowerCase();
    final scored = results
        .where(
          (result) =>
              result.type == SearchResultType.project ||
              result.type == SearchResultType.customer ||
              result.type == SearchResultType.task,
        )
        .map(
          (result) => _ScoredSearchResult(
            result,
            _scoreResult(result, queryLower, preferredType: preferredType),
          ),
        )
        .where((entry) => entry.score > 0)
        .toList();

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }

  double _scoreResult(
    SearchResult result,
    String queryLower, {
    SearchResultType? preferredType,
  }) {
    final title = result.title.toLowerCase();
    final subtitle = (result.subtitle ?? '').toLowerCase();
    final parent = (result.parentName ?? '').toLowerCase();
    final metadataFields = (result.metadata ?? const <String, dynamic>{})
        .values
        .map((value) => value?.toString().toLowerCase() ?? '')
        .where((value) => value.isNotEmpty)
        .toList();
    final tokens = _meaningfulTokens(queryLower);

    var score = 0.0;

    if (preferredType != null && result.type == preferredType) {
      score += 20;
    }

    if (widget.projectId != null &&
        result.type == SearchResultType.project &&
        result.id == widget.projectId) {
      score += 22;
    }
    if (widget.projectId != null &&
        result.type == SearchResultType.task &&
        result.parentId == widget.projectId) {
      score += 14;
    }

    if (title == queryLower) {
      score += 95;
    } else if (title.startsWith(queryLower)) {
      score += 70;
    } else if (title.contains(queryLower)) {
      score += 52;
    }

    if (subtitle == queryLower || parent == queryLower) {
      score += 55;
    } else if (subtitle.contains(queryLower) || parent.contains(queryLower)) {
      score += 28;
    }

    for (final field in metadataFields) {
      if (field == queryLower) {
        score += 75;
      } else if (field.contains(queryLower)) {
        score += 34;
      }
    }

    for (final token in tokens) {
      if (title.contains(token)) {
        score += 14;
      } else if (subtitle.contains(token) || parent.contains(token)) {
        score += 9;
      } else if (metadataFields.any((field) => field.contains(token))) {
        score += 8;
      }
    }

    if (_matchesEntityKeyword(result.type, queryLower)) {
      score += 12;
    }

    return score;
  }

  bool _isClearlyResolved(
    List<_ScoredSearchResult> scored, {
    double minimumScore = 58,
  }) {
    if (scored.isEmpty) return false;
    final top = scored.first;
    final second = scored.length > 1 ? scored[1] : null;
    final gap = second == null ? top.score : top.score - second.score;
    return top.score >= minimumScore && gap >= 10;
  }

  bool _isMeaningfullyAmbiguous(List<_ScoredSearchResult> scored) {
    if (scored.length < 2) return false;
    final top = scored.first;
    final second = scored[1];
    return top.score >= 38 &&
        second.score >= 34 &&
        (top.score - second.score) < 10;
  }

  SearchResultType? _preferredTypeFromQuery(String queryLower) {
    if (_customerKeywords.any(queryLower.contains)) {
      return SearchResultType.customer;
    }
    if (_taskKeywords.any(queryLower.contains)) {
      return SearchResultType.task;
    }
    if (_projectKeywords.any(queryLower.contains)) {
      return SearchResultType.project;
    }
    return null;
  }

  SearchResultType? _searchTypeForEntity(String entityType) {
    return switch (entityType) {
      'project' => SearchResultType.project,
      'customer' => SearchResultType.customer,
      'task' => SearchResultType.task,
      _ => null,
    };
  }

  bool _matchesEntityKeyword(SearchResultType type, String queryLower) {
    final keywords = switch (type) {
      SearchResultType.project => _projectKeywords,
      SearchResultType.customer => _customerKeywords,
      SearchResultType.task => _taskKeywords,
      _ => const <String>{},
    };
    return keywords.any(queryLower.contains);
  }

  bool _mentionsSpecificEntity(String queryLower) {
    return _projectKeywords.any(queryLower.contains) ||
        _customerKeywords.any(queryLower.contains) ||
        _taskKeywords.any(queryLower.contains);
  }

  Future<String?> _activeProjectName() async {
    final projectId = widget.projectId;
    if (projectId == null || projectId.isEmpty) return null;

    try {
      final project = await _projectService.getProject(
        projectId,
        workspaceId: widget.workspaceId,
      );
      return project?.name as String?;
    } catch (_) {
      return null;
    }
  }

  Future<_AiEntityClassification?> _classifyQueryWithAi({
    required String query,
    String? activeProjectName,
    List<String>? candidateLabels,
    AiProgressCallback? onProgress,
  }) async {
    final prompt = StringBuffer()
      ..writeln(
        'Classify this FieldFleet user question before data retrieval.',
      )
      ..writeln('')
      ..writeln('Return ONLY a valid JSON object with this exact shape:')
      ..writeln(
        '{"entityType":"project|customer|task|workspace|unknown","entityHint":"short phrase or null","confidence":0.0}',
      )
      ..writeln('')
      ..writeln('Rules:')
      ..writeln(
        '- Choose "project" for a specific job, site, address, serial number, PO number, or project name.',
      )
      ..writeln(
        '- Choose "customer" for a customer, client, owner, insured, or account.',
      )
      ..writeln(
        '- Choose "task" for a specific task, deliverable, inspection, due item, or blocker.',
      )
      ..writeln(
        '- Choose "workspace" when the question is broad and not clearly about one entity.',
      )
      ..writeln('- Never invent IDs.')
      ..writeln('')
      ..writeln('User question: $query');

    if (activeProjectName != null && activeProjectName.trim().isNotEmpty) {
      prompt.writeln('Active project on screen: ${activeProjectName.trim()}');
    }

    if (candidateLabels != null && candidateLabels.isNotEmpty) {
      prompt.writeln('');
      prompt.writeln('Possible matches already found:');
      for (final label in candidateLabels.take(6)) {
        prompt.writeln('- $label');
      }
    }

    try {
      final response = await _aiService.askQuestion(
        question: prompt.toString(),
        onProgress: onProgress,
      );
      return _AiEntityClassification.fromJson(
        _parseJsonObjectFromContent(response),
      );
    } catch (_) {
      return null;
    }
  }

  Future<String> _buildDataContext(_AiScopeResolution scope) async {
    return switch (scope.type) {
      _AiScopeType.project => _buildProjectContext(scope.result!),
      _AiScopeType.customer => _buildCustomerContext(scope.result!),
      _AiScopeType.task => _buildTaskContext(scope.result!),
      _AiScopeType.workspace => _buildWorkspaceDataContext(),
    };
  }

  Future<String> _buildProjectContext(SearchResult result) async {
    final buffer = StringBuffer();
    buffer.writeln('RESOLVED ENTITY:');
    buffer.writeln('- Scope: Project');
    buffer.writeln('- Name: ${result.title}');
    buffer.writeln('');

    try {
      final project = await _projectService.getProject(
        result.id,
        workspaceId: widget.workspaceId,
      );
      if (project == null) {
        return _buildWorkspaceDataContext();
      }

      final tasks = await _taskService
          .getTasks(project.id, workspaceId: widget.workspaceId)
          .first;
      final openTasks = tasks.where((task) => !task.isComplete).toList();
      final overdueTasks = openTasks
          .where((task) =>
              task.dueDate != null && task.dueDate!.isBefore(DateTime.now()))
          .toList();
      final matchingTasks = tasks
          .where((task) => _taskMatchesQuery(task, widget.query))
          .take(6)
          .toList();

      buffer.writeln('PROJECT SNAPSHOT:');
      buffer.writeln('- Name: ${project.name}');
      buffer.writeln('- Status: ${project.status.displayName}');
      if (project.address.isNotEmpty) {
        buffer.writeln(
            '- Address: ${AddressFormatter.condense(project.address)}');
      }
      if (project.customerName?.isNotEmpty == true) {
        buffer.writeln('- Customer: ${project.customerName}');
      }
      if (project.primaryContactName?.isNotEmpty == true) {
        buffer.writeln('- Primary contact: ${project.primaryContactName}');
      }
      if (project.purchaseOrderNumber?.isNotEmpty == true) {
        buffer.writeln('- PO Number: ${project.purchaseOrderNumber}');
      }
      if (project.serialNumber?.isNotEmpty == true) {
        buffer.writeln('- Serial Number: ${project.serialNumber}');
      }
      if (project.description?.isNotEmpty == true) {
        buffer.writeln('- Description: ${project.description}');
      }
      buffer.writeln('');

      buffer.writeln('TASK SUMMARY:');
      buffer.writeln('- Total tasks: ${tasks.length}');
      buffer.writeln('- Open tasks: ${openTasks.length}');
      buffer.writeln('- Overdue tasks: ${overdueTasks.length}');
      buffer.writeln('');

      if (matchingTasks.isNotEmpty) {
        buffer.writeln('TASKS MATCHING THE QUESTION:');
        for (final task in matchingTasks) {
          buffer.writeln(
            '- ${task.title} [${task.status}]${task.dueDate != null ? " due ${_formatDate(task.dueDate)}" : ""}',
          );
        }
        buffer.writeln('');
      } else if (overdueTasks.isNotEmpty) {
        buffer.writeln('TOP OVERDUE TASKS:');
        for (final task in overdueTasks.take(5)) {
          buffer.writeln(
            '- ${task.title}${task.dueDate != null ? " due ${_formatDate(task.dueDate)}" : ""}',
          );
        }
        buffer.writeln('');
      }

      try {
        final budget = await _budgetService.calculateBudgetSummary(
          project.id,
          widget.workspaceId,
        );
        buffer.writeln('BUDGET SUMMARY:');
        buffer.writeln(
          '- Approved: \$${budget.totalApprovedPrice.toStringAsFixed(0)}',
        );
        buffer.writeln(
          '- Actual Cost: \$${budget.totalActualCost.toStringAsFixed(0)}',
        );
        buffer.writeln(
          '- Invoiced: \$${budget.totalInvoiced.toStringAsFixed(0)}',
        );
        buffer.writeln(
          '- Margin: ${budget.overallMargin.toStringAsFixed(1)}%',
        );
        buffer.writeln('');
      } catch (_) {}
    } catch (e) {
      buffer.writeln('(Some project data could not be loaded: $e)');
    }

    return buffer.toString();
  }

  Future<String> _buildCustomerContext(SearchResult result) async {
    final buffer = StringBuffer();
    buffer.writeln('RESOLVED ENTITY:');
    buffer.writeln('- Scope: Customer');
    buffer.writeln('- Name: ${result.title}');
    buffer.writeln('');

    try {
      final customer = await _customerService.getCustomer(result.id);
      final projects =
          await _customerService.getCustomerProjects(result.id).first;

      if (customer == null) {
        return _buildWorkspaceDataContext();
      }

      final openProjects =
          projects.where((project) => !project.status.isClosed).toList();

      buffer.writeln('CUSTOMER SNAPSHOT:');
      buffer.writeln('- Name: ${customer.displayName}');
      if (customer.companyName?.isNotEmpty == true) {
        buffer.writeln('- Company: ${customer.companyName}');
      }
      if (customer.email?.isNotEmpty == true) {
        buffer.writeln('- Email: ${customer.email}');
      }
      if (customer.phone?.isNotEmpty == true) {
        buffer.writeln('- Phone: ${customer.phone}');
      }
      if (customer.address?.isNotEmpty == true) {
        buffer.writeln('- Address: ${customer.address}');
      }
      if (customer.notes?.isNotEmpty == true) {
        buffer.writeln('- Notes: ${customer.notes}');
      }
      buffer.writeln('');

      buffer.writeln('LINKED PROJECTS:');
      buffer.writeln('- Total projects: ${projects.length}');
      buffer.writeln('- Open projects: ${openProjects.length}');
      for (final project in projects.take(5)) {
        buffer.writeln('- ${project.name} (${project.status.displayName})');
      }
      buffer.writeln('');
    } catch (e) {
      buffer.writeln('(Some customer data could not be loaded: $e)');
    }

    return buffer.toString();
  }

  Future<String> _buildTaskContext(SearchResult result) async {
    final buffer = StringBuffer();
    buffer.writeln('RESOLVED ENTITY:');
    buffer.writeln('- Scope: Task');
    buffer.writeln('- Name: ${result.title}');
    buffer.writeln('');

    try {
      final task = await _taskService.getTask(
        result.id,
        workspaceId: widget.workspaceId,
      );
      if (task == null) {
        return _buildWorkspaceDataContext();
      }

      final project = await _projectService.getProject(
        task.projectId,
        workspaceId: widget.workspaceId,
      );
      final projectTasks = await _taskService
          .getTasks(task.projectId, workspaceId: widget.workspaceId)
          .first;
      final relatedTasks = projectTasks
          .where((entry) =>
              entry.id != task.id && _taskMatchesQuery(entry, widget.query))
          .take(5)
          .toList();

      buffer.writeln('TASK SNAPSHOT:');
      buffer.writeln('- Title: ${task.title}');
      buffer.writeln('- Status: ${task.status}');
      buffer.writeln('- Priority: ${task.priority}');
      if (task.dueDate != null) {
        buffer.writeln('- Due Date: ${_formatDate(task.dueDate)}');
      }
      if (task.startDate != null) {
        buffer.writeln('- Start Date: ${_formatDate(task.startDate)}');
      }
      if (task.description?.isNotEmpty == true) {
        buffer.writeln('- Description: ${task.description}');
      }
      if (project != null) {
        buffer.writeln('- Project: ${project.name}');
      }
      buffer.writeln('');

      buffer.writeln('PROJECT TASK CONTEXT:');
      buffer.writeln('- Total tasks in project: ${projectTasks.length}');
      buffer.writeln(
        '- Open tasks in project: ${projectTasks.where((entry) => !entry.isComplete).length}',
      );
      buffer.writeln('');

      if (relatedTasks.isNotEmpty) {
        buffer.writeln('RELATED TASKS MATCHING THE QUESTION:');
        for (final related in relatedTasks) {
          buffer.writeln(
            '- ${related.title} [${related.status}]${related.dueDate != null ? " due ${_formatDate(related.dueDate)}" : ""}',
          );
        }
        buffer.writeln('');
      }
    } catch (e) {
      buffer.writeln('(Some task data could not be loaded: $e)');
    }

    return buffer.toString();
  }

  Future<String> _buildWorkspaceDataContext() async {
    final queryLower = widget.query.toLowerCase();
    final buffer = StringBuffer();
    buffer.writeln('USER\'S CURRENT DATA:');
    buffer.writeln('');

    try {
      final projects =
          await _projectService.getProjectsOnce(widget.workspaceId);
      final statusCounts = <ProjectStatus, int>{};
      for (final project in projects) {
        statusCounts[project.status] = (statusCounts[project.status] ?? 0) + 1;
      }

      buffer.writeln('PROJECTS SUMMARY:');
      buffer.writeln('- Total projects: ${projects.length}');
      for (final status in ProjectStatus.values) {
        final count = statusCounts[status] ?? 0;
        if (count > 0) {
          buffer.writeln('- ${status.displayName}: $count');
        }
      }
      buffer.writeln('');

      if (queryLower.contains('project') ||
          queryLower.contains('active') ||
          queryLower.contains('list') ||
          queryLower.contains('show') ||
          queryLower.contains('what')) {
        final openProjects =
            projects.where((project) => !project.status.isClosed).toList();
        buffer.writeln('OPEN PROJECTS:');
        for (final project in openProjects.take(10)) {
          buffer.writeln('- "${project.name}" (${project.status.displayName})');
          if (project.address.isNotEmpty) {
            buffer.writeln(
              '  Location: ${AddressFormatter.condense(project.address)}',
            );
          }
        }
        buffer.writeln('');
      }

      if (queryLower.contains('task') ||
          queryLower.contains('overdue') ||
          queryLower.contains('schedule') ||
          queryLower.contains('todo') ||
          queryLower.contains('pending') ||
          queryLower.contains('complete')) {
        final allTasks =
            await _taskService.getAllWorkspaceTasks(widget.workspaceId).first;

        final incompleteTasks =
            allTasks.where((task) => !task.isComplete).toList();
        final completedTasks =
            allTasks.where((task) => task.isComplete).toList();
        final now = DateTime.now();
        final overdueTasks = incompleteTasks
            .where(
                (task) => task.dueDate != null && task.dueDate!.isBefore(now))
            .toList();
        final upcomingTasks = incompleteTasks
            .where(
              (task) =>
                  task.dueDate != null &&
                  task.dueDate!.isAfter(now) &&
                  task.dueDate!.isBefore(now.add(const Duration(days: 7))),
            )
            .toList();

        buffer.writeln('TASKS SUMMARY:');
        buffer.writeln('- Total tasks: ${allTasks.length}');
        buffer.writeln('- Incomplete: ${incompleteTasks.length}');
        buffer.writeln('- Completed: ${completedTasks.length}');
        buffer.writeln('- Overdue: ${overdueTasks.length}');
        buffer.writeln('- Due within 7 days: ${upcomingTasks.length}');
        buffer.writeln('');

        if (overdueTasks.isNotEmpty &&
            (queryLower.contains('overdue') || queryLower.contains('late'))) {
          buffer.writeln('OVERDUE TASKS:');
          for (final task in overdueTasks.take(10)) {
            final daysOverdue = now.difference(task.dueDate!).inDays;
            buffer.writeln('- "${task.title}" ($daysOverdue days overdue)');
          }
          buffer.writeln('');
        }

        if (upcomingTasks.isNotEmpty && queryLower.contains('upcoming')) {
          buffer.writeln('UPCOMING TASKS (next 7 days):');
          for (final task in upcomingTasks.take(10)) {
            final daysUntil = task.dueDate!.difference(now).inDays;
            buffer.writeln('- "${task.title}" (in $daysUntil days)');
          }
          buffer.writeln('');
        }
      }

      if (queryLower.contains('customer') ||
          queryLower.contains('client') ||
          queryLower.contains('contact')) {
        final customers =
            await _customerService.getCustomersOnce(widget.workspaceId);

        buffer.writeln('CUSTOMERS SUMMARY:');
        buffer.writeln('- Total customers: ${customers.length}');
        buffer.writeln('');

        if (customers.isNotEmpty) {
          buffer.writeln('RECENT CUSTOMERS:');
          for (final customer in customers.take(10)) {
            buffer.writeln('- "${customer.displayName}"');
            if (customer.email != null) {
              buffer.writeln('  Email: ${customer.email}');
            }
            if (customer.phone != null) {
              buffer.writeln('  Phone: ${customer.phone}');
            }
          }
          buffer.writeln('');
        }
      }
    } catch (e) {
      buffer.writeln('(Some data could not be loaded: $e)');
    }

    return buffer.toString();
  }

  bool _taskMatchesQuery(dynamic task, String query) {
    final queryLower = query.toLowerCase();
    final title = task.title?.toString().toLowerCase() ?? '';
    final description = task.description?.toString().toLowerCase() ?? '';
    final tokens = _meaningfulTokens(queryLower);
    return title.contains(queryLower) ||
        description.contains(queryLower) ||
        tokens.any(
            (token) => title.contains(token) || description.contains(token));
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '';
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  List<String> _meaningfulTokens(String query) {
    return query
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9#]+'))
        .map((token) => token.trim())
        .where(
          (token) => token.length >= 3 && !_queryStopwords.contains(token),
        )
        .toList();
  }

  String _candidateLabel(SearchResult result) {
    final subtitle = result.parentName != null
        ? '${result.parentName} - ${result.subtitle ?? ''}'.trim()
        : (result.subtitle ?? '').trim();
    return subtitle.isEmpty
        ? '${_searchResultTypeLabel(result.type)}: ${result.title}'
        : '${_searchResultTypeLabel(result.type)}: ${result.title} ($subtitle)';
  }

  Map<String, dynamic> _parseJsonObjectFromContent(String content) {
    var jsonStr = content.trim();
    if (jsonStr.startsWith('```json')) {
      jsonStr = jsonStr.substring(7);
    } else if (jsonStr.startsWith('```')) {
      jsonStr = jsonStr.substring(3);
    }
    if (jsonStr.endsWith('```')) {
      jsonStr = jsonStr.substring(0, jsonStr.length - 3);
    }

    jsonStr = jsonStr.trim();
    final startIndex = jsonStr.indexOf('{');
    final endIndex = jsonStr.lastIndexOf('}');
    if (startIndex == -1 || endIndex == -1 || endIndex <= startIndex) {
      throw const FormatException('Response did not contain a JSON object.');
    }

    final objectText = jsonStr.substring(startIndex, endIndex + 1);
    final decoded = jsonDecode(objectText);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Response JSON object was not a map.');
    }
    return decoded;
  }

  Future<void> _selectDisambiguation(SearchResult result) async {
    await _askQuestionWithScope(
      _AiScopeResolution.resolved(result, source: 'manual'),
    );
  }

  Widget _buildDisambiguationPanel(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'I found multiple possible matches. Choose one to answer in context:',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ..._disambiguationOptions.map(
            (result) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => _selectDisambiguation(result),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _searchResultTypeIcon(result.type),
                        size: 18,
                        color: AppColors.info,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              result.title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            if ((result.parentName ?? result.subtitle)
                                    ?.isNotEmpty ==
                                true)
                              Text(
                                result.parentName != null
                                    ? '${result.parentName} - ${result.subtitle ?? ''}'
                                    : result.subtitle!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        _searchResultTypeLabel(result.type),
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _askQuestionWithScope(
                _AiScopeResolution.workspace(source: 'manual_workspace'),
              ),
              child: const Text('Use workspace context instead'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.r16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.infoLight,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: _aiPersonaAvatar(
              context,
              size: 20,
              backgroundColor: AppColors.infoLight,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(_aiPersonaName(context))),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.query,
                      style: const TextStyle(fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_resolvedScopeLabel != null &&
                _disambiguationOptions.isEmpty) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Text(
                  'Answering with context: $_resolvedScopeLabel',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_isLoading)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _aiPersonaAvatar(
                            context,
                            size: 24,
                            backgroundColor: AppColors.infoLight,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _aiPersonaName(context),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _currentStatus,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      if (_resolvedScopeLabel != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _resolvedScopeLabel!,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxHeight: 220),
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            _streamedText.trim().isNotEmpty
                                ? _streamedText
                                : 'Waiting for streamed output...',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              fontFamily: 'monospace',
                              color: _streamedText.trim().isNotEmpty
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (_disambiguationOptions.isNotEmpty)
              _buildDisambiguationPanel(context)
            else if (_error != null)
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.errorLight,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: AppColors.errorDark),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.infoLight,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: MarkdownBody(
                  data: _response,
                  selectable: true,
                  styleSheet: MarkdownStyleSheet(
                    p: const TextStyle(height: 1.5),
                    strong: const TextStyle(fontWeight: FontWeight.bold),
                    listBullet: const TextStyle(height: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

const Set<String> _projectKeywords = {
  'project',
  'job',
  'site',
  'address',
  'budget',
  'estimate',
  'serial',
  'po',
};

const Set<String> _customerKeywords = {
  'customer',
  'client',
  'owner',
  'insured',
  'policyholder',
  'account',
  'contact',
};

const Set<String> _taskKeywords = {
  'task',
  'tasks',
  'todo',
  'schedule',
  'inspection',
  'overdue',
  'late',
  'blocked',
  'stuck',
  'due',
};

const Set<String> _queryStopwords = {
  'the',
  'and',
  'for',
  'with',
  'about',
  'what',
  'whats',
  'show',
  'tell',
  'give',
  'have',
  'that',
  'this',
  'from',
  'into',
  'when',
  'where',
  'which',
  'who',
  'our',
  'their',
};
