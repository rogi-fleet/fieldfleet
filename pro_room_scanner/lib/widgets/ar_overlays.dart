import 'package:flutter/material.dart';

/// Overlay that guides the user to scan the floor
class FloorScanningOverlay extends StatefulWidget {
  final bool isScanning;
  final double scanProgress; // 0.0 to 1.0
  final VoidCallback? onScanComplete;

  const FloorScanningOverlay({
    Key? key,
    required this.isScanning,
    this.scanProgress = 0.0,
    this.onScanComplete,
  }) : super(key: key);

  @override
  State<FloorScanningOverlay> createState() => _FloorScanningOverlayState();
}

class _FloorScanningOverlayState extends State<FloorScanningOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isScanning) return const SizedBox.shrink();

    return IgnorePointer(
      child: Stack(
        children: [
          // Animated Grid
          Positioned.fill(
            child: CustomPaint(
              painter: _GridPainter(
                animationValue: _controller,
                progress: widget.scanProgress,
              ),
            ),
          ),
          
          // Center Scanning Indicator
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.5 * (1 - _controller.value)),
                      width: 2,
                    ),
                    gradient: RadialGradient(
                      colors: [
                        Colors.blue.withValues(alpha: 0.2 * (1 - _controller.value)),
                        Colors.transparent,
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final Animation<double> animationValue;
  final double progress;

  _GridPainter({required this.animationValue, required this.progress}) : super(repaint: animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final double gridSize = 50.0;
    final double offset = animationValue.value * gridSize;

    // Draw vertical lines
    for (double x = size.width / 2 % gridSize - gridSize; x < size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Draw horizontal lines with movement
    for (double y = size.height / 2 % gridSize - gridSize + offset; y < size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    
    // Draw progress circle
    if (progress > 0) {
      final Paint progressPaint = Paint()
        ..color = Colors.green.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill;
        
      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        100 * progress,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => true;
}

/// Center crosshair for targeting with Ghost Line support
class CrosshairOverlay extends StatelessWidget {
  final bool isPlaneDetected;
  final double? distance;
  // ghostLineStart removed as it was unused and causing initialization error
  final double? ghostLineLength;
  final bool isSnapped;

  const CrosshairOverlay({
    Key? key,
    required this.isPlaneDetected,
    this.distance,
    this.ghostLineLength,
    this.isSnapped = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ghost Line Length Indicator
          if (ghostLineLength != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSnapped ? Colors.green : Colors.blue.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(16),
                border: isSnapped ? Border.all(color: Colors.white, width: 2) : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSnapped) ...[
                    const Icon(Icons.link, color: Colors.white, size: 16),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    "${ghostLineLength!.toStringAsFixed(2)}m",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          // Crosshair
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isSnapped 
                    ? Colors.green 
                    : (isPlaneDetected ? Colors.green : Colors.white.withValues(alpha: 0.5)),
                width: isSnapped ? 3 : 2,
              ),
            ),
            child: Center(
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: isSnapped ? Colors.green : (isPlaneDetected ? Colors.green : Colors.white),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          
          // Distance to surface
          if (distance != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                "Dist: ${distance!.toStringAsFixed(2)}m",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tutorial overlay for first-time users
class TutorialOverlay extends StatelessWidget {
  final VoidCallback onDismiss;

  const TutorialOverlay({Key? key, required this.onDismiss}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black87,
      child: InkWell(
        onTap: onDismiss,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.phone_android, size: 64, color: Colors.white),
                const SizedBox(height: 24),
                const Text(
                  "Scan the Floor",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "1. Point your camera at the floor\n2. Move slowly side to side\n3. Tap to place corners",
                  style: TextStyle(color: Colors.white70, fontSize: 16, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: onDismiss,
                  child: const Text("Got it"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
