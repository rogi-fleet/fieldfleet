import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Data for a single composition badge chip.
class CompositionBadge {
  final String label;
  final int count;
  final int total;
  final Color color;

  const CompositionBadge({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });
}

/// A row of compact chips showing composition breakdowns (e.g. status or
/// cost-type distribution within a group).
///
/// Each chip renders `count/total` with color-derived styling:
/// - Background: color at 10% opacity
/// - Border: color at 30% opacity
/// - Text: full color
class CompositionBadges extends StatelessWidget {
  final List<CompositionBadge> badges;
  final double spacing;

  const CompositionBadges({
    super.key,
    required this.badges,
    this.spacing = 4,
  });

  @override
  Widget build(BuildContext context) {
    // Only show badges with count > 0
    final visible = badges.where((b) => b.count > 0).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < visible.length; i++) ...[
          if (i > 0) SizedBox(width: spacing),
          _buildChip(visible[i]),
        ],
      ],
    );
  }

  Widget _buildChip(CompositionBadge badge) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: badge.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(
          color: badge.color.withValues(alpha: 0.50),
          width: 1,
        ),
      ),
      child: Text(
        '${badge.count} ${badge.label}',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: badge.color,
          height: 1.2,
        ),
      ),
    );
  }
}
