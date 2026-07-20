import 'dart:ui' show Offset;

/// A point in the floorplan graph.
///
/// Vertices are shared between walls — moving a vertex moves every wall and
/// area incident to it. The [lineIds] / [areaIds] back-references are
/// denormalized for cheap traversal; **all updates must go through the
/// `Vertex.add*` / `Vertex.remove*` helpers** (in `services/floorplan/class/`)
/// to keep them in sync.
class Vertex {
  final String id;
  final double x;
  final double y;
  final Set<String> lineIds;
  final Set<String> areaIds;

  const Vertex({
    required this.id,
    required this.x,
    required this.y,
    this.lineIds = const {},
    this.areaIds = const {},
  });

  Offset get offset => Offset(x, y);

  Vertex copyWith({
    double? x,
    double? y,
    Set<String>? lineIds,
    Set<String>? areaIds,
  }) =>
      Vertex(
        id: id,
        x: x ?? this.x,
        y: y ?? this.y,
        lineIds: lineIds ?? this.lineIds,
        areaIds: areaIds ?? this.areaIds,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': x,
        'y': y,
        'lineIds': lineIds.toList(),
        'areaIds': areaIds.toList(),
      };

  factory Vertex.fromJson(Map<String, dynamic> json) => Vertex(
        id: json['id'] as String,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        lineIds: ((json['lineIds'] as List?) ?? const [])
            .cast<String>()
            .toSet(),
        areaIds: ((json['areaIds'] as List?) ?? const [])
            .cast<String>()
            .toSet(),
      );
}
