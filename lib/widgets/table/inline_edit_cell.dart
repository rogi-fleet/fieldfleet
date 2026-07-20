import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/theme.dart';
import '../../utils/numeric_input.dart';
import 'inline_edit_text_field.dart';
import '../../utils/text_selection_utils.dart';

export 'inline_edit_text_field.dart' show InlineEditFrame;

enum InlineEditCellType { text, currency, percentage, number }

/// Generic click-to-edit cell that supports text, currency, percentage, and
/// numeric modes. Replaces several view-specific editable field builders.
class InlineEditCell extends StatefulWidget {
  const InlineEditCell({
    super.key,
    required this.value,
    required this.onSave,
    this.onCancel,
    this.cellType = InlineEditCellType.text,
    this.currencySymbol,
    this.placeholder = '-',
    this.displayStyle,
    this.editBorderColor,
    this.selectAllOnFocus = true,
    this.liveEquivalentText,
    this.suggestions = const [],
    this.required = false,
    this.focusNode,
    this.onEditStateChanged,
    this.controller,
    this.onKeyEvent,
    this.isEditing,
    this.onEnterEdit,
    this.editStyle,
    this.textAlign = TextAlign.left,
  });

  final String value;
  final ValueChanged<String> onSave;
  final VoidCallback? onCancel;
  final InlineEditCellType cellType;
  final String? currencySymbol;
  final String placeholder;
  final TextStyle? displayStyle;
  final Color? editBorderColor;
  final bool selectAllOnFocus;
  final String? liveEquivalentText;
  final List<String> suggestions;
  final bool required;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onEditStateChanged;
  final TextEditingController? controller;

  /// Keyboard event handler for Tab navigation (delegated to EditableFieldRegistry).
  final void Function(KeyEvent event)? onKeyEvent;

  /// External edit state. When non-null, overrides internal edit state management.
  final bool? isEditing;

  /// Called when the cell wants to enter edit mode (click). Only used with external [isEditing].
  final VoidCallback? onEnterEdit;
  final TextStyle? editStyle;
  final TextAlign textAlign;

  @override
  State<InlineEditCell> createState() => _InlineEditCellState();
}

