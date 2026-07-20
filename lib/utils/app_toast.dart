import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Consistent feedback snackbars.
///
/// The codebase has ~1,000 ad-hoc `ScaffoldMessenger...showSnackBar` calls
/// with drifting colors (AppColors.error vs Colors.red vs default). These
/// helpers are the single point of truth for feedback styling — new code
/// should call them instead of building a SnackBar inline.
void showSuccessToast(BuildContext context, String message) =>
    _show(context, message, AppColors.success, Icons.check_circle_outline);

void showErrorToast(BuildContext context, String message) => _show(
      context,
      message,
      AppColors.error,
      Icons.error_outline,
      duration: const Duration(seconds: 6),
    );

void showWarningToast(BuildContext context, String message) =>
    _show(context, message, AppColors.warningDark, Icons.warning_amber_rounded);

void showInfoToast(BuildContext context, String message) =>
    _show(context, message, AppColors.info, Icons.info_outline);

void _show(
  BuildContext context,
  String message,
  Color color,
  IconData icon, {
  Duration duration = const Duration(seconds: 4),
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: color,
        duration: duration,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.badgeRadius),
        content: Row(
          children: [
            Icon(icon, color: AppColors.textOnDark, size: 20),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: AppColors.textOnDark),
              ),
            ),
          ],
        ),
      ),
    );
}
