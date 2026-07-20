import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/floorplan/editor_mode.dart';
import '../../models/floorplan/scene.dart';
import '../../widgets/floorplan/floorplan_scene_painter.dart';

/// Render a [Scene] to a PNG byte buffer suitable for upload as the
/// thumbnail shown in the plans list.
///
/// The render fits the scene extents into [maxSide] preserving aspect ratio,
/// hides the grid, and uses the same painter the editor canvas uses so the
/// thumbnail visually matches what the user sees in the editor.
class ThumbnailRenderer {
  const ThumbnailRenderer._();

  static Future<Uint8List> renderPng(
    Scene scene, {
    int maxSide = 512,
  }) async {
    final aspect = scene.width / scene.height;
    final w = aspect >= 1 ? maxSide : (maxSide * aspect).round();
    final h = aspect >= 1 ? (maxSide / aspect).round() : maxSide;
    final scale = w / scene.width;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    );
    canvas.scale(scale);

    final painter = FloorplanScenePainter(
      scene: scene,
      mode: const IdleMode(),
      showGrid: false,
    );
    painter.paint(canvas, Size(scene.width, scene.height));

    final picture = recorder.endRecording();
    final image = await picture.toImage(w, h);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('toByteData returned null');
    }
    return data.buffer.asUint8List();
  }
}
