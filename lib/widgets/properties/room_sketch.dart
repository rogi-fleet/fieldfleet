import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Lightweight vector sketch widget for room layouts.
///
/// Strokes are stored as a list of maps:
/// `{ "color": int (ARGB), "width": double, "points": [{"x": 0..1, "y": 0..1}, ...] }`.
/// Coordinates are normalized so the same data renders crisply at any size.
class RoomSketchView extends StatelessWidget {
  final List<Map<String, dynamic>> strokes;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;

  const RoomSketchView({
    super.key,
    required this.strokes,
    this.width,
    this.height,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.cardBorder),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: CustomPaint(
          painter: _RoomSketchPainter(strokes),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _RoomSketchPainter extends CustomPainter {
  final List<Map<String, dynamic>> strokes;
  _RoomSketchPainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    if (strokes.isEmpty) return;
    for (final stroke in strokes) {
      final pts = (stroke['points'] as List?) ?? const [];
      if (pts.isEmpty) continue;
      final colorVal = (stroke['color'] as num?)?.toInt() ?? 0xFF1F2937;
      final widthVal = (stroke['width'] as num?)?.toDouble() ?? 2.0;
      final paint = Paint()
        ..color = Color(colorVal)
        ..strokeWidth = widthVal
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final path = Path();
      var first = true;
      for (final p in pts) {
        final x = ((p['x'] as num?)?.toDouble() ?? 0) * size.width;
        final y = ((p['y'] as num?)?.toDouble() ?? 0) * size.height;
        if (first) {
          path.moveTo(x, y);
          first = false;
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RoomSketchPainter old) => true;
}

/// Full-screen modal editor for the room sketch.
///
/// Returns the new list of strokes via Navigator.pop, or null if cancelled.
class RoomSketchEditor extends StatefulWidget {
  final String roomName;
  final List<Map<String, dynamic>> initialStrokes;

  const RoomSketchEditor({
    super.key,
    required this.roomName,
    required this.initialStrokes,
  });

  @override
  State<RoomSketchEditor> createState() => _RoomSketchEditorState();
}

class _RoomSketchEditorState extends State<RoomSketchEditor> {
  late List<Map<String, dynamic>> _strokes;
  Map<String, dynamic>? _currentStroke;
  Color _color = const Color(0xFF1F2937);
  double _width = 3.0;
  Size _canvasSize = Size.zero;

  static const _palette = <Color>[
    Color(0xFF1F2937), // dark slate
    AppColors.info, // blue (wet)
    AppColors.success, // green (dry)
    AppColors.error, // red (damaged)
    AppColors.warning, // amber (in progress)
  ];

  @override
  void initState() {
    super.initState();
    _strokes = widget.initialStrokes
        .map((s) => Map<String, dynamic>.from(s))
        .toList();
  }

  void _startStroke(Offset local) {
    if (_canvasSize.width <= 0 || _canvasSize.height <= 0) return;
    final stroke = <String, dynamic>{
      'color': _color.toARGB32(),
      'width': _width,
      'points': [_normalize(local)],
    };
    setState(() {
      _currentStroke = stroke;
      _strokes.add(stroke);
    });
  }

  void _extendStroke(Offset local) {
    if (_currentStroke == null) return;
    final pts = _currentStroke!['points'] as List;
    pts.add(_normalize(local));
    setState(() {});
  }

  void _endStroke() {
    _currentStroke = null;
  }

  Map<String, double> _normalize(Offset local) {
    final x = (local.dx / _canvasSize.width).clamp(0.0, 1.0);
    final y = (local.dy / _canvasSize.height).clamp(0.0, 1.0);
    return {'x': x, 'y': y};
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.removeLast());
  }

  void _clear() {
    setState(() => _strokes.clear());
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.draw, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sketch — ${widget.roomName}',
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Draw the room outline, then mark wet/dry zones using colors below.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _canvasSize = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (d) => _startStroke(d.localPosition),
                      onPanUpdate: (d) => _extendStroke(d.localPosition),
                      onPanEnd: (_) => _endStroke(),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: AppColors.cardBorder),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: CustomPaint(
                            painter: _RoomSketchPainter(_strokes),
                            size: Size.infinite,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final c in _palette)
                    GestureDetector(
                      onTap: () => setState(() => _color = c),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _color.toARGB32() == c.toARGB32()
                                ? AppColors.textPrimary
                                : AppColors.cardBorder,
                            width: _color.toARGB32() == c.toARGB32() ? 2 : 1,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 140,
                    child: Row(
                      children: [
                        const Icon(Icons.line_weight, size: 16),
                        Expanded(
                          child: Slider(
                            min: 1,
                            max: 10,
                            value: _width,
                            onChanged: (v) => setState(() => _width = v),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _strokes.isEmpty ? null : _undo,
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('Undo'),
                  ),
                  TextButton.icon(
                    onPressed: _strokes.isEmpty ? null : _clear,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Clear'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(_strokes),
                    icon: const Icon(Icons.save, size: 18),
                    label: const Text('Save sketch'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
