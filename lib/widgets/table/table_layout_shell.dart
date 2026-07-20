import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Shared shell for wide, horizontally-scrollable table layouts.
class TableLayoutShell extends StatefulWidget {
  final Widget header;
  final Widget body;
  final Widget? topControls;
  final Widget? footer;
  final double minTableWidth;
  final bool showHorizontalScrollHint;
  final EdgeInsetsGeometry horizontalHintPadding;
  final bool showHeaderDivider;

  const TableLayoutShell({
    super.key,
    required this.header,
    required this.body,
    this.topControls,
    this.footer,
    this.minTableWidth = 1100,
    this.showHorizontalScrollHint = true,
    this.horizontalHintPadding = EdgeInsets.zero,
    this.showHeaderDivider = true,
  });

  @override
  State<TableLayoutShell> createState() => _TableLayoutShellState();
}

class _TableLayoutShellState extends State<TableLayoutShell> {
  late final ScrollController _horizontalScrollController;
  late final ScrollController _footerScrollController;

  @override
  void initState() {
    super.initState();
    _horizontalScrollController = ScrollController();
    _footerScrollController = ScrollController();
    _horizontalScrollController.addListener(_syncFooterScroll);
  }

  void _syncFooterScroll() {
    if (_footerScrollController.hasClients) {
      _footerScrollController.jumpTo(_horizontalScrollController.offset);
    }
  }

  @override
  void dispose() {
    _horizontalScrollController.removeListener(_syncFooterScroll);
    _horizontalScrollController.dispose();
    _footerScrollController.dispose();
    super.dispose();
  }

  Widget _buildScrollableTable({
    required double tableWidth,
    required bool hasBoundedHeight,
    required bool needsHorizontalScroll,
  }) {
    final scrollableBody = Scrollbar(
      controller: _horizontalScrollController,
      thumbVisibility: needsHorizontalScroll,
      trackVisibility: needsHorizontalScroll,
      notificationPredicate: (notification) =>
          notification.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        controller: _horizontalScrollController,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: tableWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              widget.header,
              if (widget.showHeaderDivider) const Divider(height: 1),
              if (hasBoundedHeight)
                Expanded(child: widget.body)
              else
                widget.body,
            ],
          ),
        ),
      ),
    );

    if (widget.footer == null) {
      return scrollableBody;
    }

    // Footer is placed outside the scrollbar's scroll view so the scrollbar
    // track never overlaps it. A linked controller keeps it in sync.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasBoundedHeight) Expanded(child: scrollableBody) else scrollableBody,
        SingleChildScrollView(
          controller: _footerScrollController,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: SizedBox(
            width: tableWidth,
            child: widget.footer!,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeColors.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedHeight = constraints.hasBoundedHeight;
        final tableWidth = constraints.maxWidth > widget.minTableWidth
            ? constraints.maxWidth
            : widget.minTableWidth;
        final needsHorizontalScroll = tableWidth > constraints.maxWidth;

        Widget tableContent = _buildScrollableTable(
          tableWidth: tableWidth,
          hasBoundedHeight: hasBoundedHeight,
          needsHorizontalScroll: needsHorizontalScroll,
        );

        // In dark mode, wrap the table area in a rounded card-like container
        // so white rows float on the dark scaffold with visual separation.
        if (chrome.isDark) {
          tableContent = Container(
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x30000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: hasBoundedHeight
                ? tableContent
                : tableContent,
          );
        }

        return Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Toolbar stays stationary — does NOT scroll with the table
                if (widget.topControls != null) widget.topControls!,
                if (hasBoundedHeight)
                  Expanded(child: tableContent)
                else
                  tableContent,
              ],
            ),
            if (needsHorizontalScroll && widget.showHorizontalScrollHint)
              Positioned.fill(
                child: IgnorePointer(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: widget.horizontalHintPadding,
                      child: Container(
                        width: 32,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              AppColors.surface.withValues(alpha: 0),
                              AppColors.surface.withValues(alpha: 0.85),
                            ],
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.chevron_right,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
