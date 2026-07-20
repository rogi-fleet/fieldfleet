import 'package:flutter/material.dart';

/// Default breakpoint above which sheets are shown as centered dialogs.
const double kAdaptiveSheetBreakpoint = 600;

/// Shows a popup that adapts to screen width.
///
/// On narrow screens (< [breakpoint] px wide) and when [sheetBuilder] is
/// provided, displays a [DraggableScrollableSheet] bottom sheet.
/// On wide screens, displays a [Dialog] via [dialogBuilder].
void showAdaptivePopup(
  BuildContext context, {
  required WidgetBuilder dialogBuilder,
  WidgetBuilder? sheetBuilder,
  double breakpoint = kAdaptiveSheetBreakpoint,
  double sheetInitialSize = 0.95,
  double sheetMinSize = 0.5,
}) {
  final isNarrow = MediaQuery.sizeOf(context).width < breakpoint;
  if (isNarrow && sheetBuilder != null) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: sheetInitialSize,
        minChildSize: sheetMinSize,
        maxChildSize: sheetInitialSize,
        builder: (ctx2, _) => sheetBuilder(ctx2),
      ),
    );
  } else {
    showDialog(context: context, builder: dialogBuilder);
  }
}

/// Drop-in replacement for [showModalBottomSheet] that shows a centered
/// [Dialog] on wide screens (>= [breakpoint] px) and a bottom sheet on
/// narrow screens. Mobile bottom-sheet params (e.g. [showDragHandle],
/// [enableDrag]) are ignored on the dialog path.
Future<T?> showAdaptiveSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool showDragHandle = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useSafeArea = false,
  Color? backgroundColor,
  ShapeBorder? shape,
  BoxConstraints? constraints,
  double breakpoint = kAdaptiveSheetBreakpoint,
  double dialogMaxWidth = 560,
  double dialogMaxHeight = 720,
}) {
  final isWide = MediaQuery.sizeOf(context).width >= breakpoint;
  if (isWide) {
    return showDialog<T>(
      context: context,
      barrierDismissible: isDismissible,
      builder: (ctx) => Dialog(
        backgroundColor: backgroundColor,
        shape:
            shape ??
            const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: dialogMaxWidth,
            maxHeight: dialogMaxHeight,
          ),
          child: builder(ctx),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    showDragHandle: showDragHandle,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useSafeArea: useSafeArea,
    backgroundColor: backgroundColor,
    shape: shape,
    constraints: constraints,
    builder: builder,
  );
}
