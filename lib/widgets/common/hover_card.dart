import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// A Card wrapper that adds a subtle hover effect — shadow lift and border
/// enhancement — for desktop pointer interaction. On mobile, it behaves
/// identically to a standard Card.
class HoverCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;
  final Clip clipBehavior;
  final double minHeight;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;

  const HoverCard({
    super.key,
    required this.child,
    this.margin,
    this.clipBehavior = Clip.antiAlias,
    this.minHeight = 0,
    this.borderRadius,
    this.onTap,
  });

  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? AppRadius.cardRadius;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        margin: widget.margin ?? EdgeInsets.zero,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: radius,
          border: Border.all(
            color: _hovered
                ? AppColors.cardBorder.withValues(alpha: 0.8)
                : AppColors.cardBorder,
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0),
                    blurRadius: 0,
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          clipBehavior: widget.clipBehavior,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: radius,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
