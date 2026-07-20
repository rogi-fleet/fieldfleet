import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Circular arc gauge showing a margin percentage.
class BudgetMarginGauge extends StatelessWidget {
  final double percentage;
  final double? targetPercentage;
  final double size;

  const BudgetMarginGauge({
    super.key,
    required this.percentage,
    this.targetPercentage,
    this.size = 180,
  });

  @override
  Widget build(BuildContext context) {
    final color = percentage >= 0 ? AppColors.success : AppColors.error;
    final delta =
        targetPercentage != null ? percentage - targetPercentage! : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _GaugePainter(
              percentage: percentage.clamp(0, 100),
              trackColor: color.withValues(alpha: 0.25),
              fillColor: color,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${percentage.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  const Text(
                    'projected',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (targetPercentage != null) ...[
          const SizedBox(height: 8),
          Text(
            'Target was ${targetPercentage!.toStringAsFixed(1)}%',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          if (delta != null)
            Text(
              '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}% ${delta >= 0 ? 'above' : 'below'} target',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: delta >= 0 ? AppColors.success : AppColors.error,
              ),
            ),
        ],
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double percentage;
  final Color trackColor;
  final Color fillColor;

  _GaugePainter({
    required this.percentage,
    required this.trackColor,
    required this.fillColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) / 2) - 6;
    const strokeWidth = 14.0;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Full circle track
    canvas.drawCircle(center, radius, trackPaint);

    // Filled arc — starts at top (-90 degrees)
    final sweepAngle = (percentage / 100) * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter oldDelegate) =>
      oldDelegate.percentage != percentage ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.fillColor != fillColor;
}
