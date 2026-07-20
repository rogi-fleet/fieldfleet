import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// Fixed-width text cell used by table-style rows.
///
/// Handles common placeholder behavior so row widgets do not need to repeat
/// `SizedBox -> Text` boilerplate for simple read-only cells.
class TableTextCell extends StatelessWidget {
  const TableTextCell({
    super.key,
    required this.width,
    this.text,
    this.placeholder = '-',
    this.style,
    this.color,
    this.isBold = false,
    this.textAlign = TextAlign.left,
  });

  final double width;
  final String? text;
  final String placeholder;
  final TextStyle? style;
  final Color? color;
  final bool isBold;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final trimmed = text?.trim();
    final isPlaceholder = trimmed == null || trimmed.isEmpty;

    return SizedBox(
      width: width,
      child: Text(
        isPlaceholder ? placeholder : trimmed,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
        style: (style ?? const TextStyle()).copyWith(
          fontWeight: isBold ? FontWeight.w600 : style?.fontWeight,
          color:
              color ?? (isPlaceholder ? AppColors.textTertiary : style?.color),
        ),
      ),
    );
  }
}
