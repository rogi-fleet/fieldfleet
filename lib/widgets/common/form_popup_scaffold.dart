import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'form_popup_header.dart';
import 'unsaved_changes_guard.dart';
import '../../theme/theme.dart';

/// Shows a create/edit form inside the app's canonical popup chrome.
///
/// This is the single entry point that guarantees every form popup shares the
/// same shell as the Jobs / Customers / Task dialogs:
///   * Desktop  -> a rounded, corner-clipped [Dialog] sized to [width].
///   * Mobile   -> a [DraggableScrollableSheet] with a top-rounded surface.
/// Both render the solid-primary [FormPopupHeader] on top, then the form
/// content returned by [builder] in the remaining space.
///
/// The [builder] receives a nullable [ScrollController] — on mobile it MUST be
/// attached to the form's scroll view so the bottom sheet drags correctly; on
/// desktop it is null. The content should lay itself out as a
/// `Column(mainAxisSize: min, [Flexible(child: SingleChildScrollView(...)),
/// FormPopupFooter(...)])` so the footer pins to the bottom and the body
/// scrolls.
///
/// [fitContent] (default true) makes the desktop dialog wrap its content height
/// up to [maxHeightFactor] of the screen — right for short forms. Set it false
/// for tall/multi-step forms that should always fill [heightFactor] of the
/// screen.
///
/// Pass [dirty] to wire up the standard unsaved-changes guard: the header
/// close button, the scrim tap and the back gesture all route through
/// [maybeCloseForm], prompting before discarding edits.
Future<T?> showFormPopup<T>(
  BuildContext context, {
  required IconData? icon,
  required String title,
  VoidCallback? onBack,
  double width = 560,
  double maxHeightFactor = 0.9,
  bool fitContent = true,
  double heightFactor = 0.85,
  ValueListenable<bool>? dirty,
  required Widget Function(BuildContext context, ScrollController? scrollController)
      builder,
}) {
  final isMobile = MediaQuery.of(context).size.width < AppBreakpoints.mobile;
  if (isMobile) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _FormPopupSheet(
        icon: icon,
        title: title,
        onBack: onBack,
        dirty: dirty,
        builder: builder,
      ),
    );
  }
  return showDialog<T>(
    context: context,
    barrierDismissible: dirty == null,
    builder: (ctx) => _FormPopupDialog(
      icon: icon,
      title: title,
      onBack: onBack,
      width: width,
      fitContent: fitContent,
      heightFactor: heightFactor,
      maxHeightFactor: maxHeightFactor,
      dirty: dirty,
      builder: builder,
    ),
  );
}

/// Routes a popup close request through the unsaved-changes guard when a
/// [dirty] listenable is supplied, otherwise pops immediately.
void _handleClose(BuildContext context, ValueListenable<bool>? dirty) {
  if (dirty == null) {
    Navigator.of(context).pop();
  } else {
    maybeCloseForm(context, isDirty: dirty.value);
  }
}

/// Wraps [child] in a [PopScope] that defers to the unsaved-changes guard when
/// [dirty] is supplied; otherwise returns [child] unchanged.
Widget _maybeGuard(
  BuildContext context,
  ValueListenable<bool>? dirty,
  Widget child,
) {
  if (dirty == null) return child;
  return PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      await maybeCloseForm(context, isDirty: dirty.value);
    },
    child: child,
  );
}

class _FormPopupDialog extends StatelessWidget {
  final IconData? icon;
  final String title;
  final VoidCallback? onBack;
  final double width;
  final bool fitContent;
  final double heightFactor;
  final double maxHeightFactor;
  final ValueListenable<bool>? dirty;
  final Widget Function(BuildContext, ScrollController?) builder;

  const _FormPopupDialog({
    required this.icon,
    required this.title,
    required this.onBack,
    required this.width,
    required this.fitContent,
    required this.heightFactor,
    required this.maxHeightFactor,
    required this.dirty,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final content = builder(context, null);
    return _maybeGuard(
      context,
      dirty,
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r16)),
        clipBehavior: Clip.antiAlias,
        child: Container(
          width: width,
          height: fitContent ? null : size.height * heightFactor,
          constraints: BoxConstraints(
            maxWidth: size.width * 0.9,
            maxHeight: size.height * maxHeightFactor,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.r16),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.r16),
            child: Column(
              mainAxisSize: fitContent ? MainAxisSize.min : MainAxisSize.max,
              children: [
                FormPopupHeader(
                  icon: icon,
                  title: title,
                  onBack: onBack,
                  onClose: () => _handleClose(context, dirty),
                ),
                fitContent
                    ? Flexible(child: content)
                    : Expanded(child: content),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FormPopupSheet extends StatelessWidget {
  final IconData? icon;
  final String title;
  final VoidCallback? onBack;
  final ValueListenable<bool>? dirty;
  final Widget Function(BuildContext, ScrollController?) builder;

  const _FormPopupSheet({
    required this.icon,
    required this.title,
    required this.onBack,
    required this.dirty,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return _maybeGuard(
      context,
      dirty,
      DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                FormPopupHeader(
                  dense: true,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                  icon: icon,
                  title: title,
                  onBack: onBack,
                  onClose: () => _handleClose(context, dirty),
                ),
                Expanded(child: builder(context, scrollController)),
              ],
            ),
          );
        },
      ),
    );
  }
}
