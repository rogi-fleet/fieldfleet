import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'app_radius.dart';
import 'app_shadows.dart';
import 'chrome_colors.dart';

/// Central ThemeData factory for the FieldFleet design system.
abstract final class AppTheme {
  static ThemeData build({bool darkChrome = true}) {
    final chrome = darkChrome ? ChromeColors.dark : ChromeColors.light;

    // Content surfaces always render light, even in dark-chrome mode. Only the
    // chrome (sidebar + AppBar) is dark — everything inside the content area
    // (cards, dialogs, popups, chips, text) should match light mode so we
    // don't fight dark-on-dark text inside otherwise-light widgets.
    const surfaceColor = AppColors.surface;
    const onSurfaceColor = AppColors.textPrimary;
    // Inputs in the chrome (e.g., the top-bar search) stay dark; content-area
    // inputs always render light.
    final inputFillColor =
        darkChrome ? AppColors.sidebarHover : AppColors.surfaceAlt;
    final inputBorderColor =
        darkChrome ? AppColors.sidebarDivider : AppColors.controlBorder;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      onPrimary: AppColors.textOnPrimary,
      secondary: AppColors.secondary,
      onSecondary: AppColors.textOnPrimary,
      error: AppColors.error,
      onError: AppColors.textOnPrimary,
      surface: surfaceColor,
      onSurface: onSurfaceColor,
    );

    final textTheme = GoogleFonts.interTextTheme();

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor:
          darkChrome ? AppColors.sidebarBg : AppColors.background,

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      focusColor: Colors.transparent,

      // ── Card ────────────────────────────────────────────
      // Cards are content surfaces and always render light, even when chrome
      // is dark. The dashboard body and most screens use a light background
      // (AppColors.background) and the cards' inner text is dark, so a dark
      // card would produce dark-on-dark.
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardRadius,
          side: const BorderSide(color: AppColors.cardBorder),
        ),
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        color: AppColors.surface,
        margin: EdgeInsets.zero,
      ),

      // ── AppBar ──────────────────────────────────────────
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: chrome.background,
        foregroundColor: chrome.textActive,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: chrome.text),
        actionsIconTheme: IconThemeData(color: chrome.text),
      ),

      // ── Elevated Button ─────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.buttonRadius,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      ),

      // ── Outlined Button ─────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: chrome.scaffoldAccent,
          side: BorderSide(color: chrome.scaffoldDivider),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.buttonRadius,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        ),
      ),

      // ── Text Button ─────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: chrome.scaffoldAccent,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.buttonRadius,
          ),
        ),
      ),

      // ── Input Decoration ────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFillColor,
        hintStyle: TextStyle(
          color: darkChrome ? AppColors.sidebarText : AppColors.textTertiary,
          fontSize: 14,
        ),
        floatingLabelBehavior: FloatingLabelBehavior.never,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: AppRadius.inputRadius,
          borderSide: BorderSide(color: inputBorderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.inputRadius,
          borderSide: BorderSide(color: inputBorderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.inputRadius,
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.inputRadius,
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.inputRadius,
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.inputRadius,
          borderSide: BorderSide(color: inputBorderColor),
        ),
      ),

      // ── Navigation Bar (mobile bottom nav) ──────────────
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primarySurface,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.primary, size: 24);
          }
          return const IconThemeData(color: AppColors.textTertiary, size: 24);
        }),
      ),

      // ── TabBar ──────────────────────────────────────────
      tabBarTheme: TabBarThemeData(
        labelColor: chrome.textActive,
        unselectedLabelColor: chrome.text,
        indicatorColor: darkChrome ? AppColors.secondary : AppColors.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerHeight: darkChrome ? 0 : 1,
        dividerColor: chrome.divider,
      ),

      // ── PopupMenu ───────────────────────────────────────
      popupMenuTheme: PopupMenuThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardRadius,
          side: const BorderSide(color: AppColors.cardBorder),
        ),
        color: surfaceColor,
        shadowColor: Colors.transparent,
        textStyle: const TextStyle(color: onSurfaceColor),
        surfaceTintColor: Colors.transparent,
      ),

      // ── Dialog ──────────────────────────────────────────
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardRadius,
          side: const BorderSide(color: AppColors.cardBorder),
        ),
      ),

      // ── Bottom Sheet ────────────────────────────────────
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
      ),

      // ── Tooltip ─────────────────────────────────────────
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.sidebarBg,
          borderRadius: AppRadius.badgeRadius,
          border: Border.all(color: AppColors.glassBorder),
          boxShadow: AppShadows.sm,
        ),
        textStyle: const TextStyle(
          color: AppColors.textOnDark,
          fontSize: 12,
          letterSpacing: -0.1,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),

      // ── Divider ─────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: chrome.scaffoldDivider,
        thickness: 1,
        space: 1,
      ),

      // ── Chip ────────────────────────────────────────────
      chipTheme: ChipThemeData(
        color: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary.withValues(alpha: 0.12);
          }
          return AppColors.surfaceAlt;
        }),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.chipRadius,
          side: const BorderSide(color: AppColors.controlBorder),
        ),
        labelStyle: const TextStyle(
          color: onSurfaceColor,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      ),

      // ── Snack Bar ───────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.sidebarBg,
        contentTextStyle: const TextStyle(color: AppColors.textOnDark),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.buttonRadius,
          side: const BorderSide(color: AppColors.glassBorder),
        ),
        elevation: 0,
      ),
    );
  }
}
