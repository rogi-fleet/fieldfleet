import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../theme/theme.dart';

/// Generic skeleton for list screens. Shows [itemCount] placeholder rows
/// while data is loading. Each row mirrors a typical entity list item:
/// a circle avatar on the left + two lines of text.
class ListSkeleton extends StatelessWidget {
  final int itemCount;
  final EdgeInsetsGeometry padding;

  const ListSkeleton({
    super.key,
    this.itemCount = 8,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? Colors.grey.shade800 : AppColors.cardBorder,
      highlightColor: isDark ? Colors.grey.shade700 : AppColors.surfaceAlt,
      child: ListView.separated(
        padding: padding,
        itemCount: itemCount,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, index) => _SkeletonRow(index: index),
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  final int index;
  const _SkeletonRow({required this.index});

  @override
  Widget build(BuildContext context) {
    // Vary widths slightly so rows don't all look identical
    final titleWidth = 140.0 + (index % 3) * 30.0;
    final subtitleWidth = 90.0 + (index % 4) * 20.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          // Avatar circle
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 14,
                  width: titleWidth,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 12,
                  width: subtitleWidth,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Trailing badge placeholder
          Container(
            width: 60,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
          ),
        ],
      ),
    );
  }
}