class _InlineEditCellState extends State<InlineEditCell> {
  bool _internalIsEditing = false;
  bool get _isEditing => widget.isEditing ?? _internalIsEditing;
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ?? TextEditingController(text: widget.value);
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
  }

  @override
  void didUpdateWidget(InlineEditCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && !_isEditing) {
      _controller.text = widget.value;
    }
    if (widget.controller != oldWidget.controller) {
      if (_ownsController) _controller.dispose();
      _ownsController = widget.controller == null;
      _controller =
          widget.controller ?? TextEditingController(text: widget.value);
    }
    if (widget.focusNode != oldWidget.focusNode) {
      if (_ownsFocusNode) _focusNode.dispose();
      _ownsFocusNode = widget.focusNode == null;
      _focusNode = widget.focusNode ?? FocusNode();
    }
    // When external isEditing transitions to true, request focus
    final wasEditing = oldWidget.isEditing ?? false;
    final nowEditing = widget.isEditing ?? false;
    if (!wasEditing && nowEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_focusNode.hasFocus) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  void enterEdit() {
    _controller.text = widget.value;
    if (widget.isEditing != null) {
      // External state mode — notify parent to toggle
      widget.onEnterEdit?.call();
    } else {
      setState(() => _internalIsEditing = true);
      widget.onEditStateChanged?.call(true);
    }
    if (widget.selectAllOnFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        selectAllText(_controller);
      });
    }
  }

  void _save() {
    final trimmed = _controller.text.trim();
    if (widget.required && trimmed.isEmpty) {
      _cancel();
      return;
    }
    if (trimmed == widget.value) {
      _cancel();
      return;
    }
    widget.onSave(trimmed);
    if (widget.isEditing != null) {
      widget.onEditStateChanged?.call(false);
    } else {
      setState(() => _internalIsEditing = false);
      widget.onEditStateChanged?.call(false);
    }
  }

  void _cancel() {
    _controller.text = widget.value;
    if (widget.isEditing != null) {
      widget.onEditStateChanged?.call(false);
    } else {
      setState(() => _internalIsEditing = false);
      widget.onEditStateChanged?.call(false);
    }
    widget.onCancel?.call();
  }

  List<TextInputFormatter> get _inputFormatters {
    switch (widget.cellType) {
      case InlineEditCellType.currency:
        return NumericInput.currency;
      case InlineEditCellType.percentage:
        return NumericInput.percent(decimals: 1);
      case InlineEditCellType.number:
        return NumericInput.quantity;
      case InlineEditCellType.text:
        return [];
    }
  }

  TextInputType get _keyboardType {
    switch (widget.cellType) {
      case InlineEditCellType.text:
        return TextInputType.text;
      case InlineEditCellType.currency:
      case InlineEditCellType.percentage:
      case InlineEditCellType.number:
        return const TextInputType.numberWithOptions(decimal: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isEditing) {
      return _buildReadMode();
    }
    return _buildEditMode();
  }

  Widget _buildReadMode() {
    final isEmpty = widget.value.isEmpty;
    final style = widget.displayStyle ?? TextStyle(color: AppColors.textPrimary);
    final display = isEmpty ? widget.placeholder : widget.value;

    final textWidget = Text(
      display,
      textAlign: widget.textAlign,
      style: isEmpty
          ? style.copyWith(
              color: AppColors.textTertiary,
              fontStyle: FontStyle.italic,
            )
          : style,
      overflow: TextOverflow.ellipsis,
    );

    return _InlineEditHover(onTap: enterEdit, child: textWidget);
  }

  Widget _buildEditMode() {
    final borderColor = widget.editBorderColor ?? AppColors.info;

    if (widget.suggestions.isNotEmpty &&
        widget.cellType == InlineEditCellType.text) {
      return _buildWithAutocomplete(borderColor);
    }

    return _buildEditContainer(borderColor);
  }

  Widget _buildEditContainer(Color borderColor) {
    Widget textField = InlineEditTextField(
      controller: _controller,
      focusNode: _focusNode,
      autofocus: true,
      keyboardType: _keyboardType,
      inputFormatters: _inputFormatters,
      style: widget.editStyle ?? const TextStyle(fontSize: 14),
      decoration: const InputDecoration(
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
      wrapInFrame: false,
      onTap: widget.selectAllOnFocus ? () => _selectAll() : null,
      onSubmitted: (_) => _save(),
      onTapOutside: (_) => _save(),
    );

    // Wrap in KeyboardListener for Escape (always) and Tab navigation (optional)
    textField = KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _cancel();
          return;
        }
        widget.onKeyEvent?.call(event);
      },
      child: textField,
    );

    Widget content;
    switch (widget.cellType) {
      case InlineEditCellType.currency:
        content = Row(
          children: [
            Text(
              widget.currencySymbol ?? '\$',
              style: const TextStyle(fontSize: 14),
            ),
            Expanded(child: textField),
          ],
        );
      case InlineEditCellType.percentage:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: textField),
                const Text('%', style: TextStyle(fontSize: 14)),
              ],
            ),
            if (widget.liveEquivalentText != null &&
                widget.liveEquivalentText!.isNotEmpty)
              Text(
                widget.liveEquivalentText!,
                style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
              ),
          ],
        );
      default:
        content = textField;
    }

    return InlineEditFrame(
      borderColor: borderColor,
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
      child: content,
    );
  }

  Widget _buildWithAutocomplete(Color borderColor) {
    return RawAutocomplete<String>(
      textEditingController: _controller,
      focusNode: _focusNode,
      optionsBuilder: (textEditingValue) {
        final query = textEditingValue.text.trim().toLowerCase();
        if (query.isEmpty) return widget.suggestions;
        return widget.suggestions.where((s) => s.toLowerCase().contains(query));
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return InlineEditTextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: true,
          style: widget.editStyle ?? const TextStyle(fontSize: 14),
          borderColor: borderColor,
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
          onSubmitted: (_) {
            onFieldSubmitted();
            _save();
          },
          onTapOutside: (_) => _save(),
        );
      },
      onSelected: (selection) {
        _controller.text = selection;
        _controller.selection = TextSelection.collapsed(
          offset: selection.length,
        );
        _save();
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220, maxWidth: 220),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    title: Text(option),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  void _selectAll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      selectAllText(_controller);
    });
  }
}

/// Hover wrapper that shows a subtle background tint to hint editability.
class _InlineEditHover extends StatefulWidget {
  const _InlineEditHover({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_InlineEditHover> createState() => _InlineEditHoverState();
}

class _InlineEditHoverState extends State<_InlineEditHover> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _hovered ? AppColors.info.withValues(alpha: 0.06) : null,
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
