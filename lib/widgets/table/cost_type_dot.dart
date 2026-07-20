import 'package:flutter/material.dart';

/// Small colored circle indicator, typically used to show cost type alongside
/// an item name (labor, material, other).
class CostTypeDot extends StatelessWidget {
  const CostTypeDot({
    super.key,
    required this.color,
    this.size = 8,
    this.tooltip,
  });

  final Color color;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: dot);
    }
    return dot;
  }
}
