import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

/// Mixin for screens/widgets that load workspace-scoped data.
///
/// ## The bug it removes
///
/// On a cold load / hard refresh of a route, `AuthProvider.appUser` is briefly
/// null while the Supabase session rehydrates. Any data load triggered from
/// `initState` that reads `currentWorkspaceId` therefore gets null and — if it
/// early-returns or gates a full-screen spinner — never runs and never retries
/// (because `context.read` registers no dependency, so `didChangeDependencies`
/// doesn't re-fire when `appUser` arrives). The symptoms seen across the app:
/// an infinite spinner, a terminal "No workspace" / "User not found" state, an
/// empty dropdown (e.g. Customer Type rendering "Residential (removed)"), or a
/// hard crash from `appUser!`.
///
/// ## How to use it
///
/// ```dart
/// class _FooScreenState extends State<FooScreen> with WorkspaceGatedLoader {
///   @override
///   void onWorkspaceReady(String workspaceId) {
///     _loadThings(workspaceId);   // your existing workspace-scoped loads
///   }
/// }
/// ```
///
/// Keep `initState` for non-workspace setup (controllers, listeners, params).
/// Move every load that needs the workspace id into [onWorkspaceReady]; it is
/// called exactly once as soon as the workspace id is known, and again if the
/// active workspace changes (override [reloadOnWorkspaceChange] to disable).
///
/// Screens that resolve the workspace differently (e.g. the asset form uses
/// `activeWorkspaceId ?? workspaceId`) can override [resolveWorkspaceId].
mixin WorkspaceGatedLoader<T extends StatefulWidget> on State<T> {
  String? _wglLoadedWorkspaceId;

  /// Called once the workspace id is available (non-null, non-empty), and again
  /// when the active workspace changes if [reloadOnWorkspaceChange] is true.
  void onWorkspaceReady(String workspaceId);

  /// Whether [onWorkspaceReady] should fire again when the user switches
  /// workspace. Defaults to true; set false for one-shot create forms where a
  /// mid-edit workspace switch shouldn't clobber the in-progress form.
  bool get reloadOnWorkspaceChange => true;

  /// How this screen derives the workspace id. Override for the
  /// `activeWorkspaceId ?? workspaceId` variant.
  String? resolveWorkspaceId(AuthProvider auth) =>
      auth.appUser?.currentWorkspaceId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Provider.of with listen:true registers the dependency so this re-fires
    // the moment appUser hydrates.
    final wid = resolveWorkspaceId(Provider.of<AuthProvider>(context));
    if (wid == null || wid.isEmpty) return;
    if (wid == _wglLoadedWorkspaceId) return;
    if (_wglLoadedWorkspaceId != null && !reloadOnWorkspaceChange) return;
    _wglLoadedWorkspaceId = wid;
    onWorkspaceReady(wid);
  }
}
