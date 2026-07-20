import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chrome_provider.dart';
import 'app_colors.dart';

/// Resolved color tokens for the chrome and scaffold areas.
///
/// The chrome is the top bar, toolbars, project header, and tab bars.
/// It can be dark (matching the sidebar) or light (original white surface).
///
/// In dark mode the scaffold background is also dark, so content-level
/// colors (scaffold text, dividers, links) must also adjust.
class ChromeColors {
  // ── Chrome (toolbar/header) tokens ──
  final Color background;
  final Color surface;
  final Color text;
  final Color textActive;
  final Color divider;
  final Color hover;
  final Color selected;
  final Color sectionLabel;

  // ── Scaffold-level content tokens ──
  /// Primary text rendered directly on the scaffold background.
  final Color scaffoldText;

  /// Secondary/muted text on the scaffold background.
  final Color scaffoldTextSecondary;

  /// Divider color visible on the scaffold background.
  final Color scaffoldDivider;

  /// Accent/link color visible on the scaffold background.
  final Color scaffoldAccent;

  /// Subtle border for toolbar icon groups — less prominent than [divider].
  final Color subtleBorder;

  const ChromeColors({
    required this.background,
    required this.surface,
    required this.text,
    required this.textActive,
    required this.divider,
    required this.hover,
    required this.selected,
    required this.sectionLabel,
    required this.scaffoldText,
    required this.scaffoldTextSecondary,
    required this.scaffoldDivider,
    required this.scaffoldAccent,
    required this.subtleBorder,
  });

  static const dark = ChromeColors(
    background: AppColors.sidebarBg,
    surface: AppColors.sidebarSurface,
    text: AppColors.sidebarText,
    textActive: AppColors.sidebarTextActive,
    divider: AppColors.sidebarDivider,
    hover: AppColors.sidebarHover,
    selected: Color(0x33FF5722),
    sectionLabel: AppColors.sidebarSectionLabel,
    scaffoldText: AppColors.sidebarTextActive,
    scaffoldTextSecondary: AppColors.sidebarText,
    scaffoldDivider: AppColors.sidebarDivider,
    scaffoldAccent: AppColors.primary,
    subtleBorder: Color(0xFF2A3A4E),
  );

  static const light = ChromeColors(
    background: AppColors.surface,
    surface: AppColors.surfaceAlt,
    text: AppColors.textSecondary,
    textActive: AppColors.textPrimary,
    divider: AppColors.cardBorder,
    hover: Color(0x14004A99),
    selected: Color(0x1FFF5722),
    sectionLabel: AppColors.textTertiary,
    scaffoldText: AppColors.textPrimary,
    scaffoldTextSecondary: AppColors.textSecondary,
    scaffoldDivider: AppColors.cardBorder,
    scaffoldAccent: AppColors.primary,
    subtleBorder: AppColors.cardBorder,
  );

  /// Whether this chrome style has a dark background.
  bool get isDark => background == AppColors.sidebarBg;

  /// Read the current chrome colors from the nearest [ChromeProvider].
  static ChromeColors of(BuildContext context) {
    return context.watch<ChromeProvider>().chromeColors;
  }
}
