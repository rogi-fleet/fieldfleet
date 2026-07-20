import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Displays a numeric value with color based on its sign:
/// positive → green, negative → red, zero → tertiary gray.
class ConditionalValueText extends StatelessWidget {
  const ConditionalValueText({
    super.key,
    required this.value,
    required this.displayText,
    this.positiveColor,
    this.negativeColor,
    this.zeroColor,
    this.style,
    this.textAlign = TextAlign.left,
  });

  final double value;
  final String displayText;
  final Color? positiveColor;
  final Color? negativeColor;
  final Color? zeroColor;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final Color color;
    if (value > 0) {
      color = positiveColor ?? AppColors.success;
    } else if (value < 0) {
      color = negativeColor ?? AppColors.error;
    } else {
      color = zeroColor ?? AppColors.textTertiary;
    }
    return Text(displayText, textAlign: textAlign, style: (style ?? const TextStyle()).copyWith(color: color));
  }
}
