import 'background_pdf.dart';
import 'layer.dart';

/// Root document of a 2D planner scene.
///
/// All measurements are in [unit] (default `cm`). [width] and [height] are
/// the canvas extents in the same unit; [gridSize] is the snap step.
///
/// One scene contains many [Layer]s, but for v1 the editor only exposes a
/// single layer (`selectedLayerId == default layer`).
class Scene {
  final String id;
  final String name;
  final String unit;
  final double width;
  final double height;
  final double gridSize;

  /// Default ceiling height in scene units (cm). Walls without an explicit
  /// per-wall override extrude to this height in the 3D preview and use it
  /// for any cubic-volume calculations. 240 cm is the residential default.
  ///
  /// Old scenes saved before this field existed deserialize to this default.
  final double ceilingHeightCm;

  final String selectedLayerId;
  final Map<String, Layer> layers;
  final BackgroundPdf? background;

  const Scene({
    required this.id,
    this.name = 'Untitled Floorplan',
    this.unit = 'cm',
    this.width = 2000,
    this.height = 2000,
    this.gridSize = 20,
    this.ceilingHeightCm = 240,
    required this.selectedLayerId,
    required this.layers,
    this.background,
  });

  Layer get selectedLayer => layers[selectedLayerId]!;

  Scene copyWith({
    String? name,
    String? unit,
    double? width,
    double? height,
    double? gridSize,
    double? ceilingHeightCm,
    String? selectedLayerId,
    Map<String, Layer>? layers,
    BackgroundPdf? background,
    bool clearBackground = false,
  }) =>
      Scene(
        id: id,
        name: name ?? this.name,
        unit: unit ?? this.unit,
        width: width ?? this.width,
        height: height ?? this.height,
        gridSize: gridSize ?? this.gridSize,
        ceilingHeightCm: ceilingHeightCm ?? this.ceilingHeightCm,
        selectedLayerId: selectedLayerId ?? this.selectedLayerId,
        layers: layers ?? this.layers,
        background: clearBackground ? null : (background ?? this.background),
      );

  /// Replace the currently-selected layer.
  Scene withSelectedLayer(Layer layer) {
    final next = Map<String, Layer>.from(layers);
    next[layer.id] = layer;
    return copyWith(layers: next);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'unit': unit,
        'width': width,
        'height': height,
        'gridSize': gridSize,
        'ceilingHeightCm': ceilingHeightCm,
        'selectedLayerId': selectedLayerId,
        'layers': layers.map((k, v) => MapEntry(k, v.toJson())),
        if (background != null) 'background': background!.toJson(),
      };

  factory Scene.fromJson(Map<String, dynamic> json) {
    final rawLayers = (json['layers'] as Map).cast<String, dynamic>();
    final layers = <String, Layer>{};
    rawLayers.forEach((k, v) {
      layers[k] = Layer.fromJson((v as Map).cast<String, dynamic>());
    });
    return Scene(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Untitled Floorplan',
      unit: json['unit'] as String? ?? 'cm',
      width: (json['width'] as num?)?.toDouble() ?? 2000,
      height: (json['height'] as num?)?.toDouble() ?? 2000,
      gridSize: (json['gridSize'] as num?)?.toDouble() ?? 20,
      ceilingHeightCm: (json['ceilingHeightCm'] as num?)?.toDouble() ?? 240,
      selectedLayerId: json['selectedLayerId'] as String,
      layers: layers,
      background: json['background'] is Map
          ? BackgroundPdf.fromJson(
              (json['background'] as Map).cast<String, dynamic>())
          : null,
    );
  }
}
