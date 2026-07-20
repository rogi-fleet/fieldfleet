import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/floorplan/editor_mode.dart';
import '../../models/floorplan/elements_set.dart';
import '../../models/floorplan/scene.dart';
import '../../utils/floorplan/units.dart';
import '../../widgets/floorplan/floorplan_scene_painter.dart';

/// Render a [Scene] to image / vector / document formats for sharing,
/// printing, or hand-off to clients. PNG + PDF reuse the editor's
/// painter so visual fidelity matches what's on screen; SVG is
/// hand-rolled so it stays a true vector format that scales without
/// loss and can be edited in any vector tool.
class SceneExporter {
  const SceneExporter._();

  /// Render the scene as a PNG. [scale] controls pixels-per-scene-unit
  /// — at 1.0 the PNG is the scene's native size in pixels (which for
  /// a default 2000×2000 cm scene is 2000×2000 px).
  static Future<Uint8List> renderPng(
    Scene scene, {
    double scale = 1.0,
    bool showGrid = false,
  }) async {
    final w = (scene.width * scale).round();
    final h = (scene.height * scale).round();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    );
    canvas.scale(scale);
    // Strip selection so the painter's chrome pass (corner resize
    // handles, midpoint dots, etc.) doesn't bleed into the export.
    final cleanLayer = scene.selectedLayer.copyWith(
      selected: ElementsSet.empty,
    );
    final cleanScene = scene.withSelectedLayer(cleanLayer);
    final painter = FloorplanScenePainter(
      scene: cleanScene,
      mode: const IdleMode(),
      showGrid: showGrid,
    );
    painter.paint(canvas, Size(scene.width, scene.height));
    final picture = recorder.endRecording();
    final image = await picture.toImage(w, h);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('Image.toByteData returned null');
    }
    return data.buffer.asUint8List();
  }

  /// Render the scene as an SVG document. True vector output; opens in
  /// any browser, vector editor (Illustrator, Inkscape), or CAD tool.
  /// Walls render as thick lines, holes as gaps, areas as fills,
  /// items as positioned rectangles.
  static String renderSvg(
    Scene scene, {
    bool includeLabels = true,
  }) {
    final layer = scene.selectedLayer;
    final buffer = StringBuffer();
    buffer.writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" '
      'viewBox="0 0 ${_n(scene.width)} ${_n(scene.height)}" '
      'width="${_n(scene.width)}" height="${_n(scene.height)}">',
    );
    buffer.writeln(
      '<rect width="100%" height="100%" fill="#FAFAFA"/>',
    );

    // Areas (room fills, drawn under walls).
    for (final area in layer.areas.values) {
      final pts = area.vertexIds
          .map((id) => layer.vertices[id])
          .where((v) => v != null)
          .map((v) => '${_n(v!.x)},${_n(v.y)}')
          .join(' ');
      if (pts.isEmpty) continue;
      buffer.writeln(
        '<polygon points="$pts" fill="rgba(84,110,122,0.08)"/>',
      );
      final name = (area.properties['name'] as String?)?.trim() ?? '';
      if (includeLabels && name.isNotEmpty) {
        // Centroid label.
        var sx = 0.0, sy = 0.0, n = 0;
        for (final id in area.vertexIds) {
          final v = layer.vertices[id];
          if (v == null) continue;
          sx += v.x;
          sy += v.y;
          n++;
        }
        if (n > 0) {
          buffer.writeln(
            '<text x="${_n(sx / n)}" y="${_n(sy / n)}" '
            'font-family="Helvetica, Arial, sans-serif" '
            'font-size="14" fill="#37474F" '
            'text-anchor="middle">${_xml(name)}</text>',
          );
        }
      }
    }

    // Walls + holes.
    for (final line in layer.lines.values) {
      final a = layer.vertices[line.vertexIds[0]];
      final b = layer.vertices[line.vertexIds[1]];
      if (a == null || b == null) continue;
      final dxw = b.x - a.x;
      final dyw = b.y - a.y;
      final wallLen = _hypot(dxw, dyw);
      if (wallLen < 0.01) continue;
      final ux = dxw / wallLen;
      final uy = dyw / wallLen;
      // Sort holes along the wall so we draw segments between gaps.
      final gaps = line.holeIds
          .map((id) => layer.holes[id])
          .where((h) => h != null)
          .map((h) => (
                start: (h!.offset * wallLen) - h.width / 2,
                end: (h.offset * wallLen) + h.width / 2,
              ))
          .toList()
        ..sort((x, y) => x.start.compareTo(y.start));

      var cursor = 0.0;
      for (final g in gaps) {
        if (g.start > cursor) {
          buffer.writeln(_svgWall(
            a.x + ux * cursor,
            a.y + uy * cursor,
            a.x + ux * g.start,
            a.y + uy * g.start,
            line.thickness,
          ));
        }
        cursor = cursor > g.end ? cursor : g.end;
      }
      if (cursor < wallLen) {
        buffer.writeln(_svgWall(
          a.x + ux * cursor,
          a.y + uy * cursor,
          b.x,
          b.y,
          line.thickness,
        ));
      }
      // Length label at midpoint, perpendicular to wall.
      if (includeLabels) {
        final midX = (a.x + b.x) / 2;
        final midY = (a.y + b.y) / 2;
        buffer.writeln(
          '<text x="${_n(midX)}" y="${_n(midY - line.thickness / 2 - 4)}" '
          'font-family="Helvetica, Arial, sans-serif" '
          'font-size="11" fill="#455A64" '
          'text-anchor="middle">'
          '${_xml(formatLengthCm(wallLen, scene.unit))}</text>',
        );
      }
    }

    // Items (axis-aligned rect approximation rotated about center).
    for (final item in layer.items.values) {
      final hw = item.width / 2;
      final hh = item.height / 2;
      final rotDeg = item.rotation * 180 / 3.141592653589793;
      buffer.writeln(
        '<g transform="translate(${_n(item.x)},${_n(item.y)}) '
        'rotate(${_n(rotDeg)})">'
        '<rect x="${_n(-hw)}" y="${_n(-hh)}" '
        'width="${_n(item.width)}" height="${_n(item.height)}" '
        'fill="#CFD8DC" stroke="#455A64" stroke-width="1"/>'
        '<text x="0" y="0" font-family="Helvetica, Arial, sans-serif" '
        'font-size="10" fill="#37474F" text-anchor="middle">'
        '${_xml(item.prototype)}</text>'
        '</g>',
      );
    }

    buffer.writeln('</svg>');
    return buffer.toString();
  }

  /// Render the scene as a single-page PDF. Embeds a high-resolution
  /// PNG of the scene with a title block and scale note. For true
  /// vector PDF output use [renderSvg] and convert via a vector tool.
  static Future<Uint8List> renderPdf(
    Scene scene, {
    String? title,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
  }) async {
    // Render at 4× scale so the embedded PNG is print-quality.
    final png = await renderPng(scene, scale: 4.0);
    final image = pw.MemoryImage(png);
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat.landscape,
        margin: const pw.EdgeInsets.all(36),
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (title != null && title.isNotEmpty)
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Scene: ${formatLengthCm(scene.width, scene.unit)} × '
                '${formatLengthCm(scene.height, scene.unit)}',
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey700,
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Expanded(
                child: pw.Center(
                  child: pw.Image(image, fit: pw.BoxFit.contain),
                ),
              ),
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  // ---------------------------------------------------------------------------
  // helpers
  // ---------------------------------------------------------------------------

  static String _svgWall(
    double x1,
    double y1,
    double x2,
    double y2,
    double thickness,
  ) =>
      '<line x1="${_n(x1)}" y1="${_n(y1)}" '
      'x2="${_n(x2)}" y2="${_n(y2)}" '
      'stroke="#263238" stroke-width="${_n(thickness)}" '
      'stroke-linecap="butt"/>';

  /// Format a coordinate / length compactly (no trailing zeros, max 2 dp).
  static String _n(double v) {
    if (v.isNaN || v.isInfinite) return '0';
    final s = v.toStringAsFixed(2);
    if (s.contains('.')) {
      return s.replaceFirst(RegExp(r'\.?0+$'), '');
    }
    return s;
  }

  /// XML-escape a label for SVG `<text>` bodies.
  static String _xml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static double _hypot(double dx, double dy) =>
      math.sqrt(dx * dx + dy * dy);
}
