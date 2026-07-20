/// A door, window, or other opening that rides along a wall.
///
/// [offset] is a normalized position in `[0, 1]` along [lineId]; when the
/// host wall is split, offsets get rescaled (see
/// `services/floorplan/class/wall.dart` `splitWall`). [width] is in scene
/// units along the wall axis.
class Hole {
  final String id;
  final String prototype; // 'door' | 'window'
  final String lineId;
  final double offset;
  final double width;
  final double height;
  final double altitude; // floor offset, used by future 3D viewer
  final Map<String, dynamic> properties;

  const Hole({
    required this.id,
    required this.prototype,
    required this.lineId,
    required this.offset,
    this.width = 80.0,
    this.height = 200.0,
    this.altitude = 0.0,
    this.properties = const {},
  });

  Hole copyWith({
    String? lineId,
    double? offset,
    double? width,
    double? height,
    double? altitude,
    Map<String, dynamic>? properties,
  }) =>
      Hole(
        id: id,
        prototype: prototype,
        lineId: lineId ?? this.lineId,
        offset: offset ?? this.offset,
        width: width ?? this.width,
        height: height ?? this.height,
        altitude: altitude ?? this.altitude,
        properties: properties ?? this.properties,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'prototype': prototype,
        'lineId': lineId,
        'offset': offset,
        'width': width,
        'height': height,
        'altitude': altitude,
        'properties': properties,
      };

  factory Hole.fromJson(Map<String, dynamic> json) => Hole(
        id: json['id'] as String,
        prototype: json['prototype'] as String,
        lineId: json['lineId'] as String,
        offset: (json['offset'] as num).toDouble(),
        width: (json['width'] as num?)?.toDouble() ?? 80.0,
        height: (json['height'] as num?)?.toDouble() ?? 200.0,
        altitude: (json['altitude'] as num?)?.toDouble() ?? 0.0,
        properties:
            ((json['properties'] as Map?) ?? const {}).cast<String, dynamic>(),
      );
}
