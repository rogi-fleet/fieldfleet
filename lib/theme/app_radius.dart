import 'package:flutter/material.dart';

/// Border-radius tokens for the FieldFleet design system.
///
/// Radii are slightly more generous than before to match the
/// Apple / macOS glass aesthetic (more rounded, softer edges).
abstract final class AppRadius {
  // ── Raw values ─────────────────────────────────────────
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 10;
  static const double lg = 14;
  static const double xl = 20;
  static const double full = 999;

  // In-between steps the codebase already uses heavily (12 and 16 are the
  // two most common literals). Tokenized as-is so the migration stays
  // pixel-identical; consolidating onto the named ladder is a future,
  // deliberate design pass.
  static const double r12 = 12;
  static const double r16 = 16;

  // ── Pre-built BorderRadius objects ─────────────────────
  static final BorderRadius cardRadius = BorderRadius.circular(xl);
  static final BorderRadius badgeRadius = BorderRadius.circular(sm);
  static final BorderRadius buttonRadius = BorderRadius.circular(lg);
  static final BorderRadius inputRadius = BorderRadius.circular(lg);
  static final BorderRadius chipRadius = BorderRadius.circular(full);
}
