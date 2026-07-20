import 'package:flutter/material.dart';

class StackedField extends StatelessWidget {
  const StackedField({
    super.key,
    required this.label,
    required this.child,
    this.spacing = 6,
    this.labelColor,
  });

  final String label;
  final Widget child;
  final double spacing;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: labelColor,
          ),
        ),
        SizedBox(height: spacing),
        child,
      ],
    );
  }
}
