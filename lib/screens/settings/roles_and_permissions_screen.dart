import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/workspace_role_template.dart';
import '../../providers/auth_provider.dart';
import '../../theme/theme.dart';
import 'permission_matrix_screen.dart';
import 'role_templates_screen.dart';

/// Tabbed host for the two roles-and-permissions surfaces: the matrix
/// (overview / diff / cross-role comparison) and the editor (configure one
/// template at a time). Opening the editor for a specific role is a common
/// flow, so clicking a column header in the matrix flips to the editor tab
/// with that template selected instead of navigating to a new screen.
class RolesAndPermissionsScreen extends StatefulWidget {
  const RolesAndPermissionsScreen({
    super.key,
    this.initialTab = _RolesTab.matrix,
  });

  final _RolesTab initialTab;

  @override
  State<RolesAndPermissionsScreen> createState() =>
      _RolesAndPermissionsScreenState();
}

enum _RolesTab { matrix, editor }

class _RolesAndPermissionsScreenState extends State<RolesAndPermissionsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _matrixKey = GlobalKey<PermissionMatrixScreenState>();
  final _editorKey = GlobalKey<RoleTemplatesScreenState>();
  final ValueNotifier<bool> _editorDirty = ValueNotifier<bool>(false);
  String? _focusTemplateId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab == _RolesTab.editor ? 1 : 0,
    );
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _editorDirty.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    // Mirror the tab into the URL so copied links land on the right tab.
    final uri = GoRouterState.of(context).uri.toString();
    final expected = _tabController.index == 0
        ? '/settings/permission-matrix'
        : '/settings/role-templates';
    if (!uri.startsWith(expected)) {
      context.go(expected);
    }
    // Matrix fetches on load; if we're returning to it after edits in the
    // Editor tab, re-fetch so counts and cell values are fresh.
    if (_tabController.index == 0) {
      _matrixKey.currentState?.reload();
    }
    setState(() {}); // Refresh the dirty-indicator decoration on the tab.
  }

  void _openEditorForTemplate(WorkspaceRoleTemplate template) {
    setState(() => _focusTemplateId = template.id);
    _tabController.animateTo(1);
  }

  Future<bool> _confirmExit() async {
    // Only the editor tracks unsaved state.
    final editor = _editorKey.currentState;
    if (editor == null || !editor.hasUnsavedChanges) return true;
    return editor.confirmDiscardChanges();
  }

  /// Back-button handler. On mobile, if the editor is showing a role
  /// detail view, the first back press returns to the role list instead
  /// of exiting the whole screen. Matches the old standalone behavior.
  Future<void> _handleBack() async {
    final isMobile = MediaQuery.sizeOf(context).width <= 720;
    if (_tabController.index == 1 && isMobile) {
      final editor = _editorKey.currentState;
      if (editor != null && editor.hasMobileSelection) {
        await editor.clearSelection();
        return;
      }
    }
    if (await _confirmExit()) {
      if (!mounted) return;
      // Tab changes call context.go to sync the URL, which clobbers the
      // navigator's pop stack. Fall back to the workspace settings screen
      // when there's nothing to pop back to.
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/workspaces/settings');
      }
    }
  }

  Future<void> _refreshActiveTab() async {
    if (_tabController.index == 0) {
      await _matrixKey.currentState?.reload();
    } else {
      await _editorKey.currentState?.reload();
    }
  }

  Future<void> _triggerCreateRole() async {
    if (_tabController.index == 0) {
      _tabController.animateTo(1);
      // Wait one frame so the editor mounts before we open its dialog.
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }
    await _editorKey.currentState?.triggerCreate();
  }

  @override
  Widget build(BuildContext context) {
    final canManage = context.watch<AuthProvider>().canManageUsers;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: _handleBack,
          ),
          title: const Text('Roles & Permissions'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: _refreshActiveTab,
            ),
            if (canManage && _tabController.index == 0)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Create role'),
                  onPressed: _triggerCreateRole,
                ),
              ),
          ],
          bottom: TabBar(
            controller: _tabController,
            tabs: [
              const Tab(icon: Icon(Icons.table_chart_outlined), text: 'Matrix'),
              Tab(
                icon: const Icon(Icons.rule_folder_outlined),
                child: ValueListenableBuilder<bool>(
                  valueListenable: _editorDirty,
                  builder: (_, dirty, __) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Editor'),
                        if (dirty) ...[
                          const SizedBox(width: 6),
                          Tooltip(
                            message: 'Unsaved changes',
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: AppColors.warning,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        body: !canManage
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: Text('Only workspace admins can manage roles.'),
                ),
              )
            : TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  PermissionMatrixScreen(
                    key: _matrixKey,
                    embedded: true,
                    onOpenEditorForTemplate: _openEditorForTemplate,
                  ),
                  _EditorHost(
                    editorKey: _editorKey,
                    focusTemplateId: _focusTemplateId,
                    onDirtyChanged: (dirty) => _editorDirty.value = dirty,
                  ),
                ],
              ),
      ),
    );
  }
}

/// Wraps the embedded [RoleTemplatesScreen] to forward its internal
/// dirtyNotifier up to the shell for the tab-level dirty indicator.
class _EditorHost extends StatefulWidget {
  const _EditorHost({
    required this.editorKey,
    required this.focusTemplateId,
    required this.onDirtyChanged,
  });

  final GlobalKey<RoleTemplatesScreenState> editorKey;
  final String? focusTemplateId;
  final ValueChanged<bool> onDirtyChanged;

  @override
  State<_EditorHost> createState() => _EditorHostState();
}

class _EditorHostState extends State<_EditorHost> {
  VoidCallback? _dirtyListener;
  RoleTemplatesScreenState? _attachedState;

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _attachDirtyListener() {
    final state = widget.editorKey.currentState;
    if (state == null || state == _attachedState) return;
    _detach();
    _attachedState = state;
    _dirtyListener = () => widget.onDirtyChanged(state.dirtyNotifier.value);
    state.dirtyNotifier.addListener(_dirtyListener!);
    // Seed the current value.
    widget.onDirtyChanged(state.dirtyNotifier.value);
  }

  void _detach() {
    if (_attachedState != null && _dirtyListener != null) {
      _attachedState!.dirtyNotifier.removeListener(_dirtyListener!);
    }
    _attachedState = null;
    _dirtyListener = null;
  }

  @override
  Widget build(BuildContext context) {
    // Hook the listener once the child mounts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _attachDirtyListener();
    });
    return RoleTemplatesScreen(
      key: widget.editorKey,
      embedded: true,
      focusTemplateId: widget.focusTemplateId,
    );
  }
}

/// Convenience route builder for GoRouter — maps matrix/editor routes to the
/// unified screen with the correct initial tab so legacy links keep working.
Widget buildRolesAndPermissionsForRoute(String location) {
  final initial = location.contains('permission-matrix')
      ? _RolesTab.matrix
      : _RolesTab.editor;
  return RolesAndPermissionsScreen(initialTab: initial);
}
