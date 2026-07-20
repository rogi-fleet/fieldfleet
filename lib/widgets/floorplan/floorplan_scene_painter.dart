import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

import '../../models/floorplan/annotation.dart';
import '../../models/floorplan/editor_mode.dart';
import '../../models/floorplan/element_kind.dart';
import '../../models/floorplan/hole.dart';
import '../../models/floorplan/item.dart';
import '../../models/floorplan/scene.dart';
import '../../services/floorplan/catalog.dart';
import '../../utils/floorplan/snap.dart';
import '../../utils/floorplan/units.dart';

/// Single-pass painter that walks the scene and draws every visible element.
///
/// Phase 1: grid + walls + drawing-in-flight feedback. Holes / areas / items /
/// annotations land in Phases 2–3.
class FloorplanScenePainter extends CustomPainter {
  final Scene scene;
  final EditorMode mode;
  final bool showGrid;
  final Catalog catalog;
  final ({Offset point, SnapKind kind, String label})? snapHint;
  final ({ElementKind kind, String id})? hovered;
  final ({String prototype, ElementKind kind, Offset point, double rotation})?
      ghostPreview;

  /// Inverse of the InteractiveViewer scale, used so chrome (snap labels,
  /// in-flight wall length, alignment guides) stays a constant size on
  /// screen instead of scaling with zoom. 1.0 means no zoom.
  final double inverseViewportScale;

  FloorplanScenePainter({
    required this.scene,
    required this.mode,
    this.showGrid = true,
    this.snapHint,
    this.hovered,
    this.ghostPreview,
    this.inverseViewportScale = 1.0,
    Catalog? catalog,
  }) : catalog = catalog ?? defaultCatalog;

  @override
  void paint(Canvas canvas, Size size) {
    _paintBackground(canvas, size);
    if (showGrid) _paintGrid(canvas);
    final layer = scene.selectedLayer;
    final selectedLines = layer.selected.lines;
    final selectedHoles = layer.selected.holes;
    // Areas first — render under walls so wall outlines stay visible.
    layer.areas.forEach((id, area) {
      final pts = area.vertexIds
          .map((vid) => layer.vertices[vid])
          .whereType()
          .map((v) => Offset(v.x, v.y))
          .toList();
      _paintArea(canvas, pts);
      final name = (area.properties['name'] as String?)?.trim() ?? '';
      if (name.isNotEmpty && pts.length >= 3) {
        _paintAreaLabel(canvas, pts, name);
      }
    });
    layer.lines.forEach((id, line) {
      final a = layer.vertices[line.vertexIds[0]];
      final b = layer.vertices[line.vertexIds[1]];
      if (a == null || b == null) return;
      final isSelected = selectedLines.contains(id);
      final isHovered =
          hovered?.kind == ElementKind.line && hovered?.id == id;
      final isPending = mode is DrawingWallMode &&
          (mode as DrawingWallMode).pendingLineId == id;
      _paintWallWithHoles(
        canvas,
        Offset(a.x, a.y),
        Offset(b.x, b.y),
        thickness: line.thickness,
        selected: isSelected,
        pending: isPending,
        hovered: isHovered,
        holes:
            line.holeIds.map((hid) => layer.holes[hid]).whereType<Hole>(),
        selectedHoleIds: selectedHoles,
      );
      // Always-on length label at the midpoint, perpendicular to the
      // wall, in scene units (defaults to cm).
      _paintWallLength(canvas, Offset(a.x, a.y), Offset(b.x, b.y),
          line.thickness, scene.unit);
    });
    _paintVertices(canvas, layer.vertices.values);

    // Items render above walls so they're visible inside rooms.
    final selectedItems = layer.selected.items;
    for (final item in layer.items.values) {
      final spec = catalog.get(item.prototype);
      if (spec == null) continue;
      canvas.save();
      canvas.translate(item.x, item.y);
      canvas.rotate(item.rotation);
      spec.paint(canvas, item, selected: selectedItems.contains(item.id));
      canvas.restore();
      if (selectedItems.contains(item.id)) {
        _paintRotationHandle(canvas, item.x, item.y, item.rotation,
            math.max(item.width, item.height) / 2);
      }
    }

    // Annotations render on top of everything.
    final selectedAnnotations = layer.selected.annotations;
    for (final ann in layer.annotations.values) {
      _paintAnnotation(
        canvas,
        ann,
        selected: selectedAnnotations.contains(ann.id),
      );
    }

    // In-flight drawing chrome: ghost previews, alignment guides, the
    // live length+angle label, and room-tool previews.
    _paintGhostPreview(canvas);
    _paintAlignmentGuides(canvas);
    _paintInFlightWallLabel(canvas);
    _paintRoomToolPreview(canvas);
    _paintCalibrationPreview(canvas);

    // Selection chrome: handles for the currently-selected element so
    // direct manipulation is visually obvious.
    _paintSelectionChrome(canvas);

    // Snap hint always on top, kind-aware.
    _paintSnapHint(canvas);
  }

