import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// The standard pinned footer bar for every create/edit form popup.
///
/// Mirrors the Jobs / Customers wizard footer: a top-divided [surface] bar
/// with a left-aligned text Cancel button and a right-aligned filled primary
/// action. Use this instead of hand-rolling `AlertDialog.actions`, full-width
/// buttons, or in-scroll save buttons so every popup ends the same way.
class FormPopupFooter extends StatelessWidget {
  /// Tapped when the user cancels. Defaults to popping the current route.
  final VoidCallback? onCancel;

  /// Label for the cancel button.
  final String cancelLabel;

  /// Tapped when the user submits. Pass null to disable the primary button.
  final VoidCallback? onSubmit;

  /// Label for the primary button — "Create", "Save", "Save Changes", …
  final String submitLabel;

  /// Optional leading icon for the primary button (e.g. check / arrow_forward).
  final IconData? submitIcon;

  /// Shows a spinner inside the primary button and disables both buttons.
  final bool busy;

  /// Compact padding for mobile bottom sheets.
  final bool dense;

  /// Optional extra widget rendered between Cancel and the primary action
  /// (e.g. a "Back" button or a secondary action).
  final Widget? secondary;

  const FormPopupFooter({
    super.key,
    required this.onSubmit,
    required this.submitLabel,
    this.onCancel,
    this.cancelLabel = 'Cancel',
    this.submitIcon,
    this.busy = false,
    this.dense = false,
    this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    const spinner = SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
    );
    final style = FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
    );
    final Widget primary = submitIcon != null
        ? FilledButton.icon(
            onPressed: busy ? null : onSubmit,
            icon: busy ? spinner : Icon(submitIcon),
            label: Text(submitLabel),
            style: style,
          )
        : FilledButton(
            onPressed: busy ? null : onSubmit,
            style: style,
            child: busy ? spinner : Text(submitLabel),
          );

    return Container(
      padding: EdgeInsets.all(dense ? 12 : 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: busy
                ? null
                : (onCancel ?? () => Navigator.of(context).pop()),
            child: Text(cancelLabel),
          ),
          if (secondary != null) ...[
            const SizedBox(width: 8),
            secondary!,
          ],
          const Spacer(),
          primary,
        ],
      ),
    );
  }
}
