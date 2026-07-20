typedef ItemIdOf<T> = String Function(T item);
typedef ParentIdOf<T> = String? Function(T item);

class HierarchyUtils {
  static Map<String, List<T>> buildChildrenMap<T>(
    List<T> items, {
    required ItemIdOf<T> idOf,
    required ParentIdOf<T> parentIdOf,
    String rootKey = '',
    int Function(T a, T b)? sort,
  }) {
    final childrenByParent = <String, List<T>>{};
    for (final item in items) {
      final parentKey = parentIdOf(item) ?? rootKey;
      childrenByParent.putIfAbsent(parentKey, () => <T>[]).add(item);
    }

    if (sort != null) {
      for (final children in childrenByParent.values) {
        children.sort(sort);
      }
    }

    return childrenByParent;
  }

  static Set<String> collectDescendantIds<T>(
    String parentId,
    Map<String, List<T>> childrenByParent, {
    required ItemIdOf<T> idOf,
  }) {
    final descendants = <String>{};

    void visit(String currentParentId) {
      final children = childrenByParent[currentParentId] ?? <T>[];
      for (final child in children) {
        final childId = idOf(child);
        if (descendants.add(childId)) {
          visit(childId);
        }
      }
    }

    visit(parentId);
    return descendants;
  }

  static List<T> collectDescendants<T>(
    String parentId,
    Map<String, List<T>> childrenByParent, {
    required ItemIdOf<T> idOf,
  }) {
    final descendants = <T>[];

    void visit(String currentParentId) {
      final children = childrenByParent[currentParentId] ?? <T>[];
      for (final child in children) {
        descendants.add(child);
        visit(idOf(child));
      }
    }

    visit(parentId);
    return descendants;
  }

  static bool isDescendantOf<T>({
    required String ancestorId,
    required String candidateId,
    required Map<String, T> itemsById,
    required ParentIdOf<T> parentIdOf,
    int maxDepth = 100,
  }) {
    var currentId = candidateId;
    for (var i = 0; i < maxDepth; i++) {
      final item = itemsById[currentId];
      final parentId = item != null ? parentIdOf(item) : null;
      if (parentId == null) return false;
      if (parentId == ancestorId) return true;
      currentId = parentId;
    }
    return false;
  }

  static Set<String> collectAncestorIds<T>({
    required T item,
    required Map<String, T> itemsById,
    required ItemIdOf<T> idOf,
    required ParentIdOf<T> parentIdOf,
    int maxDepth = 100,
  }) {
    final ancestors = <String>{};
    var parentId = parentIdOf(item);
    var depth = 0;

    while (parentId != null && depth < maxDepth) {
      if (!ancestors.add(parentId)) break;
      final parent = itemsById[parentId];
      if (parent == null ||
          idOf(parent) == parentId && parentIdOf(parent) == null) {
        break;
      }
      parentId = parentIdOf(parent);
      depth++;
    }

    return ancestors;
  }
}
