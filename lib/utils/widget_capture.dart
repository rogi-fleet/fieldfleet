import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Captures a Flutter [widget] into a PNG byte buffer by mounting it
/// off-screen in the root [Overlay], waiting for layout + paint, and reading
/// the image from a [RepaintBoundary].
///
/// The widget is mounted at logical [size] and inherits MediaQuery /
/// Theme / Directionality from the captured context. Returns `null` if
/// capture fails (no overlay, render failure, etc.) so callers can degrade
/// gracefully — never throws.
Future<Uint8List?> captureWidget(
  BuildContext context,
  Widget widget,
  Size size, {
  double pixelRatio = 2.0,
}) async {
  if (!context.mounted) return null;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return null;

  final key = GlobalKey();
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: -10000,
      top: -10000,
      width: size.width,
      height: size.height,
      child: Material(
        type: MaterialType.transparency,
        child: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: widget,
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);

  try {
    // Two frames: one for build/layout, one for paint to settle.
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;

    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  } finally {
    entry.remove();
    entry.dispose();
  }
}
