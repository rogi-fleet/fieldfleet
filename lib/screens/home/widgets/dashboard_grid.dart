import 'package:flutter/material.dart';

import '../dashboard_edit_controller.dart';
import 'dashboard_widget_wrapper.dart';

/// Flow-based grid: full-width items get their own row, half-width items pack
/// 2 per row. On mobile (single column), everything is full-width.
class DashboardGrid extends StatelessWidget {
  final DashboardEditController controller;
  final int columns;
  final double gap;
  final Widget Function(String widgetId) widgetBuilder;

  const DashboardGrid({
    super.key,
    required this.controller,
    required this.columns,
    required this.gap,
    required this.widgetBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final visible = controller.visibleOrder;

    if (visible.isEmpty) return const SizedBox.shrink();

    if (columns == 1) {
      return _buildSingleColumn(visible);
    }
    return _buildTwoColumnGrid(visible);
  }

  // ---------------------------------------------------------------------------
  // Single column (mobile)
  // ---------------------------------------------------------------------------

  Widget _buildSingleColumn(List<String> visible) {
    final children = <Widget>[];

    for (var i = 0; i < visible.length; i++) {
      final id = visible[i];
      children.add(
        _buildWidget(
          id,
          index: i,
          total: visible.length,
          fullWidth: true,
        ),
      );
      if (i < visible.length - 1) {
        children.add(SizedBox(height: gap));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  // ---------------------------------------------------------------------------
  // Two-column grid
  // ---------------------------------------------------------------------------

  Widget _buildTwoColumnGrid(List<String> visible) {
    final rows = <_GridRow>[];
    _GridRow? pendingHalf;

    for (var i = 0; i < visible.length; i++) {
      final id = visible[i];
      final size = controller.config.sizeOf(id);
      final isFull = size == 'full';

      if (isFull) {
        if (pendingHalf != null) {
          rows.add(pendingHalf);
          pendingHalf = null;
        }
        rows.add(_GridRow(items: [id], fullWidth: true));
      } else {
        if (pendingHalf == null) {
          pendingHalf = _GridRow(items: [id], fullWidth: false);
        } else {
          pendingHalf.items.add(id);
          rows.add(pendingHalf);
          pendingHalf = null;
        }
      }
    }
    if (pendingHalf != null) {
      rows.add(pendingHalf);
    }

    final children = <Widget>[];
    var flatIndex = 0;

    for (final row in rows) {
      if (row.fullWidth) {
        children.add(
          _buildWidget(
            row.items.first,
            index: flatIndex,
            total: visible.length,
            fullWidth: true,
          ),
        );
        flatIndex++;
      } else {
        final hasPair = row.items.length > 1;
        children.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildWidget(
                  row.items[0],
                  index: flatIndex,
                  total: visible.length,
                  fullWidth: false,
                  collapseButtonOnLeft: true,
                  onMoveRight: hasPair
                      ? () => controller.swap(row.items[0], row.items[1])
                      : null,
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                child: hasPair
                    ? _buildWidget(
                        row.items[1],
                        index: flatIndex + 1,
                        total: visible.length,
                        fullWidth: false,
                        onMoveLeft: () =>
                            controller.swap(row.items[0], row.items[1]),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        );
        flatIndex += row.items.length;
      }

      children.add(SizedBox(height: gap));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  // ---------------------------------------------------------------------------
  // Widget builder
  // ---------------------------------------------------------------------------

  Widget _buildWidget(
    String id, {
    required int index,
    required int total,
    required bool fullWidth,
    bool collapseButtonOnLeft = false,
    VoidCallback? onMoveLeft,
    VoidCallback? onMoveRight,
  }) {
    return DashboardWidgetWrapper(
      widgetId: id,
      meta: controller.catalog.metaFor(id),
      isCollapsed: controller.config.isCollapsed(id),
      editMode: controller.editMode,
      currentSize: fullWidth ? 'full' : controller.config.sizeOf(id),
      onToggleCollapse: () => controller.toggleCollapse(id),
      onRemove: () => controller.hideWidget(id),
      onToggleSize: () => controller.toggleSize(id),
      onMoveLeft: onMoveLeft,
      onMoveRight: onMoveRight,
      onMoveUp: controller.editMode && index > 0
          ? () => controller.moveUp(id)
          : null,
      onMoveDown: controller.editMode && index < total - 1
          ? () => controller.moveDown(id)
          : null,
      collapseButtonOnLeft: collapseButtonOnLeft,
      child: widgetBuilder(id),
    );
  }
}

class _GridRow {
  final List<String> items;
  final bool fullWidth;

  _GridRow({required this.items, required this.fullWidth});
}
