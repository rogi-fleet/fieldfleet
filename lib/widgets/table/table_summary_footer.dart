import 'package:flutter/material.dart';
import 'table_column_schema.dart';
import 'table_text_cell.dart';
import '../../theme/theme.dart';

/// Reusable sticky footer row for table views showing aggregated totals.
///
/// 40px height, [surfaceContainerHighest] background, top border.
/// Scrolls horizontally with columns but stays pinned at the bottom.
class TableSummaryFooter extends StatelessWidget {
  final String label;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  const TableSummaryFooter({
    super.key,
    this.label = 'TOTALS',
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.base),
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 44,
      padding: padding,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        border: Border(
          top: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
      child: Row(children: children),
    );
  }
}

/// Fixed-width footer cell for simple summary values.
class TableSummaryCell extends StatelessWidget {
  const TableSummaryCell({
    super.key,
    required this.width,
    this.text,
    this.placeholder = '-',
    this.color,
    this.isBold = false,
    this.textAlign = TextAlign.left,
  });

  final double width;
  final String? text;
  final String placeholder;
  final Color? color;
  final bool isBold;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return TableTextCell(
      width: width,
      text: text,
      placeholder: placeholder,
      isBold: isBold,
      color: color,
      textAlign: textAlign,
      style: const TextStyle(fontSize: 13),
    );
  }
}

/// Expanded leading label area used at the start of summary/footer rows.
class TableSummaryLabel extends StatelessWidget {
  const TableSummaryLabel({
    super.key,
    required this.text,
    this.inset = 0,
    this.style,
  });

  final String text;
  final double inset;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Row(
        children: [
          if (inset > 0) SizedBox(width: inset),
          Text(
            text,
            style:
                style ??
                TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: colorScheme.primary,
                ),
          ),
        ],
      ),
    );
  }
}

/// Builds aligned footer cells matching column widths, mirroring
/// [buildTableHeaderCells]. Unmapped columns get a dash placeholder.
List<Widget> buildTableFooterCells({
  required BuildContext context,
  required List<TableColumnSchema> columns,
  required Map<String, double> widths,
  required Map<String, Widget> cellMap,
  bool Function(TableColumnSchema column)? isVisible,
}) {
  final widgets = <Widget>[];
  for (final column in columns) {
    final visible = isVisible?.call(column) ?? true;
    if (!visible) continue;

    final width = widths[column.id] ?? column.defaultWidth;
    final cell = cellMap[column.id];
    Widget child = SizedBox(
      width: width,
      child:
          cell ??
          Text(
            '-',
            style: const TextStyle(fontSize: 13, color: Color(0xFF9E9E9E)),
          ),
    );
    if (column.borderLeft) {
      child = Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        padding: const EdgeInsets.only(left: 8),
        child: child,
      );
    }
    widgets.add(child);
  }
  return widgets;
}
