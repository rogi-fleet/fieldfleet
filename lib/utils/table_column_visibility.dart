/// Immutable set of visible column IDs with a toggle operation.
class TableColumnVisibility {
  TableColumnVisibility(Iterable<String> columns)
      : _visible = Set.of(columns);

  const TableColumnVisibility._empty() : _visible = const {};

  static const TableColumnVisibility empty = TableColumnVisibility._empty();

  final Set<String> _visible;

  bool isVisible(String columnId) => _visible.contains(columnId);

  /// Returns a new instance with [columnId] toggled on or off.
  TableColumnVisibility toggle(String columnId) {
    final next = Set.of(_visible);
    if (!next.remove(columnId)) next.add(columnId);
    return TableColumnVisibility(next);
  }

  /// Returns an unmodifiable copy of the visible column set.
  Set<String> toSet() => Set.unmodifiable(_visible);

  List<String> toList() => _visible.toList();
}
