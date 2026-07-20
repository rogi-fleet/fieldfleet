import 'package:flutter/widgets.dart';

/// Responsive breakpoints and sidebar width constants.
abstract final class AppBreakpoints {
  static const double mobile = 600;
  static const double compact = 700;
  static const double tablet = 900;
  static const double desktop = 1200;

  // Sidebar widths
  static const double sidebarExpanded = 240;
  static const double sidebarCollapsed = 72;

  // Top bar
  static const double topBarHeight = 64;

  /// Helpers that accept [BoxConstraints] (from LayoutBuilder) or raw width.
  static bool isMobile(double width) => width < mobile;
  static bool isTablet(double width) => width >= mobile && width < tablet;
  static bool isDesktop(double width) => width >= tablet;
  static bool isWideDesktop(double width) => width >= desktop;

  /// Convenience that works with [MediaQuery].
  static bool isMobileContext(BuildContext context) =>
      MediaQuery.sizeOf(context).width < mobile;
}
