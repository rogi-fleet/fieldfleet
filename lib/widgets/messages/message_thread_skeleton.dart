import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../theme/theme.dart';

/// Skeleton placeholder for the message thread list while data is loading.
/// Mirrors the layout of incoming/outgoing chat bubbles so the load-in is
/// visually consistent with the rendered thread.
class MessageThreadSkeleton extends StatelessWidget {
  final int itemCount;

  const MessageThreadSkeleton({super.key, this.itemCount = 10});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? Colors.grey.shade800 : AppColors.cardBorder,
      highlightColor: isDark ? Colors.grey.shade700 : AppColors.surfaceAlt,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.base, horizontal: AppSpacing.md),
        itemCount: itemCount,
        itemBuilder: (_, index) => _BubbleSkeletonRow(index: index),
      ),
    );
  }
}

class _BubbleSkeletonRow extends StatelessWidget {
  final int index;
  const _BubbleSkeletonRow({required this.index});

  @override
  Widget build(BuildContext context) {
    // Alternate sides with a sticky "run" so consecutive bubbles cluster
    // like a real conversation does.
    final isMe = (index ~/ 2).isOdd;

    // Vary widths and heights so rows don't look identical.
    final bubbleWidth = 140.0 + (index % 5) * 35.0;
    final bubbleHeight = 32.0 + (index % 3) * 16.0;
    final showSenderName = !isMe && index % 2 == 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showSenderName) ...[
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 4),
              child: _box(height: 10, width: 70, radius: AppRadius.xs),
            ),
          ],
          _box(
            height: bubbleHeight,
            width: bubbleWidth,
            radius: AppRadius.lg,
          ),
        ],
      ),
    );
  }

  static Widget _box({
    required double height,
    required double width,
    required double radius,
  }) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
