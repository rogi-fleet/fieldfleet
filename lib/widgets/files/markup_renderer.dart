import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/file_markup.dart';

/// Renders a networked image with a [MarkupPainter] overlay. The image is
/// wrapped in an [AspectRatio] that matches the image's natural dimensions
/// so the overlay's normalized 0..1 coordinates map 1:1 onto the image
/// pixels — no letterbox drift on rotation or viewport change. Used by the
/// viewer (read-only) and shared with the editor's canvas via the
/// `_buildCanvasInner`/AspectRatio pattern there.
class MarkupImageOverlay extends StatefulWidget {
  final String imageUrl;
  final List<MarkupShape> shapes;

  /// Quarter-turn rotation applied to the composed image + overlay.
  /// 0 / 90 / 180 / 270. Rotation wraps both the image and the painter
  /// so shapes stay glued to the same image pixels after rotation.
  final int rotation;

  /// Horizontal / vertical mirror applied on top of rotation. Like
  /// [rotation], this is a view transform — the underlying bytes are
  /// never mirrored. Applying both flips is equivalent to rotating 180°.
  final bool flipHorizontal;
  final bool flipVertical;

  /// Non-destructive crop expressed as a normalized rect (0..1 in the
  /// original image's coordinate space). `Rect.fromLTWH(0,0,1,1)` means
  /// "show the whole image". Applied before rotation/flip.
  final Rect cropRect;

  /// Optional placeholder while the image resolves.
  final Widget? placeholder;

  const MarkupImageOverlay({
    super.key,
    required this.imageUrl,
    required this.shapes,
    this.rotation = 0,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.cropRect = const Rect.fromLTWH(0, 0, 1, 1),
    this.placeholder,
  });

  @override
  State<MarkupImageOverlay> createState() => _MarkupImageOverlayState();
}

class _MarkupImageOverlayState extends State<MarkupImageOverlay> {
  Size? _imageSize;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant MarkupImageOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _detach();
      _imageSize = null;
      _resolve();
    }
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _detach() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  void _resolve() {
    final provider = CachedNetworkImageProvider(widget.imageUrl);
    _stream = provider.resolve(ImageConfiguration.empty);
    _listener = ImageStreamListener(
      (info, _) {
        if (!mounted) return;
        setState(() {
          _imageSize = Size(
            info.image.width.toDouble(),
            info.image.height.toDouble(),
          );
        });
      },
      onError: (_, __) {},
    );
    _stream!.addListener(_listener!);
  }

  @override
  Widget build(BuildContext context) {
    final size = _imageSize;
    final stack = Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: widget.imageUrl,
          fit: size == null ? BoxFit.contain : BoxFit.fill,
          placeholder: (_, __) =>
              widget.placeholder ?? const SizedBox.shrink(),
          errorWidget: (_, __, ___) => const Icon(
            Icons.broken_image,
            color: Colors.white,
            size: 80,
          ),
        ),
        if (widget.shapes.isNotEmpty)
          IgnorePointer(
            child: LayoutBuilder(
              builder: (_, c) => CustomPaint(
                size: Size(c.maxWidth, c.maxHeight),
                painter: MarkupPainter(shapes: widget.shapes),
              ),
            ),
          ),
      ],
    );

    // Crop is applied FIRST (innermost) so rotate/flip operate on the
    // cropped view — that matches how users reason about the transform
    // pipeline (crop the region I care about, then rotate/flip it).
    final crop = widget.cropRect;
    final hasCrop = crop.left > 0 ||
        crop.top > 0 ||
        crop.width < 1 ||
        crop.height < 1;
    Widget cropped = stack;
    if (hasCrop) {
      cropped = ClipRect(
        child: LayoutBuilder(
          builder: (_, constraints) {
            final clipW = constraints.maxWidth;
            final clipH = constraints.maxHeight;
            // We want the *visible* clip rect (clipW × clipH) to show the
            // crop sub-region of the full image. Scale the stack up so
            // that its cropped area fills the clip, then translate so
            // the crop's top-left lands at (0,0).
            final fullW = clipW / crop.width;
            final fullH = clipH / crop.height;
            return OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: 0,
              minHeight: 0,
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: Transform.translate(
                offset: Offset(-crop.left * fullW, -crop.top * fullH),
                child: SizedBox(width: fullW, height: fullH, child: stack),
              ),
            );
          },
        ),
      );
    }

    // Aspect ratio reflects the visible (cropped) region, with a
    // 90/270 rotation swap so the outer box fits the final orientation.
    double? effectiveAspect;
    if (size != null) {
      final cw = size.width * crop.width;
      final ch = size.height * crop.height;
      effectiveAspect = (widget.rotation == 90 || widget.rotation == 270)
          ? ch / cw
          : cw / ch;
    }

    Widget transformed = RotatedBox(
      quarterTurns: ((widget.rotation % 360) / 90).round(),
      child: cropped,
    );
    if (widget.flipHorizontal || widget.flipVertical) {
      transformed = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..scale(
            widget.flipHorizontal ? -1.0 : 1.0,
            widget.flipVertical ? -1.0 : 1.0,
          ),
        child: transformed,
      );
    }

    return Center(
      child: effectiveAspect == null
          ? transformed
          : AspectRatio(aspectRatio: effectiveAspect, child: transformed),
    );
  }
}

