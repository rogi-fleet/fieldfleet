import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/user.dart';
import '../theme/theme.dart';
import 'user_avatar.dart';

/// A text field that supports @mentioning users
/// 
/// When the user types "@", a dropdown appears with matching workspace members.
/// Selected mentions are stored and the text shows the user's display name.
class MentionInputField extends StatefulWidget {
  final TextEditingController controller;
  final List<AppUser> members;
  final String hintText;
  final int maxLines;
  final int minLines;
  final VoidCallback? onSubmit;
  final ValueChanged<List<String>>? onMentionsChanged;
  final InputDecoration? decoration;
  final bool enabled;

  const MentionInputField({
    super.key,
    required this.controller,
    required this.members,
    this.hintText = 'Add a comment...',
    this.maxLines = 3,
    this.minLines = 1,
    this.onSubmit,
    this.onMentionsChanged,
    this.decoration,
    this.enabled = true,
  });

  @override
  State<MentionInputField> createState() => MentionInputFieldState();
}

class MentionInputFieldState extends State<MentionInputField> {
  final FocusNode _focusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  final List<String> _mentionedUserIds = [];
  int _mentionStartIndex = -1;
  int _selectedSuggestionIndex = 0;
  List<AppUser> _filteredMembers = [];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _onFocusChanged() {
    // Defer removal so a tap on a suggestion has time to register before
    // the focus-loss handler tears down the overlay.
    if (!_focusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!mounted) return;
        if (!_focusNode.hasFocus) {
          _removeOverlay();
        }
      });
    }
  }

  void _onTextChanged() {
    final text = widget.controller.text;
    final cursorPosition = widget.controller.selection.baseOffset;
    
    if (cursorPosition < 0 || cursorPosition > text.length) return;

    // Find the @ symbol before the cursor
    int atIndex = -1;
    for (int i = cursorPosition - 1; i >= 0; i--) {
      final char = text[i];
      if (char == '@') {
        atIndex = i;
        break;
      } else if (char == ' ' || char == '\n') {
        break;
      }
    }

    if (atIndex >= 0) {
      // Extract the query after @
      final query = text.substring(atIndex + 1, cursorPosition).toLowerCase();
      _mentionStartIndex = atIndex;
      
      // Filter members by query
      _filteredMembers = widget.members.where((member) {
        final name = (member.displayName ?? member.email).toLowerCase();
        return name.contains(query);
      }).toList();
      
      _selectedSuggestionIndex = 0;
      
      if (_filteredMembers.isNotEmpty) {
        _showOverlay();
      } else {
        _removeOverlay();
      }
    } else {
      _mentionStartIndex = -1;
      _removeOverlay();
    }
  }

  void _showOverlay() {
    _removeOverlay();
    
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: 280,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, -8),
          followerAnchor: Alignment.bottomLeft,
          targetAnchor: Alignment.topLeft,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: _buildSuggestionsList(),
            ),
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

  Widget _buildSuggestionsList() {
    if (_filteredMembers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Text(
          'No members found',
          style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      itemCount: _filteredMembers.length,
      itemBuilder: (context, index) {
        final member = _filteredMembers[index];
        final isSelected = index == _selectedSuggestionIndex;
        
        return Listener(
          // Capture the gesture on pointer-down — fires before the TextField
          // focus-loss handler can tear down the overlay.
          onPointerDown: (_) => _selectMember(member),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            color: isSelected
                ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
                : null,
            child: Row(
              children: [
                UserAvatar(
                  user: member,
                  size: AvatarSize.small,
                  onTap: null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.displayName ?? member.email,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (member.displayName != null)
                        Text(
                          member.email,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _selectMember(AppUser member) {
    final text = widget.controller.text;
    final displayName = member.displayName ?? member.email;
    
    // Replace @query with @displayName
    final beforeMention = text.substring(0, _mentionStartIndex);
    final cursorPosition = widget.controller.selection.baseOffset;
    final afterMention = text.substring(cursorPosition);
    
    final newText = '$beforeMention@$displayName $afterMention';
    widget.controller.text = newText;
    
    // Position cursor after the mention
    final newCursorPosition = beforeMention.length + displayName.length + 2; // +2 for @ and space
    widget.controller.selection = TextSelection.collapsed(offset: newCursorPosition);
    
    // Track the mentioned user
    if (!_mentionedUserIds.contains(member.id)) {
      _mentionedUserIds.add(member.id);
      widget.onMentionsChanged?.call(_mentionedUserIds);
    }
    
    _removeOverlay();
    _mentionStartIndex = -1;
    _focusNode.requestFocus();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (_overlayEntry == null || _filteredMembers.isEmpty) {
      return false;
    }

    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        setState(() {
          _selectedSuggestionIndex = 
              (_selectedSuggestionIndex + 1) % _filteredMembers.length;
        });
        _showOverlay(); // Rebuild overlay
        return true;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        setState(() {
          _selectedSuggestionIndex = 
              (_selectedSuggestionIndex - 1 + _filteredMembers.length) % _filteredMembers.length;
        });
        _showOverlay(); // Rebuild overlay
        return true;
      } else if (event.logicalKey == LogicalKeyboardKey.enter && 
                 !HardwareKeyboard.instance.isShiftPressed) {
        if (_overlayEntry != null && _filteredMembers.isNotEmpty) {
          _selectMember(_filteredMembers[_selectedSuggestionIndex]);
          return true;
        }
      } else if (event.logicalKey == LogicalKeyboardKey.escape) {
        _removeOverlay();
        return true;
      }
    }

    return false;
  }

  /// Get the list of mentioned user IDs
  List<String> get mentionedUserIds => List.unmodifiable(_mentionedUserIds);

  /// Clear mentions (call when comment is submitted)
  void clearMentions() {
    _mentionedUserIds.clear();
  }

  @override
  Widget build(BuildContext context) {
    final defaultDecoration = InputDecoration(
      hintText: widget.hintText,
      hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        borderSide: BorderSide(color: AppColors.cardBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        borderSide: BorderSide(color: AppColors.cardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: 10,
      ),
      isDense: true,
      filled: true,
      fillColor: Colors.white,
    );

    return CompositedTransformTarget(
      link: _layerLink,
      child: Focus(
        // Intercept arrow / enter / escape keys when the suggestions overlay
        // is visible. Other keystrokes fall through to the TextField.
        onKeyEvent: (node, event) {
          return _handleKeyEvent(event)
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        },
        child: TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          decoration: widget.decoration ?? defaultDecoration,
          style: const TextStyle(fontSize: 14),
          maxLines: widget.maxLines,
          minLines: widget.minLines,
          enabled: widget.enabled,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) {
            if (_overlayEntry == null) {
              widget.onSubmit?.call();
            }
          },
        ),
      ),
    );
  }
}