  void _paintSelectionChrome(Canvas canvas) {
    final layer = scene.selectedLayer;
    final scale = inverseViewportScale;
    final accent = AppColors.info;

    // Wall midpoint handle.
    for (final lineId in layer.selected.lines) {
      final line = layer.lines[lineId];
      if (line == null) continue;
      final a = layer.vertices[line.vertexIds[0]];
      final b = layer.vertices[line.vertexIds[1]];
      if (a == null || b == null) continue;
      final mid = Offset((a.x + b.x) / 2, (a.y + b.y) / 2);
      _paintHandle(canvas, mid, accent, scale, isSquare: false);
    }

    // Item: 4 corner resize handles + angle label on rotation handle.
    for (final itemId in layer.selected.items) {
      final item = layer.items[itemId];
      if (item == null) continue;
      final hw = item.width / 2;
      final hh = item.height / 2;
      final cos = math.cos(item.rotation);
      final sin = math.sin(item.rotation);
      // Compute the four corner positions in world coords.
      Offset corner(double lx, double ly) => Offset(
            item.x + lx * cos - ly * sin,
            item.y + lx * sin + ly * cos,
          );
      final corners = [
        corner(-hw, -hh),
        corner(hw, -hh),
        corner(hw, hh),
        corner(-hw, hh),
      ];
      for (final c in corners) {
        _paintHandle(canvas, c, accent, scale, isSquare: true);
      }
      // Rotation handle angle label.
      final radius = math.max(item.width, item.height) / 2;
      final hx = item.x +
          math.cos(item.rotation - math.pi / 2) * (radius + 24 * scale);
      final hy = item.y +
          math.sin(item.rotation - math.pi / 2) * (radius + 24 * scale);
      final deg = (item.rotation * 180 / math.pi).round();
      _paintScreenLabel(
        canvas,
        Offset(hx + 10 * scale, hy - 18 * scale),
        '${(deg + 360) % 360}°',
        color: accent,
      );
    }

    // Hole: slide handle at the hole center on its host wall.
    for (final holeId in layer.selected.holes) {
      final hole = layer.holes[holeId];
      if (hole == null) continue;
      final line = layer.lines[hole.lineId];
      if (line == null) continue;
      final a = layer.vertices[line.vertexIds[0]];
      final b = layer.vertices[line.vertexIds[1]];
      if (a == null || b == null) continue;
      final aP = Offset(a.x, a.y);
      final bP = Offset(b.x, b.y);
      final wallLen = (bP - aP).distance;
      if (wallLen < 0.5) continue;
      final dir = (bP - aP) / wallLen;
      final center = aP + dir * (hole.offset * wallLen);
      _paintHandle(canvas, center, accent, scale, isSquare: false);
    }
  }

  void _paintHandle(
    Canvas canvas,
    Offset at,
    Color color,
    double scale, {
    required bool isSquare,
  }) {
    final r = 5.0 * scale;
    if (isSquare) {
      final rect = Rect.fromCenter(center: at, width: r * 2, height: r * 2);
      canvas.drawRect(rect, Paint()..color = Colors.white);
      canvas.drawRect(
        rect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 * scale,
      );
    } else {
      canvas.drawCircle(at, r, Paint()..color = Colors.white);
      canvas.drawCircle(
        at,
        r,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 * scale,
      );
    }
  }

