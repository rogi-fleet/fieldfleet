import 'element_kind.dart';

/// Selected element IDs, partitioned by kind.
///
/// Mirrors react-planner's `ElementsSet` Record. Treat instances as immutable
/// — use [copyWith] / [withSelection] / [cleared] to derive new sets.
class ElementsSet {
  final Set<String> vertices;
  final Set<String> lines;
  final Set<String> holes;
  final Set<String> areas;
  final Set<String> items;
  final Set<String> annotations;

  const ElementsSet({
    this.vertices = const {},
    this.lines = const {},
    this.holes = const {},
    this.areas = const {},
    this.items = const {},
    this.annotations = const {},
  });

  static const empty = ElementsSet();

  bool get isEmpty =>
      vertices.isEmpty &&
      lines.isEmpty &&
      holes.isEmpty &&
      areas.isEmpty &&
      items.isEmpty &&
      annotations.isEmpty;

  bool get isNotEmpty => !isEmpty;

  int get totalCount =>
      vertices.length +
      lines.length +
      holes.length +
      areas.length +
      items.length +
      annotations.length;

  Set<String> idsFor(ElementKind kind) => switch (kind) {
        ElementKind.vertex => vertices,
        ElementKind.line => lines,
        ElementKind.hole => holes,
        ElementKind.area => areas,
        ElementKind.item => items,
        ElementKind.annotation => annotations,
      };

  ElementsSet withSelection(ElementKind kind, String id) =>
      _copyWithKind(kind, {...idsFor(kind), id});

  ElementsSet withDeselection(ElementKind kind, String id) =>
      _copyWithKind(kind, idsFor(kind).where((e) => e != id).toSet());

  ElementsSet replacingSelection(ElementKind kind, Set<String> ids) =>
      _copyWithKind(kind, ids);

  ElementsSet cleared() => empty;

  ElementsSet _copyWithKind(ElementKind kind, Set<String> next) =>
      ElementsSet(
        vertices: kind == ElementKind.vertex ? next : vertices,
        lines: kind == ElementKind.line ? next : lines,
        holes: kind == ElementKind.hole ? next : holes,
        areas: kind == ElementKind.area ? next : areas,
        items: kind == ElementKind.item ? next : items,
        annotations: kind == ElementKind.annotation ? next : annotations,
      );

  Map<String, dynamic> toJson() => {
        'vertices': vertices.toList(),
        'lines': lines.toList(),
        'holes': holes.toList(),
        'areas': areas.toList(),
        'items': items.toList(),
        'annotations': annotations.toList(),
      };

  factory ElementsSet.fromJson(Map<String, dynamic> json) => ElementsSet(
        vertices: _readSet(json['vertices']),
        lines: _readSet(json['lines']),
        holes: _readSet(json['holes']),
        areas: _readSet(json['areas']),
        items: _readSet(json['items']),
        annotations: _readSet(json['annotations']),
      );

  static Set<String> _readSet(dynamic value) {
    if (value is List) return value.cast<String>().toSet();
    return const {};
  }
}
