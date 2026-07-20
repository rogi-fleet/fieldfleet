/// A room or other closed polygonal region.
///
/// Areas are **derived** from closed wall loops (see
/// `utils/floorplan/graph_cycles.dart` in Phase 2), not authored. The vertex
/// list is in CCW order ready for `Path.moveTo` rendering.
class Area {
  final String id;
  final String prototype; // 'area' for v1
  final List<String> vertexIds;
  final String fillColor;
  final Map<String, dynamic> properties;

  const Area({
    required this.id,
    this.prototype = 'area',
    required this.vertexIds,
    this.fillColor = '#E0E0E033',
    this.properties = const {},
  });

  Area copyWith({
    List<String>? vertexIds,
    String? fillColor,
    Map<String, dynamic>? properties,
  }) =>
      Area(
        id: id,
        prototype: prototype,
        vertexIds: vertexIds ?? this.vertexIds,
        fillColor: fillColor ?? this.fillColor,
        properties: properties ?? this.properties,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'prototype': prototype,
        'vertexIds': vertexIds,
        'fillColor': fillColor,
        'properties': properties,
      };

  factory Area.fromJson(Map<String, dynamic> json) => Area(
        id: json['id'] as String,
        prototype: json['prototype'] as String? ?? 'area',
        vertexIds: (json['vertexIds'] as List).cast<String>(),
        fillColor: json['fillColor'] as String? ?? '#E0E0E033',
        properties:
            ((json['properties'] as Map?) ?? const {}).cast<String, dynamic>(),
      );
}
