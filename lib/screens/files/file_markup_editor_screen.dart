import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/file_attachment.dart';
import '../../models/file_markup.dart';
import '../../providers/auth_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../widgets/files/markup_renderer.dart';

/// Non-destructive markup editor for an image file.
///
/// MVP tool set: free draw, arrow, text. Shapes are stored with normalized
/// coordinates (0..1) so they survive rotation and render at any viewport
/// size — see [MarkupRenderer] for the corresponding painter. Undo/redo is
/// an immutable history stack of `List<MarkupShape>` snapshots. Saving
/// upserts the head to `file_markup_layers`; "Revert to Original" deletes
/// the row entirely. Original file bytes are never touched.
class FileMarkupEditorScreen extends StatefulWidget {
  final FileAttachment file;

  const FileMarkupEditorScreen({super.key, required this.file});

  @override
  State<FileMarkupEditorScreen> createState() => _FileMarkupEditorScreenState();
}

enum _Tool {
  freeDraw,
  arrow,
  text,
  callout,
  polyline,
  timestamp,
  crop,
  select,
  pan,
}

/// Identifies a drag handle on the crop rectangle. Each corner plus a
/// "body" handle for moving the whole rect.
enum _CropHandle { topLeft, topRight, bottomLeft, bottomRight, body, none }

class _FileMarkupEditorScreenState extends State<FileMarkupEditorScreen> {
  final _service = ServiceLocator.fileMarkupService;
  final _uuid = const Uuid();

  /// History stack — [_history]`[_historyIndex]` is the current shape list.
  /// An edit truncates everything past the current index before pushing,
  /// standard undo/redo semantics.
  final List<List<MarkupShape>> _history = <List<MarkupShape>>[<MarkupShape>[]];
  int _historyIndex = 0;

  _Tool _tool = _Tool.freeDraw;
  String _color = '#FF5722';
  double _strokeWidth = 3.0;

  bool _exporting = false;

  /// Quarter-turn view rotation applied to the image + markup overlay.
  /// Non-destructive: the underlying file bytes are never rotated.
  int _rotation = 0;
  bool _flipH = false;
  bool _flipV = false;

  /// Normalized crop rect (0..1 of the original image). `(0,0,1,1)` means
  /// no crop. Mutated by the Crop tool's drag gestures.
  Rect _cropRect = const Rect.fromLTWH(0, 0, 1, 1);

  /// Which crop handle the user is currently dragging, and the rect at
  /// gesture start so we can compute deltas in normalized space.
  _CropHandle _cropDragHandle = _CropHandle.none;
  Rect? _cropDragStartRect;
  Offset? _cropDragStartPoint;

  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;

  // --- In-progress shape while dragging. Transient, not in history yet. ---
  List<Offset>? _drawingPoints;
  Offset? _arrowFrom;
  Offset? _arrowTo;

  // --- Callout session: drag places anchor→first tail; text prompt follows.
  Offset? _calloutAnchor;
  Offset? _calloutTail;

  // --- Polyline session: list of vertices placed by tap. Rendered live
  // as a transient shape until the user taps the Finish button or picks
  // another tool, at which point it's committed to history.
  List<Offset>? _polylinePoints;

  // --- Selection. When set, the tile + floating toolbar appear. Also drives
  // "add tail" on callouts: _addingTailFor holds the id of a callout whose
  // next tap will drop another tail and clear this flag.
  String? _selectedShapeId;
  String? _addingTailFor;

  // --- Render metrics captured in LayoutBuilder for coord normalization. ---
  Size? _canvasSize;

  // --- Natural image dimensions — resolved once via ImageStream so the
  // canvas can size itself to the image's aspect ratio. This eliminates
  // the letterbox around BoxFit.contain so gesture coords map directly
  // into image-relative 0..1 space; the same transform applies on the
  // viewer side via MarkupImageOverlay.
  Size? _imageSize;
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;

  static const _palette = [
    '#FF5722', // orange (default)
    '#2563EB', // blue
    '#16A34A', // green
    '#F59E0B', // amber
    '#DC2626', // red
    '#9333EA', // purple
    '#111827', // near-black
    '#FFFFFF', // white
  ];

  List<MarkupShape> get _shapes => _history[_historyIndex];

  @override
  void initState() {
    super.initState();
    _load();
    _resolveImageSize();
  }

  @override
  void dispose() {
    if (_imageStream != null && _imageListener != null) {
      _imageStream!.removeListener(_imageListener!);
    }
    super.dispose();
  }

  void _resolveImageSize() {
    final provider = CachedNetworkImageProvider(widget.file.fileUrl);
    _imageStream = provider.resolve(ImageConfiguration.empty);
    _imageListener = ImageStreamListener(
      (info, _) {
        if (!mounted) return;
        setState(() {
          _imageSize = Size(
            info.image.width.toDouble(),
            info.image.height.toDouble(),
          );
        });
      },
      onError: (_, __) {
        // Fall back to full-canvas mapping below.
      },
    );
    _imageStream!.addListener(_imageListener!);
  }

