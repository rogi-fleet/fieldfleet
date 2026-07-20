import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/workspace_provider.dart';
import '../theme/theme.dart';

/// A tiny app-wide controller that tracks the user's navigation history so
/// we can offer Back / Forward buttons in addition to GoRouter's normal flow.
///
/// Attach it once after the [GoRouter] has been created (see `main.dart`).
class NavHistoryController extends ChangeNotifier {
  NavHistoryController._();
  static final NavHistoryController instance = NavHistoryController._();

  final List<String> _back = <String>[];
  final List<String> _forward = <String>[];
  String? _current;
  bool _navigating = false;
  GoRouter? _router;

  bool get canBack => _back.isNotEmpty;
  bool get canForward => _forward.isNotEmpty;
  String? get current => _current;

  /// Bind the controller to the live [GoRouter] instance. Idempotent.
  void attach(GoRouter router) {
    if (_router == router) return;
    _router?.routerDelegate.removeListener(_onRouteChanged);
    _router = router;
    _router!.routerDelegate.addListener(_onRouteChanged);
    _onRouteChanged();
  }

  /// Tear down the listener and clear state. Call from app dispose.
  void detach() {
    _router?.routerDelegate.removeListener(_onRouteChanged);
    _router = null;
    _back.clear();
    _forward.clear();
    _current = null;
    _navigating = false;
  }

  void _onRouteChanged() {
    final r = _router;
    if (r == null) return;
    final loc = r.routerDelegate.currentConfiguration.uri.toString();
    if (loc == _current) return;
    if (_navigating) {
      _navigating = false;
    } else {
      if (_current != null) _back.add(_current!);
      _forward.clear();
    }
    _current = loc;
    notifyListeners();
  }

  void goBack() {
    if (!canBack || _router == null) return;
    final to = _back.removeLast();
    if (_current != null) _forward.add(_current!);
    _navigating = true;
    _router!.go(to);
  }

  void goForward() {
    if (!canForward || _router == null) return;
    final to = _forward.removeLast();
    if (_current != null) _back.add(_current!);
    _navigating = true;
    _router!.go(to);
  }

  void goHome() {
    _router?.go('/');
  }
}

/// Static lookup of top-level path segments → human display label so we don't
/// surface raw URL slugs in the breadcrumb trail.
const Map<String, String> _crumbLabels = {
  '': 'Dashboard',
  'projects': 'Projects',
  'tasks': 'Tasks',
  'customers': 'Customers',
  'financials': 'Financials',
  'vendors': 'Vendors',
  'team': 'Team',
  'assets': 'Assets',
  'vehicles': 'Vehicles',
  'reports': 'Reports',
  'catalog': 'Catalog',
  'templates': 'Templates',
  'files': 'Files',
  'inventory': 'Inventory',
  'documents': 'Financials',
  'calendar': 'Calendar',
  'messages': 'Messages',
  'settings': 'Settings',
  'profile': 'Profile',
  'help': 'Help',
  'workspaces': 'Workspaces',
  'time-tracking': 'Time Tracking',
  'notifications': 'Notifications',
  'onboarding': 'Onboarding',
  'new': 'New',
  'create': 'Create',
};

String _labelFor(String segment, {String? projectTerminology}) {
  // Workspace-specific override: when the workspace has renamed projects
  // (e.g. "Jobs", "Sites"), the URL stays at /projects for back-compat
  // but the breadcrumb should match the page header.
  if (segment.toLowerCase() == 'projects' &&
      projectTerminology != null &&
      projectTerminology.isNotEmpty) {
    return projectTerminology;
  }
  final l = _crumbLabels[segment.toLowerCase()];
  if (l != null) return l;
  // Fallback: don't display long opaque IDs (UUIDs, numeric IDs).
  if (segment.length > 12 || RegExp(r'^[0-9a-f-]{8,}$').hasMatch(segment)) {
    return 'Detail';
  }
  // Title-case kebab/snake
  final cleaned = segment.replaceAll(RegExp(r'[-_]'), ' ');
  return cleaned
      .split(' ')
      .where((p) => p.isNotEmpty)
      .map((p) => p[0].toUpperCase() + p.substring(1))
      .join(' ');
}

