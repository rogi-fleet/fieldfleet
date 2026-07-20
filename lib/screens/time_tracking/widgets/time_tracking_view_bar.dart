import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../theme/app_breakpoints.dart';
import '../../../widgets/common/view_icon_button.dart';
import '../../../widgets/common/view_toolbar.dart';

/// The view types available in the time tracking section.
enum TimeTrackingView {
  dashboard('/time-tracking/dashboard', Icons.dashboard_outlined, 'Dashboard'),
  clock('/time-tracking', Icons.timer_outlined, 'Clock In'),
  timesheet('/time-tracking/timesheet', Icons.calendar_today_outlined, 'Timesheet'),
  weekly('/time-tracking/weekly', Icons.calendar_view_week_outlined, 'Weekly'),
  approvals('/time-tracking/approvals', Icons.fact_check_outlined, 'Approvals'),
  employees('/time-tracking/employees', Icons.people_outlined, 'Employees');

  final String path;
  final IconData icon;
  final String label;
  const TimeTrackingView(this.path, this.icon, this.label);

  /// Whether this view is admin-only.
  bool get adminOnly =>
      this == TimeTrackingView.dashboard ||
      this == TimeTrackingView.approvals ||
      this == TimeTrackingView.employees;
}

/// Shared toolbar for all time tracking screens.
///
/// Shows a [ViewToolbar] with view-mode icons, optional search,
/// and optional quick toggles. Navigates between time tracking routes.
class TimeTrackingViewBar extends StatelessWidget {
  final TimeTrackingView currentView;

  /// Optional search callback. Pass null to hide search.
  final ValueChanged<String>? onSearch;
  final String searchQuery;
  final String searchHint;

  /// Extra quick-toggle widgets shown to the right of the view icons.
  final List<Widget> quickToggles;

  /// Filter count badge. Null hides the filter icon.
  final int? filterCount;
  final VoidCallback? onFilterTap;

  /// When provided, tapping a view icon invokes this callback instead of
  /// navigating via go_router. Used when the toolbar is embedded inside
  /// another context (e.g., a project detail tab) so switching views
  /// swaps the inner content without leaving the host screen.
  final ValueChanged<TimeTrackingView>? onViewChanged;

  const TimeTrackingViewBar({
    super.key,
    required this.currentView,
    this.onSearch,
    this.searchQuery = '',
    this.searchHint = 'Search...',
    this.quickToggles = const [],
    this.filterCount,
    this.onFilterTap,
    this.onViewChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthProvider>().canManageUsers;
    final isMobile = AppBreakpoints.isMobileContext(context);

    return ViewToolbar(
      leading: isMobile && onViewChanged == null
          ? IconButton(
              icon: const Icon(Icons.arrow_back, size: 20),
              onPressed: () => context.go('/'),
              tooltip: 'Back',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            )
          : null,
      searchHint: searchHint,
      searchQuery: searchQuery,
      onSearch: onSearch ?? (_) {},
      centerSlot: _buildViewIcons(context, isAdmin),
      quickToggles: quickToggles,
      filterCount: filterCount,
      onFilterTap: onFilterTap,
    );
  }

  Widget _buildViewIcons(BuildContext context, bool isAdmin) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final view in TimeTrackingView.values)
          if (!view.adminOnly || isAdmin)
            ViewIconButton(
              icon: view.icon,
              tooltip: view.label,
              isSelected: currentView == view,
              onTap: () {
                if (currentView == view) return;
                if (onViewChanged != null) {
                  onViewChanged!(view);
                } else {
                  context.go(view.path);
                }
              },
            ),
      ],
    );
  }
}