  Future<void> _load() async {
    try {
      final layer = await _service.getLayer(widget.file.id);
      if (!mounted) return;
      setState(() {
        if (layer != null) {
          _history
            ..clear()
            ..add(List<MarkupShape>.from(layer.shapes));
          _historyIndex = 0;
          _rotation = layer.rotation;
          _flipH = layer.flipHorizontal;
          _flipV = layer.flipVertical;
          _cropRect = layer.cropRect;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not load markup: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  // ─── History ────────────────────────────────────────────────────────────
  void _pushState(List<MarkupShape> next) {
    final trimmed = _history.sublist(0, _historyIndex + 1);
    setState(() {
      _history
        ..clear()
        ..addAll(trimmed)
        ..add(next);
      _historyIndex = _history.length - 1;
      _dirty = true;
    });
  }

  void _undo() {
    if (_historyIndex == 0) return;
    setState(() {
      _historyIndex--;
      _dirty = true;
    });
  }

  void _redo() {
    if (_historyIndex >= _history.length - 1) return;
    setState(() {
      _historyIndex++;
      _dirty = true;
    });
  }

  // ─── Coords ─────────────────────────────────────────────────────────────
  Offset _toNormalized(Offset local) {
    final size = _canvasSize;
    if (size == null || size.width == 0 || size.height == 0) return local;
    return Offset(
      (local.dx / size.width).clamp(0.0, 1.0),
      (local.dy / size.height).clamp(0.0, 1.0),
    );
  }

  // ─── Gestures per tool ──────────────────────────────────────────────────
  void _onPanStart(DragStartDetails d) {
    final p = _toNormalized(d.localPosition);
    switch (_tool) {
      case _Tool.freeDraw:
        setState(() => _drawingPoints = [p]);
        break;
      case _Tool.arrow:
        setState(() {
          _arrowFrom = p;
          _arrowTo = p;
        });
        break;
      case _Tool.callout:
        setState(() {
          _calloutAnchor = p;
          _calloutTail = p;
        });
        break;
      case _Tool.crop:
        _cropDragHandle = _hitTestCropHandle(p);
        _cropDragStartRect = _cropRect;
        _cropDragStartPoint = p;
        if (_cropDragHandle == _CropHandle.none) {
          // Started drag outside the current crop — begin drawing a new
          // rect. Anchor the new crop's top-left to where the drag began.
          _cropDragHandle = _CropHandle.bottomRight;
          setState(() => _cropRect = Rect.fromLTWH(p.dx, p.dy, 0.001, 0.001));
          _cropDragStartRect = _cropRect;
        }
        break;
      case _Tool.text:
      case _Tool.polyline:
      case _Tool.timestamp:
      case _Tool.select:
      case _Tool.pan:
        break; // use tap, not drag (Pan is handled by InteractiveViewer)
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final p = _toNormalized(d.localPosition);
    switch (_tool) {
      case _Tool.freeDraw:
        if (_drawingPoints == null) return;
        setState(() => _drawingPoints!.add(p));
        break;
      case _Tool.arrow:
        setState(() => _arrowTo = p);
        break;
      case _Tool.callout:
        if (_calloutAnchor == null) return;
        setState(() => _calloutTail = p);
        break;
      case _Tool.crop:
        _updateCropFromDrag(p);
        break;
      case _Tool.text:
      case _Tool.polyline:
      case _Tool.timestamp:
      case _Tool.select:
      case _Tool.pan:
        break;
    }
  }

  Future<void> _onPanEnd(DragEndDetails _) async {
    switch (_tool) {
      case _Tool.freeDraw:
        final pts = _drawingPoints;
        setState(() => _drawingPoints = null);
        if (pts == null || pts.length < 2) return;
        _pushState([
          ..._shapes,
          FreeDrawShape(
            id: _uuid.v4(),
            color: _color,
            width: _strokeWidth,
            points: pts,
          ),
        ]);
        break;
      case _Tool.arrow:
        final from = _arrowFrom;
        final to = _arrowTo;
        setState(() {
          _arrowFrom = null;
          _arrowTo = null;
        });
        if (from == null || to == null) return;
        if ((from - to).distanceSquared < 1e-6) return;
        _pushState([
          ..._shapes,
          ArrowShape(
            id: _uuid.v4(),
            color: _color,
            width: _strokeWidth,
            from: from,
            to: to,
          ),
        ]);
        break;
      case _Tool.callout:
        final anchor = _calloutAnchor;
        final tail = _calloutTail;
        setState(() {
          _calloutAnchor = null;
          _calloutTail = null;
        });
        if (anchor == null || tail == null) return;
        if ((anchor - tail).distanceSquared < 1e-6) return;
        final text = await _promptForText(title: 'Callout text');
        if (text == null || text.trim().isEmpty) return;
        _pushState([
          ..._shapes,
          CalloutShape(
            id: _uuid.v4(),
            color: _color,
            anchor: anchor,
            tails: [tail],
            text: text.trim(),
          ),
        ]);
        break;
      case _Tool.crop:
        _cropDragHandle = _CropHandle.none;
        _cropDragStartRect = null;
        _cropDragStartPoint = null;
        _dirty = true;
        break;
      case _Tool.text:
      case _Tool.polyline:
      case _Tool.timestamp:
      case _Tool.select:
      case _Tool.pan:
        break;
    }
  }

  Future<void> _onTapDown(TapDownDetails d) async {
    final at = _toNormalized(d.localPosition);

    // "Add tail" mode is a one-shot click that appends a tail to a
    // specific callout, regardless of which tool is currently selected.
    if (_addingTailFor != null) {
      final targetId = _addingTailFor!;
      setState(() => _addingTailFor = null);
      final shapes = [..._shapes];
      final idx = shapes.indexWhere((s) => s.id == targetId);
      if (idx < 0) return;
      final existing = shapes[idx];
      if (existing is! CalloutShape) return;
      shapes[idx] = CalloutShape(
        id: existing.id,
        color: existing.color,
        anchor: existing.anchor,
        tails: [...existing.tails, at],
        text: existing.text,
        fontSize: existing.fontSize,
      );
      _pushState(shapes);
      return;
    }

    switch (_tool) {
      case _Tool.text:
        final text = await _promptForText();
        if (text == null || text.trim().isEmpty) return;
        _pushState([
          ..._shapes,
          TextShape(
            id: _uuid.v4(),
            color: _color,
            at: at,
            text: text.trim(),
          ),
        ]);
        break;
      case _Tool.timestamp:
        _pushState([
          ..._shapes,
          TimestampShape(
            id: _uuid.v4(),
            color: _color,
            at: at,
            capturedAt: DateTime.now(),
          ),
        ]);
        break;
      case _Tool.polyline:
        setState(() {
          _polylinePoints = [...(_polylinePoints ?? const []), at];
        });
        break;
      case _Tool.select:
        final hitId = _hitTest(at);
        setState(() => _selectedShapeId = hitId);
        break;
      case _Tool.crop:
      case _Tool.pan:
        // Drag-only tools — nothing to do on tap.
        break;
      case _Tool.freeDraw:
      case _Tool.arrow:
      case _Tool.callout:
        // Clicking on empty area in a drawing tool clears selection so
        // the floating toolbar doesn't cover the next drawing.
        if (_selectedShapeId != null) {
          setState(() => _selectedShapeId = null);
        }
        break;
    }
  }

  void _selectTool(_Tool tool) {
    // Leaving the polyline tool (or choosing a different one mid-sequence)
    // commits whatever's been placed if it has enough points to be a line.
    if (_tool == _Tool.polyline && tool != _Tool.polyline) {
      _finishPolyline();
    }
    setState(() {
      _tool = tool;
      if (tool != _Tool.select) _selectedShapeId = null;
    });
  }

  void _finishPolyline() {
    final pts = _polylinePoints;
    if (pts == null) return;
    setState(() => _polylinePoints = null);
    if (pts.length < 2) return;
    _pushState([
      ..._shapes,
      PolylineShape(
        id: _uuid.v4(),
        color: _color,
        width: _strokeWidth,
        points: pts,
      ),
    ]);
  }

  /// Hit-test shapes at the given normalized point. Tolerance is ~12px
  /// at typical canvas sizes — we convert by canvasSize on the fly.
  String? _hitTest(Offset normalizedP) {
    final size = _canvasSize;
    if (size == null) return null;
    final tolerance = 12.0 / size.shortestSide;
    final tolerance2 = tolerance * tolerance;
    final p = normalizedP;

    Offset denorm(Offset n) => Offset(n.dx, n.dy);

    // Topmost (latest-added) shape wins — matches painter draw order.
    for (var i = _shapes.length - 1; i >= 0; i--) {
      final shape = _shapes[i];
      switch (shape) {
        case FreeDrawShape():
          for (var j = 1; j < shape.points.length; j++) {
            if (_distSqToSegment(p, shape.points[j - 1], shape.points[j]) <
                tolerance2) {
              return shape.id;
            }
          }
          break;
        case ArrowShape():
          if (_distSqToSegment(p, shape.from, shape.to) < tolerance2) {
            return shape.id;
          }
          break;
        case PolylineShape():
          for (var j = 1; j < shape.points.length; j++) {
            if (_distSqToSegment(p, shape.points[j - 1], shape.points[j]) <
                tolerance2) {
              return shape.id;
            }
          }
          break;
        case CalloutShape():
          // Generous hit area around the anchor (bubble) + each tail line.
          if ((p - denorm(shape.anchor)).distanceSquared <
              tolerance2 * 16) {
            return shape.id;
          }
          for (final tail in shape.tails) {
            if (_distSqToSegment(p, shape.anchor, tail) < tolerance2) {
              return shape.id;
            }
          }
          break;
        case TextShape():
          if ((p - denorm(shape.at)).distanceSquared < tolerance2 * 36) {
            return shape.id;
          }
          break;
        case TimestampShape():
          if ((p - denorm(shape.at)).distanceSquared < tolerance2 * 36) {
            return shape.id;
          }
          break;
      }
    }
    return null;
  }

  static double _distSqToSegment(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) {
      final rx = p.dx - a.dx;
      final ry = p.dy - a.dy;
      return rx * rx + ry * ry;
    }
    var t = ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / lenSq;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    final closestX = a.dx + t * dx;
    final closestY = a.dy + t * dy;
    final rx = p.dx - closestX;
    final ry = p.dy - closestY;
    return rx * rx + ry * ry;
  }

  void _deleteSelected() {
    final id = _selectedShapeId;
    if (id == null) return;
    setState(() => _selectedShapeId = null);
    _pushState(_shapes.where((s) => s.id != id).toList());
  }

  void _beginAddingTail() {
    final id = _selectedShapeId;
    if (id == null) return;
    final target = _shapes.firstWhere(
      (s) => s.id == id,
      orElse: () => throw StateError('selected shape missing'),
    );
    if (target is! CalloutShape) return;
    setState(() => _addingTailFor = id);
  }

  Future<String?> _promptForText({String title = 'Text label'}) async {
    final controller = TextEditingController();
    return showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Say something'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  // ─── Save / Revert ──────────────────────────────────────────────────────
  Future<void> _save() async {
    // Capture context-dependent values before the async gap so the
    // mounted check is the only post-await context use.
    final authorId = context.read<AuthProvider>().appUser?.id;
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await _service.upsertLayer(
        workspaceId: widget.file.workspaceId,
        fileAttachmentId: widget.file.id,
        shapes: _shapes,
        rotation: _rotation,
        flipHorizontal: _flipH,
        flipVertical: _flipV,
        cropRect: _cropRect,
        authorId: authorId,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
      });
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  /// Flatten the current image + markup layer into a PNG and upload it as
  /// a new file_attachment in the same project. Non-destructive: the
  /// original file and its markup row are both left alone.
  ///
  /// The composed PNG applies the full transform pipeline (crop → rotate →
  /// flip) + shapes so the output matches what the viewer renders, not
  /// the image-native editor canvas. Rendering runs through a direct
  /// PictureRecorder/Canvas rather than a RepaintBoundary capture because
  /// the editor canvas intentionally stays image-native (simpler drawing).
  Future<void> _saveAsNewFile() async {
    if (_exporting) return;
    final uploader = context.read<AuthProvider>().appUser?.id ?? '';
    setState(() => _exporting = true);
    try {
      final bytes = await _renderTransformedPng();

      final newName = _exportedFileName(widget.file.fileName);
      final uploaded = await ServiceLocator.storageService.uploadFileBytes(
        bytes: bytes,
        fileName: newName,
        workspaceId: widget.file.workspaceId,
        projectId: widget.file.projectId,
        folderId: widget.file.folderId,
        uploadedBy: uploader,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved "${uploaded.fileName}"'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Turn `photo.jpg` into `photo (marked up).png`. Falls back gracefully
  /// for names without an extension.
  String _exportedFileName(String original) {
    final dot = original.lastIndexOf('.');
    final stem = dot > 0 ? original.substring(0, dot) : original;
    return '$stem (marked up).png';
  }

  /// Composite image + markup with the current transform pipeline
  /// (crop → rotate → flip) into a PNG. Mirrors what the viewer renders
  /// so "Save as new file" produces the expected WYSIWYG output.
  Future<Uint8List> _renderTransformedPng() async {
    final image = await _loadUiImage(widget.file.fileUrl);
    try {
      final origW = image.width.toDouble();
      final origH = image.height.toDouble();
      final cropPx = Rect.fromLTWH(
        _cropRect.left * origW,
        _cropRect.top * origH,
        _cropRect.width * origW,
        _cropRect.height * origH,
      );

      // Output dimensions reflect the VISIBLE (post-transform) view.
      // 90/270 rotation swaps the aspect so the image doesn't crush.
      final cropW = cropPx.width;
      final cropH = cropPx.height;
      final rotated90 = _rotation == 90 || _rotation == 270;
      final outW = rotated90 ? cropH : cropW;
      final outH = rotated90 ? cropW : cropH;

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(
        recorder,
        Rect.fromLTWH(0, 0, outW, outH),
      );

      // Paint a white backdrop so transparent images don't bleed through.
      canvas.drawRect(
        Rect.fromLTWH(0, 0, outW, outH),
        Paint()..color = const Color(0xFFFFFFFF),
      );

      // Transform stack: crop → rotate → flip, applied inside-out so the
      // last matrix op executes first on the drawn content.
      //
      // 1. Translate to output center
      // 2. Flip (mirror across the center axis)
      // 3. Rotate around the center
      // 4. Translate to top-left of the cropped region
      // All subsequent draws treat (0,0)..(cropW,cropH) as the cropped
      // image's own coordinate space.
      canvas.save();
      canvas.translate(outW / 2, outH / 2);
      if (_flipH || _flipV) {
        canvas.scale(_flipH ? -1.0 : 1.0, _flipV ? -1.0 : 1.0);
      }
      canvas.rotate(_rotation * math.pi / 180);
      canvas.translate(-cropW / 2, -cropH / 2);

      // Draw the cropped sub-region of the source into the full cropped
      // canvas area. drawImageRect handles scaling + clipping.
      canvas.drawImageRect(
        image,
        cropPx,
        Rect.fromLTWH(0, 0, cropW, cropH),
        Paint()..filterQuality = FilterQuality.high,
      );

      // Shapes are normalized to the FULL image. Translate back by the
      // crop offset (in cropped-image pixels) before handing MarkupPainter
      // the full-image size — a shape at normalized image-native (x, y)
      // lands at (x*origW - cropPx.left, y*origH - cropPx.top), which is
      // its correct position inside the cropped frame.
      canvas.save();
      canvas.translate(-cropPx.left, -cropPx.top);
      MarkupPainter(shapes: _shapes).paint(canvas, Size(origW, origH));
      canvas.restore();

      canvas.restore();

      final picture = recorder.endRecording();
      final outImage = await picture.toImage(
        outW.round().clamp(1, 8192),
        outH.round().clamp(1, 8192),
      );
      picture.dispose();
      final byteData =
          await outImage.toByteData(format: ui.ImageByteFormat.png);
      outImage.dispose();
      if (byteData == null) throw StateError('Failed to encode PNG');
      return byteData.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  /// Resolve a network image URL into a decoded [ui.Image] via the image
  /// cache — reuses anything already loaded by MarkupImageOverlay or the
  /// editor canvas, so save-as is usually sub-second on a warm cache.
  Future<ui.Image> _loadUiImage(String url) {
    final completer = Completer<ui.Image>();
    final provider = CachedNetworkImageProvider(url);
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!completer.isCompleted) completer.complete(info.image);
        stream.removeListener(listener);
      },
      onError: (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  Future<void> _revert() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revert to original?'),
        content: const Text(
          'This removes every markup layer on this file. The original image '
          'is unchanged. Markup cannot be recovered after reverting.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Revert'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _service.deleteLayer(widget.file.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Revert failed: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  // ─── Render ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // The AppBar sits on a pure-black scaffold, so override the global
    // tooltip theme (near-black bubble) with a high-contrast white bubble —
    // otherwise tooltips like "Rotate 90° left" blend into the AppBar and
    // are unreadable. Icons and Revert text are forced to pure white for
    // the same reason; the global theme paints them in slate-300.
    final tooltipOverride = TooltipThemeData(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      textStyle: const TextStyle(
        color: Color(0xFF111827),
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      preferBelow: true,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Markup'),
        actions: [
          TooltipTheme(
            data: tooltipOverride,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.undo),
                  tooltip: 'Undo',
                  onPressed: _historyIndex == 0 ? null : _undo,
                ),
                IconButton(
                  icon: const Icon(Icons.redo),
                  tooltip: 'Redo',
                  onPressed:
                      _historyIndex >= _history.length - 1 ? null : _redo,
                ),
                IconButton(
                  icon: const Icon(Icons.rotate_90_degrees_ccw),
                  tooltip: 'Rotate 90° left',
                  onPressed: () => setState(() {
                    _rotation = (_rotation + 270) % 360;
                    _dirty = true;
                  }),
                ),
                IconButton(
                  icon: const Icon(Icons.rotate_90_degrees_cw),
                  tooltip: 'Rotate 90° right',
                  onPressed: () => setState(() {
                    _rotation = (_rotation + 90) % 360;
                    _dirty = true;
                  }),
                ),
                IconButton(
                  icon: const Icon(Icons.flip),
                  tooltip: 'Flip horizontal',
                  onPressed: () => setState(() {
                    _flipH = !_flipH;
                    _dirty = true;
                  }),
                ),
                IconButton(
                  icon: Transform.rotate(
                    angle: 1.5708, // 90° so Icons.flip shows vertical mirror
                    child: const Icon(Icons.flip),
                  ),
                  tooltip: 'Flip vertical',
                  onPressed: () => setState(() {
                    _flipV = !_flipV;
                    _dirty = true;
                  }),
                ),
                if (_cropRect.width < 1 || _cropRect.height < 1)
                  IconButton(
                    icon: const Icon(Icons.crop_free),
                    tooltip: 'Reset crop',
                    onPressed: _resetCrop,
                  ),
                IconButton(
                  icon: _exporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_alt),
                  tooltip: 'Save as new file (flattened)',
                  onPressed: _exporting ? null : _saveAsNewFile,
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _revert,
            icon: const Icon(
              Icons.restart_alt,
              color: Colors.white,
              size: 18,
            ),
            label: const Text(
              'Revert',
              style: TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(width: 4),
          ElevatedButton.icon(
            onPressed: _saving || !_dirty ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child:
                        CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check, size: 16),
            label: const Text('Save'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(child: _buildCanvas()),
                _buildToolbar(),
              ],
            ),
    );
  }

  Widget _buildCanvas() {
    // Wrap the image + overlay in an AspectRatio whose ratio matches the
    // natural image dimensions. That way the gesture rect is 1:1 with the
    // image (no letterbox) and normalized coords map directly. Falls back
    // to fit-to-canvas rendering if the image size hasn't resolved yet —
    // the user may draw in that narrow window, and coords will shift once
    // dimensions load. Acceptable; the stream usually resolves in <200ms.
    final imageSize = _imageSize;
    return Center(
      child: imageSize == null
          ? _buildCanvasInner(constraints: null)
          : AspectRatio(
              aspectRatio: imageSize.width / imageSize.height,
              child: _buildCanvasInner(constraints: imageSize),
            ),
    );
  }

  Widget _buildCanvasInner({Size? constraints}) {
    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        _canvasSize = size;

        final transientShapes = <MarkupShape>[];
        if (_drawingPoints != null && _drawingPoints!.length > 1) {
          transientShapes.add(FreeDrawShape(
            id: '__live__',
            color: _color,
            width: _strokeWidth,
            points: _drawingPoints!,
          ));
        }
        if (_arrowFrom != null && _arrowTo != null) {
          transientShapes.add(ArrowShape(
            id: '__live__',
            color: _color,
            width: _strokeWidth,
            from: _arrowFrom!,
            to: _arrowTo!,
          ));
        }
        if (_calloutAnchor != null && _calloutTail != null) {
          transientShapes.add(CalloutShape(
            id: '__live__',
            color: _color,
            anchor: _calloutAnchor!,
            tails: [_calloutTail!],
            text: '',
          ));
        }
        if (_polylinePoints != null && _polylinePoints!.length >= 2) {
          transientShapes.add(PolylineShape(
            id: '__live__',
            color: _color,
            width: _strokeWidth,
            points: _polylinePoints!,
          ));
        }

        // InteractiveViewer wraps the canvas so 2-finger pinch zooms in
        // for precision drawing. When the Pan tool is active, IV claims
        // 1-finger drags too so the user can reposition the zoomed
        // canvas; every other tool leaves panEnabled false so drawing
        // gestures reach the GestureDetector unimpeded.
        // gesture.localPosition stays in child-local coordinates
        // regardless of the IV transform, so normalization by
        // `_canvasSize` keeps working unchanged.
        return InteractiveViewer(
          panEnabled: _tool == _Tool.pan,
          scaleEnabled: true,
          minScale: 1,
          maxScale: 5,
          clipBehavior: Clip.none,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: _onTapDown,
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            child: Stack(
              fit: StackFit.expand,
              children: [
              CachedNetworkImage(
                imageUrl: widget.file.fileUrl,
                // fill is safe because the enclosing AspectRatio already
                // matches the image's natural ratio (see _buildCanvas).
                // When the ratio isn't known yet, we fall back to contain.
                fit: _imageSize == null ? BoxFit.contain : BoxFit.fill,
                errorWidget: (_, __, ___) => const Icon(
                  Icons.broken_image,
                  color: Colors.white,
                  size: 80,
                ),
              ),
              IgnorePointer(
                child: CustomPaint(
                  size: size,
                  painter: MarkupPainter(
                    shapes: [..._shapes, ...transientShapes],
                  ),
                ),
              ),
              if (_selectedShapeId != null)
                IgnorePointer(
                  child: CustomPaint(
                    size: size,
                    painter: _SelectionHighlightPainter(
                      shape: _shapes.firstWhere(
                        (s) => s.id == _selectedShapeId,
                        orElse: () => _shapes.first,
                      ),
                      size: size,
                    ),
                  ),
                ),
              if (_tool == _Tool.crop ||
                  _cropRect.width < 1 ||
                  _cropRect.height < 1)
                IgnorePointer(
                  child: CustomPaint(
                    size: size,
                    painter: _CropOverlayPainter(
                      cropRect: _cropRect,
                      drawHandles: _tool == _Tool.crop,
                    ),
                  ),
                ),
              if (_addingTailFor != null)
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.add_location_alt,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            kIsWeb ? 'Click anywhere on the image to drop the next callout tail' : 'Tap anywhere on the image to drop the next callout tail',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              setState(() => _addingTailFor = null),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_selectedShapeId != null && _addingTailFor == null)
                Positioned(
                  bottom: 12,
                  left: 12,
                  right: 12,
                  child: _buildSelectionToolbar(),
                ),
              if (_polylinePoints != null &&
                  _polylinePoints!.isNotEmpty &&
                  _selectedShapeId == null &&
                  _addingTailFor == null)
                Positioned(
                  bottom: 12,
                  left: 12,
                  right: 12,
                  child: _buildPolylineToolbar(),
                ),
              if (_rotation != 0 || _flipH || _flipV)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    child: Text(
                      _viewTransformLabel(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSelectionToolbar() {
    final shape = _shapes.firstWhere(
      (s) => s.id == _selectedShapeId,
      orElse: () => _shapes.first,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _shapeLabel(shape),
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          const SizedBox(width: 12),
          if (shape is CalloutShape)
            TextButton.icon(
              onPressed: _beginAddingTail,
              icon: const Icon(Icons.add, color: Colors.white, size: 16),
              label: const Text(
                'Add tail',
                style: TextStyle(color: Colors.white),
              ),
            ),
          TextButton.icon(
            onPressed: _deleteSelected,
            icon: const Icon(
              Icons.delete_outline,
              color: Colors.white,
              size: 16,
            ),
            label: const Text(
              'Delete',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  String _viewTransformLabel() {
    final parts = <String>[];
    if (_rotation != 0) parts.add('$_rotation°');
    if (_flipH) parts.add('flipped H');
    if (_flipV) parts.add('flipped V');
    if (_cropRect.width < 1 || _cropRect.height < 1) {
      final wp = (_cropRect.width * 100).round();
      final hp = (_cropRect.height * 100).round();
      parts.add('cropped $wp%×$hp%');
    }
    return 'Viewed as ${parts.join(' · ')}';
  }

  // ─── Crop helpers ──────────────────────────────────────────────────────
  /// Hit-test the user's drag-start point against the 4 corners + body of
  /// the current crop rect. Coords are normalized; handle radius is 0.04
  /// of the shorter canvas side.
  _CropHandle _hitTestCropHandle(Offset p) {
    final r = _cropRect;
    const grab = 0.04;
    bool near(Offset a, Offset b) =>
        (a - b).distanceSquared < grab * grab;
    if (near(p, r.topLeft)) return _CropHandle.topLeft;
    if (near(p, r.topRight)) return _CropHandle.topRight;
    if (near(p, r.bottomLeft)) return _CropHandle.bottomLeft;
    if (near(p, r.bottomRight)) return _CropHandle.bottomRight;
    if (r.contains(p)) return _CropHandle.body;
    return _CropHandle.none;
  }

  void _updateCropFromDrag(Offset current) {
    final start = _cropDragStartRect;
    final startPoint = _cropDragStartPoint;
    if (start == null || startPoint == null) return;
    final dx = current.dx - startPoint.dx;
    final dy = current.dy - startPoint.dy;

    double clamp01(double v) => v.clamp(0.0, 1.0);
    const minSize = 0.05;

    Rect next = start;
    switch (_cropDragHandle) {
      case _CropHandle.body:
        // Translate; clamp so the rect stays inside 0..1.
        final nx = (start.left + dx).clamp(0.0, 1.0 - start.width);
        final ny = (start.top + dy).clamp(0.0, 1.0 - start.height);
        next = Rect.fromLTWH(nx, ny, start.width, start.height);
        break;
      case _CropHandle.topLeft:
        final l = clamp01(start.left + dx).clamp(0.0, start.right - minSize);
        final t = clamp01(start.top + dy).clamp(0.0, start.bottom - minSize);
        next = Rect.fromLTRB(l, t, start.right, start.bottom);
        break;
      case _CropHandle.topRight:
        final r = clamp01(start.right + dx).clamp(start.left + minSize, 1.0);
        final t = clamp01(start.top + dy).clamp(0.0, start.bottom - minSize);
        next = Rect.fromLTRB(start.left, t, r, start.bottom);
        break;
      case _CropHandle.bottomLeft:
        final l = clamp01(start.left + dx).clamp(0.0, start.right - minSize);
        final b = clamp01(start.bottom + dy).clamp(start.top + minSize, 1.0);
        next = Rect.fromLTRB(l, start.top, start.right, b);
        break;
      case _CropHandle.bottomRight:
        final r = clamp01(start.right + dx).clamp(start.left + minSize, 1.0);
        final b = clamp01(start.bottom + dy).clamp(start.top + minSize, 1.0);
        next = Rect.fromLTRB(start.left, start.top, r, b);
        break;
      case _CropHandle.none:
        return;
    }
    setState(() => _cropRect = next);
  }

  void _resetCrop() {
    setState(() {
      _cropRect = const Rect.fromLTWH(0, 0, 1, 1);
      _dirty = true;
    });
  }

  Widget _buildPolylineToolbar() {
    final count = _polylinePoints?.length ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Polyline: $count point${count == 1 ? '' : 's'}',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: count >= 2 ? _finishPolyline : null,
            icon: const Icon(Icons.check, color: Colors.white, size: 16),
            label: const Text(
              'Finish',
              style: TextStyle(color: Colors.white),
            ),
          ),
          TextButton.icon(
            onPressed: () => setState(() => _polylinePoints = null),
            icon:
                const Icon(Icons.close, color: Colors.white70, size: 16),
            label: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  String _shapeLabel(MarkupShape shape) {
    switch (shape) {
      case FreeDrawShape():
        return 'Drawing';
      case ArrowShape():
        return 'Arrow';
      case PolylineShape():
        return 'Polyline';
      case CalloutShape():
        return shape.isMultiArrow
            ? 'Callout (${shape.tails.length} arrows)'
            : 'Callout';
      case TextShape():
        return 'Text';
      case TimestampShape():
        return 'Timestamp';
    }
  }

  Widget _buildToolbar() {
    return Material(
      color: AppColors.sidebarBg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          children: [
            _ToolButton(
              icon: Icons.draw,
              label: 'Draw',
              active: _tool == _Tool.freeDraw,
              onTap: () => _selectTool(_Tool.freeDraw),
            ),
            _ToolButton(
              icon: Icons.arrow_upward,
              label: 'Arrow',
              active: _tool == _Tool.arrow,
              onTap: () => _selectTool(_Tool.arrow),
            ),
            _ToolButton(
              icon: Icons.title,
              label: 'Text',
              active: _tool == _Tool.text,
              onTap: () => _selectTool(_Tool.text),
            ),
            _ToolButton(
              icon: Icons.comment,
              label: 'Callout',
              active: _tool == _Tool.callout,
              onTap: () => _selectTool(_Tool.callout),
            ),
            _ToolButton(
              icon: Icons.timeline,
              label: 'Polyline',
              active: _tool == _Tool.polyline,
              onTap: () => _selectTool(_Tool.polyline),
            ),
            _ToolButton(
              icon: Icons.schedule,
              label: 'Stamp',
              active: _tool == _Tool.timestamp,
              onTap: () => _selectTool(_Tool.timestamp),
            ),
            _ToolButton(
              icon: Icons.crop,
              label: 'Crop',
              active: _tool == _Tool.crop,
              onTap: () => _selectTool(_Tool.crop),
            ),
            _ToolButton(
              icon: Icons.pan_tool_alt,
              label: 'Select',
              active: _tool == _Tool.select,
              onTap: () => _selectTool(_Tool.select),
            ),
            _ToolButton(
              icon: Icons.open_with,
              label: 'Pan',
              active: _tool == _Tool.pan,
              onTap: () => _selectTool(_Tool.pan),
            ),
            const VerticalDivider(color: Colors.white24, indent: 6, endIndent: 6),
            ..._palette.map((hex) {
              final selected = hex.toLowerCase() == _color.toLowerCase();
              return GestureDetector(
                onTap: () => setState(() => _color = hex),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: _hexToColor(hex),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? Colors.white : Colors.white24,
                      width: selected ? 3 : 1,
                    ),
                  ),
                ),
              );
            }),
            const Spacer(),
            Text(
              'Width',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11),
            ),
            SizedBox(
              width: 140,
              child: Slider(
                min: 1,
                max: 12,
                divisions: 11,
                value: _strokeWidth,
                label: _strokeWidth.round().toString(),
                onChanged: (v) => setState(() => _strokeWidth = v),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _hexToColor(String hex) {
    var v = hex.replaceAll('#', '');
    if (v.length == 6) v = 'FF$v';
    return Color(int.parse(v, radix: 16));
  }
}

/// Paints a subtle bounding-box halo around the selected shape so the user
/// knows what the floating toolbar's actions will affect. Shape-type aware
/// so a callout shows its bubble + every tail endpoint.
class _SelectionHighlightPainter extends CustomPainter {
  final MarkupShape shape;
  final Size size;

  _SelectionHighlightPainter({required this.shape, required this.size});

  Offset _den(Offset n) => Offset(n.dx * size.width, n.dy * size.height);

  @override
  void paint(Canvas canvas, Size s) {
    final paint = Paint()
      ..color = Colors.yellow.withValues(alpha: 0.85)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    Rect? rect;
    switch (shape) {
      case FreeDrawShape(:final points):
      case PolylineShape(:final points):
        rect = _boundsOf(points);
        break;
      case ArrowShape(:final from, :final to):
        rect = _boundsOf([from, to]);
        break;
      case CalloutShape():
        final s = shape as CalloutShape;
        final pts = [s.anchor, ...s.tails];
        rect = _boundsOf(pts);
        // Also ring each tail point so multi-arrow calloutss show what's
        // selectable when the user taps "Add tail".
        for (final tail in s.tails) {
          canvas.drawCircle(_den(tail), 6, paint);
        }
        canvas.drawCircle(_den(s.anchor), 8, paint);
        break;
      case TextShape(:final at):
      case TimestampShape(:final at):
        final p = _den(at);
        canvas.drawRect(
          Rect.fromCenter(center: p, width: 60, height: 28),
          paint,
        );
        return;
    }

    if (rect != null) {
      final denormRect = Rect.fromLTRB(
        rect.left * size.width - 6,
        rect.top * size.height - 6,
        rect.right * size.width + 6,
        rect.bottom * size.height + 6,
      );
      final rr = RRect.fromRectAndRadius(denormRect, const Radius.circular(6));
      canvas.drawRRect(rr, paint);
    }
  }

  Rect? _boundsOf(List<Offset> points) {
    if (points.isEmpty) return null;
    var minX = points.first.dx;
    var minY = points.first.dy;
    var maxX = minX;
    var maxY = minY;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  @override
  bool shouldRepaint(covariant _SelectionHighlightPainter oldDelegate) =>
      oldDelegate.shape != shape || oldDelegate.size != size;
}

/// Draws the crop rectangle over the editor canvas with corner handles.
/// Pixels outside the rect get a dark scrim so the user can tell the kept
/// vs. discarded regions apart without rendering the real crop (the
/// editor always shows the full image so drawing anywhere is still
/// possible; the viewer is what actually applies the crop).
class _CropOverlayPainter extends CustomPainter {
  final Rect cropRect; // normalized
  final bool drawHandles;

  const _CropOverlayPainter({
    required this.cropRect,
    required this.drawHandles,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final pxRect = Rect.fromLTWH(
      cropRect.left * size.width,
      cropRect.top * size.height,
      cropRect.width * size.width,
      cropRect.height * size.height,
    );

    // Scrim outside the crop rect.
    final scrim = Paint()..color = Colors.black.withValues(alpha: 0.4);
    final full = Rect.fromLTWH(0, 0, size.width, size.height);
    final outside = Path()
      ..addRect(full)
      ..addRect(pxRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(outside, scrim);

    // Dashed border around the crop rect.
    final border = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    _drawDashedRect(canvas, pxRect, border);

    if (!drawHandles) return;

    // Corner handles: small white-filled squares with a black outline.
    final handleFill = Paint()..color = Colors.white;
    final handleStroke = Paint()
      ..color = Colors.black
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const handleSize = 12.0;
    for (final corner in [
      pxRect.topLeft,
      pxRect.topRight,
      pxRect.bottomLeft,
      pxRect.bottomRight,
    ]) {
      final r = Rect.fromCenter(
        center: corner,
        width: handleSize,
        height: handleSize,
      );
      canvas.drawRect(r, handleFill);
      canvas.drawRect(r, handleStroke);
    }
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    const dashLen = 6.0;
    const gap = 4.0;
    void dashedLine(Offset a, Offset b) {
      final total = (b - a).distance;
      if (total == 0) return;
      final dir = (b - a) / total;
      var drawn = 0.0;
      while (drawn < total) {
        final segEnd = drawn + dashLen;
        final s = a + dir * drawn;
        final e = a + dir * (segEnd.clamp(0, total));
        canvas.drawLine(s, e, paint);
        drawn = segEnd + gap;
      }
    }

    dashedLine(rect.topLeft, rect.topRight);
    dashedLine(rect.topRight, rect.bottomRight);
    dashedLine(rect.bottomRight, rect.bottomLeft);
    dashedLine(rect.bottomLeft, rect.topLeft);
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) =>
      oldDelegate.cropRect != cropRect ||
      oldDelegate.drawHandles != drawHandles;
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(
        icon,
        color: active ? AppColors.secondary : Colors.white,
        size: 18,
      ),
      label: Text(
        label,
        style: TextStyle(
          color: active ? AppColors.secondary : Colors.white,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          fontSize: 12,
        ),
      ),
    );
  }
}

