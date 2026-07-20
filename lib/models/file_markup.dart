import 'dart:convert';
import 'dart:ui' show Offset, Rect;

/// One vector shape in a [MarkupLayer].
///
/// Coordinates are stored in **normalized** space (each component in 0..1)
/// so the markup renders correctly regardless of viewport size or rotation.
/// Subclasses are serialized by their `type` tag into the `shapes` JSONB
/// column on `file_markup_layers`.
sealed class MarkupShape {
  final String id;
  final String color; // hex, e.g. '#FF5722'

  const MarkupShape({required this.id, required this.color});

  String get type;

  Map<String, dynamic> toJson();

  static MarkupShape fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    final id = json['id'] as String;
    final color = json['color'] as String? ?? '#FF5722';
    switch (type) {
      case 'free_draw':
        return FreeDrawShape(
          id: id,
          color: color,
          width: (json['width'] as num?)?.toDouble() ?? 3.0,
          points: _pointsFromJson(json['points']),
        );
      case 'arrow':
        return ArrowShape(
          id: id,
          color: color,
          width: (json['width'] as num?)?.toDouble() ?? 3.0,
          from: _pointFromJson(json['from']),
          to: _pointFromJson(json['to']),
        );
      case 'callout':
        return CalloutShape(
          id: id,
          color: color,
          fontSize: (json['fontSize'] as num?)?.toDouble() ?? 14.0,
          anchor: _pointFromJson(json['anchor']),
          tails: _pointsFromJson(json['tails']),
          text: json['text'] as String? ?? '',
        );
      case 'polyline':
        return PolylineShape(
          id: id,
          color: color,
          width: (json['width'] as num?)?.toDouble() ?? 3.0,
          points: _pointsFromJson(json['points']),
        );
      case 'text':
        return TextShape(
          id: id,
          color: color,
          fontSize: (json['fontSize'] as num?)?.toDouble() ?? 18.0,
          at: _pointFromJson(json['at']),
          text: json['text'] as String? ?? '',
        );
      case 'timestamp':
        return TimestampShape(
          id: id,
          color: color,
          at: _pointFromJson(json['at']),
          capturedAt: DateTime.parse(json['captured_at'] as String),
        );
      default:
        // Forward-compat: unknown types are dropped so newer server-side
        // shapes don't break older clients. Returning null and filtering
        // would be cleaner but requires the caller to filter; keeping this
        // as a recoverable free-draw stub would be worse. Throw — callers
        // already catch during JSON decode.
        throw FormatException('Unknown markup shape type: $type');
    }
  }

  static Offset _pointFromJson(dynamic raw) {
    final list = (raw as List).cast<num>();
    return Offset(list[0].toDouble(), list[1].toDouble());
  }

  static List<Offset> _pointsFromJson(dynamic raw) {
    return (raw as List? ?? const [])
        .map((p) => _pointFromJson(p))
        .toList();
  }

  static List<List<double>> _pointsToJson(List<Offset> pts) =>
      pts.map((p) => [p.dx, p.dy]).toList();
}

class FreeDrawShape extends MarkupShape {
  final List<Offset> points;
  final double width;

  const FreeDrawShape({
    required super.id,
    required super.color,
    required this.points,
    this.width = 3.0,
  });

  @override
  String get type => 'free_draw';

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'color': color,
        'width': width,
        'points': MarkupShape._pointsToJson(points),
      };
}

class ArrowShape extends MarkupShape {
  final Offset from;
  final Offset to;
  final double width;

  const ArrowShape({
    required super.id,
    required super.color,
    required this.from,
    required this.to,
    this.width = 3.0,
  });

  @override
  String get type => 'arrow';

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'color': color,
        'width': width,
        'from': [from.dx, from.dy],
        'to': [to.dx, to.dy],
      };
}

class CalloutShape extends MarkupShape {
  final Offset anchor;
  final List<Offset> tails;
  final String text;
  final double fontSize;

  const CalloutShape({
    required super.id,
    required super.color,
    required this.anchor,
    required this.tails,
    required this.text,
    this.fontSize = 14.0,
  });

  /// True when the callout fans multiple arrows from one anchor — the
  /// customer's heavy-use "multi-arrow callout" is just a [CalloutShape]
  /// with `tails.length > 1`.
  bool get isMultiArrow => tails.length > 1;

  @override
  String get type => 'callout';

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'color': color,
        'fontSize': fontSize,
        'anchor': [anchor.dx, anchor.dy],
        'tails': MarkupShape._pointsToJson(tails),
        'text': text,
      };
}

class PolylineShape extends MarkupShape {
  final List<Offset> points;
  final double width;

