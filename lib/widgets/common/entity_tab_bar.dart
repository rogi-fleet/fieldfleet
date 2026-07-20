import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import '../adaptive_navigation.dart';

/// Describes a single tab rendered by [EntityTabBar].
class EntityTabDefinition {
  final String label;
  final IconData? icon;

  const EntityTabDefinition({required this.label, this.icon});
}

/// Shared detail-screen tab bar, extracted verbatim from the project detail
/// screen (docs/ui_chrome_unification_proposal.md, P2-1).
///
/// Renders the InkWell button row with the 2px bottom-border indicator. On
/// narrow widths it computes how many primary tabs fit and folds the rest
/// into a "More" overflow menu — when the currently-selected tab is hidden in
/// the overflow, the More button shows that tab's name instead. Dispatches
/// [TabSwitchNotification] whenever the selected tab settles, so the mobile
/// scaffold re-shows the bottom navigation bar (see adaptive_navigation.dart).
///
/// Hosted in a box context (e.g. inside a [SliverToBoxAdapter]).
class EntityTabBar extends StatefulWidget {
  final List<EntityTabDefinition> tabs;
  final TabController controller;

  /// Forces compact (mobile) rendering regardless of available width.
  /// When false (default), compact mode kicks in below [AppBreakpoints.tablet].
  final bool compact;

  /// Called when the user picks a tab (button tap or More-menu selection).
  /// When null, the widget calls [TabController.animateTo] itself. Hosts that
  /// do extra work on selection (e.g. updating the route for `?tab=` deep
  /// links, lazy-loading tab content) should pass a callback and animate the
  /// controller there.
  final ValueChanged<int>? onTabSelected;

  const EntityTabBar({
    super.key,
    required this.tabs,
    required this.controller,
    this.compact = false,
    this.onTabSelected,
  });

  @override
  State<EntityTabBar> createState() => _EntityTabBarState();
}

class _EntityTabBarState extends State<EntityTabBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleTabChanged);
  }

  @override
  void didUpdateWidget(covariant EntityTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleTabChanged);
      widget.controller.addListener(_handleTabChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTabChanged);
    super.dispose();
  }

  void _handleTabChanged() {
    if (!mounted) return;
    // Re-render the selection highlight.
    setState(() {});
    if (widget.controller.indexIsChanging) return;
    // Re-shows the mobile bottom navigation bar on tab change.
    TabSwitchNotification().dispatch(context);
  }

  void _selectTab(int index) {
    final onTabSelected = widget.onTabSelected;
    if (onTabSelected != null) {
      onTabSelected(index);
    } else {
      widget.controller.animateTo(index);
    }
  }

  /// Get the tab name for a given tab index
  String _getTabNameForIndex(int index) {
    if (index >= 0 && index < widget.tabs.length) {
      return widget.tabs[index].label;
    }
    return 'More';
  }

  String _getTabName(int index) {
    return _getTabNameForIndex(index);
  }

  double _estimateTabWidth(
    BuildContext context,
    String label, {
    bool compact = false,
  }) {
    final style = TextStyle(
      color: Theme.of(context).colorScheme.onSurface,
      fontWeight: FontWeight.w500,
      fontSize: 14,
    );
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
    )..layout();
    final horizontalPadding = compact ? 24.0 : 28.0;
    return painter.width + horizontalPadding;
  }

  int _computeMobilePrimaryTabCount(BuildContext context, double maxWidth) {
    if (widget.tabs.isEmpty) return 0;
    final moreButtonWidth = 96.0;
    final rightPadding = 8.0;
    var usedWidth = 0.0;
    var count = 0;

    for (var i = 0; i < widget.tabs.length; i++) {
      final tabLabel = _getTabNameForIndex(i);
      final tabWidth = _estimateTabWidth(context, tabLabel, compact: true);
      final hasRemainingTabs = i < widget.tabs.length - 1;
      final requiredWidth =
          usedWidth +
          tabWidth +
          (hasRemainingTabs ? moreButtonWidth : 0) +
          rightPadding;

      if (requiredWidth <= maxWidth) {
        usedWidth += tabWidth;
        count++;
      } else {
        break;
      }
    }

    if (count == 0) return 1;
    return count;
  }

  Widget _buildTabButton(
    BuildContext context,
    int index,
    String label, {
    bool compact = false,
    IconData? icon,
  }) {
    final chrome = ChromeColors.of(context);
    final isSelected = widget.controller.index == index;
    final activeColor = chrome.isDark ? AppColors.secondary : AppColors.primary;
    final fgColor = isSelected ? chrome.textActive : chrome.text;
    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: InkWell(
        onTap: () {
          _selectTab(index);
        },
        hoverColor: chrome.hover,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 14,
            vertical: compact ? 10 : 14,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? activeColor : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: fgColor),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: fgColor,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final chrome = ChromeColors.of(context);
        final isMobile =
            widget.compact || constraints.maxWidth < AppBreakpoints.tablet;
        final primaryTabCount = isMobile
            ? _computeMobilePrimaryTabCount(context, constraints.maxWidth)
            : widget.tabs.length;
        final hasMoreTabs = widget.tabs.length > primaryTabCount;
        final moreTabsStartIndex = primaryTabCount;

        return Container(
          decoration: BoxDecoration(
            color: chrome.background,
            border: chrome.isDark
                ? null
                : Border(
                    top: BorderSide(color: chrome.divider, width: 1),
                    bottom: BorderSide(color: chrome.divider, width: 1),
                  ),
            boxShadow: [
              if (chrome.isDark)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Primary tabs (as many as fit on narrow widths)
                for (int i = 0; i < primaryTabCount; i++)
                  _buildTabButton(
                    context,
                    i,
                    _getTabNameForIndex(i),
                    compact: isMobile,
                    icon: widget.tabs[i].icon,
                  ),
                // Show remaining tabs or More button based on screen size
                if (hasMoreTabs && isMobile) ...[
                  // More button for mobile
                  PopupMenuButton<int>(
                    tooltip: 'More tabs',
                    onSelected: (index) {
                      _selectTab(index);
                    },
                    itemBuilder: (context) => [
                      for (
                        int i = moreTabsStartIndex;
                        i < widget.tabs.length;
                        i++
                      )
                        PopupMenuItem(
                          value: i,
                          child: Row(
                            children: [
                              Icon(
                                widget.tabs[i].icon ?? Icons.tab,
                                size: 20,
                                color: widget.controller.index == i
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                _getTabNameForIndex(i),
                                style: widget.controller.index == i
                                    ? TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        fontWeight: FontWeight.w500,
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        ),
                    ],
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 12 : 16,
                        vertical: isMobile ? 10 : 16,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.controller.index >= moreTabsStartIndex
                                ? _getTabName(widget.controller.index)
                                : 'More',
                            style: TextStyle(
                              color:
                                  widget.controller.index >= moreTabsStartIndex
                                  ? chrome.textActive
                                  : chrome.text,
                              fontWeight:
                                  widget.controller.index >= moreTabsStartIndex
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_drop_down,
                            size: 20,
                            color:
                                widget.controller.index >= moreTabsStartIndex
                                ? chrome.textActive
                                : chrome.text,
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else if (hasMoreTabs) ...[
                  // Desktop: show all remaining tabs
                  for (int i = moreTabsStartIndex; i < widget.tabs.length; i++)
                    _buildTabButton(
                      context,
                      i,
                      _getTabNameForIndex(i),
                      compact: isMobile,
                      icon: widget.tabs[i].icon,
                    ),
                ],
                const SizedBox(width: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}