  /// Hit-test the four corner resize handles for [itemId]. Returns the
  /// 0-based corner index (0=TL, 1=TR, 2=BR, 3=BL in item-local frame)
  /// or null if no handle is under [point]. Tolerance scales with the
  /// inverse viewport.
  int? pickItemResizeHandle(Offset point, String itemId, double tolerance) {
    final item = scene.selectedLayer.items[itemId];
    if (item == null) return null;
    final hw = item.width / 2;
    final hh = item.height / 2;
    final cos = math.cos(item.rotation);
    final sin = math.sin(item.rotation);
    final cornersLocal = [
      const Offset(-1, -1),
      const Offset(1, -1),
      const Offset(1, 1),
      const Offset(-1, 1),
    ];
    final r = (5.0 * inverseViewportScale) + tolerance;
    for (var i = 0; i < cornersLocal.length; i++) {
      final lx = cornersLocal[i].dx * hw;
      final ly = cornersLocal[i].dy * hh;
      final wx = item.x + lx * cos - ly * sin;
      final wy = item.y + lx * sin + ly * cos;
      if ((Offset(wx, wy) - point).distance <= r) return i;
    }
    return null;
  }

  void _paintSnapHint(Canvas canvas) {
    final hint = snapHint;
    if (hint == null) return;
    final scale = inverseViewportScale;
    final color = AppColors.info;
    switch (hint.kind) {
      case SnapKind.vertex:
        // Ringed dot: outer stroke + inner fill.
        canvas.drawCircle(
          hint.point,
          7 * scale,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 * scale,
        );
        canvas.drawCircle(
          hint.point,
          2.5 * scale,
          Paint()..color = color,
        );
      case SnapKind.lineSegment:
      case SnapKind.line:
        // Square mark indicating "on the wall".
        final r = 5.0 * scale;
        canvas.drawRect(
          Rect.fromCenter(center: hint.point, width: r * 2, height: r * 2),
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 * scale,
        );
      case SnapKind.grid:
        // Cross.
        final r = 5.0 * scale;
        final paint = Paint()
          ..color = color
          ..strokeWidth = 1.5 * scale;
        canvas.drawLine(
          hint.point + Offset(-r, 0),
          hint.point + Offset(r, 0),
          paint,
        );
        canvas.drawLine(
          hint.point + Offset(0, -r),
          hint.point + Offset(0, r),
          paint,
        );
    }
    // Kind label, screen-space anchored above-right of the snap.
    _paintScreenLabel(
      canvas,
      hint.point + Offset(10 * scale, -16 * scale),
      hint.label,
      color: color,
    );
  }

