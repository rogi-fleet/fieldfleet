import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// A consistent search bar used across all list/filter views.
///
/// Matches the style established in the projects view:
/// - Outlined border using [AppColors.cardBorder]
/// - Primary-color focused border (2px)
/// - 300ms debounce by default
/// - Clear (×) icon when text is present
class AppSearchBar extends StatefulWidget {
  final String hintText;
  final String? initialValue;
  final ValueChanged<String> onChanged;
  final double? width;
  final double? height;
  final Duration debounceDuration;

  const AppSearchBar({
    super.key,
    required this.hintText,
    this.initialValue,
    required this.onChanged,
    this.width,
    this.height,
    this.debounceDuration = const Duration(milliseconds: 300),
  });

  @override
  State<AppSearchBar> createState() => _AppSearchBarState();
}

class _AppSearchBarState extends State<AppSearchBar> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      _controller.text = widget.initialValue!;
    }
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant AppSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue &&
        widget.initialValue != null &&
        widget.initialValue != _controller.text) {
      _controller.text = widget.initialValue!;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(widget.debounceDuration, () {
      widget.onChanged(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasCustomHeight = widget.height != null;
    final verticalPadding = hasCustomHeight ? 8.0 : 12.0;
    final iconConstraints = hasCustomHeight
        ? BoxConstraints(
            minWidth: widget.height!,
            minHeight: widget.height!,
          )
        : null;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: TextField(
        controller: _controller,
        onChanged: _onTextChanged,
        decoration: InputDecoration(
          hintText: widget.hintText,
          prefixIcon: const Icon(Icons.search, size: 20),
          prefixIconConstraints: iconConstraints,
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () {
                    _controller.clear();
                    widget.onChanged('');
                  },
                )
              : null,
          suffixIconConstraints: iconConstraints,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: AppColors.cardBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: AppColors.cardBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 2,
            ),
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: AppSpacing.base,
            vertical: verticalPadding,
          ),
          isDense: true,
        ),
      ),
    );
  }
}
