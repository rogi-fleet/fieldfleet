import 'package:flutter/material.dart';

import 'app_text_weights.dart';

/// Named typography scale for the FieldFleet design system.
///
/// The codebase has 3,000+ inline `fontSize:` literals spread across ~20
/// distinct sizes with no naming convention. These tokens collapse that to
/// nine documented slots. Inline `TextStyle(fontSize: ...)` should be
/// replaced with a slot (plus `.copyWith(...)` for color/weight overrides)
/// as code is touched.
///
/// Styles deliberately carry no color so they stay valid under any theme
/// brightness — color comes from the ambient `DefaultTextStyle` or an
/// explicit `.copyWith(color: ...)`.
///
///   display   → marketing/hero numbers, onboarding headlines
///   h1        → page titles
///   h2        → section titles, dialog titles
///   h3        → card titles, emphasized rows
///   body      → default copy, form values
///   bodySmall → dense table cells, secondary copy
///   caption   → helper text, timestamps, metadata
///   label     → chip labels, table headers, overlines
///   micro     → tiny annotations (chart axes, badge counts)
abstract final class AppTextStyles {
  static const TextStyle display = TextStyle(
    fontSize: 32,
    fontWeight: AppTextWeights.bold,
    height: 1.2,
  );

  static const TextStyle h1 = TextStyle(
    fontSize: 24,
    fontWeight: AppTextWeights.semibold,
    height: 1.25,
  );

  static const TextStyle h2 = TextStyle(
    fontSize: 20,
    fontWeight: AppTextWeights.semibold,
    height: 1.3,
  );

  static const TextStyle h3 = TextStyle(
    fontSize: 16,
    fontWeight: AppTextWeights.semibold,
    height: 1.35,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: AppTextWeights.regular,
    height: 1.4,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 13,
    fontWeight: AppTextWeights.regular,
    height: 1.4,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: AppTextWeights.regular,
    height: 1.35,
  );

  static const TextStyle label = TextStyle(
    fontSize: 11,
    fontWeight: AppTextWeights.medium,
    height: 1.3,
    letterSpacing: 0.2,
  );

  static const TextStyle micro = TextStyle(
    fontSize: 10,
    fontWeight: AppTextWeights.medium,
    height: 1.3,
    letterSpacing: 0.2,
  );
}
