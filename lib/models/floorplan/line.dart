/// A wall (or other linear element) connecting two vertices.
///
/// [vertexIds] always has length 2 in canonical order — the order is stable
/// so hole offsets (`Hole.offset`, 0..1) remain meaningful when walls are
/// looked up later.
class FloorLine {
  final String id;
  final String prototype; // 'wall' for v1
  final List<String> vertexIds;
  final List<String> holeIds;
  final double thickness;

  /// Optional per-wall height override in scene units (cm). `null` means
  /// "use the scene's [Scene.ceilingHeightCm] default". A non-null value
  /// is the wall's own height — used by the 3D preview for stepped
  /// ceilings, half-walls, and partial partitions.
  ///
  /// Old scenes saved before this field existed deserialize to `null`.
  final double? heightCm;

  final Map<String, dynamic> properties;

  const FloorLine({
    required this.id,
    this.prototype = 'wall',
    required this.vertexIds,
    this.holeIds = const [],
    this.thickness = 20.0,
    this.heightCm,
    this.properties = const {},
  });

  /// Resolve the wall's effective height. Pass the owning scene's
  /// [Scene.ceilingHeightCm]; returns the per-wall override when present
  /// or the scene default otherwise.
  double effectiveHeightCm(double sceneCeilingHeightCm) =>
      heightCm ?? sceneCeilingHeightCm;

  FloorLine copyWith({
    String? prototype,
    List<String>? vertexIds,
    List<String>? holeIds,
    double? thickness,
    double? heightCm,
    bool clearHeight = false,
    Map<String, dynamic>? properties,
  }) =>
      FloorLine(
        id: id,
        prototype: prototype ?? this.prototype,
        vertexIds: vertexIds ?? this.vertexIds,
        holeIds: holeIds ?? this.holeIds,
        thickness: thickness ?? this.thickness,
        heightCm: clearHeight ? null : (heightCm ?? this.heightCm),
        properties: properties ?? this.properties,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'prototype': prototype,
        'vertexIds': vertexIds,
        'holeIds': holeIds,
        'thickness': thickness,
        if (heightCm != null) 'heightCm': heightCm,
        'properties': properties,
      };

  factory FloorLine.fromJson(Map<String, dynamic> json) => FloorLine(
        id: json['id'] as String,
        prototype: json['prototype'] as String? ?? 'wall',
        vertexIds: (json['vertexIds'] as List).cast<String>(),
        holeIds: ((json['holeIds'] as List?) ?? const []).cast<String>(),
        thickness: (json['thickness'] as num?)?.toDouble() ?? 20.0,
        heightCm: (json['heightCm'] as num?)?.toDouble(),
        properties:
            ((json['properties'] as Map?) ?? const {}).cast<String, dynamic>(),
      );
}
