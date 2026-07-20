import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Reusable responsive card grid used across entity list screens.
class EntityCardGrid extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext context, int index, double cardWidth)
  itemBuilder;
  final Widget Function(BuildContext context, double cardWidth)?
  trailingBuilder;
  final EdgeInsetsGeometry padding;
  final double spacing;
  final double maxCardWidth;
  final int mobileColumns;

  const EntityCardGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.trailingBuilder,
    this.padding = const EdgeInsets.all(AppSpacing.base),
    this.spacing = 12,
    this.maxCardWidth = 380,
    this.mobileColumns = 2,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final horizontalPadding = _horizontalPadding(padding);
        final availableWidth = math.max(0.0, width - (horizontalPadding * 2));
        final columnCount = _columnCount(width, availableWidth);
        final totalCards = itemCount + (trailingBuilder != null ? 1 : 0);

        final totalSpacing = spacing * math.max(0, columnCount - 1);
        final rawCardWidth = columnCount == 0
            ? 0.0
            : math.max(0.0, (availableWidth - totalSpacing) / columnCount);
        final cardWidth = width < AppBreakpoints.mobile
            ? rawCardWidth
            : math.min(maxCardWidth, rawCardWidth);

        if (totalCards == 0) {
          return const SizedBox.shrink();
        }

        final rowCount = (totalCards / columnCount).ceil();

        return ListView.builder(
          padding: padding,
          itemCount: rowCount,
          itemBuilder: (context, rowIndex) {
            final rowChildren = <Widget>[];
            final rowStart = rowIndex * columnCount;
            final rowEnd = math.min(rowStart + columnCount, totalCards);

            for (int index = rowStart; index < rowEnd; index++) {
              if (rowChildren.isNotEmpty) {
                rowChildren.add(SizedBox(width: spacing));
              }

              rowChildren.add(
                SizedBox(
                  width: cardWidth,
                  child: _buildCardAt(context, index, cardWidth),
                ),
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: rowIndex == rowCount - 1 ? 0 : spacing,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: rowChildren,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCardAt(BuildContext context, int index, double cardWidth) {
    if (index < itemCount) {
      return itemBuilder(context, index, cardWidth);
    }
    return trailingBuilder!(context, cardWidth);
  }

  int _columnCount(double width, double availableWidth) {
    if (width < AppBreakpoints.mobile) {
      return mobileColumns == 1 ? 1 : 2;
    }

    final maxWidthColumns =
        ((availableWidth + spacing) / (maxCardWidth + spacing)).floor();
    return math.max(2, maxWidthColumns);
  }

  double _horizontalPadding(EdgeInsetsGeometry geometry) {
    final resolved = geometry.resolve(TextDirection.ltr);
    return resolved.left;
  }
}
