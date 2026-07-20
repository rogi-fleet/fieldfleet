import 'package:flutter/material.dart';

/// The standard header bar for every create/edit form popup in the app.
///
/// Renders the canonical solid-primary title bar — white leading icon, white
/// title and white close button — that the customer and project create
/// dialogs use. Every form popup (desktop [Dialog] and mobile bottom sheet)
/// should use this so they all share one consistent theme instead of each
/// hand-rolling its own header (light tints, primaryContainer, gradients,
/// plain AlertDialog titles, …).
///
/// Desktop dialogs clip their corners with a [ClipRRect], so leave
/// [borderRadius] null there. Mobile bottom sheets have a rounded top but no
/// clip, so pass a top-rounded [borderRadius] so the bar follows the sheet.
class FormPopupHeader extends StatelessWidget {
  /// Leading icon shown before the title. Pass null to omit (e.g. when a
  /// back button replaces it).
  final IconData? icon;

  /// Header title — "Create New X" / "Edit X".
  final String title;

  /// Invoked when the close (X) button is tapped.
  final VoidCallback onClose;

  /// When provided, a leading back arrow is shown before the icon/title.
  final VoidCallback? onBack;

  /// Use the more compact mobile sizing (smaller padding and icons).
  final bool dense;

  /// Optional rounded corners for the bar — pass a top-rounded radius for
  /// bottom sheets; leave null for desktop dialogs that clip via [ClipRRect].
  final BorderRadiusGeometry? borderRadius;

  const FormPopupHeader({
    super.key,
    required this.title,
    required this.onClose,
    this.icon,
    this.onBack,
    this.dense = false,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconSize = dense ? 20.0 : 22.0;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 16 : 20,
        vertical: dense ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: borderRadius,
      ),
      child: Row(
        children: [
          if (onBack != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: IconButton(
                icon: Icon(Icons.arrow_back,
                    color: Colors.white, size: iconSize),
                onPressed: onBack,
                tooltip: 'Back',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: iconSize),
            SizedBox(width: dense ? 8 : 10),
          ],
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: Colors.white, size: dense ? 20 : 24),
            onPressed: onClose,
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }
}
