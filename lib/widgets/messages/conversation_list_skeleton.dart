import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../theme/theme.dart';

/// Skeleton placeholder for the conversation list while data is loading.
/// Mirrors the layout of [ConversationListItem].
class ConversationListSkeleton extends StatelessWidget {
  final int itemCount;

  const ConversationListSkeleton({super.key, this.itemCount = 8});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? Colors.grey.shade800 : AppColors.cardBorder,
      highlightColor: isDark ? Colors.grey.shade700 : AppColors.surfaceAlt,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        itemCount: itemCount,
        itemBuilder: (_, index) => _ConversationSkeletonRow(index: index),
      ),
    );
  }
}

class _ConversationSkeletonRow extends StatelessWidget {
  final int index;
  const _ConversationSkeletonRow({required this.index});

  @override
  Widget build(BuildContext context) {
    // Vary widths so rows don't all look identical
    final titleWidth = 120.0 + (index % 4) * 25.0;
    final subtitleWidth = 160.0 + (index % 3) * 30.0;
    final scopeWidth = 40.0 + (index % 3) * 10.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Unread indicator bar
            Container(
              width: 3,
              height: 54,
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            // Avatar circle
            Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(top: 2),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            // Content column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + timestamp row
                  Row(
                    children: [
                      _box(height: 14, width: titleWidth),
                      const Spacer(),
                      _box(height: 11, width: 32),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Subtitle
                  _box(height: 13, width: subtitleWidth),
                  const SizedBox(height: 8),
                  // Scope label row
                  Row(
                    children: [
                      _box(height: 11, width: scopeWidth),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _box({required double height, required double width}) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
    );
  }
}
