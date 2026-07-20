import 'package:flutter/material.dart';
import '../../theme/theme.dart';

class DraggableDivider extends StatefulWidget {
  const DraggableDivider({super.key, required this.width});
  final double width;

  @override
  State<DraggableDivider> createState() => _DraggableDividerState();
}

class _DraggableDividerState extends State<DraggableDivider> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        width: widget.width,
        color: AppColors.surface,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 4,
            height: 32,
            decoration: BoxDecoration(
              color: _hovered ? AppColors.secondary : AppColors.cardBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}
