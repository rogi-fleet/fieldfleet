import 'package:flutter/material.dart';

/// The FieldFleet wordmark.
///
/// Renders the brand lockup entirely as text and shapes so it stays crisp at
/// any size.
/// The lockup is laid out at a fixed internal design size and scaled to the
/// requested [height] with a [FittedBox].
class LogoWidget extends StatelessWidget {
  final double height;
  final bool showTagline;
  final Color? textColor;
  final bool lightTheme;

  const LogoWidget({
    super.key,
    this.height = 80,
    this.showTagline = true,
    this.textColor,
    this.lightTheme = false,
  });

  /// Brand colors sampled from the FieldFleet logo artwork. Kept in sync with
  /// `tool/generate_brand_logos.dart`, which renders the matching app icons.
  static const Color _navy = Color(0xFF12283F);
  static const Color _orange = Color(0xFFF47A2A);

  @override
  Widget build(BuildContext context) {
    final wordColor = textColor ?? (lightTheme ? Colors.white : _navy);

    // The lockup is built at these absolute sizes and then scaled down to
    // [height] by the FittedBox, so glyphs are always rendered larger than
    // they display — keeping them sharp.
    final wordmark = Text(
      'FieldFleet',
      style: TextStyle(
        fontFamily: 'Arial',
        fontSize: 100,
        fontWeight: FontWeight.w800,
        letterSpacing: -3,
        height: 1.0,
        color: wordColor,
        shadows: [
          Shadow(
            color: _orange.withValues(alpha: 0.16),
            offset: const Offset(4, 4),
            blurRadius: 0,
          ),
        ],
      ),
    );

    final Widget lockup = showTagline
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              wordmark,
              const SizedBox(height: 14),
              Text(
                'FIELD OPERATIONS PLATFORM',
                style: TextStyle(
                  fontFamily: 'Arial',
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 4.5,
                  height: 1.0,
                  color: wordColor.withValues(alpha: 0.55),
                ),
              ),
            ],
          )
        : wordmark;

    return SizedBox(
      height: height,
      child: FittedBox(
        fit: BoxFit.contain,
        child: lockup,
      ),
    );
  }
}
