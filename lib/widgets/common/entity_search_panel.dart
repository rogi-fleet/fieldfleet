import 'package:flutter/material.dart';
import '../../theme/theme.dart';

class EntitySearchPanel extends StatefulWidget {
  final TextEditingController controller;
  final String searchQuery;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final Widget? filters;
  final EdgeInsetsGeometry padding;
  final bool filled;
  /// When true, shows only a magnifying glass icon that expands to a search
  /// field on tap. Defaults to false for backwards compatibility.
  final bool collapsible;

  const EntitySearchPanel({
    super.key,
    required this.controller,
    required this.searchQuery,
    required this.hintText,
    required this.onChanged,
    required this.onClear,
    this.filters,
    this.padding = const EdgeInsets.all(AppSpacing.sm),
    this.filled = false,
    this.collapsible = false,
  });

  @override
  State<EntitySearchPanel> createState() => _EntitySearchPanelState();
}

class _EntitySearchPanelState extends State<EntitySearchPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.collapsible && !_expanded) {
      return Padding(
        padding: widget.padding,
        child: Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            icon: const Icon(Icons.search, size: 22),
            tooltip: widget.hintText,
            onPressed: () => setState(() => _expanded = true),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ),
      );
    }

    return Padding(
      padding: widget.padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: widget.controller,
            autofocus: widget.collapsible,
            decoration: InputDecoration(
              hintText: widget.hintText,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: widget.collapsible || widget.searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        widget.onClear();
                        if (widget.collapsible) {
                          setState(() => _expanded = false);
                        }
                      },
                    )
                  : null,
              filled: widget.filled,
              fillColor: widget.filled ? Colors.white : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                borderSide: widget.filled ? BorderSide.none : BorderSide(),
              ),
            ),
            onChanged: widget.onChanged,
          ),
          if (widget.filters != null) ...[const SizedBox(height: 12), widget.filters!],
        ],
      ),
    );
  }
}
