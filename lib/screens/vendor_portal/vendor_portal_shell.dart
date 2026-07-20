import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/safe_router_state.dart';

/// Shell layout for authenticated vendor portal screens: app bar with
/// sign-out, plus a body slot. Each screen wraps itself in this shell.
class VendorPortalShell extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget> actions;

  const VendorPortalShell({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
  });

  Future<void> _signOut(BuildContext context) async {
    try {
      await ServiceLocator.vendorPortalService.signOut();
    } catch (_) {}
    if (!context.mounted) return;
    context.go('/vendor-portal');
  }

  @override
  Widget build(BuildContext context) {
    final email = ServiceLocator.vendorPortalService.getPortalEmail();
    // Path-only read; query params are irrelevant to the tab match below.
    final route = safeRouteUri(context).path;

    int? indexFor(String r) {
      if (r.startsWith('/vendor-portal/bids')) return 1;
      if (r.startsWith('/vendor-portal/work-orders')) return 2;
      if (r.startsWith('/vendor-portal/selections')) return 3;
      if (r.startsWith('/vendor-portal/bills')) return 4;
      if (r.startsWith('/vendor-portal')) return 0;
      return null;
    }

    final selectedIndex = indexFor(route) ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          ...actions,
          if (email != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Center(
                child: Text(email,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textTertiary)),
              ),
            ),
          IconButton(
            tooltip: 'Sign Out',
            icon: const Icon(Icons.logout),
            onPressed: () => _signOut(context),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (i) {
          switch (i) {
            case 0:
              context.go('/vendor-portal/dashboard');
              break;
            case 1:
              context.go('/vendor-portal/bids');
              break;
            case 2:
              context.go('/vendor-portal/work-orders');
              break;
            case 3:
              context.go('/vendor-portal/selections');
              break;
            case 4:
              context.go('/vendor-portal/bills');
              break;
          }
        },
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.dashboard_outlined), label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.gavel_outlined), label: 'Bids'),
          NavigationDestination(
              icon: Icon(Icons.assignment_outlined), label: 'Work Orders'),
          NavigationDestination(
              icon: Icon(Icons.checklist_outlined), label: 'Selections'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined), label: 'Bills'),
        ],
      ),
      body: child,
    );
  }
}
