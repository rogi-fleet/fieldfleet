import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../config/build_info.dart';
import '../models/project.dart';
import '../providers/auth_provider.dart';
import '../providers/chrome_provider.dart';
import '../providers/workspace_provider.dart';
import '../theme/theme.dart';
import 'logo_widget.dart';
import 'common/draggable_divider.dart';
import 'messaging_popup.dart';
import 'project_form_popup.dart';
import 'task_form_popup.dart';
import 'customer_form_popup.dart';
import 'vendor_form_popup.dart';
import '../services/service_locator.dart';
import 'photo_capture_assign_dialog.dart';
import 'project_selector_dialog.dart';
import 'top_bar.dart'; // Renamed to ContentHeader inside the file, but file name remains for now
import 'user_avatar.dart';
import 'ai_chat_popup.dart';
import 'budget_item_form_popup.dart';
import 'workspace_avatar.dart';
import 'workspace_switcher.dart';
import 'asset_form_popup.dart';
import 'vehicle_form_popup.dart';
import 'catalog/catalog_item_form_popup.dart';
import '../screens/time_tracking/time_entry_form_dialog.dart';
import 'nav_breadcrumb_bar.dart';
import '../utils/safe_router_state.dart';

/// Notification dispatched by child widgets when the user switches an in-page
/// tab (e.g. project detail tabs). The mobile scaffold listens for this and
/// re-shows the bottom navigation bar.
class TabSwitchNotification extends Notification {}

/// A stateful widget that listens to a [TabController] (or the nearest
/// [DefaultTabController]) and dispatches [TabSwitchNotification] whenever the
/// selected tab changes. Wrap any tabbed body with this widget.
class TabSwitchNotifier extends StatefulWidget {
  final TabController? controller;
  final Widget child;
  const TabSwitchNotifier({super.key, this.controller, required this.child});

  @override
  State<TabSwitchNotifier> createState() => _TabSwitchNotifierState();
}

class _TabSwitchNotifierState extends State<TabSwitchNotifier> {
  TabController? _controller;

  void _onTabChanged() {
    if (_controller != null && !_controller!.indexIsChanging) {
      TabSwitchNotification().dispatch(context);
    }
  }

  void _attachController(TabController? c) {
    if (c == _controller) return;
    _controller?.removeListener(_onTabChanged);
    _controller = c;
    _controller?.addListener(_onTabChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachController(
      widget.controller ?? DefaultTabController.maybeOf(context),
    );
  }

  @override
  void didUpdateWidget(covariant TabSwitchNotifier oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _attachController(
        widget.controller ?? DefaultTabController.maybeOf(context),
      );
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTabChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Navigation items visible to client role
const _clientVisibleIndices = {
  0,
  2,
  6,
  14,
  19,
  15,
}; // Dashboard, Projects, Schedule, Profile, Help, Logout (Inbox moved to top bar)

/// Mapping of navigation indices to workspace configuration IDs
const _indexToSectionId = {
  2: 'projects',
  3: 'tasks',
  4: 'customers',
  5: 'financials',
  7: 'vendors',
  8: 'timesheets',
  9: 'team',
  10: 'assets',
  11: 'vehicles',
  12: 'reports',
  16: 'catalog',
  17: 'templates',
  18: 'files', // formerly 'documents' — now the unified Files section
  20: 'inventory',
  23: 'opportunities',
};

/// Mapping of sectionId to module name for permission check
const _sectionIdToModule = {
  'projects': 'projects',
  'tasks': 'tasks',
  'customers': 'projects', // Customers often linked to projects/CRM
  'financials': 'budget',
  'vendors': 'budget',
  'timesheets': 'team',
  'team': 'team',
  'assets': 'settings',
  'vehicles': 'settings',
  'reports': 'projects',
  'catalog': 'budget',
  'templates': 'settings',
  'files': 'documents', // reuse 'documents' module permission key
  'documents':
      'documents', // kept for backward compat with stored workspace configs
  'inventory': 'budget', // gate inventory access on budget/financial perms
  'opportunities': 'projects', // CRM pipeline gated on project access
};

/// Sidebar section grouping for organized navigation
class _NavSection {
  final String label;
  final List<int> indices;
  const _NavSection(this.label, this.indices);
}

const _navSections = [
  _NavSection('MAIN', [0, 2, 3, 6]),
  _NavSection('MANAGE', [4, 7, 9, 18]),
  // Assets (index 10) removed from the sidebar — it now lives as the
  // "Equipment" tab inside Inventory (index 20). The index/destination is
  // retained below to preserve positional indexing, just no longer surfaced.
  _NavSection('TRACK', [16, 20, 11]),
  _NavSection('ANALYZE', [17, 12]),
  _NavSection('HELP', [19]),
];

bool _canAccessWorkspaceSettings(AuthProvider authProvider) {
  return authProvider.canAccessSettings || authProvider.canManageUsers;
}

List<PopupMenuEntry<String>> _buildProfileMenuEntries({
  required bool canAccessWorkspaceSettings,
}) {
  return <PopupMenuEntry<String>>[
    const PopupMenuItem(
      value: 'profile',
      child: Row(
        children: [
          Icon(Icons.person, size: 20),
          SizedBox(width: 12),
          Text('My Profile'),
        ],
      ),
    ),
    if (canAccessWorkspaceSettings)
      const PopupMenuItem(
        value: 'workspace_settings',
        child: Row(
          children: [
            Icon(Icons.settings, size: 20),
            SizedBox(width: 12),
            Text('Workspace Settings'),
          ],
        ),
      ),
    const PopupMenuDivider(),
    const PopupMenuItem(
      value: 'create_workspace',
      child: Row(
        children: [
          Icon(Icons.add_business, size: 20),
          SizedBox(width: 12),
          Text('Create Workspace'),
        ],
      ),
    ),
    const PopupMenuItem(
      value: 'logout',
      child: Row(
        children: [
          Icon(Icons.logout, size: 20),
          SizedBox(width: 12),
          Text('Logout'),
        ],
      ),
    ),
  ];
}

Future<void> _handleProfileMenuSelection(
  BuildContext context,
  AuthProvider authProvider,
  String value,
) async {
  switch (value) {
    case 'profile':
      context.go('/profile');
      break;
    case 'workspace_settings':
      if (!_canAccessWorkspaceSettings(authProvider)) {
        return;
      }
      context.go('/workspaces/settings');
      break;
    case 'create_workspace':
      context.go('/onboarding?newWorkspace=true');
      break;
    case 'logout':
      await authProvider.signOut();
      if (context.mounted) {
        context.pushReplacement('/login');
      }
      break;
  }
}

class AdaptiveNavigation extends StatelessWidget {
  final Widget child;
  final int selectedIndex;

  const AdaptiveNavigation({
    super.key,
    required this.child,
    required this.selectedIndex,
  });

  void _onDestinationSelected(BuildContext context, int index) async {
    final screenWidth = MediaQuery.maybeOf(context)?.size.width;
    final isMobile = screenWidth != null
        ? AppBreakpoints.isMobile(screenWidth)
        : false;

    switch (index) {
      case 0:
        context.go('/');
        break;
      // Keep Messages reachable from mobile "More" menu.
      case 1:
        if (isMobile) {
          showMessagingPopup(context);
        } else {
          context.go('/messages');
        }
        break;
      case 2:
        context.go('/projects');
        break;
      case 3:
        context.go('/tasks');
        break;
      case 4:
        context.go('/customers');
        break;
      case 5:
        context.go('/financials');
        break;
      case 6:
        context.go('/calendar');
        break;
      case 7:
        context.go('/vendors');
        break;
      case 8:
        context.go('/time-tracking');
        break;
      case 9:
        context.go('/team');
        break;
      case 10:
        context.go('/equipment');
        break;
      case 11:
        context.go('/vehicles');
        break;
      case 12:
        context.go('/reports');
        break;
      case 13:
        context.go('/settings/users');
        break;
      case 14:
        context.go('/profile');
        break;
      case 15:
        // Logout
        print('DEBUG: Logout clicked - calling signOut');
        await context.read<AuthProvider>().signOut();
        print('DEBUG: signOut completed, navigating to login');
        if (context.mounted) {
          context.pushReplacement('/login');
          print('DEBUG: Navigation to login called');
        } else {
          print('DEBUG: Context not mounted!');
        }
        break;
      case 16:
        context.go('/catalog');
        break;
      case 17:
        context.go('/templates');
        break;
      case 18:
        context.go('/files');
        break;
      case 19:
        context.go('/help');
        break;
      case 20:
        context.go('/inventory');
        break;
      case 23:
        context.go('/opportunities');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use drawer for mobile (< 600px), rail for desktop
        if (AppBreakpoints.isMobile(constraints.maxWidth)) {
          return _MobileScaffold(
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) =>
                _onDestinationSelected(context, index),
            child: child,
          );
        } else {
          return _DesktopScaffold(
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) =>
                _onDestinationSelected(context, index),
            child: child,
          );
        }
      },
    );
  }
}

