import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Shared styling tokens for segmented toolbar toggles.
class SegmentedToggleStyles {
  const SegmentedToggleStyles._();

  static ButtonStyle toolbar(BuildContext context, {bool compact = false}) {
    final colorScheme = Theme.of(context).colorScheme;

    return ButtonStyle(
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      tapTargetSize: compact
          ? MaterialTapTargetSize.shrinkWrap
          : MaterialTapTargetSize.padded,
      minimumSize: WidgetStateProperty.all(Size(0, compact ? 34 : 40)),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      ),
      textStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      side: WidgetStateProperty.resolveWith((states) {
        return BorderSide(
          color: states.contains(WidgetState.selected)
              ? colorScheme.outline
              : colorScheme.outlineVariant,
        );
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.secondary;
        }
        return colorScheme.onSurfaceVariant;
      }),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        return colorScheme.surface;
      }),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return AppColors.secondary.withValues(alpha: 0.12);
        }
        if (states.contains(WidgetState.hovered)) {
          return AppColors.secondary.withValues(alpha: 0.06);
        }
        return null;
      }),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }
}
