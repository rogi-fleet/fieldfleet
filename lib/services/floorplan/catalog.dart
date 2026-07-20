import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

import '../../models/floorplan/item.dart';

/// One placeable element type in the floorplan catalog (sofa, table,
/// sink…). Each element knows its default footprint and how to draw
/// itself at a given world position + rotation.
///
/// In a future phase the catalog becomes pluggable per discipline
/// (electrical fixtures, plumbing, …) — for now everything is registered
/// in [defaultCatalog].
class CatalogElement {
  final String prototype;
  final String name;
  final IconData icon;
  final double defaultWidth;
  final double defaultHeight;
  final void Function(Canvas, Item, {required bool selected}) paint;

  const CatalogElement({
    required this.prototype,
    required this.name,
    required this.icon,
    required this.defaultWidth,
    required this.defaultHeight,
    required this.paint,
  });
}

/// Lookup + iteration helpers. Built once at startup; treat as read-only.
class Catalog {
  final Map<String, CatalogElement> _byPrototype;

  Catalog(List<CatalogElement> elements)
      : _byPrototype = {for (final e in elements) e.prototype: e};

  Iterable<CatalogElement> get all => _byPrototype.values;

  CatalogElement? get(String prototype) => _byPrototype[prototype];
}

// ---------------------------------------------------------------------------
// Default catalog — small but covers a typical residential layout.
// All paint methods receive the [Item] in scene coords; the caller has
// already applied translation + rotation to the canvas.
// ---------------------------------------------------------------------------

final Catalog defaultCatalog = Catalog([
  CatalogElement(
    prototype: 'sofa',
    name: 'Sofa',
    icon: Icons.weekend_outlined,
    defaultWidth: 200,
    defaultHeight: 90,
    paint: _paintRectFurniture(stroke: Color(0xFF455A64), fill: Color(0xFFCFD8DC)),
  ),
  CatalogElement(
    prototype: 'chair',
    name: 'Chair',
    icon: Icons.chair_outlined,
    defaultWidth: 50,
    defaultHeight: 50,
    paint: _paintRectFurniture(stroke: Color(0xFF455A64), fill: Color(0xFFECEFF1)),
  ),
  CatalogElement(
    prototype: 'table',
    name: 'Table',
    icon: Icons.table_restaurant_outlined,
    defaultWidth: 160,
    defaultHeight: 90,
    paint: _paintRectFurniture(stroke: Color(0xFF6D4C41), fill: Color(0xFFD7CCC8)),
  ),
  CatalogElement(
    prototype: 'bed',
    name: 'Bed',
    icon: Icons.bed_outlined,
    defaultWidth: 200,
    defaultHeight: 160,
    paint: _paintBed,
  ),
  CatalogElement(
    prototype: 'sink',
    name: 'Sink',
    icon: Icons.kitchen_outlined,
    defaultWidth: 60,
    defaultHeight: 50,
    paint: _paintCircleInRect(stroke: Color(0xFF1565C0), fill: Color(0xFFE3F2FD)),
  ),
  CatalogElement(
    prototype: 'toilet',
    name: 'Toilet',
    icon: Icons.wc_outlined,
    defaultWidth: 50,
    defaultHeight: 70,
    paint: _paintToilet,
  ),
  CatalogElement(
    prototype: 'stove',
    name: 'Stove',
    icon: Icons.local_fire_department_outlined,
    defaultWidth: 60,
    defaultHeight: 60,
    paint: _paintStove,
  ),
]);

// ---------------------------------------------------------------------------
// Painter helpers. Each takes the centered Item and draws it in its local
// coordinate frame (caller has already translated to item.x, item.y and
// rotated by item.rotation).
// ---------------------------------------------------------------------------

void Function(Canvas, Item, {required bool selected}) _paintRectFurniture({
  required Color stroke,
  required Color fill,
}) {
  return (canvas, item, {required selected}) {
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: item.width,
      height: item.height,
    );
    final corner = math.min(item.width, item.height) * 0.08;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(corner));
    canvas.drawRRect(rrect, Paint()..color = fill);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = selected ? AppColors.info : stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2 : 1,
    );
  };
}

void _paintBed(Canvas canvas, Item item, {required bool selected}) {
  // Bed frame.
  final frameRect = Rect.fromCenter(
    center: Offset.zero,
    width: item.width,
    height: item.height,
  );
  final framePaint = Paint()..color = const Color(0xFFEFEBE9);
  canvas.drawRRect(
    RRect.fromRectAndRadius(frameRect, const Radius.circular(8)),
    framePaint,
  );
  // Mattress.
  final mattressRect = frameRect.deflate(8);
  canvas.drawRRect(
    RRect.fromRectAndRadius(mattressRect, const Radius.circular(6)),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  // Pillows along the head (top).
  final pillowH = item.height * 0.18;
  final pillowW = (item.width - 24) / 2;
  for (var i = 0; i < 2; i++) {
    final pr = Rect.fromLTWH(
      mattressRect.left + 4 + i * (pillowW + 4),
      mattressRect.top + 6,
      pillowW,
      pillowH,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(pr, const Radius.circular(4)),
      Paint()..color = const Color(0xFFE0E0E0),
    );
  }
  canvas.drawRRect(
    RRect.fromRectAndRadius(frameRect, const Radius.circular(8)),
    Paint()
      ..color = selected ? AppColors.info : const Color(0xFF8D6E63)
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 2 : 1,
  );
}

void Function(Canvas, Item, {required bool selected}) _paintCircleInRect({
  required Color stroke,
  required Color fill,
}) {
  return (canvas, item, {required selected}) {
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: item.width,
      height: item.height,
    );
    canvas.drawRect(rect, Paint()..color = const Color(0xFFFAFAFA));
    canvas.drawRect(
      rect,
      Paint()
        ..color = selected ? AppColors.info : stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final r = math.min(item.width, item.height) * 0.4;
    canvas.drawCircle(Offset.zero, r, Paint()..color = fill);
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  };
}

void _paintToilet(Canvas canvas, Item item, {required bool selected}) {
  final tankH = item.height * 0.35;
  final tankRect = Rect.fromLTWH(
    -item.width / 2,
    -item.height / 2,
    item.width,
    tankH,
  );
  final bowlRect = Rect.fromLTWH(
    -item.width / 2 + 4,
    -item.height / 2 + tankH,
    item.width - 8,
    item.height - tankH - 4,
  );
  canvas.drawRect(tankRect, Paint()..color = const Color(0xFFF5F5F5));
  canvas.drawOval(bowlRect, Paint()..color = const Color(0xFFFFFFFF));
  final stroke = Paint()
    ..color = selected ? AppColors.info : const Color(0xFF455A64)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  canvas.drawRect(tankRect, stroke);
  canvas.drawOval(bowlRect, stroke);
}

void _paintStove(Canvas canvas, Item item, {required bool selected}) {
  final rect = Rect.fromCenter(
    center: Offset.zero,
    width: item.width,
    height: item.height,
  );
  canvas.drawRect(rect, Paint()..color = const Color(0xFFECEFF1));
  // Four burners.
  final r = math.min(item.width, item.height) * 0.16;
  for (final dx in [-1, 1]) {
    for (final dy in [-1, 1]) {
      canvas.drawCircle(
        Offset(item.width * 0.22 * dx, item.height * 0.22 * dy),
        r,
        Paint()..color = const Color(0xFFB0BEC5),
      );
    }
  }
  canvas.drawRect(
    rect,
    Paint()
      ..color = selected ? AppColors.info : const Color(0xFF546E7A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1,
  );
}
