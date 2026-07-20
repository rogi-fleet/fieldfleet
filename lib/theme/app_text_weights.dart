import 'package:flutter/material.dart';

/// Semantic FontWeight tokens for the FieldFleet design system.
///
/// The codebase mixed `w500`, `w600`, and `bold` for "emphasized" text with
/// no convention — these tokens collapse that to three slots and document
/// where each one belongs. Inline weight literals should be replaced as
/// touched.
///
///   regular  → body copy, captions, table cells
///   medium   → labels, secondary buttons, subtle emphasis
///   semibold → primary buttons, section titles, KPI numbers
///   bold     → page titles, headlines, marketing chrome only
abstract final class AppTextWeights {
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semibold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;
}
