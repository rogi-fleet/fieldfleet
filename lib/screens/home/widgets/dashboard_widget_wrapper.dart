import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/workspace_provider.dart';
import '../../../theme/theme.dart';
import '../../../utils/project_terminology.dart';
import '../dashboard_widget_catalog.dart';
import 'edit_mode_overlay.dart';

/// Wraps each dashboard widget Card with collapse/expand + edit mode overlay.
class DashboardWidgetWrapper extends StatelessWidget {
  final String widgetId;
  final DashboardWidgetMeta meta;
  final Widget child;
  final bool isCollapsed;
  final bool editMode;
  final String currentSize;
  final VoidCallback onToggleCollapse;
  final VoidCallback onRemove;
  final VoidCallback onToggleSize;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final bool collapseButtonOnLeft;
  // When false, the floating collapse/expand chevron is suppressed. Used by
  // the v3 grid where the cell has a fixed height — collapsing would leave a
  // dead empty zone, so the chevron isn't shown.
  final bool showCollapseButton;

  const DashboardWidgetWrapper({
    super.key,
    required this.widgetId,
    required this.meta,
    required this.child,
    required this.isCollapsed,
    required this.editMode,
    required this.currentSize,
    required this.onToggleCollapse,
    required this.onRemove,
    required this.onToggleSize,
    this.onMoveLeft,
    this.onMoveRight,
    this.onMoveUp,
    this.onMoveDown,
    this.collapseButtonOnLeft = false,
    this.showCollapseButton = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (isCollapsed && !editMode) {
      content = _CollapsedHeader(meta: meta, onExpand: onToggleCollapse);
    } else {
      content = Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          if (!editMode && showCollapseButton)
            Positioned(
              top: -10,
              right: collapseButtonOnLeft ? null : AppSpacing.base,
              left: collapseButtonOnLeft ? AppSpacing.base : null,
              child: _ExpandedHeader(onCollapse: onToggleCollapse),
            ),
        ],
      );
    }

    if (editMode) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          content,
          Positioned.fill(
            child: EditModeOverlay(
              widgetId: widgetId,
              currentSize: currentSize,
              onRemove: onRemove,
              onToggleSize: onToggleSize,
              onMoveLeft: onMoveLeft,
              onMoveRight: onMoveRight,
              onMoveUp: onMoveUp,
              onMoveDown: onMoveDown,
            ),
          ),
        ],
      );
    }

    return content;
  }
}

class _CollapsedHeader extends StatelessWidget {
  final DashboardWidgetMeta meta;
  final VoidCallback onExpand;

  const _CollapsedHeader({required this.meta, required this.onExpand});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onExpand,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Icon(meta.icon, size: 20, color: meta.accentColor),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  substituteProjectTerminology(
                    meta.label,
                    context.watch<WorkspaceProvider>().projectTerminology,
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              const Icon(
                Icons.expand_more,
                size: 20,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpandedHeader extends StatelessWidget {
  final VoidCallback onCollapse;

  const _ExpandedHeader({required this.onCollapse});

  @override
  Widget build(BuildContext context) {
    final borderColor = AppColors.cardBorder.withValues(alpha: 0.7);
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt.withValues(alpha: 0.96),
          shape: BoxShape.circle,
          border: Border.all(color: borderColor),
          boxShadow: const [
            BoxShadow(
              color: Color(0x120F172A),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: InkWell(
          onTap: onCollapse,
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(
              Icons.keyboard_arrow_up,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
