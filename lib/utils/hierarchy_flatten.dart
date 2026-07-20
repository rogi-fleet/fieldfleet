/// Generic flattened hierarchy row metadata.
class HierarchyFlatEntry<T> {
  final T item;
  final int depth;
  final List<bool> treeGuides;
  final bool isLastChild;
  final bool hasChildren;

  const HierarchyFlatEntry({
    required this.item,
    required this.depth,
    required this.treeGuides,
    required this.isLastChild,
    required this.hasChildren,
  });
}

/// Flattens parent/child structures into render-ready entries with tree metadata.
List<HierarchyFlatEntry<T>> flattenHierarchy<T>({
  required List<T> items,
  required String Function(T) idOf,
  required String? Function(T) parentIdOf,
  required bool Function(T) isExpandedOf,
  int Function(T a, T b)? sortSiblings,
}) {
  if (items.isEmpty) return <HierarchyFlatEntry<T>>[];

  final itemIds = items.map(idOf).toSet();
  final childrenByParent = <String, List<T>>{};
  final rootItems = <T>[];

  for (final item in items) {
    final parentId = parentIdOf(item);
    if (parentId == null || !itemIds.contains(parentId)) {
      rootItems.add(item);
      continue;
    }
    childrenByParent.putIfAbsent(parentId, () => <T>[]).add(item);
  }

  if (sortSiblings != null) {
    rootItems.sort(sortSiblings);
    for (final siblings in childrenByParent.values) {
      siblings.sort(sortSiblings);
    }
  }

  final rows = <HierarchyFlatEntry<T>>[];
  final visited = <String>{};

  void dfs(T item, int depth, List<bool> treeGuides, bool isLastChild) {
    final itemId = idOf(item);
    if (!visited.add(itemId)) return;

    final children = childrenByParent[itemId] ?? <T>[];
    final hasChildren = children.isNotEmpty;
    rows.add(
      HierarchyFlatEntry<T>(
        item: item,
        depth: depth,
        treeGuides: treeGuides,
        isLastChild: isLastChild,
        hasChildren: hasChildren,
      ),
    );

    if (!hasChildren || !isExpandedOf(item)) return;

    final childGuides = [...treeGuides, !isLastChild];
    for (var i = 0; i < children.length; i++) {
      dfs(children[i], depth + 1, childGuides, i == children.length - 1);
    }
  }

  for (var i = 0; i < rootItems.length; i++) {
    dfs(rootItems[i], 0, const <bool>[], i == rootItems.length - 1);
  }

  return rows;
}
