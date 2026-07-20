import 'dart:ui' show Offset;

/// A point-placed element with rotation: furniture, fixtures, equipment.
class Item {
  final String id;
  final String prototype; // catalog key, e.g. 'sofa', 'sink'
  final double x;
  final double y;
  final double rotation; // radians, clockwise from positive X
  final double width;
  final double height;
  final Map<String, dynamic> properties;

  const Item({
    required this.id,
    required this.prototype,
    required this.x,
    required this.y,
    this.rotation = 0,
    this.width = 100,
    this.height = 100,
    this.properties = const {},
  });

  Offset get offset => Offset(x, y);

  Item copyWith({
    double? x,
    double? y,
    double? rotation,
    double? width,
    double? height,
    Map<String, dynamic>? properties,
  }) =>
      Item(
        id: id,
        prototype: prototype,
        x: x ?? this.x,
        y: y ?? this.y,
        rotation: rotation ?? this.rotation,
        width: width ?? this.width,
        height: height ?? this.height,
        properties: properties ?? this.properties,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'prototype': prototype,
        'x': x,
        'y': y,
        'rotation': rotation,
        'width': width,
        'height': height,
        'properties': properties,
      };

  factory Item.fromJson(Map<String, dynamic> json) => Item(
        id: json['id'] as String,
        prototype: json['prototype'] as String,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
        width: (json['width'] as num?)?.toDouble() ?? 100,
        height: (json['height'] as num?)?.toDouble() ?? 100,
        properties:
            ((json['properties'] as Map?) ?? const {}).cast<String, dynamic>(),
      );
}
