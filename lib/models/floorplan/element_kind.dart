/// The kinds of selectable elements in a floorplan layer.
///
/// Used as the key in [ElementsSet] so the editor can track selection per
/// element class without losing the source ID.
enum ElementKind {
  vertex,
  line,
  hole,
  area,
  item,
  annotation,
}
