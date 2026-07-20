/// Which slice of the workspace the global Files screen is showing.
///
/// The sidebar picks a scope; the right pane renders files matching it.
/// `byProject` keeps the existing per-job experience (ProjectFilesScreen);
/// the other scopes flatten across projects and are rendered by
/// `WorkspaceFilesBrowser`.
sealed class FilesScope {
  const FilesScope();

  const factory FilesScope.allWorkspace() = AllWorkspaceScope;
  const factory FilesScope.byProject(String projectId) = ByProjectScope;
  const factory FilesScope.byCustomer(String customerId) = ByCustomerScope;
  const factory FilesScope.byTag(String tagId) = ByTagScope;
}

class AllWorkspaceScope extends FilesScope {
  const AllWorkspaceScope();
  @override
  bool operator ==(Object other) => other is AllWorkspaceScope;
  @override
  int get hashCode => 0;
}

class ByProjectScope extends FilesScope {
  final String projectId;
  const ByProjectScope(this.projectId);
  @override
  bool operator ==(Object other) =>
      other is ByProjectScope && other.projectId == projectId;
  @override
  int get hashCode => Object.hash('project', projectId);
}

class ByCustomerScope extends FilesScope {
  final String customerId;
  const ByCustomerScope(this.customerId);
  @override
  bool operator ==(Object other) =>
      other is ByCustomerScope && other.customerId == customerId;
  @override
  int get hashCode => Object.hash('customer', customerId);
}

class ByTagScope extends FilesScope {
  final String tagId;
  const ByTagScope(this.tagId);
  @override
  bool operator ==(Object other) =>
      other is ByTagScope && other.tagId == tagId;
  @override
  int get hashCode => Object.hash('tag', tagId);
}