  void _paintAlignmentGuides(Canvas canvas) {
    final m = mode;
    if (m is! DrawingWallMode) return;
    final layer = scene.selectedLayer;
    final start = layer.vertices[m.startVertexId];
    final end = layer.vertices[m.endVertexId];
    if (start == null || end == null) return;
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 4) return;
    final angle = math.atan2(dy, dx);
    // Closest multiple of π/4 (every 45°).
    const step = math.pi / 4;
    final snapped = (angle / step).round() * step;
    final diffDeg = ((angle - snapped) * 180 / math.pi).abs();
    if (diffDeg > 4) return;
    // Paint a dashed guide line through the start vertex along the
    // snapped angle, extending well past the cursor in both directions.
    final paint = Paint()
      ..color = const Color(0x66E91E63)
      ..strokeWidth = 1 * inverseViewportScale;
    final dirX = math.cos(snapped);
    final dirY = math.sin(snapped);
    const reach = 4000.0;
    final p1 =
        Offset(start.x - dirX * reach, start.y - dirY * reach);
    final p2 = Offset(start.x + dirX * reach, start.y + dirY * reach);
    _drawDashedLine(canvas, p1, p2, paint, dashLen: 8, gapLen: 6);
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint, {
    required double dashLen,
    required double gapLen,
  }) {
    final total = (b - a).distance;
    if (total < 0.5) return;
    final unit = (b - a) / total;
    var travelled = 0.0;
    while (travelled < total) {
      final segEnd = math.min(travelled + dashLen, total);
      canvas.drawLine(
        a + unit * travelled,
        a + unit * segEnd,
        paint,
      );
      travelled += dashLen + gapLen;
    }
  }

  void _paintInFlightWallLabel(Canvas canvas) {
    final m = mode;
    if (m is! DrawingWallMode) return;
    final layer = scene.selectedLayer;
    final start = layer.vertices[m.startVertexId];
    final end = layer.vertices[m.endVertexId];
    if (start == null || end == null) return;
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 4) return;
    final angleDeg = (math.atan2(dy, dx) * 180 / math.pi)
        .toStringAsFixed(0);
    final label =
        '${formatLengthCm(len, scene.unit)} · $angleDeg°';
    final mid = Offset((start.x + end.x) / 2, (start.y + end.y) / 2);
    _paintScreenLabel(
      canvas,
      mid + Offset(12 * inverseViewportScale, -24 * inverseViewportScale),
      label,
      color: AppColors.info,
    );
  }

  void _paintGhostPreview(Canvas canvas) {
    final ghost = ghostPreview;
    if (ghost == null) return;
    if (ghost.kind == ElementKind.hole) {
      // Door / window ghost: scaled-down filled rect overlaid on the
      // target wall position. Doors get a quarter-circle swing arc.
      final isDoor = ghost.prototype == 'door';
      final color = AppColors.info.withValues(alpha: 0.6);
      final size = 80.0;
      canvas.save();
      canvas.translate(ghost.point.dx, ghost.point.dy);
      canvas.rotate(ghost.rotation);
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: size,
        height: 12,
      );
      canvas.drawRect(rect, Paint()..color = color);
      if (isDoor) {
        canvas.drawArc(
          Rect.fromCircle(center: Offset(-size / 2, 0), radius: size),
          -math.pi / 2,
          math.pi / 2,
          false,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
      canvas.restore();
    } else if (ghost.kind == ElementKind.item) {
      final spec = catalog.get(ghost.prototype);
      if (spec == null) return;
      canvas.save();
      canvas.translate(ghost.point.dx, ghost.point.dy);
      canvas.rotate(ghost.rotation);
      // Render the catalog element at 50% opacity by saving a layer
      // and applying a translucent paint.
      canvas.saveLayer(
        Rect.fromCenter(
          center: Offset.zero,
          width: spec.defaultWidth * 1.5,
          height: spec.defaultHeight * 1.5,
        ),
        Paint()..color = const Color(0x80FFFFFF),
      );
      spec.paint(
        canvas,
        Item(
          id: '__ghost__',
          prototype: ghost.prototype,
          x: 0,
          y: 0,
          rotation: 0,
          width: spec.defaultWidth,
          height: spec.defaultHeight,
        ),
        selected: false,
      );
      canvas.restore();
      canvas.restore();
    }
  }

  void _paintRoomToolPreview(Canvas canvas) {
    final m = mode;
    final scale = inverseViewportScale;
    if (m is DrawingRectangleRoomMode &&
        m.start != null &&
        m.current != null) {
      final rect = Rect.fromPoints(m.start!, m.current!);
      canvas.drawRect(
        rect,
        Paint()..color = const Color(0x331976D2),
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = AppColors.info
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * scale,
      );
      // Width/height labels along the top + left edges.
      final w = rect.width.abs();
      final h = rect.height.abs();
      _paintScreenLabel(
        canvas,
        Offset(rect.center.dx, rect.top - 18 * scale),
        formatLengthCm(w, scene.unit),
        color: AppColors.info,
      );
      _paintScreenLabel(
        canvas,
        Offset(rect.left - 60 * scale, rect.center.dy),
        formatLengthCm(h, scene.unit),
        color: AppColors.info,
      );
    } else if (m is TracingRoomMode && m.points.isNotEmpty) {
      // Connect placed points with a solid line; show start vertex
      // as a halo so users see where to click to close.
      final paint = Paint()
        ..color = AppColors.info
        ..strokeWidth = 2 * scale
        ..style = PaintingStyle.stroke;
      for (var i = 0; i < m.points.length - 1; i++) {
        canvas.drawLine(m.points[i], m.points[i + 1], paint);
      }
      // Highlight the first vertex so the close target is visible.
      canvas.drawCircle(
        m.points.first,
        8 * scale,
        Paint()
          ..color = AppColors.info
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * scale,
      );
    }
  }

  void _paintCalibrationPreview(Canvas canvas) {
    final m = mode;
    if (m is! CalibratingMode || m.first == null) return;
    final scale = inverseViewportScale;
    final color = const Color(0xFFE91E63);
    canvas.drawCircle(
      m.first!,
      8 * scale,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * scale,
    );
    _paintScreenLabel(
      canvas,
      m.first! + Offset(12 * scale, -18 * scale),
      'A',
      color: color,
    );
    if (m.second != null) {
      canvas.drawCircle(
        m.second!,
        8 * scale,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * scale,
      );
      _paintScreenLabel(
        canvas,
        m.second! + Offset(12 * scale, -18 * scale),
        'B',
        color: color,
      );
      canvas.drawLine(
        m.first!,
        m.second!,
        Paint()
          ..color = color
          ..strokeWidth = 1.5 * scale,
      );
    }
  }

  /// Helper that paints a small chip-style label at scene coords [at]
  /// but with a screen-space font size — so labels don't grow with zoom.
  void _paintScreenLabel(
    Canvas canvas,
    Offset at,
    String text, {
    required Color color,
  }) {
    final scale = inverseViewportScale;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white,
          fontSize: 11 * scale,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final pad = 4.0 * scale;
    final bgRect = Rect.fromLTWH(
      at.dx - pad,
      at.dy - pad,
      tp.width + pad * 2,
      tp.height + pad * 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, Radius.circular(3 * scale)),
      Paint()..color = color,
    );
    tp.paint(canvas, at);
  }

  void _paintRotationHandle(
    Canvas canvas,
    double cx,
    double cy,
    double rotation,
    double radius,
  ) {
    final handleRadius = radius + 24;
    final hx = cx + math.cos(rotation - math.pi / 2) * handleRadius;
    final hy = cy + math.sin(rotation - math.pi / 2) * handleRadius;
    final paint = Paint()
      ..color = AppColors.info
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(cx, cy), Offset(hx, hy), paint);
    canvas.drawCircle(Offset(hx, hy), 6, Paint()..color = AppColors.info);
  }

  void _paintAnnotation(
    Canvas canvas,
    Annotation ann, {
    required bool selected,
  }) {
    final c = _hexColor(ann.color, fallback: const Color(0xFF222222));
    final paint = Paint()
      ..color = selected ? AppColors.info : c
      ..strokeWidth = 2;
    if (ann is TextAnnotation) {
      _paintTextLabel(canvas, ann, paint.color);
    } else if (ann is ArrowAnnotation) {
      canvas.drawLine(ann.from, ann.to, paint);
      _paintArrowhead(canvas, ann.from, ann.to, paint);
    } else if (ann is DimensionAnnotation) {
      _paintDimension(canvas, ann, paint.color);
    }
  }

  void _paintTextLabel(Canvas canvas, TextAnnotation ann, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: ann.text.isEmpty ? 'Label' : ann.text,
        style: TextStyle(
          color: color,
          fontSize: ann.fontSize,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(ann.x, ann.y);
    if (ann.rotation != 0) canvas.rotate(ann.rotation);
    tp.paint(canvas, Offset.zero);
    canvas.restore();
  }

  void _paintArrowhead(Canvas canvas, Offset from, Offset to, Paint paint) {
    final dir = to - from;
    final len = dir.distance;
    if (len < 0.01) return;
    final unit = dir / len;
    final perp = Offset(-unit.dy, unit.dx);
    const head = 12.0;
    final p1 = to;
    final p2 = to - unit * head + perp * (head * 0.4);
    final p3 = to - unit * head - perp * (head * 0.4);
    final path = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = paint.color);
  }

  void _paintDimension(Canvas canvas, DimensionAnnotation ann, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    canvas.drawLine(ann.from, ann.to, paint);
    // Tick marks at each end.
    final dir = (ann.to - ann.from);
    final len = dir.distance;
    if (len < 0.01) return;
    final unit = dir / len;
    final perp = Offset(-unit.dy, unit.dx);
    const tick = 6.0;
    canvas.drawLine(ann.from + perp * tick, ann.from - perp * tick, paint);
    canvas.drawLine(ann.to + perp * tick, ann.to - perp * tick, paint);
    // Label centered along the line.
    final mid = (ann.from + ann.to) / 2;
    final label = formatLengthCm(len, ann.unit);
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(mid.dx, mid.dy);
    canvas.rotate(math.atan2(unit.dy, unit.dx));
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height - 2));
    canvas.restore();
  }

  Color _hexColor(String hex, {required Color fallback}) {
    var h = hex.replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return fallback;
    return Color(int.parse(h, radix: 16));
  }

  void _paintBackground(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFFAFAFA);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, scene.width, scene.height),
      paint,
    );
    // Border around scene extents.
    final border = Paint()
      ..color = const Color(0xFFE0E0E0)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, scene.width, scene.height),
      border,
    );
  }

  void _paintGrid(Canvas canvas) {
    final step = scene.gridSize;
    if (step <= 0) return;
    final majorEvery = 5;
    final minor = Paint()
      ..color = const Color(0xFFE8E8E8)
      ..strokeWidth = 0.5;
    final major = Paint()
      ..color = const Color(0xFFCFCFCF)
      ..strokeWidth = 0.8;
    var i = 0;
    for (double x = 0; x <= scene.width; x += step, i++) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, scene.height),
        i % majorEvery == 0 ? major : minor,
      );
    }
    i = 0;
    for (double y = 0; y <= scene.height; y += step, i++) {
      canvas.drawLine(
        Offset(0, y),
        Offset(scene.width, y),
        i % majorEvery == 0 ? major : minor,
      );
    }
  }

  void _paintAreaLabel(Canvas canvas, List<Offset> points, String name) {
    // Centroid = mean of vertex coordinates. Good enough for v1; the
    // visual centroid (true polygon centroid) is overkill for labels.
    var sx = 0.0, sy = 0.0;
    for (final p in points) {
      sx += p.dx;
      sy += p.dy;
    }
    final cx = sx / points.length;
    final cy = sy / points.length;
    final tp = TextPainter(
      text: TextSpan(
        text: name,
        style: const TextStyle(
          color: Color(0xFF37474F),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  void _paintArea(Canvas canvas, List<Offset> points) {
    if (points.length < 3) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()..color = const Color(0x14546E7A),
    );
  }

  void _paintWallWithHoles(
    Canvas canvas,
    Offset a,
    Offset b, {
    required double thickness,
    required bool selected,
    required bool pending,
    required bool hovered,
    required Iterable<Hole> holes,
    required Set<String> selectedHoleIds,
  }) {
    // Hovered: paint a wider translucent halo behind the wall stroke so
    // the user can see what the next click is about to act on.
    if (hovered) {
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = const Color(0x441976D2)
          ..strokeWidth = thickness + 8,
      );
    }
    final color = pending
        ? const Color(0xFF1E88E5)
        : selected
            ? AppColors.info
            : const Color(0xFF263238);
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.butt
      ..strokeWidth = thickness;

    final wallLen = (b - a).distance;
    if (wallLen < 0.01) return;
    final dir = (b - a) / wallLen;
    // Sort hole gaps along the wall to draw filled segments between them.
    final gaps = holes
        .map((h) => (
              start: (h.offset * wallLen) - h.width / 2,
              end: (h.offset * wallLen) + h.width / 2,
              hole: h,
            ))
        .toList()
      ..sort((x, y) => x.start.compareTo(y.start));

    var cursor = 0.0;
    for (final g in gaps) {
      if (g.start > cursor) {
        canvas.drawLine(a + dir * cursor, a + dir * g.start, paint);
      }
      cursor = math.max(cursor, g.end);
      _paintHole(
        canvas,
        a + dir * (g.hole.offset * wallLen),
        dir,
        g.hole,
        thickness,
        isSelected: selectedHoleIds.contains(g.hole.id),
      );
    }
    if (cursor < wallLen) {
      canvas.drawLine(a + dir * cursor, b, paint);
    }
  }

  void _paintWallLength(
    Canvas canvas,
    Offset a,
    Offset b,
    double thickness,
    String unit,
  ) {
    final len = (b - a).distance;
    if (len < 20) return; // skip tiny wall segments to avoid label clutter
    final mid = (a + b) / 2;
    final dir = (b - a) / len;
    final perp = Offset(-dir.dy, dir.dx);
    final tp = TextPainter(
      text: TextSpan(
        text: formatLengthCm(len, unit),
        style: const TextStyle(
          color: Color(0xFF455A64),
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(mid.dx, mid.dy);
    // Keep label upright when the wall points right-to-left.
    var angle = math.atan2(dir.dy, dir.dx);
    if (angle > math.pi / 2 || angle < -math.pi / 2) {
      angle += math.pi;
    }
    canvas.rotate(angle);
    // Offset perpendicular so label sits above the wall, not on top.
    final off = (thickness / 2) + 4;
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height - off));
    canvas.restore();
    // perp is referenced to keep computation explicit; ignore unused
    // variable warning by forcing a reference.
    if (perp.distance < 0) return; // unreachable; keeps perp non-dead
  }

  void _paintHole(
    Canvas canvas,
    Offset center,
    Offset wallDir,
    Hole hole,
    double wallThickness, {
    required bool isSelected,
  }) {
    final perp = Offset(-wallDir.dy, wallDir.dx);
    final halfW = hole.width / 2;
    final halfT = wallThickness / 2;
    final paint = Paint()
      ..color = isSelected ? AppColors.info : const Color(0xFF607D8B)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    if (hole.prototype == 'door') {
      // Door = thin rectangle (the leaf) + a quarter-circle swing arc on
      // one side of the wall.
      final rectPath = Path()
        ..moveTo(
          (center - wallDir * halfW + perp * halfT).dx,
          (center - wallDir * halfW + perp * halfT).dy,
        )
        ..lineTo(
          (center + wallDir * halfW + perp * halfT).dx,
          (center + wallDir * halfW + perp * halfT).dy,
        )
        ..lineTo(
          (center + wallDir * halfW - perp * halfT).dx,
          (center + wallDir * halfW - perp * halfT).dy,
        )
        ..lineTo(
          (center - wallDir * halfW - perp * halfT).dx,
          (center - wallDir * halfW - perp * halfT).dy,
        )
        ..close();
      canvas.drawPath(
        rectPath,
        Paint()..color = const Color(0xFFFAFAFA),
      );

      final hinge = center - wallDir * halfW;
      // Door leaf line.
      canvas.drawLine(hinge, hinge + perp * hole.width, paint);
      // Swing arc.
      final arcRect = Rect.fromCircle(center: hinge, radius: hole.width);
      canvas.drawArc(
        arcRect,
        math.atan2(perp.dy, perp.dx),
        -math.pi / 2,
        false,
        paint,
      );
    } else if (hole.prototype == 'window') {
      // Window = clear span (lighter fill) + a center mullion line.
      final p1 = center - wallDir * halfW + perp * halfT;
      final p2 = center + wallDir * halfW + perp * halfT;
      final p3 = center + wallDir * halfW - perp * halfT;
      final p4 = center - wallDir * halfW - perp * halfT;
      final path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..lineTo(p3.dx, p3.dy)
        ..lineTo(p4.dx, p4.dy)
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = const Color(0xFFE3F2FD),
      );
      canvas.drawPath(path, paint);
      canvas.drawLine(
        center - wallDir * halfW,
        center + wallDir * halfW,
        paint,
      );
    }
  }

  void _paintVertices(Canvas canvas, Iterable values) {
    final fill = Paint()..color = const Color(0xFF455A64);
    final stroke = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final v in values) {
      final c = Offset(v.x, v.y);
      canvas.drawCircle(c, 3.5, fill);
      canvas.drawCircle(c, 3.5, stroke);
    }
  }

  @override
  bool shouldRepaint(FloorplanScenePainter old) =>
      !identical(old.scene, scene) ||
      old.mode != mode ||
      old.showGrid != showGrid ||
      old.snapHint != snapHint ||
      old.hovered != hovered ||
      old.ghostPreview != ghostPreview ||
      old.inverseViewportScale != inverseViewportScale;

  /// Hit-test the topmost element at scene-space [point]. Used by the gesture
  /// pane's Select mode. Returns `(kind, id)` or `null`.
  ({ElementKind kind, String id})? pickElement(Offset point, double tolerance) {
    final layer = scene.selectedLayer;
    // Vertices first (they're drawn on top).
    for (final v in layer.vertices.values) {
      if ((Offset(v.x, v.y) - point).distance <= tolerance) {
        return (kind: ElementKind.vertex, id: v.id);
      }
    }
    // Holes next (drawn over walls).
    for (final entry in layer.holes.entries) {
      final hole = entry.value;
      final line = layer.lines[hole.lineId];
      if (line == null) continue;
      final a = layer.vertices[line.vertexIds[0]];
      final b = layer.vertices[line.vertexIds[1]];
      if (a == null || b == null) continue;
      final wallLen = (Offset(b.x, b.y) - Offset(a.x, a.y)).distance;
      if (wallLen < 0.01) continue;
      final dir = (Offset(b.x, b.y) - Offset(a.x, a.y)) / wallLen;
      final center = Offset(a.x, a.y) + dir * (hole.offset * wallLen);
      if ((center - point).distance <= hole.width / 2 + tolerance) {
        return (kind: ElementKind.hole, id: entry.key);
      }
    }
    // Items next.
    for (final entry in layer.items.entries) {
      final item = entry.value;
      final dx = (point.dx - item.x);
      final dy = (point.dy - item.y);
      // Reverse the item's rotation to test against axis-aligned bounds.
      final cosR = math.cos(-item.rotation);
      final sinR = math.sin(-item.rotation);
      final lx = dx * cosR - dy * sinR;
      final ly = dx * sinR + dy * cosR;
      if (lx.abs() <= item.width / 2 + tolerance &&
          ly.abs() <= item.height / 2 + tolerance) {
        return (kind: ElementKind.item, id: entry.key);
      }
    }
    // Annotations next (drawn over walls/items).
    for (final entry in layer.annotations.entries) {
      final ann = entry.value;
      Offset? anchor;
      double pickRadius = 14;
      if (ann is TextAnnotation) {
        anchor = ann.offset;
        pickRadius = 24;
      } else if (ann is ArrowAnnotation) {
        anchor = (ann.from + ann.to) / 2;
        pickRadius = 14;
      } else if (ann is DimensionAnnotation) {
        anchor = (ann.from + ann.to) / 2;
        pickRadius = 14;
      }
      if (anchor != null && (anchor - point).distance <= pickRadius + tolerance) {
        return (kind: ElementKind.annotation, id: entry.key);
      }
    }
    // Then walls.
    for (final entry in layer.lines.entries) {
      final line = entry.value;
      final a = layer.vertices[line.vertexIds[0]];
      final b = layer.vertices[line.vertexIds[1]];
      if (a == null || b == null) continue;
      final d = _distancePointToSegment(
        point,
        Offset(a.x, a.y),
        Offset(b.x, b.y),
      );
      if (d <= line.thickness / 2 + tolerance) {
        return (kind: ElementKind.line, id: entry.key);
      }
    }
    return null;
  }

  /// True when [point] is on the rotation handle drawn for [itemId]. The
  /// handle sits a fixed distance above the item along its current
  /// rotation; see _paintRotationHandle for the geometry.
  bool pickRotationHandle(Offset point, String itemId, double tolerance) {
    final item = scene.selectedLayer.items[itemId];
    if (item == null) return false;
    final radius = math.max(item.width, item.height) / 2;
    final handleRadius = radius + 24;
    final hx = item.x + math.cos(item.rotation - math.pi / 2) * handleRadius;
    final hy = item.y + math.sin(item.rotation - math.pi / 2) * handleRadius;
    return (Offset(hx, hy) - point).distance <= 8 + tolerance;
  }

  static double _distancePointToSegment(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final lenSq = dx * dx + dy * dy;
    if (lenSq < 1e-6) return (p - a).distance;
    final t = (((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / lenSq)
        .clamp(0.0, 1.0);
    final proj = Offset(a.dx + t * dx, a.dy + t * dy);
    return (p - proj).distance;
  }
}
