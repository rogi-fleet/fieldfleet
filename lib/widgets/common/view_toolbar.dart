import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/theme.dart';
import 'view_icon_button.dart';

/// A unified toolbar for all list/grid views.
///
/// Provides a single-row layout with four zones:
///
/// ```
/// 🔍  [══ centerSlot ══]  [quickToggles]  [🔽]
/// ```
///
/// - **Search icon** (left): expands into a text field, pushing center out.
/// - **Center slot**: view-specific segmented toggle (e.g. List/Calendar/Gantt).
/// - **Quick toggles** (right): grouped in a rounded rectangle container.
/// - **Filter icon** (far right): grouped in a rounded rectangle; badge shows count.
class ViewToolbar extends StatefulWidget {
  /// Optional leading widget (e.g. back button) shown before search.
  final Widget? leading;

  /// Hint text shown in the search field when expanded.
  final String searchHint;

  /// Called when the search query changes (debounced).
  final ValueChanged<String> onSearch;

  /// The current search query (for external state sync).
  final String searchQuery;

  /// The main view-mode control (segmented button, tabs, etc.).
  /// Hidden when search is expanded.
  final Widget? centerSlot;

  /// Compact quick-toggle chips shown to the right of the center slot.
  /// Remain visible even when search is expanded.
  final List<Widget> quickToggles;

  /// Number of active advanced filters (shown as badge on filter icon).
  /// Set to 0 to hide the badge. Set to null to hide the filter icon entirely.
  final int? filterCount;

  /// Called when the filter icon is tapped.
  final VoidCallback? onFilterTap;

  /// Debounce duration for search input.
  final Duration debounceDuration;

  /// Whether to show the bottom border.
  final bool showBottomBorder;

  /// Whether the search affordance is shown. Set to false for views that have
  /// no searchable list, so the search box is not an inert dead control.
  final bool showSearch;

  const ViewToolbar({
    super.key,
    this.leading,
    required this.searchHint,
    required this.onSearch,
    this.searchQuery = '',
    this.centerSlot,
    this.quickToggles = const [],
    this.filterCount,
    this.onFilterTap,
    this.debounceDuration = const Duration(milliseconds: 300),
    this.showBottomBorder = true,
    this.showSearch = true,
  });

  @override
  State<ViewToolbar> createState() => _ViewToolbarState();
}

class _ViewToolbarState extends State<ViewToolbar> {
  bool _searchExpanded = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (widget.searchQuery.isNotEmpty) {
      _searchController.text = widget.searchQuery;
      _searchExpanded = true;
    }
  }

  @override
  void didUpdateWidget(covariant ViewToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != _searchController.text) {
      _searchController.text = widget.searchQuery;
      if (widget.searchQuery.isNotEmpty && !_searchExpanded) {
        _searchExpanded = true;
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _expandSearch() {
    setState(() => _searchExpanded = true);
    // Focus after the frame so the text field is mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  void _collapseSearch() {
    _debounce?.cancel();
    _searchController.clear();
    widget.onSearch('');
    setState(() => _searchExpanded = false);
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(widget.debounceDuration, () {
      widget.onSearch(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeColors.of(context);
    final isMobile = AppBreakpoints.isMobileContext(context);
    final hideExtras = _searchExpanded && isMobile;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: chrome.background,
        border: widget.showBottomBorder
            ? Border(bottom: BorderSide(color: chrome.divider))
            : null,
      ),
      child: Row(
        children: [
          // ── Leading widget (e.g. back button) ──
          if (widget.leading != null) ...[
            widget.leading!,
            const SizedBox(width: 4),
          ],

          // ── Search zone (left) ──
          if (_searchExpanded && widget.showSearch) ...[
            Expanded(
              child: SizedBox(
                height: 36,
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  onChanged: _onSearchChanged,
                  style: TextStyle(fontSize: 14, color: chrome.textActive),
                  decoration: InputDecoration(
                    hintText: widget.searchHint,
                    hintStyle: TextStyle(color: chrome.sectionLabel),
                    prefixIcon: Icon(
                      Icons.search,
                      size: 20,
                      color: chrome.text,
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.close, size: 18, color: chrome.text),
                      onPressed: _collapseSearch,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                    ),
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: BorderSide(color: chrome.divider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: BorderSide(color: chrome.divider),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: BorderSide(
                        color: chrome.isDark
                            ? AppColors.primaryLight
                            : AppColors.primary,
                        width: 2,
                      ),
                    ),
                    filled: true,
                    fillColor: chrome.surface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.base,
                      vertical: AppSpacing.sm,
                    ),
                    isDense: true,
                  ),
                ),
              ),
            ),
          ] else ...[
            if (widget.showSearch) ...[
              ViewIconButton(
                icon: Icons.search,
                tooltip: 'Search',
                isSelected: false,
                onTap: _expandSearch,
              ),
              const SizedBox(width: 10),
            ],
            // ── Center slot ──
            if (widget.centerSlot != null) Flexible(child: widget.centerSlot!),
          ],

          // ── Quick toggles (hidden on mobile when search is expanded) ──
          if (widget.quickToggles.isNotEmpty && !hideExtras) ...[
            const SizedBox(width: 10),
            for (int i = 0; i < widget.quickToggles.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              widget.quickToggles[i],
            ],
          ],

          // ── Filter icon (hidden on mobile when search is expanded) ──
          if (widget.filterCount != null && !hideExtras) ...[
            const SizedBox(width: 10),
            _FilterIconButton(
              count: widget.filterCount!,
              onTap: widget.onFilterTap,
            ),
          ],
        ],
      ),
    );
  }
}

/// Filter icon with an optional badge showing the active filter count.
class _FilterIconButton extends StatelessWidget {
  final int count;
  final VoidCallback? onTap;

  const _FilterIconButton({required this.count, this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasActive = count > 0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IgnorePointer(
          ignoring: onTap == null,
          child: Opacity(
            opacity: onTap == null ? 0.5 : 1,
            child: ViewIconButton(
              icon: hasActive ? Icons.filter_alt : Icons.filter_alt_outlined,
              tooltip: 'Filters',
              isSelected: hasActive,
              onTap: () => onTap?.call(),
            ),
          ),
        ),
        if (hasActive)
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xs),
              decoration: const BoxDecoration(
                color: AppColors.secondary,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