class _DesktopScaffold extends StatefulWidget {
  final int selectedIndex;
  final Function(int) onDestinationSelected;
  final Widget child;

  const _DesktopScaffold({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.child,
  });

  @override
  State<_DesktopScaffold> createState() => _DesktopScaffoldState();
}

class _DesktopScaffoldState extends State<_DesktopScaffold> {
  bool _isCollapsed = false;
  bool _isInboxExpanded = false;
  double _inboxSplitRatio = 0.4;

  void _toggleCollapsed() {
    setState(() {
      _isCollapsed = !_isCollapsed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.appUser;

    // Check if email verification is required
    // emailVerified == false means explicitly not verified (new user)
    print(
      '🔒 DESKTOP NAV: currentUser is ${currentUser != null ? "loaded" : "null"}',
    );
    print('🔒 DESKTOP NAV: emailVerified = ${currentUser?.emailVerified}');
    if (currentUser != null && currentUser.emailVerified == false) {
      print('🔒 DESKTOP NAV: Redirecting to /verify-email-pending');
      // Schedule redirect to verification screen
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          context.go('/verify-email-pending');
        }
      });
      // Show loading while redirecting
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Build destinations list dynamically to include badge on Inbox
    final allDestinations = _buildDestinations(context, currentUser);

    return Scaffold(
      body: Row(
        children: [
          _buildSidebar(
            context,
            allDestinations,
            widget.selectedIndex,
            widget.onDestinationSelected,
            _isCollapsed,
          ),
          Expanded(
            child: Column(
              children: [
                const ContentHeader(),
                Expanded(
                  child: ValueListenableBuilder<String?>(
                    valueListenable: MessagingOverlayController.instance,
                    builder: (context, overlayValue, child) {
                      if (overlayValue == null) {
                        return child!;
                      }

                      final inboxPanel = MessagingOverlayPanel(
                        initialConversationId: overlayValue.isEmpty
                            ? null
                            : overlayValue,
                        onClose: () {
                          MessagingOverlayController.instance.hide();
                          setState(() => _isInboxExpanded = false);
                        },
                        onToggleExpand: () => setState(
                          () => _isInboxExpanded = !_isInboxExpanded,
                        ),
                        isExpanded: _isInboxExpanded,
                      );

                      if (_isInboxExpanded) return inboxPanel;

                      return LayoutBuilder(
                        builder: (context, constraints) {
                          const dividerWidth = 8.0;
                          final available = constraints.maxWidth - dividerWidth;
                          // Not enough room for a side-by-side split: show inbox full-width.
                          if (available - 300.0 < 320.0) return inboxPanel;
                          final inboxWidth = (available * _inboxSplitRatio)
                              .clamp(320.0, available - 300.0);
                          final pageWidth = available - inboxWidth;

                          return Row(
                            children: [
                              SizedBox(width: pageWidth, child: child!),
                              GestureDetector(
                                onHorizontalDragUpdate: (details) {
                                  setState(() {
                                    _inboxSplitRatio =
                                        ((_inboxSplitRatio * available -
                                                    details.delta.dx) /
                                                available)
                                            .clamp(
                                              320.0 / available,
                                              1.0 - 300.0 / available,
                                            );
                                  });
                                },
                                child: const DraggableDivider(
                                  width: dividerWidth,
                                ),
                              ),
                              SizedBox(width: inboxWidth, child: inboxPanel),
                            ],
                          );
                        },
                      );
                    },
                    child: widget.child,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<NavigationRailDestination> _buildDestinations(
    BuildContext context,
    dynamic currentUser,
  ) {
    final projectTerminology = context
        .watch<WorkspaceProvider>()
        .projectTerminology;
    return [
      const NavigationRailDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
        label: Text('Dashboard'),
      ),
      // Index 1: Inbox placeholder - kept to preserve index mapping, but hidden in rendering
      const NavigationRailDestination(
        icon: Icon(Icons.chat_bubble_outline),
        selectedIcon: Icon(Icons.chat_bubble),
        label: Text('Inbox'),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.folder_outlined),
        selectedIcon: const Icon(Icons.folder),
        label: Text(projectTerminology),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.add_task_outlined),
        selectedIcon: Icon(Icons.add_task),
        label: Text('Tasks'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.person_add_outlined),
        selectedIcon: Icon(Icons.person_add),
        label: Text('Customers'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.account_balance_wallet_outlined),
        selectedIcon: Icon(Icons.account_balance_wallet),
        label: Text('Financials'),
      ),
      // Index 6: Calendar — unified event/deadline view
      const NavigationRailDestination(
        icon: Icon(Icons.calendar_today_outlined),
        selectedIcon: Icon(Icons.calendar_today),
        label: Text('Calendar'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.store_outlined),
        selectedIcon: Icon(Icons.store),
        label: Text('Vendors'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.access_time_outlined),
        selectedIcon: Icon(Icons.access_time),
        label: Text('Time'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.group_outlined),
        selectedIcon: Icon(Icons.group),
        label: Text('Team'),
      ),
      // Index 10: retained for positional indexing; no longer in the sidebar
      // (Assets are now the "Equipment" tab inside Inventory).
      const NavigationRailDestination(
        icon: Icon(Icons.inventory_2_outlined),
        selectedIcon: Icon(Icons.inventory_2),
        label: Text('Equipment'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.directions_car_outlined),
        selectedIcon: Icon(Icons.directions_car),
        label: Text('Vehicles'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.assessment_outlined),
        selectedIcon: Icon(Icons.assessment),
        label: Text('Reports'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: Text('Settings'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person),
        label: Text('My Profile'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.logout),
        selectedIcon: Icon(Icons.logout),
        label: Text('Logout'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.list_alt_outlined),
        selectedIcon: Icon(Icons.list_alt),
        label: Text('Catalog'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.file_copy_outlined),
        selectedIcon: Icon(Icons.file_copy),
        label: Text('Templates'),
      ),

      const NavigationRailDestination(
        icon: Icon(Icons.folder_outlined),
        selectedIcon: Icon(Icons.folder),
        label: Text('Files'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.help_outline),
        selectedIcon: Icon(Icons.help),
        label: Text('Help & About'),
      ),
      // Index 20: Inventory (consumables + supplies + POs + equipment rentals)
      const NavigationRailDestination(
        icon: Icon(Icons.warehouse_outlined),
        selectedIcon: Icon(Icons.warehouse),
        label: Text('Inventory'),
      ),
      // Index 21: retained for positional indexing; the Contents module is
      // not part of this distribution.
      const NavigationRailDestination(
        icon: Icon(Icons.inventory_2_outlined),
        selectedIcon: Icon(Icons.inventory_2),
        label: Text('Contents'),
      ),
      // Index 22: retained for positional indexing; the Accounting module is
      // not part of this distribution.
      const NavigationRailDestination(
        icon: Icon(Icons.account_balance_outlined),
        selectedIcon: Icon(Icons.account_balance),
        label: Text('Accounting'),
      ),
      // Index 23: Opportunities — lead pipeline (P2-1)
      const NavigationRailDestination(
        icon: Icon(Icons.trending_up_outlined),
        selectedIcon: Icon(Icons.trending_up),
        label: Text('Opportunities'),
      ),
    ];
  }

  /// Build the set of visible nav indices for the current user/workspace
  Set<int> _getVisibleNavIndices(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final isClient = authProvider.isClientRole;
    final visibleIndices = isClient ? _clientVisibleIndices : null;
    final workspaceTabs = context
        .watch<WorkspaceProvider>()
        .enabledNavigationTabs;

    final result = <int>{};
    // Flat ordered list of all nav indices from sections
    final allIndices = _navSections.expand((s) => s.indices).toList();

    for (final i in allIndices) {
      if (visibleIndices != null && !visibleIndices.contains(i)) continue;

      if (workspaceTabs.isNotEmpty) {
        final sectionId = _indexToSectionId[i];
        if (sectionId != null && !workspaceTabs.contains(sectionId)) continue;
      }

      if (!authProvider.effectivePermissions.isAdmin) {
        final activeWorkspace = context
            .read<WorkspaceProvider>()
            .activeWorkspace;
        if (activeWorkspace != null) {
          final sectionId = _indexToSectionId[i];
          final module = _sectionIdToModule[sectionId] ?? sectionId;
          final access = activeWorkspace.modulePermissions[module] ?? 'read';
          if (access == 'none') continue;
        }
      }

      result.add(i);
    }
    return result;
  }

  Widget _buildSidebar(
    BuildContext context,
    List<NavigationRailDestination> allDestinations,
    int selectedIndex,
    Function(int) onSelect,
    bool isCollapsed,
  ) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.appUser;
    final visibleNavIndices = _getVisibleNavIndices(context);
    final isDarkChrome = context.watch<ChromeProvider>().isDarkChrome;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: isCollapsed
          ? AppBreakpoints.sidebarCollapsed
          : AppBreakpoints.sidebarExpanded,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0B1220), // slightly deeper at top-left
            Color(0xFF0F172A), // sidebarBg midpoint
            Color(0xFF0C1830), // subtle blue at bottom-right
          ],
          stops: [0.0, 0.55, 1.0],
        ),
        borderRadius: BorderRadius.only(
          topRight: isDarkChrome ? Radius.zero : Radius.circular(AppRadius.xl),
          bottomRight: Radius.circular(AppRadius.xl),
        ),
        boxShadow: AppShadows.sidebar,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Toggle button and Logo row
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 20, 8, 12),
            child: Row(
              children: [
                if (!isCollapsed) ...[
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: 12),
                      child: LogoWidget(
                        height: 48,
                        showTagline: false,
                        lightTheme: true,
                      ),
                    ),
                  ),
                ],
                if (isCollapsed) const Spacer(),
                // Toggle button
                IconButton(
                  icon: Icon(
                    isCollapsed ? Icons.chevron_right : Icons.chevron_left,
                    color: AppColors.sidebarText,
                    size: 20,
                  ),
                  tooltip: isCollapsed ? 'Expand' : 'Collapse',
                  onPressed: _toggleCollapsed,
                ),
              ],
            ),
          ),
          // Workspace Switcher
          if (!isCollapsed)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              child: WorkspaceSwitcher(contentColor: Colors.white),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
            child: Divider(
              height: 1,
              color: AppColors.sidebarDivider.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Navigation Items with section grouping
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              children: _buildSectionedNavItems(
                allDestinations,
                selectedIndex,
                onSelect,
                isCollapsed,
                visibleNavIndices,
              ),
            ),
          ),
          // User profile section at bottom
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
            child: Divider(
              height: 1,
              color: AppColors.sidebarDivider.withValues(alpha: 0.5),
            ),
          ),
          if (currentUser != null)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: PopupMenuButton<String>(
                offset: const Offset(0, -80),
                tooltip: 'Show menu',
                onSelected: (value) {
                  _handleProfileMenuSelection(context, authProvider, value);
                },
                child: Row(
                  children: [
                    UserAvatar(
                      user: currentUser,
                      size: AvatarSize.small,
                      onTap: null, // Menu handles taps
                    ),
                    const SizedBox(width: 12),
                    if (!isCollapsed)
                      Expanded(
                        // Tooltip so the full name + email are visible
                        // when truncated to fit the sidebar column.
                        child: Tooltip(
                          message:
                              '${currentUser.displayName ?? 'User'}\n${currentUser.email}',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                currentUser.displayName ?? 'User',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                  color: AppColors.sidebarTextActive,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                currentUser.email,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.sidebarSectionLabel,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (!isCollapsed)
                      const Icon(
                        Icons.more_vert,
                        size: 20,
                        color: AppColors.sidebarText,
                      ),
                  ],
                ),
                itemBuilder: (context) => _buildProfileMenuEntries(
                  canAccessWorkspaceSettings: _canAccessWorkspaceSettings(
                    authProvider,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildSectionedNavItems(
    List<NavigationRailDestination> allDestinations,
    int selectedIndex,
    Function(int) onSelect,
    bool isCollapsed,
    Set<int> visibleNavIndices,
  ) {
    final widgets = <Widget>[];

    for (final section in _navSections) {
      final sectionIndices = section.indices
          .where((i) => visibleNavIndices.contains(i))
          .toList();
      if (sectionIndices.isEmpty) continue;

      // Section label or divider
      if (widgets.isNotEmpty) {
        if (isCollapsed) {
          widgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
              child: Divider(
                height: 1,
                color: AppColors.sidebarDivider.withValues(alpha: 0.4),
              ),
            ),
          );
        } else {
          widgets.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Text(
                section.label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.sidebarSectionLabel,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          );
        }
      }

      // Nav items for this section
      for (final actualIndex in sectionIndices) {
        final destination = allDestinations[actualIndex];
        final isSelected = selectedIndex == actualIndex;

        Icon icon;
        Text label;

        if (isSelected) {
          icon = destination.selectedIcon as Icon;
        } else {
          icon = destination.icon as Icon;
        }
        label = destination.label as Text;

        Widget leadingWidget = icon;
        final labelText = label.data ?? '';

        final navItem = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 1.5),
          child: Semantics(
            button: true,
            selected: isSelected,
            label: labelText,
            child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: InkWell(
              onTap: () => onSelect(actualIndex),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              hoverColor: AppColors.sidebarHover.withValues(alpha: 0.6),
              splashColor: Colors.white.withValues(alpha: 0.06),
              highlightColor: Colors.white.withValues(alpha: 0.04),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: EdgeInsets.symmetric(
                  horizontal: isCollapsed ? 8.0 : 14.0,
                  vertical: 10.0,
                ),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            AppColors.primary.withAlpha(55),
                            AppColors.primary.withAlpha(28),
                          ],
                        )
                      : null,
                  color: isSelected ? null : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: isSelected
                      ? Border.all(
                          color: AppColors.primary.withAlpha(65),
                          width: 0.5,
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    IconTheme(
                      data: IconThemeData(
                        color: isSelected
                            ? AppColors.secondary
                            : AppColors.sidebarText,
                        size: 20,
                      ),
                      child: leadingWidget,
                    ),
                    if (!isCollapsed) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: DefaultTextStyle(
                          style: TextStyle(
                            color: isSelected
                                ? AppColors.sidebarTextActive
                                : AppColors.sidebarText,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            fontSize: 13.5,
                          ),
                          child: label,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          ),
        );

        // Wrap collapsed items with Tooltip
        if (isCollapsed) {
          widgets.add(
            Tooltip(
              message: (label.data ?? ''),
              preferBelow: false,
              verticalOffset: 0,
              waitDuration: const Duration(milliseconds: 400),
              child: navItem,
            ),
          );
        } else {
          widgets.add(navItem);
        }
      }

      if (section.label == 'HELP' && (kDebugMode || BuildInfo.sha.isNotEmpty)) {
        widgets.add(_buildBuildIndicator(isCollapsed));
      }
    }

    return widgets;
  }

  Widget _buildBuildIndicator(bool isCollapsed) {
    final indicator = Row(
      children: [
        const Icon(
          Icons.build_circle_outlined,
          size: 14,
          color: AppColors.sidebarSectionLabel,
        ),
        if (!isCollapsed) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Build ${BuildInfo.indicatorLabel}',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.sidebarSectionLabel,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );

    final content = Padding(
      padding: EdgeInsets.fromLTRB(isCollapsed ? 18 : 20, 8, 20, 2),
      child: indicator,
    );

    if (isCollapsed) {
      return Tooltip(
        message: BuildInfo.fullLabel,
        preferBelow: false,
        verticalOffset: 0,
        waitDuration: const Duration(milliseconds: 300),
        child: content,
      );
    }
    return content;
  }
}

class _MobileScaffold extends StatefulWidget {
  final int selectedIndex;
  final Function(int) onDestinationSelected;
  final Widget child;

  const _MobileScaffold({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.child,
  });

  @override
  State<_MobileScaffold> createState() => _MobileScaffoldState();
}

class _MobileScaffoldState extends State<_MobileScaffold>
    with SingleTickerProviderStateMixin {
  bool _showQuickAdd = false;
  bool _showMore = false;
  bool _showAccountSection = false;
  bool _showWorkspaceSection = false;
  bool _isSwitchingWorkspace = false;
  bool _isNavVisible = true;
  double _scrollDelta = 0;
  static const _scrollThreshold = 15.0;
  late final AnimationController _navAnimController;
  late final Animation<Offset> _navSlideAnimation;
  final ScrollController _moreScrollController = ScrollController();
  GoRouter? _router;
  String? _lastLoadedUserId;

  @override
  void initState() {
    super.initState();
    _navAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _navSlideAnimation =
        Tween<Offset>(begin: Offset.zero, end: const Offset(0, 1.5)).animate(
          CurvedAnimation(parent: _navAnimController, curve: Curves.easeInOut),
        );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-show nav on any route change (e.g. project sub-tabs)
    _router?.routerDelegate.removeListener(_onRouteChanged);
    _router = GoRouter.of(context);
    _router!.routerDelegate.addListener(_onRouteChanged);

    final currentWorkspaceId = context
        .read<AuthProvider>()
        .appUser
        ?.currentWorkspaceId;
    context.read<WorkspaceProvider>().setCurrentWorkspaceId(currentWorkspaceId);

    // Ensure workspaces are loaded for the workspace switcher
    final userId = context.read<AuthProvider>().appUser?.id;
    if (userId != null && userId != _lastLoadedUserId) {
      _lastLoadedUserId = userId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<WorkspaceProvider>().loadWorkspaces(userId);
        }
      });
    }
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_onRouteChanged);
    _navAnimController.dispose();
    _moreScrollController.dispose();
    super.dispose();
  }

  void _onRouteChanged() {
    _showNav();
  }

  @override
  void didUpdateWidget(covariant _MobileScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-show nav when switching tabs
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _showNav();
    }
  }

  void _showNav() {
    if (!_isNavVisible) {
      _isNavVisible = true;
      _scrollDelta = 0;
      _navAnimController.reverse();
    }
  }

  void _hideNav() {
    if (_isNavVisible) {
      _isNavVisible = false;
      _scrollDelta = 0;
      _navAnimController.forward();
    }
  }

  bool _handleScrollNotification(Notification notification) {
    // Don't hide nav while overlays are open
    if (_showQuickAdd || _showMore) return false;

    if (notification is ScrollUpdateNotification) {
      if (notification.metrics.axis == Axis.horizontal) return false;
      final delta = notification.scrollDelta ?? 0;
      // Reset accumulator on direction change
      if ((_scrollDelta > 0 && delta < 0) || (_scrollDelta < 0 && delta > 0)) {
        _scrollDelta = 0;
      }
      _scrollDelta += delta;

      // Don't hide nav when at the top edge — on iOS the overscroll
      // bounce-back produces positive deltas that would falsely trigger hide.
      final atTop =
          notification.metrics.pixels <= notification.metrics.minScrollExtent;

      if (_scrollDelta > _scrollThreshold && _isNavVisible && !atTop) {
        _hideNav();
      } else if (_scrollDelta < -_scrollThreshold && !_isNavVisible) {
        _showNav();
      }
    } else if (notification is ScrollEndNotification) {
      _scrollDelta = 0;
    }
    return false;
  }

  void _dismiss() => setState(() {
    _showQuickAdd = false;
    _showMore = false;
    _showAccountSection = false;
    _showWorkspaceSection = false;
  });

  bool _isMoreDestinationSelected({
    required bool isClient,
    required AuthProvider authProvider,
    required List<String> workspaceTabs,
  }) {
    bool showTab(String tab) =>
        workspaceTabs.isEmpty || workspaceTabs.contains(tab);
    bool canAccess(String module) =>
        authProvider.effectivePermissions.hasModuleAccess(module, 'read');

    final moreIndices = <int>{
      if (!isClient && showTab('timesheets') && canAccess('team')) 8,
      if (!isClient && showTab('customers') && canAccess('projects')) 4,
      if (!isClient && showTab('vendors') && canAccess('budget')) 7,
      if (!isClient && showTab('team') && canAccess('team')) 9,
      if (!isClient && showTab('files') && canAccess('documents')) 18,
      if (!isClient && showTab('vehicles') && canAccess('settings')) 11,
      if (!isClient && showTab('catalog') && canAccess('budget')) 16,
      if (!isClient && showTab('reports') && canAccess('projects')) 12,
      if (!isClient && showTab('templates') && canAccess('settings')) 17,
      19,
    };

    return moreIndices.contains(widget.selectedIndex);
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.appUser;
    final isClient = authProvider.isClientRole;
    final workspaceTabs = context
        .watch<WorkspaceProvider>()
        .enabledNavigationTabs;

    if (currentUser != null && currentUser.emailVerified == false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/verify-email-pending');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final projectTerminology = context
        .watch<WorkspaceProvider>()
        .projectTerminology;

    return Scaffold(
      appBar: null,
      extendBody: true,
      bottomNavigationBar: SlideTransition(
        position: _navSlideAnimation,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              0,
              12,
              Theme.of(context).platform == TargetPlatform.iOS ? 16 : 8,
            ),
            child: Container(
              height: 70,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.navBarGradientStart,
                    AppColors.navBarGradientEnd,
                  ],
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildNavItem(
                        context,
                        0,
                        Icons.home_outlined,
                        Icons.home,
                        'Home',
                      ),
                    ),
                    Expanded(
                      child: _buildNavItem(
                        context,
                        2,
                        Icons.folder_outlined,
                        Icons.folder,
                        projectTerminology,
                      ),
                    ),
                    Expanded(
                      child: _buildNavItem(
                        context,
                        1,
                        Icons.inbox_outlined,
                        Icons.inbox,
                        'Inbox',
                      ),
                    ),
                    // ── Integrated FAB ──
                    SizedBox(
                      width: 72,
                      child: Center(
                        child: Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.secondary.withValues(
                                  alpha: 0.4,
                                ),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Material(
                            color: AppColors.secondary,
                            shape: const CircleBorder(),
                            child: InkWell(
                              onTap: () => setState(() {
                                _showQuickAdd = !_showQuickAdd;
                                _showMore = false;
                                _showAccountSection = false;
                              }),
                              customBorder: const CircleBorder(),
                              splashColor: Colors.white.withValues(alpha: 0.2),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                transitionBuilder: (child, anim) =>
                                    ScaleTransition(scale: anim, child: child),
                                child: Icon(
                                  _showQuickAdd ? Icons.close : Icons.add,
                                  key: ValueKey(_showQuickAdd),
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: !isClient
                          ? _buildNavItem(
                              context,
                              3,
                              Icons.add_task_outlined,
                              Icons.add_task,
                              'Tasks',
                            )
                          : _buildAiNavItem(context),
                    ),
                    if (!isClient) Expanded(child: _buildAiNavItem(context)),
                    Expanded(
                      child: _buildMoreNavItem(
                        isSelected: _isMoreDestinationSelected(
                          isClient: isClient,
                          authProvider: authProvider,
                          workspaceTabs: workspaceTabs,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      body: NotificationListener<TabSwitchNotification>(
        onNotification: (_) {
          _showNav();
          return true;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: _handleScrollNotification,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final mediaSize = MediaQuery.sizeOf(context);
              final boundedWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : mediaSize.width;
              final boundedHeight = constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : mediaSize.height;

              return SizedBox(
                width: boundedWidth,
                height: boundedHeight,
                child: Stack(
                  children: [
                    Column(
                      children: [
                        SafeArea(
                          bottom: false,
                          child: Material(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                              child: NavBreadcrumbBar(compact: true),
                            ),
                          ),
                        ),
                        Expanded(child: widget.child),
                      ],
                    ),
                    if (_showQuickAdd)
                      _buildQuickAddOverlay(context, authProvider),
                    if (_showMore)
                      _buildMoreOverlay(
                        context,
                        authProvider,
                        isClient,
                        workspaceTabs,
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ── Bottom nav items ───────────────────────────────────────────────────────

  Widget _buildNavItem(
    BuildContext context,
    int index,
    IconData outlinedIcon,
    IconData filledIcon,
    String label,
  ) {
    final isSelected = widget.selectedIndex == index;
    return _NavItemShell(
      onTap: () {
        _dismiss();
        _showNav();
        widget.onDestinationSelected(index);
      },
      isSelected: isSelected,
      icon: isSelected ? filledIcon : outlinedIcon,
      label: label,
    );
  }

  Widget _buildAiNavItem(BuildContext context) {
    return _NavItemShell(
      onTap: () => showAiChatPopup(context),
      isSelected: false,
      icon: Icons.auto_awesome_outlined,
      label: 'AI',
    );
  }

  Widget _buildMoreNavItem({required bool isSelected}) {
    final highlightMore = _showMore || isSelected;

    return _NavItemShell(
      onTap: () => setState(() {
        final nextShowMore = !_showMore;
        _showMore = nextShowMore;
        _showQuickAdd = false;
        if (!nextShowMore) {
          _showAccountSection = false;
        }
      }),
      isSelected: highlightMore,
      icon: _showMore ? Icons.menu_open : Icons.menu,
      label: 'More',
    );
  }

  // ── Quick Add overlay ──────────────────────────────────────────────────────

  /// Returns the project ID if the current route is inside a project, else null.
  String? _currentRouteProjectId(BuildContext context) {
    final uri = safeRouteUri(context).toString();
    final match = RegExp(r'/projects/([^/?#]+)').firstMatch(uri);
    return match?.group(1);
  }

  /// Returns the active tab name if the current route is a project detail page.
  /// Checks both `?tab=budget` query param and `/projects/:id/budget` path.
  String? _currentRouteProjectTab(BuildContext context) {
    final uri = safeRouteUri(context);
    final tabParam = uri.queryParameters['tab'];
    if (tabParam != null) return tabParam;
    // Detect standalone tab routes like /projects/:id/budget
    final path = uri.path;
    final match = RegExp(r'/projects/[^/?#]+/(\w+)').firstMatch(path);
    return match?.group(1);
  }

  Widget _buildQuickAddOverlay(
    BuildContext context,
    AuthProvider authProvider,
  ) {
    final workspaceId = authProvider.appUser?.currentWorkspaceId ?? '';
    final projectTerminology = context
        .read<WorkspaceProvider>()
        .projectTerminology;
    final singularTerm =
        projectTerminology.endsWith('s') && projectTerminology.length > 1
        ? projectTerminology.substring(0, projectTerminology.length - 1)
        : projectTerminology;
    final isField = authProvider.isFieldMode;
    final platformBottomPad = Theme.of(context).platform == TargetPlatform.iOS
        ? 16.0
        : 8.0;
    // Use viewPadding (raw system safe-area) not padding — with extendBody:true
    // the Scaffold inflates MediaQuery.padding.bottom by the full nav bar height,
    // so using padding would double-count platformBottomPad + 70 and create a gap.
    final overlayBottomInset =
        MediaQuery.viewPaddingOf(context).bottom + platformBottomPad + 70;

    // Route context
    final currentUri = safeRouteUri(context).toString();
    final projectId = _currentRouteProjectId(context);
    final currentTab = _currentRouteProjectTab(context);
    final insideProject = projectId != null;
    final onBudgetTab = insideProject && currentTab == 'budget';

    // Task - pre-scoped to the current project when inside one
    final taskAction = _OverlayAction(
      icon: Icons.add_task_outlined,
      label: 'Task',
      color: AppColors.success,
      onTap: () async {
        if (workspaceId.isEmpty) return;
        if (insideProject) {
          showTaskFormPopup(context, projectId: projectId);
        } else {
          final project = await showDialog<Project>(
            context: context,
            builder: (ctx) => ProjectSelectorDialog(workspaceId: workspaceId),
          );
          if (project != null && context.mounted) {
            showTaskFormPopup(context, projectId: project.id);
          }
        }
      },
    );

    final photoAction = _OverlayAction(
      icon: Icons.camera_alt_outlined,
      label: 'Photo',
      color: AppColors.secondary,
      onTap: () async {
        Project? preSelected;
        if (projectId != null) {
          preSelected = await ServiceLocator.projectService.getProject(
            projectId,
          );
        }
        if (context.mounted) {
          showPhotoCaptureAssignDialog(
            context,
            preSelectedProject: preSelected,
          );
        }
      },
    );

    // Budget-tab actions (only shown when on the budget tab of a project)
    final budgetActions = onBudgetTab && workspaceId.isNotEmpty
        ? [
            _OverlayAction(
              icon: Icons.add,
              label: 'Budget Item',
              color: AppColors.success,
              onTap: () => showBudgetItemFormPopup(
                context,
                projectId: projectId,
                workspaceId: workspaceId,
                hierarchyLevel: 0,
                isGroup: false,
              ),
            ),
            _OverlayAction(
              icon: Icons.create_new_folder_outlined,
              label: 'Budget Group',
              color: AppColors.info,
              onTap: () => showBudgetItemFormPopup(
                context,
                projectId: projectId,
                workspaceId: workspaceId,
                hierarchyLevel: 0,
                isGroup: true,
              ),
            ),
          ]
        : <_OverlayAction>[];

    // Reusable action definitions
    final jobAction = _OverlayAction(
      icon: Icons.folder_outlined,
      label: singularTerm,
      color: AppColors.info,
      onTap: () => showProjectFormPopup(context),
    );
    final customerAction = _OverlayAction(
      icon: Icons.person_add_outlined,
      label: 'Customer',
      color: AppColors.warning,
      onTap: () => showCustomerFormPopup(context),
    );
    final messageAction = _OverlayAction(
      icon: Icons.message_outlined,
      label: 'Message',
      color: AppColors.messageAccent,
      onTap: () => showMessagingPopup(context),
    );
    final documentAction = _OverlayAction(
      icon: Icons.receipt_outlined,
      label: 'Document',
      color: AppColors.error,
      onTap: () => context.go('/documents/create'),
    );
    final vendorAction = _OverlayAction(
      icon: Icons.store_outlined,
      label: 'Vendor',
      color: AppColors.financialAccent,
      onTap: () => showVendorFormPopup(context),
    );
    final inviteAction = authProvider.canManageUsers
        ? _OverlayAction(
            icon: Icons.person_add_outlined,
            label: 'Invite',
            color: AppColors.info,
            onTap: () =>
                context.push('/settings/invite?workspaceId=$workspaceId'),
          )
        : null;

    // Context-specific actions
    final vehicleAction = _OverlayAction(
      icon: Icons.directions_car_outlined,
      label: 'Vehicle',
      color: AppColors.info,
      onTap: () => showVehicleFormPopup(context),
    );
    final assetAction = _OverlayAction(
      icon: Icons.inventory_2_outlined,
      label: 'Equipment',
      color: AppColors.info,
      onTap: () => showAssetFormPopup(context),
    );
    final catalogItemAction = _OverlayAction(
      icon: Icons.category_outlined,
      label: 'Catalog Item',
      color: AppColors.financialAccent,
      onTap: () => showCatalogItemFormPopup(context),
    );
    final logTimeAction = _OverlayAction(
      icon: Icons.timer_outlined,
      label: 'Log Time',
      color: AppColors.success,
      onTap: () => showTimeEntryFormDialog(
        context,
        selectedDate: DateTime.now(),
        initialProjectId: insideProject ? projectId : null,
      ),
    );

    // Mobile-only: launch the AR room scan flow. Routes into the current
    // project when we have one; otherwise prompts the user to pick one
    // first, mirroring the Task action's UX.
    final isMobilePlatform = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final scanRoomAction = isMobilePlatform
            ? _OverlayAction(
                icon: Icons.view_in_ar_outlined,
                label: 'Scan Room',
                color: AppColors.secondary,
                onTap: () async {
                  if (workspaceId.isEmpty) return;
                  if (insideProject) {
                    context.push(
                      '/projects/$projectId/plans/scan',
                    );
                  } else {
                    final project = await showDialog<Project>(
                      context: context,
                      builder: (ctx) =>
                          ProjectSelectorDialog(workspaceId: workspaceId),
                    );
                    if (project != null && context.mounted) {
                      context.push('/projects/${project.id}/plans/scan');
                    }
                  }
                },
              )
            : null;

    // Default global list used when no specific context matches
    final globalActions = <_OverlayAction>[
      jobAction,
      taskAction,
      photoAction,
      if (scanRoomAction != null) scanRoomAction,
      customerAction,
      messageAction,
      documentAction,
      vendorAction,
      if (inviteAction != null) inviteAction,
    ];

    List<_OverlayAction> buildContextActions() {
      // Budget tab: focused on budget-specific + scoped task/photo
      if (onBudgetTab) {
        return [...budgetActions, taskAction, photoAction, messageAction, documentAction];
      }

      // Inside a project: scoped actions, no "create job"
      if (insideProject) {
        return [
          taskAction,
          photoAction,
          if (scanRoomAction != null) scanRoomAction,
          messageAction,
          documentAction,
          logTimeAction,
        ];
      }

      // Route-specific ordering
      if (currentUri.startsWith('/time-tracking')) {
        return [logTimeAction, ...globalActions];
      }
      if (currentUri.startsWith('/vehicles')) {
        return [vehicleAction, ...globalActions];
      }
      if ((currentUri.startsWith('/assets') || currentUri.startsWith('/equipment'))) {
        return [assetAction, ...globalActions];
      }
      if (currentUri.startsWith('/catalog')) {
        return [catalogItemAction, ...globalActions];
      }
      if (currentUri.startsWith('/customers')) {
        return [
          customerAction, jobAction, taskAction, photoAction,
          messageAction, documentAction, vendorAction,
          if (inviteAction != null) inviteAction,
        ];
      }
      if (currentUri.startsWith('/vendors')) {
        return [
          vendorAction, jobAction, taskAction, photoAction,
          customerAction, messageAction, documentAction,
          if (inviteAction != null) inviteAction,
        ];
      }
      if (currentUri.startsWith('/tasks')) {
        return [
          taskAction, jobAction, photoAction, customerAction,
          messageAction, documentAction, vendorAction,
          if (inviteAction != null) inviteAction,
        ];
      }
      if (currentUri.startsWith('/team')) {
        return [
          if (inviteAction != null) inviteAction,
          jobAction, taskAction, photoAction,
          customerAction, messageAction, documentAction, vendorAction,
        ];
      }
      if (currentUri.startsWith('/files')) {
        return [
          photoAction, jobAction, taskAction, customerAction,
          messageAction, documentAction, vendorAction,
          if (inviteAction != null) inviteAction,
        ];
      }

      return globalActions;
    }

    final actions = isField
        ? [...budgetActions, taskAction, photoAction]
        : buildContextActions();

    return _GlassOverlay(
      onDismiss: _dismiss,
      alignment: Alignment.bottomCenter,
      insetPadding: EdgeInsets.fromLTRB(12, 12, 12, overlayBottomInset),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add new',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = (constraints.maxWidth - 24) / 3;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: actions.map((a) {
                    return SizedBox(
                      width: itemWidth,
                      child: _buildQuickAddButton(context, a),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAddButton(BuildContext context, _OverlayAction action) {
    return InkWell(
      onTap: () {
        _dismiss();
        action.onTap();
      },
      borderRadius: BorderRadius.circular(AppRadius.r12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.sidebarSurface.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(AppRadius.r12),
          border: Border.all(
            color: AppColors.sidebarDivider.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: action.color.withAlpha(45),
                shape: BoxShape.circle,
              ),
              child: Icon(action.icon, color: action.color, size: 20),
            ),
            const SizedBox(height: 6),
            Text(
              action.label,
              style: const TextStyle(
                color: AppColors.sidebarTextActive,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoreButton(BuildContext context, _OverlayAction action) {
    final isSelected =
        action.destinationIndex != null &&
        widget.selectedIndex == action.destinationIndex;
    final iconColor = isSelected ? AppColors.secondary : AppColors.sidebarText;
    final labelColor = isSelected ? AppColors.secondary : AppColors.sidebarText;

    return InkWell(
      onTap: () {
        _dismiss();
        _showNav();
        action.onTap();
      },
      borderRadius: BorderRadius.circular(AppRadius.r12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.sidebarSurface.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(AppRadius.r12),
          border: Border.all(
            color: AppColors.sidebarDivider.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.secondary.withAlpha(45)
                    : AppColors.sidebarHover.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: Icon(action.icon, color: iconColor, size: 20),
            ),
            const SizedBox(height: 6),
            Text(
              action.label,
              style: TextStyle(
                color: labelColor,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChromeModeTile() {
    final chromeProvider = context.watch<ChromeProvider>();
    final isDarkChrome = chromeProvider.isDarkChrome;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.sidebarSurface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: AppColors.sidebarDivider.withValues(alpha: 0.5),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 2),
        leading: Icon(
          Icons.dark_mode_outlined,
          color: isDarkChrome ? AppColors.secondary : AppColors.sidebarText,
          size: 20,
        ),
        title: const Text(
          'Dark Mode',
          style: TextStyle(
            color: AppColors.sidebarTextActive,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: Switch.adaptive(
          value: isDarkChrome,
          activeThumbColor: AppColors.secondary,
          activeTrackColor: AppColors.secondary.withValues(alpha: 0.35),
          onChanged: (value) {
            chromeProvider.setDarkChrome(value);
          },
        ),
        onTap: () {
          chromeProvider.setDarkChrome(!isDarkChrome);
        },
        dense: true,
        visualDensity: const VisualDensity(vertical: -1),
      ),
    );
  }

  // ── Inline workspace switcher ───────────────────────────────────────────────

  Widget _buildInlineWorkspaceSection(
    AuthProvider authProvider,
    WorkspaceProvider workspaceProvider,
  ) {
    final currentUser = authProvider.appUser;
    if (currentUser == null) return const SizedBox.shrink();

    final currentWorkspaceId = currentUser.currentWorkspaceId;
    final workspaces = workspaceProvider.workspaces;

    // Don't show if only one workspace
    if (workspaces.length <= 1 && !workspaceProvider.isLoading) {
      return const SizedBox.shrink();
    }

    final currentMembership = workspaces
        .where((w) => w.workspaceId == currentWorkspaceId)
        .firstOrNull;
    final currentWorkspaceName =
        currentMembership?.workspaceName ?? 'Current Workspace';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.sidebarSurface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: AppColors.sidebarDivider.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _showWorkspaceSection = !_showWorkspaceSection;
              });
              if (_showWorkspaceSection) {
                Future.delayed(const Duration(milliseconds: 240), () {
                  if (_moreScrollController.hasClients) {
                    _moreScrollController.animateTo(
                      _moreScrollController.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                    );
                  }
                });
              }
            },
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
              child: Row(
                children: [
                  WorkspaceAvatar(
                    avatarUrl: currentMembership?.avatarUrl,
                    workspaceName: currentWorkspaceName,
                    size: WorkspaceAvatarSize.small,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentWorkspaceName,
                          style: const TextStyle(
                            color: AppColors.sidebarTextActive,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Text(
                          'Workspace',
                          style: TextStyle(
                            color: AppColors.sidebarSectionLabel,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isSwitchingWorkspace)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.sidebarText,
                      ),
                    )
                  else
                    AnimatedRotation(
                      turns: _showWorkspaceSection ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      child: const Icon(
                        Icons.expand_more,
                        color: AppColors.sidebarText,
                        size: 22,
                      ),
                    ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: _showWorkspaceSection
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Divider(color: AppColors.sidebarDivider, height: 1),
                      ...workspaces.map((workspace) {
                        final isSelected =
                            workspace.workspaceId == currentWorkspaceId;
                        return ListTile(
                          leading: WorkspaceAvatar(
                            avatarUrl: workspace.avatarUrl,
                            workspaceName: workspace.workspaceName,
                            size: WorkspaceAvatarSize.small,
                          ),
                          title: Text(
                            workspace.workspaceName,
                            style: TextStyle(
                              color: isSelected
                                  ? AppColors.secondary
                                  : AppColors.sidebarTextActive,
                              fontSize: 14,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            workspace.displayRoleName,
                            style: const TextStyle(
                              color: AppColors.sidebarSectionLabel,
                              fontSize: 11,
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check,
                                  size: 18,
                                  color: AppColors.secondary,
                                )
                              : null,
                          onTap: isSelected
                              ? null
                              : () async {
                                  setState(() => _isSwitchingWorkspace = true);
                                  try {
                                    await authProvider.switchWorkspace(
                                      workspace.workspaceId,
                                    );
                                    if (context.mounted) {
                                      _dismiss();
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Error switching workspace: $e',
                                          ),
                                          backgroundColor: AppColors.error,
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(
                                        () => _isSwitchingWorkspace = false,
                                      );
                                    }
                                  }
                                },
                          dense: true,
                          visualDensity: const VisualDensity(vertical: -1),
                        );
                      }),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // ── Inline account section ─────────────────────────────────────────────────

  Widget _buildInlineAccountSection(
    dynamic currentUser,
    List<_OverlayAction> accountItems,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.sidebarSurface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: AppColors.sidebarDivider.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _showAccountSection = !_showAccountSection;
              });
              if (_showAccountSection) {
                // Delay until AnimatedSize finishes expanding (220ms)
                Future.delayed(const Duration(milliseconds: 240), () {
                  if (_moreScrollController.hasClients) {
                    _moreScrollController.animateTo(
                      _moreScrollController.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                    );
                  }
                });
              }
            },
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
              child: Row(
                children: [
                  UserAvatar(
                    user: currentUser,
                    size: AvatarSize.small,
                    onTap: null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentUser.displayName ?? 'User',
                          style: const TextStyle(
                            color: AppColors.sidebarTextActive,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          currentUser.email,
                          style: const TextStyle(
                            color: AppColors.sidebarSectionLabel,
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _showAccountSection ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    child: const Icon(
                      Icons.expand_more,
                      color: AppColors.sidebarText,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: _showAccountSection
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Divider(color: AppColors.sidebarDivider, height: 1),
                      ...accountItems.map((item) {
                        final isSelected =
                            item.destinationIndex != null &&
                            item.destinationIndex! >= 0 &&
                            widget.selectedIndex == item.destinationIndex;
                        return ListTile(
                          leading: Icon(
                            item.icon,
                            color: isSelected
                                ? AppColors.secondary
                                : AppColors.sidebarText,
                            size: 20,
                          ),
                          title: Text(
                            item.label,
                            style: TextStyle(
                              color: isSelected
                                  ? AppColors.secondary
                                  : AppColors.sidebarTextActive,
                              fontSize: 14,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(
                                  Icons.circle,
                                  size: 8,
                                  color: AppColors.secondary,
                                )
                              : null,
                          onTap: item.onTap,
                          dense: true,
                          visualDensity: const VisualDensity(vertical: -1),
                        );
                      }),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // ── More overlay ───────────────────────────────────────────────────────────

  Widget _buildMoreOverlay(
    BuildContext context,
    AuthProvider authProvider,
    bool isClient,
    List<String> workspaceTabs,
  ) {
    final currentUser = authProvider.appUser;
    final platformBottomPad = Theme.of(context).platform == TargetPlatform.iOS
        ? 16.0
        : 8.0;
    final overlayBottomInset =
        MediaQuery.viewPaddingOf(context).bottom + platformBottomPad + 70;
    final overlayMaxHeight =
        (MediaQuery.sizeOf(context).height - overlayBottomInset - 12)
            .clamp(240.0, MediaQuery.sizeOf(context).height)
            .toDouble();

    bool showTab(String tab) =>
        workspaceTabs.isEmpty || workspaceTabs.contains(tab);
    bool canAccess(String module) =>
        authProvider.effectivePermissions.hasModuleAccess(module, 'read');

    final canAccessSettings = _canAccessWorkspaceSettings(authProvider);

    final items = <_OverlayAction>[
      if (!isClient && showTab('timesheets') && canAccess('team'))
        _OverlayAction(
          icon: Icons.access_time,
          label: 'Time',
          color: AppColors.secondary,
          destinationIndex: 9,
          onTap: () => widget.onDestinationSelected(8),
        ),
      if (!isClient && showTab('customers') && canAccess('projects'))
        _OverlayAction(
          icon: Icons.person_add_outlined,
          label: 'Customers',
          color: AppColors.secondary,
          destinationIndex: 4,
          onTap: () => widget.onDestinationSelected(4),
        ),
      if (!isClient && showTab('vendors') && canAccess('budget'))
        _OverlayAction(
          icon: Icons.store_outlined,
          label: 'Vendors',
          color: AppColors.secondary,
          destinationIndex: 7,
          onTap: () => widget.onDestinationSelected(7),
        ),
      if (!isClient && showTab('team') && canAccess('team'))
        _OverlayAction(
          icon: Icons.group_outlined,
          label: 'Team',
          color: AppColors.secondary,
          destinationIndex: 9,
          onTap: () => widget.onDestinationSelected(9),
        ),
      if (!isClient && showTab('files') && canAccess('documents'))
        _OverlayAction(
          icon: Icons.folder_outlined,
          label: 'Files',
          color: AppColors.secondary,
          destinationIndex: 18,
          onTap: () => widget.onDestinationSelected(18),
        ),
      if (!isClient && showTab('vehicles') && canAccess('settings'))
        _OverlayAction(
          icon: Icons.directions_car_outlined,
          label: 'Vehicles',
          color: AppColors.secondary,
          destinationIndex: 11,
          onTap: () => widget.onDestinationSelected(11),
        ),
      if (!isClient && showTab('catalog') && canAccess('budget'))
        _OverlayAction(
          icon: Icons.list_alt_outlined,
          label: 'Catalog',
          color: AppColors.secondary,
          destinationIndex: 16,
          onTap: () => widget.onDestinationSelected(16),
        ),
      if (!isClient && showTab('reports') && canAccess('projects'))
        _OverlayAction(
          icon: Icons.assessment,
          label: 'Reports',
          color: AppColors.secondary,
          destinationIndex: 12,
          onTap: () => widget.onDestinationSelected(12),
        ),
      if (!isClient && showTab('templates') && canAccess('settings'))
        _OverlayAction(
          icon: Icons.file_copy,
          label: 'Templates',
          color: AppColors.secondary,
          destinationIndex: 17,
          onTap: () => widget.onDestinationSelected(17),
        ),
      _OverlayAction(
        icon: Icons.help_outline,
        label: 'Help',
        color: AppColors.secondary,
        destinationIndex: 19,
        onTap: () => widget.onDestinationSelected(19),
      ),
    ];

    final accountItems = <_OverlayAction>[
      _OverlayAction(
        icon: Icons.person_outline,
        label: 'My Profile',
        color: AppColors.secondary,
        destinationIndex: 14,
        onTap: () {
          _dismiss();
          context.go('/profile');
        },
      ),
      if (canAccessSettings)
        _OverlayAction(
          icon: Icons.settings_outlined,
          label: 'Workspace',
          color: AppColors.secondary,
          destinationIndex: 13,
          onTap: () {
            _dismiss();
            context.go('/workspaces/settings');
          },
        ),
      _OverlayAction(
        icon: Icons.smartphone_outlined,
        label: 'Mobile app',
        color: AppColors.secondary,
        destinationIndex: -1,
        onTap: () {
          _dismiss();
          context.go('/apps');
        },
      ),
      _OverlayAction(
        icon: Icons.logout,
        label: 'Logout',
        color: AppColors.secondary,
        destinationIndex: 15,
        onTap: () async {
          _dismiss();
          await authProvider.signOut();
          if (context.mounted) {
            context.pushReplacement('/login');
          }
        },
      ),
    ];

    return _GlassOverlay(
      onDismiss: _dismiss,
      alignment: Alignment.bottomCenter,
      insetPadding: EdgeInsets.fromLTRB(12, 12, 12, overlayBottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: overlayMaxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: SingleChildScrollView(
            controller: _moreScrollController,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'More',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final itemWidth = (constraints.maxWidth - 24) / 3;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: items.map((a) {
                        return SizedBox(
                          width: itemWidth,
                          child: _buildMoreButton(context, a),
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 14),
                _buildChromeModeTile(),
                if (currentUser != null) ...[
                  const SizedBox(height: 14),
                  const Divider(color: AppColors.sidebarDivider, height: 1),
                  const SizedBox(height: 10),
                  _buildInlineWorkspaceSection(
                    authProvider,
                    context.watch<WorkspaceProvider>(),
                  ),
                  const SizedBox(height: 10),
                  _buildInlineAccountSection(currentUser, accountItems),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Shared overlay helpers ─────────────────────────────────────────────────

class _OverlayAction {
  final IconData icon;
  final String label;
  final Color color;
  final int? destinationIndex;
  final VoidCallback onTap;

  const _OverlayAction({
    required this.icon,
    required this.label,
    required this.color,
    this.destinationIndex,
    required this.onTap,
  });
}

class _GlassOverlay extends StatelessWidget {
  final VoidCallback onDismiss;
  final Alignment alignment;
  final Widget child;
  final EdgeInsetsGeometry insetPadding;

  const _GlassOverlay({
    required this.onDismiss,
    required this.alignment,
    required this.child,
    this.insetPadding = const EdgeInsets.all(AppSpacing.md),
  });

  @override
  Widget build(BuildContext context) {
    final panelDecoration = BoxDecoration(
      color: AppColors.sidebarBg.withAlpha(220),
      borderRadius: BorderRadius.circular(AppRadius.r16),
      border: Border.all(
        color: AppColors.sidebarDivider.withValues(alpha: 0.5),
        width: 0.5,
      ),
    );

    final panelContent = Container(decoration: panelDecoration, child: child);

    return GestureDetector(
      onTap: onDismiss,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: Colors.black.withAlpha(110),
        child: Align(
          alignment: alignment,
          child: GestureDetector(
            onTap: () {}, // absorb taps inside panel
            child: Padding(
              padding: insetPadding,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.r16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: panelContent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Shared bottom nav item ──────────────────────────────────────────────────

class _NavItemShell extends StatelessWidget {
  const _NavItemShell({
    required this.onTap,
    required this.isSelected,
    required this.icon,
    required this.label,
  });

  final VoidCallback onTap;
  final bool isSelected;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? AppColors.secondary : AppColors.sidebarText;
    return InkWell(
      onTap: onTap,
      splashColor: AppColors.sidebarHover.withValues(alpha: 0.4),
      child: SizedBox(
        height: 70,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