/// Persistent navigation strip with Back / Forward / Home buttons and a
/// breadcrumb trail of the current path. Mounted globally so every page
/// inside the app shell automatically gets it.
class NavBreadcrumbBar extends StatelessWidget {
  final bool compact;
  const NavBreadcrumbBar({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: NavHistoryController.instance,
      builder: (context, _) {
        final ctrl = NavHistoryController.instance;
        final loc = ctrl.current ?? '';
        final path = Uri.parse(loc).path;
        final segments = path
            .split('/')
            .where((s) => s.isNotEmpty)
            .toList(growable: false);
        final atHome = segments.isEmpty;

        final chrome = ChromeColors.of(context);
        final iconColor = chrome.text;
        final mutedColor = chrome.text.withValues(alpha: 0.55);

        Widget btn({
          required IconData icon,
          required String tooltip,
          required bool enabled,
          required VoidCallback onTap,
        }) {
          return IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: tooltip,
            icon: Icon(icon, color: enabled ? iconColor : mutedColor),
            onPressed: enabled ? onTap : null,
          );
        }

        final projectTerminology =
            context.watch<WorkspaceProvider>().projectTerminology;
        final crumbs = <Widget>[];
        // Always start with a Home crumb so the user has a single click home
        // even when the trail is rendered.
        crumbs.add(_Crumb(
          label: 'Home',
          isLast: atHome,
          onTap: atHome ? null : () => ctrl.goHome(),
        ));
        // Build cumulative path crumbs for each segment.
        var acc = '';
        for (var i = 0; i < segments.length; i++) {
          acc = '$acc/${segments[i]}';
          final isLast = i == segments.length - 1;
          final target = acc;
          crumbs.add(const _CrumbSeparator());
          crumbs.add(_Crumb(
            label: _labelFor(
              segments[i],
              projectTerminology: projectTerminology,
            ),
            isLast: isLast,
            onTap: isLast ? null : () => context.go(target),
          ));
        }

        return Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Row(
            children: [
              btn(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                enabled: ctrl.canBack,
                onTap: ctrl.goBack,
              ),
              btn(
                icon: Icons.arrow_forward_rounded,
                tooltip: 'Forward',
                enabled: ctrl.canForward,
                onTap: ctrl.goForward,
              ),
              // The full trail already starts with a Home crumb, so the home
              // icon button is only needed when the trail is hidden.
              if (compact)
                btn(
                  icon: Icons.home_rounded,
                  tooltip: 'Dashboard',
                  enabled: !atHome,
                  onTap: ctrl.goHome,
                ),
              if (!compact) ...[
                const SizedBox(width: 4),
                Container(
                  width: 1,
                  height: 18,
                  color: chrome.text.withValues(alpha: 0.15),
                ),
                const SizedBox(width: 8),
                Expanded(
                  // Align left so a short trail sits next to the buttons;
                  // reverse keeps the tail of a long trail visible.
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: crumbs,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Crumb extends StatelessWidget {
  final String label;
  final bool isLast;
  final VoidCallback? onTap;
  const _Crumb({required this.label, required this.isLast, this.onTap});

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeColors.of(context);
    final color = isLast
        ? chrome.text
        : chrome.text.withValues(alpha: 0.65);
    final style = TextStyle(
      color: color,
      fontSize: 12.5,
      fontWeight: isLast ? FontWeight.w600 : FontWeight.w500,
    );

    if (onTap == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
        child: Text(label, style: style, overflow: TextOverflow.ellipsis),
      );
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
        child: Text(label, style: style, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _CrumbSeparator extends StatelessWidget {
  const _CrumbSeparator();

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Icon(
        Icons.chevron_right_rounded,
        size: 14,
        color: chrome.text.withValues(alpha: 0.35),
      ),
    );
  }
}
