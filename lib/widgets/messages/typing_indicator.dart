import 'package:flutter/material.dart';
import '../../theme/theme.dart';

class TypingIndicator extends StatefulWidget {
  final List<String> typingUserNames;

  const TypingIndicator({super.key, required this.typingUserNames});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _buildLabel() {
    if (widget.typingUserNames.isEmpty) return '';
    if (widget.typingUserNames.length == 1) {
      return '${widget.typingUserNames[0]} is typing';
    }
    if (widget.typingUserNames.length == 2) {
      return '${widget.typingUserNames[0]} and ${widget.typingUserNames[1]} are typing';
    }
    return 'Several people are typing';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.typingUserNames.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.xs),
      child: Row(
        children: [
          _AnimatedDots(controller: _controller),
          const SizedBox(width: 8),
          Text(
            _buildLabel(),
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedDots extends StatelessWidget {
  final AnimationController controller;

  const _AnimatedDots({required this.controller});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Each dot peaks at a different phase
            final phase = (controller.value - i * 0.2).clamp(0.0, 1.0);
            final opacity = (0.3 + 0.7 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2)).clamp(0.3, 1.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.onSurface.withValues(alpha: opacity),
              ),
            );
          }),
        );
      },
    );
  }
}
