import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// Pill sizes for [StatusChip]. `regular` suits cards and detail headers;
/// `compact` suits dense table rows.
enum StatusChipSize { regular, compact }

/// Canonical status pill: tinted background, matching border and label.
///
/// Replaces the half-dozen private `_StatusChip` copies that each rendered
/// the same visual language with slightly different padding, radius and
/// font size. Callers keep their own status → (label, color) mapping and
/// hand the resolved pair here, so every status reads the same everywhere.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.size = StatusChipSize.regular,
    this.outlined = true,
  });

  final String label;
  final Color color;
  final StatusChipSize size;

  /// Set false for ultra-dense contexts where the border adds visual noise.
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final compact = size == StatusChipSize.compact;
    return Container(
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 7, vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.chipRadius,
        border: outlined
            ? Border.all(color: color.withValues(alpha: 0.3))
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: compact ? 11 : 12,
          fontWeight: AppTextWeights.semibold,
          color: color,
        ),
      ),
    );
  }
}
