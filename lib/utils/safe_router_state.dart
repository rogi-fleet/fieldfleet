import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Reads the current route URI for persistent chrome (top bar, nav shell,
/// quick-add overlay) that rebuilds outside of navigation events.
///
/// `GoRouterState.of` subscribes the context to route changes, but it throws
/// a [GoError] during transient frames where the Navigator's routes and
/// go_router's page registry are mid-update — reliably reproducible by
/// resizing the window, whose MediaQuery change rebuilds chrome widgets
/// before the registry is consistent (go_router 14.x). In release builds the
/// throw escalated to the global error screen.
///
/// On that transient failure, fall back to the router delegate's current
/// configuration, which is always available. The ModalRoute dependency that
/// `GoRouterState.of` establishes before throwing re-runs the build once the
/// registry settles, so the fallback value is never left on screen stale.
Uri safeRouteUri(BuildContext context) {
  try {
    return GoRouterState.of(context).uri;
  } on GoError {
    return GoRouter.of(context).routerDelegate.currentConfiguration.uri;
  }
}
