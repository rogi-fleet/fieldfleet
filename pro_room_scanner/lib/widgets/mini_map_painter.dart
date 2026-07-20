import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models_and_math.dart';

class MiniMapPainter extends CustomPainter {
  final List<RoomPoint> points;
  MiniMapPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    // Auto-Scale
    double minX = double.infinity, maxX = -double.infinity;
    double minZ = double.infinity, maxZ = -double.infinity;
    for (var p in points) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.z < minZ) minZ = p.z;
      if (p.z > maxZ) maxZ = p.z;
    }

    double w = maxX - minX;
    double h = maxZ - minZ;
    if (w == 0) w = 1; if (h == 0) h = 1;

    double padding = 20;
    double scale = math.min((size.width - padding) / w, (size.height - padding) / h);
    double dx = (size.width - (w * scale)) / 2 - (minX * scale);
    double dy = (size.height - (h * scale)) / 2 - (minZ * scale);

    Offset toCanvas(RoomPoint p) => Offset(p.x * scale + dx, p.z * scale + dy);

    // Draw Path
    Paint paint = Paint()..color = Colors.blue..strokeWidth = 3.0..style = PaintingStyle.stroke;
    Path path = Path();
    path.moveTo(toCanvas(points[0]).dx, toCanvas(points[0]).dy);
    for (int i = 1; i < points.length; i++) {
      var o = toCanvas(points[i]);
      path.lineTo(o.dx, o.dy);
    }
    // Don't close path yet, show open shape
    canvas.drawPath(path, paint);

    // Draw Points
    Paint pointPaint = Paint()..color = Colors.red..style = PaintingStyle.fill;
    for (var p in points) {
      canvas.drawCircle(toCanvas(p), 4, pointPaint);
    }
    
    // Draw room label if present (show label of first point)
    if (points.isNotEmpty && points.first.roomLabel != null) {
      TextPainter tp = TextPainter(
        text: TextSpan(
          text: points.first.roomLabel!,
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 10),
        ),
        textDirection: ui.TextDirection.ltr,
      );
      tp.layout();
      Offset center = Offset(size.width / 2, size.height / 2);
      canvas.drawRect(
        Rect.fromCenter(center: center, width: tp.width + 6, height: tp.height + 4),
        Paint()..color = Colors.white.withOpacity(0.9),
      );
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
