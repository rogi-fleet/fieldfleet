import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Shared visual tokens for table/list views (task, budget, property).
class TableViewStyles {
  const TableViewStyles._();

  static TextStyle? headerLabelStyle(BuildContext context) {
    return Theme.of(context).textTheme.labelMedium?.copyWith(
      color: AppColors.textSecondary,
      fontWeight: FontWeight.w600,
    );
  }

  static BorderSide rowDivider(BuildContext context) {
    return BorderSide(
      color: Theme.of(
        context,
      ).colorScheme.outlineVariant.withValues(alpha: 0.5),
      width: 1,
    );
  }
}