  const PolylineShape({
    required super.id,
    required super.color,
    required this.points,
    this.width = 3.0,
  });

  @override
  String get type => 'polyline';

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'color': color,
        'width': width,
        'points': MarkupShape._pointsToJson(points),
      };
}

class TextShape extends MarkupShape {
  final Offset at;
  final String text;
  final double fontSize;

  const TextShape({
    required super.id,
    required super.color,
    required this.at,
    required this.text,
    this.fontSize = 18.0,
  });

  @override
  String get type => 'text';

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'color': color,
        'fontSize': fontSize,
        'at': [at.dx, at.dy],
        'text': text,
      };
}

class TimestampShape extends MarkupShape {
  final Offset at;
  final DateTime capturedAt;

  const TimestampShape({
    required super.id,
    required super.color,
    required this.at,
    required this.capturedAt,
  });

  @override
  String get type => 'timestamp';

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'color': color,
        'at': [at.dx, at.dy],
        'captured_at': capturedAt.toIso8601String(),
      };
}

/// Full markup layer for a file. Immutable — editor state holds a history
/// stack of these and upserts the head on save.
class MarkupLayer {
  final String id;
  final String workspaceId;
  final String fileAttachmentId;
  final List<MarkupShape> shapes;

  /// Quarter-turn view rotation (0, 90, 180, or 270). The viewer applies
  /// this transform on top of the original image bytes, which stay
  /// untouched — reverting the layer clears the rotation.
  final int rotation;

  /// Non-destructive horizontal / vertical flip. Same viewer-only model
  /// as [rotation] — the image bytes themselves are never mirrored.
  final bool flipHorizontal;
  final bool flipVertical;

  /// Normalized crop rect (0..1 of the original image). `Rect.fromLTWH(0,0,1,1)`
  /// means "no crop — show the whole image." Anything else clips the viewer
  /// display to that sub-region. Shapes keep image-native coords; shapes
  /// outside the crop simply render outside the viewer's clip.
  final Rect cropRect;

  bool get hasCrop =>
      cropRect.left > 0 ||
      cropRect.top > 0 ||
      cropRect.width < 1 ||
      cropRect.height < 1;

  final String? authorId;
  final DateTime updatedAt;
  final DateTime createdAt;

  const MarkupLayer({
    required this.id,
    required this.workspaceId,
    required this.fileAttachmentId,
    required this.shapes,
    this.rotation = 0,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.cropRect = const Rect.fromLTWH(0, 0, 1, 1),
    this.authorId,
    required this.updatedAt,
    required this.createdAt,
  });

  MarkupLayer copyWith({
    List<MarkupShape>? shapes,
    int? rotation,
    bool? flipHorizontal,
    bool? flipVertical,
    Rect? cropRect,
  }) =>
      MarkupLayer(
        id: id,
        workspaceId: workspaceId,
        fileAttachmentId: fileAttachmentId,
        shapes: shapes ?? this.shapes,
        rotation: rotation ?? this.rotation,
        flipHorizontal: flipHorizontal ?? this.flipHorizontal,
        flipVertical: flipVertical ?? this.flipVertical,
        cropRect: cropRect ?? this.cropRect,
        authorId: authorId,
        updatedAt: updatedAt,
        createdAt: createdAt,
      );

  factory MarkupLayer.fromSupabase(Map<String, dynamic> json) {
    final raw = json['shapes'];
    final shapes = raw is String
        ? (jsonDecode(raw) as List)
            .cast<Map<String, dynamic>>()
            .map(MarkupShape.fromJson)
            .toList()
        : (raw as List)
            .cast<Map<String, dynamic>>()
            .map(MarkupShape.fromJson)
            .toList();
    final cropX = (json['crop_x'] as num?)?.toDouble() ?? 0;
    final cropY = (json['crop_y'] as num?)?.toDouble() ?? 0;
    final cropW = (json['crop_width'] as num?)?.toDouble() ?? 1;
    final cropH = (json['crop_height'] as num?)?.toDouble() ?? 1;
    return MarkupLayer(
      id: json['id'] as String,
      workspaceId: json['workspace_id'] as String,
      fileAttachmentId: json['file_attachment_id'] as String,
      shapes: shapes,
      rotation: (json['rotation'] as num?)?.toInt() ?? 0,
      flipHorizontal: json['flip_horizontal'] as bool? ?? false,
      flipVertical: json['flip_vertical'] as bool? ?? false,
      cropRect: Rect.fromLTWH(cropX, cropY, cropW, cropH),
      authorId: json['author_id'] as String?,
      updatedAt: DateTime.parse(json['updated_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
