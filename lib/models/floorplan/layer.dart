import 'annotation.dart';
import 'area.dart';
import 'elements_set.dart';
import 'hole.dart';
import 'item.dart';
import 'line.dart';
import 'vertex.dart';

/// A single editable layer in a [Scene]. Holds all geometry as ID-keyed maps
/// so lookups and back-references are O(1).
class Layer {
  final String id;
  final String name;
  final int order;
  final bool visible;
  final double opacity;
  final Map<String, Vertex> vertices;
  final Map<String, FloorLine> lines;
  final Map<String, Hole> holes;
  final Map<String, Area> areas;
  final Map<String, Item> items;
  final Map<String, Annotation> annotations;
  final ElementsSet selected;

  const Layer({
    required this.id,
    this.name = 'Layer',
    this.order = 0,
    this.visible = true,
    this.opacity = 1.0,
    this.vertices = const {},
    this.lines = const {},
    this.holes = const {},
    this.areas = const {},
    this.items = const {},
    this.annotations = const {},
    this.selected = ElementsSet.empty,
  });

  Layer copyWith({
    String? name,
    int? order,
    bool? visible,
    double? opacity,
    Map<String, Vertex>? vertices,
    Map<String, FloorLine>? lines,
    Map<String, Hole>? holes,
    Map<String, Area>? areas,
    Map<String, Item>? items,
    Map<String, Annotation>? annotations,
    ElementsSet? selected,
  }) =>
      Layer(
        id: id,
        name: name ?? this.name,
        order: order ?? this.order,
        visible: visible ?? this.visible,
        opacity: opacity ?? this.opacity,
        vertices: vertices ?? this.vertices,
        lines: lines ?? this.lines,
        holes: holes ?? this.holes,
        areas: areas ?? this.areas,
        items: items ?? this.items,
        annotations: annotations ?? this.annotations,
        selected: selected ?? this.selected,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'order': order,
        'visible': visible,
        'opacity': opacity,
        'vertices':
            vertices.map((k, v) => MapEntry(k, v.toJson())),
        'lines': lines.map((k, v) => MapEntry(k, v.toJson())),
        'holes': holes.map((k, v) => MapEntry(k, v.toJson())),
        'areas': areas.map((k, v) => MapEntry(k, v.toJson())),
        'items': items.map((k, v) => MapEntry(k, v.toJson())),
        'annotations':
            annotations.map((k, v) => MapEntry(k, v.toJson())),
        'selected': selected.toJson(),
      };

  factory Layer.fromJson(Map<String, dynamic> json) => Layer(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Layer',
        order: (json['order'] as num?)?.toInt() ?? 0,
        visible: json['visible'] as bool? ?? true,
        opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
        vertices: _readMap(json['vertices'], Vertex.fromJson),
        lines: _readMap(json['lines'], FloorLine.fromJson),
        holes: _readMap(json['holes'], Hole.fromJson),
        areas: _readMap(json['areas'], Area.fromJson),
        items: _readMap(json['items'], Item.fromJson),
        annotations: _readMap(json['annotations'], Annotation.fromJson),
        selected: json['selected'] is Map
            ? ElementsSet.fromJson(
                (json['selected'] as Map).cast<String, dynamic>())
            : ElementsSet.empty,
      );

  static Map<String, T> _readMap<T>(
    dynamic raw,
    T Function(Map<String, dynamic>) build,
  ) {
    if (raw is! Map) return <String, T>{};
    final out = <String, T>{};
    raw.forEach((k, v) {
      if (v is Map) out[k as String] = build(v.cast<String, dynamic>());
    });
    return out;
  }
}
