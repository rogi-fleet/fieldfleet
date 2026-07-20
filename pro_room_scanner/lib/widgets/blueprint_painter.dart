import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models_and_math.dart';

class BlueprintPainter extends CustomPainter {
  final List<RoomPoint> points;
  final List<WallOpening> openings;
  final AppUnit unit;
  final int? selectedIndex;
  final List<Attachment> attachments;
  final int? selectedCornerIndex;
  final WallOpening? ghostOpening;

  BlueprintPainter(
    this.points, 
    this.openings, 
    this.unit, 
    this.selectedIndex, 
    {
      this.attachments = const [], 
      this.selectedCornerIndex,
      this.ghostOpening,
    }
  );

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

    double padding = 60;
    double scale = math.min((size.width - padding) / w, (size.height - padding) / h);
    double dx = (size.width - (w * scale)) / 2 - (minX * scale);
    double dy = (size.height - (h * scale)) / 2 - (minZ * scale);

    Offset toCanvas(RoomPoint p) => Offset(p.x * scale + dx, p.z * scale + dy);

    // Draw Fill
    Path path = Path();
    path.moveTo(toCanvas(points[0]).dx, toCanvas(points[0]).dy);
    for (int i = 1; i < points.length; i++) {
      var o = toCanvas(points[i]);
      path.lineTo(o.dx, o.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = Colors.blue.withOpacity(0.1)..style = PaintingStyle.fill);

    // Draw Walls
    Paint wallPaint = Paint()..color = Colors.black..strokeWidth = 5.0..style = PaintingStyle.stroke;
    for (int i = 0; i < points.length; i++) {
      var p1 = points[i];
      var p2 = points[(i + 1) % points.length];
      canvas.drawLine(toCanvas(p1), toCanvas(p2), wallPaint);
      
      // Dimensions
      _drawLabel(canvas, toCanvas(p1), toCanvas(p2), p1.distanceTo(p2));
    }

    // Draw corner points
    Paint cornerPaint = Paint()..color = Colors.blue..style = PaintingStyle.fill;
    Paint selectedCornerPaint = Paint()..color = Colors.amber..style = PaintingStyle.fill;
    Paint cornerStrokePaint = Paint()..color = Colors.white..strokeWidth = 2..style = PaintingStyle.stroke;
    
    for (int i = 0; i < points.length; i++) {
      final isSelected = selectedCornerIndex == i;
      final cornerPos = toCanvas(points[i]);
      
      // Draw larger highlight for selected corner
      if (isSelected) {
        canvas.drawCircle(cornerPos, 15, selectedCornerPaint);
        canvas.drawCircle(cornerPos, 15, cornerStrokePaint);
      } else {
        canvas.drawCircle(cornerPos, 8, cornerPaint);
        canvas.drawCircle(cornerPos, 8, cornerStrokePaint);
      }
    }

    // Draw Openings
    for (int i = 0; i < openings.length; i++) {
      _drawOpening(canvas, openings[i], toCanvas, scale, isSelected: selectedIndex == i);
    }
    
    // Draw Ghost Opening
    if (ghostOpening != null) {
      _drawOpening(canvas, ghostOpening!, toCanvas, scale, isGhost: true);
    }
    
    // Draw room label in center of floor plan (if any point has a label)
    String? roomLabel = points.firstWhere((p) => p.roomLabel != null, orElse: () => points.first).roomLabel;
    if (roomLabel != null) {
      // Calculate center of polygon
      double centerX = 0, centerZ = 0;
      for (var p in points) {
        centerX += p.x;
        centerZ += p.z;
      }
      centerX /= points.length;
      centerZ /= points.length;
      
      Offset center = toCanvas(RoomPoint(centerX, centerZ));
      TextPainter tp = TextPainter(
        text: TextSpan(
          text: roomLabel,
          style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        textDirection: ui.TextDirection.ltr,
      );
      tp.layout();
      canvas.drawRect(
        Rect.fromCenter(center: center, width: tp.width + 12, height: tp.height + 8),
        Paint()..color = Colors.white.withOpacity(0.9),
      );
      canvas.drawRect(
        Rect.fromCenter(center: center, width: tp.width + 12, height: tp.height + 8),
        Paint()..color = Colors.blue..style = PaintingStyle.stroke..strokeWidth = 2,
      );
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    }
  }
  
  void _drawOpening(Canvas canvas, WallOpening op, Offset Function(RoomPoint) toCanvas, double scale, {bool isSelected = false, bool isGhost = false}) {
    Offset c = toCanvas(op.position);
    double widthPx = op.width * scale;
    
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(op.rotation);
    
    // Highlight if selected
    if (isSelected) {
      canvas.drawCircle(Offset.zero, widthPx / 2 + 15, Paint()..color = Colors.orange.withOpacity(0.3)..style = PaintingStyle.fill);
      canvas.drawCircle(Offset.zero, widthPx / 2 + 15, Paint()..color = Colors.orange..strokeWidth = 2..style = PaintingStyle.stroke);
    }
    
    double opacity = isGhost ? 0.5 : 1.0;
    
    // Cutout
    canvas.drawRect(
      Rect.fromCenter(center: Offset.zero, width: widthPx, height: 6), 
      Paint()..color = Colors.white.withOpacity(opacity)
    );

    if (op.type == OpeningType.door) {
      // Door Swing
      canvas.drawRect(
        Rect.fromLTWH(-widthPx/2, -widthPx, 4, widthPx), 
        Paint()..color = Colors.red.withOpacity(opacity)
      );
      canvas.drawArc(
        Rect.fromLTWH(-widthPx/2, -widthPx, widthPx*2, widthPx*2), 
        math.pi, math.pi/2, false, 
        Paint()..color = Colors.red.withOpacity(opacity)..style = PaintingStyle.stroke
      );
    } else {
      // Window (Glass)
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: widthPx, height: 2), 
        Paint()..color = Colors.blue.withOpacity(opacity)
      );
    }
    canvas.restore();
  }

  void _drawLabel(Canvas c, Offset p1, Offset p2, double dist) {
    Offset mid = Offset((p1.dx + p2.dx)/2, (p1.dy + p2.dy)/2);
    String text = UnitConverter.formatLength(dist, unit);
    TextPainter tp = TextPainter(text: TextSpan(text: text, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)), textDirection: ui.TextDirection.ltr);
    tp.layout();
    c.drawRect(Rect.fromCenter(center: mid, width: tp.width+4, height: tp.height+4), Paint()..color = Colors.white.withOpacity(0.8));
    tp.paint(c, mid - Offset(tp.width/2, tp.height/2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
