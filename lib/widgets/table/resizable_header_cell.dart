import 'package:flutter/material.dart';

/// Reusable resizable table header cell used across list/table views.
class ResizableHeaderCell extends StatefulWidget {
  final String? label;
  final IconData? icon;
  final String? tooltip;
  final double width;
  final double minWidth;
  final double maxWidth;
  final ValueChanged<double> onResize;
  final TextAlign align;
  final TextStyle? textStyle;
  final Color? iconColor;
  final Color? dividerColor;
  final double dividerHeight;
  final double handleWidth;
  final EdgeInsetsGeometry contentPadding;
  final bool showHoverAffordances;
  final VoidCallback? onSortTap;
  final bool isSorted;
  final bool sortAscending;
  final VoidCallback? onMoreTap;
  final List<PopupMenuEntry<String>> Function(BuildContext context)?
  moreMenuBuilder;
  final ValueChanged<String>? onMoreMenuSelected;

  const ResizableHeaderCell({
    super.key,
    this.label,
    this.icon,
    this.tooltip,
    required this.width,
    this.minWidth = 40,
    this.maxWidth = 500,
    required this.onResize,
    this.align = TextAlign.left,
    this.textStyle,
    this.iconColor,
    this.dividerColor,
    this.dividerHeight = 16,
    this.handleWidth = 8,
    this.contentPadding = const EdgeInsets.only(right: 8),
    this.showHoverAffordances = false,
    this.onSortTap,
    this.isSorted = false,
    this.sortAscending = true,
    this.onMoreTap,
    this.moreMenuBuilder,
    this.onMoreMenuSelected,
  });

  @override
  State<ResizableHeaderCell> createState() => _ResizableHeaderCellState();
}

class _ResizableHeaderCellState extends State<ResizableHeaderCell> {
  bool _isHovered = false;
  late double _currentWidth;

  @override
  void initState() {
    super.initState();
    _currentWidth = widget.width;
  }

  @override
  void didUpdateWidget(ResizableHeaderCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.width != widget.width) {
      _currentWidth = widget.width;
    }
  }

  @override
  Widget build(BuildContext context) {
    final alignment = switch (widget.align) {
      TextAlign.center => Alignment.center,
      TextAlign.right => Alignment.centerRight,
      _ => Alignment.centerLeft,
    };

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: SizedBox(
        width: widget.width,
        height: 24,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Padding(
                padding: widget.contentPadding,
                child: GestureDetector(
                  onTap: widget.onSortTap,
                  behavior: HitTestBehavior.opaque,
                  child: MouseRegion(
                    cursor: widget.onSortTap != null
                        ? SystemMouseCursors.click
                        : SystemMouseCursors.basic,
                    child: Align(
                      alignment: alignment,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.icon != null)
                            Tooltip(
                              message: widget.tooltip ?? widget.label ?? '',
                              child: Icon(
                                widget.icon,
                                size: 16,
                                color: widget.isSorted
                                    ? Theme.of(context).colorScheme.primary
                                    : widget.iconColor ??
                                        Theme.of(context).hintColor,
                              ),
                            )
                          else
                            Flexible(
                              child: Tooltip(
                                message: widget.tooltip ?? widget.label ?? '',
                                child: Text(
                                  widget.label ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: widget.align,
                                  style: widget.isSorted
                                      ? widget.textStyle?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        )
                                      : widget.textStyle,
                                ),
                              ),
                            ),
                          if (widget.onSortTap != null &&
                              (widget.isSorted || _isHovered)) ...[
                            const SizedBox(width: 2),
                            AnimatedOpacity(
                              duration: const Duration(milliseconds: 150),
                              opacity: widget.isSorted ? 1.0 : 0.5,
                              child: Icon(
                                widget.isSorted
                                    ? (widget.sortAscending
                                        ? Icons.arrow_upward
                                        : Icons.arrow_downward)
                                    : Icons.unfold_more,
                                size: 14,
                                color: widget.isSorted
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).hintColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.showHoverAffordances)
              Positioned(
                left: 0,
                right: widget.handleWidth + 2,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  ignoring: !_isHovered,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 140),
                    opacity: _isHovered ? 1 : 0,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          right: 4,
                          top: 2,
                          child: _HeaderIconButton(
                            icon: Icons.more_horiz,
                            tooltip: 'Column options',
                            onTap: (buttonContext) async {
                              final entries =
                                  widget.moreMenuBuilder?.call(context) ??
                                  const <PopupMenuEntry<String>>[];
                              if (entries.isEmpty) {
                                widget.onMoreTap?.call();
                                return;
                              }

                              final buttonBox =
                                  buttonContext.findRenderObject() as RenderBox;
                              final overlay =
                                  Overlay.of(
                                        context,
                                        rootOverlay: true,
                                      ).context.findRenderObject()
                                      as RenderBox;
                              final buttonRect = Rect.fromLTWH(
                                buttonBox
                                    .localToGlobal(
                                      Offset.zero,
                                      ancestor: overlay,
                                    )
                                    .dx,
                                buttonBox
                                    .localToGlobal(
                                      Offset.zero,
                                      ancestor: overlay,
                                    )
                                    .dy,
                                buttonBox.size.width,
                                buttonBox.size.height,
                              );
                              final selected = await showMenu<String>(
                                context: context,
                                position: RelativeRect.fromRect(
                                  buttonRect.shift(const Offset(0, 4)),
                                  Offset.zero & overlay.size,
                                ),
                                items: entries,
                              );
                              if (selected != null) {
                                widget.onMoreMenuSelected?.call(selected);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Positioned(
              right: 0,
              top: 4,
              bottom: 4,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) {
                    _currentWidth = (_currentWidth + details.delta.dx)
                        .clamp(widget.minWidth, widget.maxWidth)
                        .toDouble();
                    widget.onResize(_currentWidth);
                  },
                  child: SizedBox(
                    width: widget.handleWidth,
                    child: Center(
                      child: Container(
                        width: 1,
                        height: widget.dividerHeight,
                        color:
                            widget.dividerColor ??
                            Theme.of(
                              context,
                            ).dividerColor.withValues(alpha: 0.65),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final ValueChanged<BuildContext>? onTap;

  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap?.call(context),
        child: SizedBox(
          width: 22,
          height: 20,
          child: Icon(icon, size: 18, color: Theme.of(context).hintColor),
        ),
      ),
    );
  }
}
