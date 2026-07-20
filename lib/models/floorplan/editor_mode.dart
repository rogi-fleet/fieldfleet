import 'dart:ui' show Offset;

/// Sealed enumeration of editor modes — what the next pointer event means.
///
/// Mirrors react-planner's flat `MODE_*` enum but keeps in-progress payloads
/// (which line is being drawn, which vertex is being dragged) inline on the
/// mode itself, so no separate `drawingSupport` Map is needed.
sealed class EditorMode {
  const EditorMode();
}

class IdleMode extends EditorMode {
  const IdleMode();
}

class PanMode extends EditorMode {
  const PanMode();
}

class SelectMode extends EditorMode {
  const SelectMode();
}

class WaitingDrawingWallMode extends EditorMode {
  const WaitingDrawingWallMode();
}

class DrawingWallMode extends EditorMode {
  /// In-flight wall the next mouse-up will commit, plus its start vertex id.
  final String pendingLineId;
  final String startVertexId;
  final String endVertexId;

  const DrawingWallMode({
    required this.pendingLineId,
    required this.startVertexId,
    required this.endVertexId,
  });
}

class DraggingVertexMode extends EditorMode {
  final String vertexId;
  final double startX;
  final double startY;

  const DraggingVertexMode({
    required this.vertexId,
    required this.startX,
    required this.startY,
  });
}

class DraggingLineMode extends EditorMode {
  final String lineId;
  final double startX;
  final double startY;

  const DraggingLineMode({
    required this.lineId,
    required this.startX,
    required this.startY,
  });
}

class WaitingDrawingHoleMode extends EditorMode {
  /// Door or window prototype the user picked from the catalog.
  final String holePrototype;

  const WaitingDrawingHoleMode({required this.holePrototype});
}

class DrawingHoleMode extends EditorMode {
  final String pendingHoleId;
  final String holePrototype;

  const DrawingHoleMode({
    required this.pendingHoleId,
    required this.holePrototype,
  });
}

class PlacingItemMode extends EditorMode {
  final String itemPrototype;

  const PlacingItemMode({required this.itemPrototype});
}

class DraggingItemMode extends EditorMode {
  final String itemId;
  final double startX;
  final double startY;

  const DraggingItemMode({
    required this.itemId,
    required this.startX,
    required this.startY,
  });
}

class RotatingItemMode extends EditorMode {
  final String itemId;
  final double startAngle;

  const RotatingItemMode({required this.itemId, required this.startAngle});
}

class AddingAnnotationMode extends EditorMode {
  /// `'text' | 'arrow' | 'dimension'`.
  final String annotationKind;

  const AddingAnnotationMode({required this.annotationKind});
}

/// Drag-to-define-rectangle room. Pointer-down sets [start]; updates
/// to [current] every move; pointer-up commits a 4-wall room.
class DrawingRectangleRoomMode extends EditorMode {
  final Offset? start;
  final Offset? current;

  const DrawingRectangleRoomMode({this.start, this.current});
}

/// Click-to-add-vertex polygon room. Cursor preview shows the next
/// segment; auto-closes when the next click would land within snap
/// distance of the first vertex.
class TracingRoomMode extends EditorMode {
  final List<Offset> points;

  const TracingRoomMode({this.points = const []});
}

/// Two-click calibration flow. First click sets [first]; second click
/// sets [second]; the calibration dialog reads both, asks for the
/// real-world distance, and applies the scale.
class CalibratingMode extends EditorMode {
  final Offset? first;
  final Offset? second;

  const CalibratingMode({this.first, this.second});
}
