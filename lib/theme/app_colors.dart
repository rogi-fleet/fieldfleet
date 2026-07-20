import 'package:flutter/material.dart';

/// Centralized color tokens for the FieldFleet design system.
abstract final class AppColors {
  // ── Brand ──────────────────────────────────────────────
  static const Color primary = Color(0xFF004A99);
  static const Color primaryLight = Color(0xFF1A6FD1);
  static const Color primaryDark = Color(0xFF003370);
  static const Color primarySurface = Color(0xFFE8F1FB);

  static const Color secondary = Color(0xFFFF5722);
  static const Color secondaryLight = Color(0xFFFF8A65);
  static const Color secondaryDark = Color(0xFFE64A19);
  static const Color secondarySurface = Color(0xFFFFF3E0);

  // ── Sidebar / Nav ──────────────────────────────────────
  static const Color sidebarBg = Color(0xFF0F172A);
  static const Color sidebarSurface = Color(0xFF1E293B);
  static const Color sidebarHover = Color(0xFF334155);
  static const Color sidebarSelected = Color(0xFF1E3A5F);
  static const Color sidebarText = Color(0xFFCBD5E1);
  static const Color sidebarTextActive = Colors.white;
  static const Color sidebarDivider = Color(0xFF334155);
  static const Color sidebarSectionLabel = Color(0xFF64748B);

  // ── Bottom Nav Bar ───────────────────────────────────────
  static const Color navBarGradientStart = Color(0xFF1E293B);
  static const Color navBarGradientEnd = Color(0xFF162032);

  // ── Surfaces & Backgrounds ─────────────────────────────
  static const Color surface = Colors.white;
  // Pale blue-pearl tint — mimics macOS Ventura's window background
  static const Color surfaceAlt = Color(0xFFF7FAFF);
  // Soft blue-white scaffold: more premium than neutral gray
  static const Color background = Color(0xFFF0F4FB);
  // Ultra-subtle border: ~5 % black — glass/Apple style
  static const Color cardBorder = Color(0x0D000000);
  // Slightly more visible border for UI controls (inputs, chips, dropdowns)
  static const Color controlBorder = Color(0x1A000000);

  // ── Glass / Translucency helpers ───────────────────────
  /// Inner highlight on dark glass surfaces.
  static const Color glassHighlight = Color(0x1AFFFFFF);

  /// Very subtle white edge on dark containers.
  static const Color glassBorder = Color(0x12FFFFFF);

  // ── Text ───────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textTertiary = Color(0xFF94A3B8);
  static const Color textOnPrimary = Colors.white;
  static const Color textOnDark = Colors.white;

  // ── Semantic / Status ──────────────────────────────────
  static const Color success = Color(0xFF16A34A);
  static const Color successLight = Color(0xFFDCFCE7);
  static const Color successDark = Color(0xFF15803D);

  static const Color warning = Color(0xFFF59E0B);
  static const Color warningLight = Color(0xFFFEF3C7);
  static const Color warningDark = Color(0xFFD97706);

  static const Color error = Color(0xFFDC2626);
  static const Color errorLight = Color(0xFFFEE2E2);
  static const Color errorDark = Color(0xFFB91C1C);

  static const Color info = Color(0xFF2563EB);
  static const Color infoLight = Color(0xFFDBEAFE);
  static const Color infoDark = Color(0xFF1D4ED8);

  // ── Entity Accents ─────────────────────────────────────
  static const Color projectAccent = Color(0xFF2563EB);
  static const Color projectAccentLight = Color(0xFFDBEAFE);

  static const Color taskAccent = Color(0xFF16A34A);
  static const Color taskAccentLight = Color(0xFFDCFCE7);

  static const Color customerAccent = Color(0xFFF59E0B);
  static const Color customerAccentLight = Color(0xFFFEF3C7);

  static const Color financialAccent = Color(0xFF0891B2);
  static const Color financialAccentLight = Color(0xFFCFFAFE);

  static const Color messageAccent = Color(0xFF7C3AED);
  static const Color messageAccentLight = Color(0xFFEDE9FE);
  static const Color messageAccentDark = Color(0xFF6D28D9);

  static const Color activityAccent = Color(0xFF8B5CF6);
  static const Color activityAccentLight = Color(0xFFF5F3FF);

  static const Color invoiceAccent = Color(0xFF0D9488);
  static const Color planAccent = Color(0xFF4F46E5);

  // ── Media / Overlay chrome ─────────────────────────────
  static const Color mediaScrim = Color(0xFF000000);

  // ── Categorical Palette ────────────────────────────────
  static const List<Color> categoryPalette = [
    Color(0xFF2563EB), // blue
    Color(0xFF16A34A), // green
    Color(0xFFF59E0B), // amber
    Color(0xFF7C3AED), // purple
    Color(0xFF0891B2), // cyan
    Color(0xFF4F46E5), // indigo
    Color(0xFFDB2777), // pink
    Color(0xFFDC2626), // red
    Color(0xFF0D9488), // teal
    Color(0xFFEA580C), // orange
    Color(0xFF65A30D), // lime
    Color(0xFF9333EA), // violet
  ];
}
