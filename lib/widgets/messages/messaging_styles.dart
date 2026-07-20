import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Shared styling helpers for the messaging UI.
///
/// Uses the app's primary brand colour (`colorScheme.primary`) to stay
/// consistent with the rest of the app (e.g. the project popup).
abstract final class MessagingStyles {
  // ── Reusable widgets ─────────────────────────────────────

  /// Framed compose input that borrows the stronger focus treatment used by
  /// inline-edit cells in tables/tasks, while still looking appropriate in
  /// full-form messaging UIs.
  static Widget composeFieldFrame(
    BuildContext context, {
    required Widget child,
    required bool isFocused,
    bool enabled = true,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(12)),
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final borderColor = enabled
        ? (isFocused
              ? colorScheme.primary
              : theme.dividerColor.withValues(alpha: 0.75))
        : theme.dividerColor.withValues(alpha: 0.35);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: borderRadius,
        border: Border.all(
          color: borderColor,
          width: isFocused && enabled ? 2 : 1,
        ),
      ),
      child: child,
    );
  }

  static InputDecoration composeFieldDecoration({
    required String hintText,
    TextStyle? hintStyle,
    EdgeInsetsGeometry contentPadding = EdgeInsets.zero,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: hintStyle,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      filled: false,
      fillColor: Colors.transparent,
      isDense: true,
      contentPadding: contentPadding,
    );
  }

  /// Rounded composer decoration used by the mobile thread composer.
  static InputDecoration roundedComposeDecoration(
    BuildContext context, {
    required String hintText,
    TextStyle? hintStyle,
    EdgeInsetsGeometry contentPadding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: 10,
    ),
    double borderRadius = 24,
    bool enabled = true,
    bool isDense = true,
  }) {
    final theme = Theme.of(context);
    final divider = theme.dividerColor;
    final enabledBorderColor = divider.withValues(alpha: enabled ? 0.75 : 0.35);
    final disabledBorderColor = divider.withValues(alpha: 0.35);
    final focusedBorderColor = theme.colorScheme.primary;
    final effectiveHintStyle =
        hintStyle ??
        theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.9),
        );

    OutlineInputBorder buildBorder(Color color, double width) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(borderRadius)),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      hintText: hintText,
      hintStyle: effectiveHintStyle,
      border: buildBorder(enabledBorderColor, 1),
      enabledBorder: buildBorder(enabledBorderColor, 1),
      disabledBorder: buildBorder(disabledBorderColor, 1),
      focusedBorder: buildBorder(focusedBorderColor, 2),
      filled: false,
      fillColor: Colors.transparent,
      isDense: isDense,
      contentPadding: contentPadding,
    );
  }

  /// Small icon badge with primary colour background (used in headers).
  static Widget iconBadge(
    BuildContext context,
    IconData icon, {
    double size = 14,
  }) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, size: size, color: Colors.white),
    );
  }

  /// Section header decoration – solid primary colour, matching the project
  /// popup style.
  static BoxDecoration solidHeaderDecoration(BuildContext context) {
    return BoxDecoration(color: Theme.of(context).colorScheme.primary);
  }

  /// Subtle tinted header (light primary wash at the top fading to surface).
  /// Used for secondary sections like the conversation list pane.
  static BoxDecoration tintedHeaderDecoration(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: cs.primary.withValues(alpha: 0.06),
      border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
    );
  }

  // ── Button styles ────────────────────────────────────────

  /// Standard filled button style using primary colour.
  static ButtonStyle filledButtonStyle(
    BuildContext context, {
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.md,
    ),
    double borderRadius = 12,
  }) {
    return FilledButton.styleFrom(
      backgroundColor: Theme.of(context).colorScheme.primary,
      foregroundColor: Colors.white,
      padding: padding,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }

  /// Compact send-button style used in compose / thread headers.
  static ButtonStyle sendButtonStyle(BuildContext context) {
    return filledButtonStyle(
      context,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 10),
      borderRadius: 10,
    );
  }

  // ── Empty state ──────────────────────────────────────────

  /// Circle background for empty-state icons using a soft primary tint.
  static Widget emptyStateIcon(
    BuildContext context, {
    IconData icon = Icons.forum_rounded,
    double diameter = 88,
    double iconSize = 40,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: iconSize, color: primary),
    );
  }
}
