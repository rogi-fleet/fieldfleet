import 'package:flutter/material.dart';
import '../../theme/theme.dart';

class CardPlaceholderBackground extends StatelessWidget {
  final bool compact;
  final Widget? centerOverlay;
  final double? watermarkSize;

  const CardPlaceholderBackground({
    super.key,
    this.compact = false,
    this.centerOverlay,
    this.watermarkSize,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveWatermarkSize = watermarkSize ?? (compact ? 84.0 : 172.0);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0A1628),
            Color(0xFF0D4F8B),
            AppColors.textSecondary,
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _CardPlaceholderGridPainter()),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.06),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.22),
                  ],
                ),
              ),
            ),
          ),
          _buildConstructionBlock(
            top: compact ? -8 : -10,
            left: compact ? -8 : -6,
            width: compact ? 44 : 86,
            height: compact ? 30 : 56,
            opacity: 0.16,
          ),
          _buildConstructionBlock(
            top: compact ? 18 : 40,
            right: compact ? -10 : -8,
            width: compact ? 36 : 78,
            height: compact ? 42 : 118,
            opacity: 0.16,
          ),
          _buildConstructionBlock(
            bottom: compact ? -10 : -12,
            left: compact ? 16 : 36,
            width: compact ? 60 : 138,
            height: compact ? 42 : 112,
            opacity: 0.1,
          ),
          _buildConstructionBlock(
            bottom: compact ? 12 : 24,
            right: compact ? 14 : 22,
            width: compact ? 30 : 94,
            height: compact ? 28 : 56,
            opacity: 0.15,
          ),
          Center(
            child: Opacity(
              opacity: 0.12,
              child: Image.asset(
                'assets/images/logo_icon.png',
                width: effectiveWatermarkSize,
                height: effectiveWatermarkSize,
                fit: BoxFit.contain,
                color: Colors.white,
                colorBlendMode: BlendMode.srcATop,
              ),
            ),
          ),
          if (centerOverlay != null) Center(child: centerOverlay!),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.2),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConstructionBlock({
    double? top,
    double? right,
    double? bottom,
    double? left,
    required double width,
    required double height,
    required double opacity,
  }) {
    return Positioned(
      top: top,
      right: right,
      bottom: bottom,
      left: left,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: opacity),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _CardPlaceholderGridPainter extends CustomPainter {
  const _CardPlaceholderGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;

    const spacing = 44.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
