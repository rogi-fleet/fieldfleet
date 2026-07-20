import 'package:flutter/material.dart';
import 'resizable_header_cell.dart';
import 'table_column_schema.dart';

List<Widget> buildTableHeaderCells({
  required BuildContext context,
  required List<TableColumnSchema> columns,
  required Map<String, double> widths,
  bool Function(TableColumnSchema column)? isVisible,
  ValueChanged<TableColumnResize>? onColumnResize,
  TextStyle? textStyle,
  Color? iconColor,
  Color? dividerColor,
  bool showHoverAffordances = false,
  List<PopupMenuEntry<String>> Function(
    TableColumnSchema column,
    BuildContext context,
  )?
  headerMenuBuilder,
  void Function(TableColumnSchema column, String value)? onHeaderMenuSelected,
  void Function(TableColumnSchema column)? onSortTap,
  String? sortedColumnId,
  bool sortAscending = true,
}) {
  final widgets = <Widget>[];
  bool prevHadResizeHandle = false;
  for (final column in columns) {
    final visible = isVisible?.call(column) ?? true;
    if (!visible) continue;

    final isSorted = sortedColumnId == column.id;
    final width = widths[column.id] ?? column.defaultWidth;
    Widget wrapBorder(Widget child) {
      // Skip the left border when the previous column already drew a resize-
      // handle divider — otherwise two vertical lines appear side-by-side.
      if (!column.borderLeft || prevHadResizeHandle) return child;
      final borderColor =
          dividerColor ?? Theme.of(context).colorScheme.outlineVariant;
      // When the column is resizable, make the left border a drag handle so
      // the user can also resize from the left edge (e.g. the Name↔Qty boundary).
      if (column.resizable && onColumnResize != null) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LeftBorderResizeHandle(
              columnWidth: width,
              minWidth: column.minWidth,
              maxWidth: column.maxWidth,
              dividerColor: borderColor,
              onResize: (newWidth) => onColumnResize(
                TableColumnResize(columnId: column.id, width: newWidth),
              ),
            ),
            child,
          ],
        );
      }
      return Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: borderColor),
          ),
        ),
        padding: const EdgeInsets.only(left: 8),
        child: child,
      );
    }

    if (column.resizable && onColumnResize != null) {
      widgets.add(
        wrapBorder(ResizableHeaderCell(
          label: column.label,
          icon: column.icon,
          tooltip: column.tooltip,
          width: width,
          minWidth: column.minWidth,
          maxWidth: column.maxWidth,
          onResize: (newWidth) => onColumnResize(
            TableColumnResize(columnId: column.id, width: newWidth),
          ),
          align: column.align,
          textStyle: textStyle,
          iconColor: iconColor,
          dividerColor: dividerColor,
          showHoverAffordances: showHoverAffordances,
          onSortTap: onSortTap != null ? () => onSortTap(column) : null,
          isSorted: isSorted,
          sortAscending: isSorted ? sortAscending : true,
          moreMenuBuilder: headerMenuBuilder == null
              ? null
              : (ctx) => headerMenuBuilder(column, ctx),
          onMoreMenuSelected: onHeaderMenuSelected == null
              ? null
              : (value) => onHeaderMenuSelected(column, value),
        )),
      );
      prevHadResizeHandle = true;
      continue;
    }

    // For non-resizable columns: if sort is enabled, use a sortable label
    if (onSortTap != null) {
      widgets.add(
        wrapBorder(_NonResizableSortableHeader(
          label: column.label,
          icon: column.icon,
          tooltip: column.tooltip,
          width: width,
          align: column.align,
          textStyle: textStyle,
          iconColor: iconColor,
          isSorted: isSorted,
          sortAscending: isSorted ? sortAscending : true,
          onTap: () => onSortTap(column),
        )),
      );
    } else {
      widgets.add(
        wrapBorder(SizedBox(
          width: width,
          child: column.icon != null
              ? Tooltip(
                  message: column.tooltip ?? column.label ?? '',
                  child: Align(
                    alignment: switch (column.align) {
                      TextAlign.center => Alignment.center,
                      TextAlign.right => Alignment.centerRight,
                      _ => Alignment.centerLeft,
                    },
                    child: Icon(
                      column.icon,
                      size: 16,
                      color: iconColor ?? Theme.of(context).hintColor,
                    ),
                  ),
                )
              : Text(
                  column.label ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: column.align,
                  style: textStyle,
                ),
        )),
      );
    }
    prevHadResizeHandle = false;
  }
  return widgets;
}

/// Draggable left-border handle that resizes a column from its left edge.
/// Drag direction is inverted: dragging left widens the column.
class _LeftBorderResizeHandle extends StatefulWidget {
  final double columnWidth;
  final double minWidth;
  final double maxWidth;
  final Color dividerColor;
  final ValueChanged<double> onResize;

  const _LeftBorderResizeHandle({
    required this.columnWidth,
    required this.minWidth,
    required this.maxWidth,
    required this.dividerColor,
    required this.onResize,
  });

  @override
  State<_LeftBorderResizeHandle> createState() =>
      _LeftBorderResizeHandleState();
}

class _LeftBorderResizeHandleState extends State<_LeftBorderResizeHandle> {
  late double _trackedWidth;

  @override
  void initState() {
    super.initState();
    _trackedWidth = widget.columnWidth;
  }

  @override
  void didUpdateWidget(_LeftBorderResizeHandle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.columnWidth != widget.columnWidth) {
      _trackedWidth = widget.columnWidth;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          _trackedWidth = (_trackedWidth - details.delta.dx)
              .clamp(widget.minWidth, widget.maxWidth)
              .toDouble();
          widget.onResize(_trackedWidth);
        },
        child: SizedBox(
          width: 8,
          child: Center(
            child: Container(
              width: 1,
              height: 16,
              color: widget.dividerColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// Sortable header cell for non-resizable columns when sort is enabled.
class _NonResizableSortableHeader extends StatefulWidget {
  final String? label;
  final IconData? icon;
  final String? tooltip;
  final double width;
  final TextAlign align;
  final TextStyle? textStyle;
  final Color? iconColor;
  final bool isSorted;
  final bool sortAscending;
  final VoidCallback onTap;

  const _NonResizableSortableHeader({
    this.label,
    this.icon,
    this.tooltip,
    required this.width,
    this.align = TextAlign.left,
    this.textStyle,
    this.iconColor,
    required this.isSorted,
    required this.sortAscending,
    required this.onTap,
  });

  @override
  State<_NonResizableSortableHeader> createState() =>
      _NonResizableSortableHeaderState();
}

class _NonResizableSortableHeaderState
    extends State<_NonResizableSortableHeader> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final alignment = switch (widget.align) {
      TextAlign.center => Alignment.center,
      TextAlign.right => Alignment.centerRight,
      _ => Alignment.centerLeft,
    };

    final sortIcon = widget.isSorted
        ? (widget.sortAscending ? Icons.arrow_upward : Icons.arrow_downward)
        : Icons.unfold_more;
    final showIcon = widget.isSorted || _isHovered;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: widget.width,
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
                          : widget.iconColor ?? Theme.of(context).hintColor,
                    ),
                  )
                else
                  Flexible(
                    child: Text(
                      widget.label ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: widget.align,
                      style: widget.isSorted
                          ? widget.textStyle?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : widget.textStyle,
                    ),
                  ),
                if (showIcon) ...[
                  const SizedBox(width: 2),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: widget.isSorted ? 1.0 : 0.5,
                    child: Icon(
                      sortIcon,
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
    );
  }
}
