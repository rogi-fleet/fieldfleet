import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../theme/theme.dart';

/// A celebration animation widget that shows when a task is completed
class CompletionCelebration extends StatefulWidget {
  final VoidCallback? onComplete;

  const CompletionCelebration({super.key, this.onComplete});

  @override
  State<CompletionCelebration> createState() => _CompletionCelebrationState();
}

class _CompletionCelebrationState extends State<CompletionCelebration>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<Particle> _particles = [];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // Generate particles
    final random = math.Random();
    for (int i = 0; i < 30; i++) {
      _particles.add(
        Particle(
          color: _getRandomColor(random),
          angle: random.nextDouble() * 2 * math.pi,
          velocity: 50 + random.nextDouble() * 100,
          size: 4 + random.nextDouble() * 8,
        ),
      );
    }

    _controller.forward().then((_) {
      widget.onComplete?.call();
    });
  }

  Color _getRandomColor(math.Random random) {
    final colors = [
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.yellow,
      Colors.orange,
      Colors.purple,
      Colors.pink,
      Colors.cyan,
    ];
    return colors[random.nextInt(colors.length)];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          children: [
            // Center checkmark
            Center(
              child: Opacity(
                opacity: 1 - _controller.value,
                child: Transform.scale(
                  scale: 0.5 + (_controller.value * 0.5),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.success.withOpacity(0.4),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 50,
                    ),
                  ),
                ),
              ),
            ),
            // Particles
            ..._particles.map((particle) {
              final progress = _controller.value;
              final x = math.cos(particle.angle) * particle.velocity * progress;
              final y =
                  math.sin(particle.angle) * particle.velocity * progress +
                  (100 * progress * progress); // Add gravity

              return Positioned(
                left:
                    MediaQuery.of(context).size.width / 2 +
                    x -
                    particle.size / 2,
                top:
                    MediaQuery.of(context).size.height / 2 +
                    y -
                    particle.size / 2,
                child: Opacity(
                  opacity: 1 - progress,
                  child: Container(
                    width: particle.size,
                    height: particle.size,
                    decoration: BoxDecoration(
                      color: particle.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class Particle {
  final Color color;
  final double angle;
  final double velocity;
  final double size;

  Particle({
    required this.color,
    required this.angle,
    required this.velocity,
    required this.size,
  });
}

/// Shows a celebration overlay
void showCelebration(BuildContext context) {
  final overlay = Overlay.of(context);
  late OverlayEntry overlayEntry;

  overlayEntry = OverlayEntry(
    builder: (context) => CompletionCelebration(
      onComplete: () {
        overlayEntry.remove();
      },
    ),
  );

  overlay.insert(overlayEntry);
}
