import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Shared compact search input used in table control bars.
class TableSearchField extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;
  final double width;
  final double height;
  final double fontSize;

  const TableSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.hintText,
    this.width = 220,
    this.height = 36,
    this.fontSize = 13,
  });

  @override
  State<TableSearchField> createState() => _TableSearchFieldState();
}

class _TableSearchFieldState extends State<TableSearchField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant TableSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleControllerChanged);
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeColors.of(context);

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: TextField(
        controller: widget.controller,
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: TextStyle(
            fontSize: widget.fontSize,
            color: chrome.sectionLabel,
          ),
          prefixIcon: Icon(
            Icons.search,
            size: 18,
            color: chrome.text,
          ),
          suffixIcon: widget.controller.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    size: 16,
                    color: chrome.text,
                  ),
                  onPressed: () {
                    widget.controller.clear();
                    widget.onChanged('');
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                )
              : null,
          isDense: true,
          filled: true,
          fillColor: chrome.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide(color: chrome.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide(color: chrome.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide(
              color: chrome.isDark ? AppColors.primaryLight : AppColors.primary,
              width: 2,
            ),
          ),
        ),
        style: TextStyle(
          fontSize: widget.fontSize,
          color: chrome.textActive,
        ),
      ),
    );
  }
}
