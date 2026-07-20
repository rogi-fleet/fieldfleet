import 'package:flutter/material.dart';
import '../../theme/theme.dart';
import 'timeline_calculator.dart';

class TimelineHeader extends StatelessWidget {
  final TimelineCalculator calculator;
  final ScrollController scrollController;

  const TimelineHeader({
    super.key,
    required this.calculator,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final labels = calculator.generateDateLabels();
    final pixelsPerDay = calculator.pixelsPerDay;

    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 2,
          ),
        ),
      ),
      child: ListView.builder(
        controller: scrollController,
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        itemCount: labels.length,
        itemBuilder: (context, index) {
          final label = labels[index];
          final width = calculator.viewMode == TimelineView.day
              ? pixelsPerDay / 24 // Hourly segments for day view
              : calculator.viewMode == TimelineView.week
                  ? pixelsPerDay // Daily segments for week view
                  : calculator.viewMode == TimelineView.month
                      ? pixelsPerDay * 7 // Weekly segments for month view
                      : calculator.viewMode == TimelineView.year
                          ? pixelsPerDay * 91 // Quarterly segments for year view
                          : pixelsPerDay * 30; // Monthly segments for quarter view

          return Container(
            width: width,
            decoration: BoxDecoration(
              color: label.isWeekend
                  ? Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3)
                  : null,
              border: Border(
                right: BorderSide(
                  color: Theme.of(context).dividerColor.withOpacity(0.3),
                ),
              ),
            ),
            child: Center(
              child: Text(
                label.label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: label.isWeekend
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
          );
        },
      ),
    );
  }
}

class TodayIndicator extends StatelessWidget {
  final TimelineCalculator calculator;
  final double height;

  const TodayIndicator({
    super.key,
    required this.calculator,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final range = calculator.getVisibleRange();
    final now = DateTime.now();

    // Don't show if today is not in visible range
    if (now.isBefore(range.start) || now.isAfter(range.end)) {
      return const SizedBox.shrink();
    }

    final position = calculator.dateToPixel(now, range.start);

    return Positioned(
      left: position,
      top: 0,
      bottom: 0,
      child: Container(
        width: 2,
        height: height,
        color: AppColors.error,
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.error,
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
            child: Text(
              'Today',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