/// CustomPainter that renders every [MarkupShape] type from normalized
/// coordinates into the given [Size]. Used by both the markup editor and
/// the read-only viewer overlay, so every shape type is painted here even
/// though the MVP editor only creates a subset.
class MarkupPainter extends CustomPainter {
  final List<MarkupShape> shapes;

  MarkupPainter({required this.shapes});

  Offset _denorm(Offset p, Size size) =>
      Offset(p.dx * size.width, p.dy * size.height);

  Color _hex(String hex) {
    var v = hex.replaceAll('#', '');
    if (v.length == 6) v = 'FF$v';
    return Color(int.parse(v, radix: 16));
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final shape in shapes) {
      switch (shape) {
        case FreeDrawShape():
          _drawPath(canvas, size, shape.points, shape.color, shape.width);
          break;
        case ArrowShape():
          _drawArrow(
            canvas,
            _denorm(shape.from, size),
            _denorm(shape.to, size),
            shape.color,
            shape.width,
          );
          break;
        case PolylineShape():
          _drawPath(canvas, size, shape.points, shape.color, shape.width,
              closed: false);
          break;
        case CalloutShape():
          _drawCallout(canvas, size, shape);
          break;
        case TextShape():
          _drawText(
            canvas,
            _denorm(shape.at, size),
            shape.text,
            shape.color,
            shape.fontSize,
          );
          break;
        case TimestampShape():
          _drawText(
            canvas,
            _denorm(shape.at, size),
            _formatTimestamp(shape.capturedAt),
            shape.color,
            14,
          );
          break;
      }
    }
  }

  void _drawPath(
    Canvas canvas,
    Size size,
    List<Offset> normalizedPoints,
    String color,
    double width, {
    bool closed = false,
  }) {
    if (normalizedPoints.length < 2) return;
    final path = Path()
      ..moveTo(
        normalizedPoints.first.dx * size.width,
        normalizedPoints.first.dy * size.height,
      );
    for (var i = 1; i < normalizedPoints.length; i++) {
      final p = normalizedPoints[i];
      path.lineTo(p.dx * size.width, p.dy * size.height);
    }
    if (closed) path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = _hex(color)
        ..strokeWidth = width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawArrow(
    Canvas canvas,
    Offset from,
    Offset to,
    String color,
    double width,
  ) {
    final paint = Paint()
      ..color = _hex(color)
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(from, to, paint);

    // Arrowhead — two strokes at 30° from the shaft, 12 + 2*width long.
    final angle = math.atan2(to.dy - from.dy, to.dx - from.dx);
    final headLen = 12.0 + width * 2;
    const headAngle = math.pi / 6;
    final h1 = to -
        Offset(
          math.cos(angle - headAngle) * headLen,
          math.sin(angle - headAngle) * headLen,
        );
    final h2 = to -
        Offset(
          math.cos(angle + headAngle) * headLen,
          math.sin(angle + headAngle) * headLen,
        );
    canvas.drawLine(to, h1, paint);
    canvas.drawLine(to, h2, paint);
  }

  void _drawCallout(Canvas canvas, Size size, CalloutShape shape) {
    final anchor = _denorm(shape.anchor, size);
    final strokeColor = _hex(shape.color);
    final fillPaint = Paint()
      ..color = strokeColor.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = strokeColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Anchor bubble — simple rounded rect sized to the text.
    final textPainter = _buildTextPainter(
      shape.text.isEmpty ? '…' : shape.text,
      strokeColor,
      shape.fontSize,
    );
    textPainter.layout();
    const padding = 6.0;
    final bubble = Rect.fromCenter(
      center: anchor,
      width: textPainter.width + padding * 2,
      height: textPainter.height + padding * 2,
    );
    final rrect = RRect.fromRectAndRadius(bubble, const Radius.circular(6));
    canvas.drawRRect(rrect, fillPaint);
    canvas.drawRRect(rrect, strokePaint);
    textPainter.paint(canvas, bubble.topLeft + const Offset(padding, padding));

    // Each tail — simple line from the bubble edge to the tail point.
    for (final tailN in shape.tails) {
      final tail = _denorm(tailN, size);
      // Find the intersection of the line (anchor → tail) with the bubble
      // edge so tails don't start inside the bubble rect.
      final edge = _clipLineToRect(anchor, tail, bubble) ?? anchor;
      canvas.drawLine(edge, tail, strokePaint);
      // Small arrowhead at the tail tip.
      final angle = math.atan2(tail.dy - edge.dy, tail.dx - edge.dx);
      const headLen = 8.0;
      const headAngle = math.pi / 6;
      final h1 = tail -
          Offset(
            math.cos(angle - headAngle) * headLen,
            math.sin(angle - headAngle) * headLen,
          );
      final h2 = tail -
          Offset(
            math.cos(angle + headAngle) * headLen,
            math.sin(angle + headAngle) * headLen,
          );
      canvas.drawLine(tail, h1, strokePaint);
      canvas.drawLine(tail, h2, strokePaint);
    }
  }

  /// Return the point on the edge of [rect] crossed by the line from
  /// [inside] to [outside]. Returns null when the line is degenerate.
  Offset? _clipLineToRect(Offset inside, Offset outside, Rect rect) {
    final dx = outside.dx - inside.dx;
    final dy = outside.dy - inside.dy;
    if (dx == 0 && dy == 0) return null;
    // Parameterize line as inside + t*(outside-inside), t in [0,1]. The
    // exit point is the smallest t > 0 that lies on any rect edge. For a
    // bubble that contains `inside`, the crossing is to the right/left or
    // top/bottom depending on direction.
    final ts = <double>[];
    if (dx != 0) {
      ts.add((rect.left - inside.dx) / dx);
      ts.add((rect.right - inside.dx) / dx);
    }
    if (dy != 0) {
      ts.add((rect.top - inside.dy) / dy);
      ts.add((rect.bottom - inside.dy) / dy);
    }
    // Pick the smallest positive t whose hit-point is within the rect bounds.
    double? best;
    for (final t in ts) {
      if (t <= 0) continue;
      final hit = Offset(inside.dx + dx * t, inside.dy + dy * t);
      if (hit.dx < rect.left - 0.1 ||
          hit.dx > rect.right + 0.1 ||
          hit.dy < rect.top - 0.1 ||
          hit.dy > rect.bottom + 0.1) {
        continue;
      }
      if (best == null || t < best) best = t;
    }
    if (best == null) return null;
    return Offset(inside.dx + dx * best, inside.dy + dy * best);
  }

  void _drawText(
    Canvas canvas,
    Offset at,
    String text,
    String color,
    double fontSize,
  ) {
    final painter = _buildTextPainter(text, _hex(color), fontSize);
    painter.layout();
    painter.paint(canvas, at);
  }

  TextPainter _buildTextPainter(String text, Color color, double fontSize) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          shadows: const [
            Shadow(
              color: Colors.black54,
              blurRadius: 2,
              offset: Offset(1, 1),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 4,
    );
  }

  String _formatTimestamp(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  @override
  bool shouldRepaint(covariant MarkupPainter oldDelegate) =>
      !identical(oldDelegate.shapes, shapes);
}
