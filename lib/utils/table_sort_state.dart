/// Immutable 3-state column sort: ascending → descending → unsorted.
class TableSortState {
  const TableSortState({this.column, this.ascending = true});

  final String? column;
  final bool ascending;

  /// Cycles sort for [columnId]: off → asc → desc → off.
  TableSortState toggle(String columnId) {
    if (column == columnId) {
      return ascending
          ? TableSortState(column: columnId, ascending: false)
          : const TableSortState();
    }
    return TableSortState(column: columnId);
  }
}
