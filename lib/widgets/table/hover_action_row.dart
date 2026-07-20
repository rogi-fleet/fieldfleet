import 'package:flutter/material.dart';

/// Wraps row content in a [MouseRegion] and reveals action buttons on hover
/// via an animated width/opacity transition.
class HoverActionRow extends StatefulWidget {
  const HoverActionRow({
    super.key,
    required this.builder,
    this.actions = const [],
    this.actionWidth = 56,
    this.hoverColor,
    this.animationDuration = const Duration(milliseconds: 150),
    this.enabled = true,
    this.onHoverChanged,
  });

  final Widget Function(bool isHovered) builder;
  final List<Widget> actions;
  final double actionWidth;
  final Color? hoverColor;
  final Duration animationDuration;
  final bool enabled;
  final ValueChanged<bool>? onHoverChanged;

  @override
  State<HoverActionRow> createState() => _HoverActionRowState();
}

class _HoverActionRowState extends State<HoverActionRow> {
  bool _isHovered = false;

  bool get _showActions => _isHovered && widget.enabled;

  void _setHovered(bool hovered) {
    if (!widget.enabled && hovered) return;
    if (_isHovered == hovered) return;
    setState(() => _isHovered = hovered);
    widget.onHoverChanged?.call(hovered);
  }

  @override
  void didUpdateWidget(HoverActionRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Clear hover when disabled (e.g. during drag)
    if (!widget.enabled && _isHovered) {
      _isHovered = false;
      widget.onHoverChanged?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: Row(
        children: [
          Expanded(child: widget.builder(_isHovered)),
          if (widget.actions.isNotEmpty)
            AnimatedContainer(
              duration: widget.animationDuration,
              curve: Curves.easeOut,
              width: _showActions ? widget.actionWidth : 0,
              child: IgnorePointer(
                ignoring: !_showActions,
                child: AnimatedOpacity(
                  opacity: _showActions ? 1.0 : 0.0,
                  duration: widget.animationDuration,
                  child: Row(children: widget.actions),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
