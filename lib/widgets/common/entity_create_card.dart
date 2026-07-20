import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../theme/theme.dart';

enum EntityCreateCardSize { compact, regular, tall }

class EntityCreateCard extends StatefulWidget {
  final VoidCallback onTap;
  final String title;
  final String subtitle;
  final double minHeight;
  final IconData icon;
  final EntityCreateCardSize size;

  const EntityCreateCard({
    super.key,
    required this.onTap,
    required this.title,
    required this.subtitle,
    this.minHeight = 440,
    this.icon = Icons.add,
    this.size = EntityCreateCardSize.regular,
  });

  @override
  State<EntityCreateCard> createState() => _EntityCreateCardState();
}

class _EntityCreateCardState extends State<EntityCreateCard> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final borderColor = primary.withValues(alpha: _isHovered ? 0.72 : 0.5);
    final iconBg = primary.withValues(alpha: _isHovered ? 0.24 : 0.16);
    final iconBorder = primary.withValues(alpha: _isHovered ? 0.34 : 0.22);
    final scale = _isPressed ? 0.985 : (_isHovered ? 1.015 : 1.0);
    final shadowAlpha = _isHovered ? 0.18 : 0.08;
    final iconBaseSize = switch (widget.size) {
      EntityCreateCardSize.compact => 62.0,
      EntityCreateCardSize.regular => 78.0,
      EntityCreateCardSize.tall => 86.0,
    };
    final iconSize = switch (widget.size) {
      EntityCreateCardSize.compact => 34.0,
      EntityCreateCardSize.regular => 42.0,
      EntityCreateCardSize.tall => 46.0,
    };
    final titleFontSize = switch (widget.size) {
      EntityCreateCardSize.compact => 16.0,
      EntityCreateCardSize.regular => 20.0,
      EntityCreateCardSize.tall => 22.0,
    };
    final subtitleFontSize = switch (widget.size) {
      EntityCreateCardSize.compact => 14.0,
      EntityCreateCardSize.regular => 15.0,
      EntityCreateCardSize.tall => 16.0,
    };
    final verticalPadding = switch (widget.size) {
      EntityCreateCardSize.compact => AppSpacing.md,
      EntityCreateCardSize.regular => AppSpacing.xl,
      EntityCreateCardSize.tall => AppSpacing.xl,
    };

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
      }),
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
          child: InkWell(
            onTap: widget.onTap,
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapCancel: () => setState(() => _isPressed = false),
            onTapUp: (_) => setState(() => _isPressed = false),
            borderRadius: AppRadius.cardRadius,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: AppRadius.cardRadius,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    primary.withValues(alpha: _isHovered ? 0.13 : 0.08),
                    primary.withValues(alpha: _isHovered ? 0.05 : 0.02),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: primary.withValues(alpha: shadowAlpha),
                    blurRadius: _isHovered ? 18 : 10,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: CustomPaint(
                foregroundPainter: _DashedRoundedBorderPainter(
                  color: borderColor,
                  strokeWidth: _isHovered ? 1.8 : 1.5,
                  dash: 8,
                  gap: 6,
                  borderRadius: AppRadius.cardRadius,
                ),
                child: Container(
                  constraints: BoxConstraints(minHeight: widget.minHeight),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: 0,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(height: verticalPadding),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        curve: Curves.easeOut,
                        width: _isHovered ? iconBaseSize + 6 : iconBaseSize,
                        height: _isHovered ? iconBaseSize + 6 : iconBaseSize,
                        decoration: BoxDecoration(
                          color: iconBg,
                          shape: BoxShape.circle,
                          border: Border.all(color: iconBorder, width: 2.2),
                        ),
                        child: Icon(
                          widget.icon,
                          size: _isHovered ? iconSize + 2 : iconSize,
                          color: primary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        widget.subtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: subtitleFontSize,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      SizedBox(height: verticalPadding),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedRoundedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dash;
  final double gap;
  final BorderRadius borderRadius;

  const _DashedRoundedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.dash,
    required this.gap,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect).deflate(strokeWidth / 2);
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color;

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoundedBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.dash != dash ||
        oldDelegate.gap != gap ||
        oldDelegate.borderRadius != borderRadius;
  }
}
