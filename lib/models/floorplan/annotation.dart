import 'dart:ui' show Offset;

/// Free-form markup that lives in the planner's own coordinate system,
/// distinct from the per-file `MarkupShape` system in `lib/models/file_markup.dart`.
///
/// v1 supports three kinds: text label, arrow, dimension line. The kind is
/// the discriminator on JSON round-trip.
sealed class Annotation {
  final String id;
  final String color;

  const Annotation({required this.id, required this.color});

  String get kind;

  Map<String, dynamic> toJson();

  static Annotation fromJson(Map<String, dynamic> json) {
    final kind = json['kind'] as String;
    final id = json['id'] as String;
    final color = json['color'] as String? ?? '#222222';
    switch (kind) {
      case 'text':
        return TextAnnotation(
          id: id,
          color: color,
          x: (json['x'] as num).toDouble(),
          y: (json['y'] as num).toDouble(),
          text: json['text'] as String? ?? '',
          fontSize: (json['fontSize'] as num?)?.toDouble() ?? 14,
          rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
        );
      case 'arrow':
        return ArrowAnnotation(
          id: id,
          color: color,
          fromX: (json['fromX'] as num).toDouble(),
          fromY: (json['fromY'] as num).toDouble(),
          toX: (json['toX'] as num).toDouble(),
          toY: (json['toY'] as num).toDouble(),
          width: (json['width'] as num?)?.toDouble() ?? 2,
        );
      case 'dimension':
        return DimensionAnnotation(
          id: id,
          color: color,
          fromX: (json['fromX'] as num).toDouble(),
          fromY: (json['fromY'] as num).toDouble(),
          toX: (json['toX'] as num).toDouble(),
          toY: (json['toY'] as num).toDouble(),
          offset: (json['offset'] as num?)?.toDouble() ?? 30,
          unit: json['unit'] as String? ?? 'cm',
        );
    }
    throw FormatException('Unknown annotation kind: $kind');
  }
}

class TextAnnotation extends Annotation {
  final double x;
  final double y;
  final String text;
  final double fontSize;
  final double rotation;

  const TextAnnotation({
    required super.id,
    required super.color,
    required this.x,
    required this.y,
    required this.text,
    this.fontSize = 14,
    this.rotation = 0,
  });

  Offset get offset => Offset(x, y);

  @override
  String get kind => 'text';

  TextAnnotation copyWith({
    double? x,
    double? y,
    String? text,
    String? color,
    double? fontSize,
    double? rotation,
  }) =>
      TextAnnotation(
        id: id,
        color: color ?? this.color,
        x: x ?? this.x,
        y: y ?? this.y,
        text: text ?? this.text,
        fontSize: fontSize ?? this.fontSize,
        rotation: rotation ?? this.rotation,
      );

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'color': color,
        'x': x,
        'y': y,
        'text': text,
        'fontSize': fontSize,
        'rotation': rotation,
      };
}

class ArrowAnnotation extends Annotation {
  final double fromX;
  final double fromY;
  final double toX;
  final double toY;
  final double width;

  const ArrowAnnotation({
    required super.id,
    required super.color,
    required this.fromX,
    required this.fromY,
    required this.toX,
    required this.toY,
    this.width = 2,
  });

  Offset get from => Offset(fromX, fromY);
  Offset get to => Offset(toX, toY);

  @override
  String get kind => 'arrow';

  ArrowAnnotation copyWith({
    double? fromX,
    double? fromY,
    double? toX,
    double? toY,
    String? color,
    double? width,
  }) =>
      ArrowAnnotation(
        id: id,
        color: color ?? this.color,
        fromX: fromX ?? this.fromX,
        fromY: fromY ?? this.fromY,
        toX: toX ?? this.toX,
        toY: toY ?? this.toY,
        width: width ?? this.width,
      );

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'color': color,
        'fromX': fromX,
        'fromY': fromY,
        'toX': toX,
        'toY': toY,
        'width': width,
      };
}

class DimensionAnnotation extends Annotation {
  final double fromX;
  final double fromY;
  final double toX;
  final double toY;
  final double offset; // perpendicular offset of the dimension line
  final String unit;

  const DimensionAnnotation({
    required super.id,
    required super.color,
    required this.fromX,
    required this.fromY,
    required this.toX,
    required this.toY,
    this.offset = 30,
    this.unit = 'cm',
  });

  Offset get from => Offset(fromX, fromY);
  Offset get to => Offset(toX, toY);

  @override
  String get kind => 'dimension';

  DimensionAnnotation copyWith({
    double? fromX,
    double? fromY,
    double? toX,
    double? toY,
    double? offset,
    String? color,
    String? unit,
  }) =>
      DimensionAnnotation(
        id: id,
        color: color ?? this.color,
        fromX: fromX ?? this.fromX,
        fromY: fromY ?? this.fromY,
        toX: toX ?? this.toX,
        toY: toY ?? this.toY,
        offset: offset ?? this.offset,
        unit: unit ?? this.unit,
      );

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'color': color,
        'fromX': fromX,
        'fromY': fromY,
        'toX': toX,
        'toY': toY,
        'offset': offset,
        'unit': unit,
      };
}
