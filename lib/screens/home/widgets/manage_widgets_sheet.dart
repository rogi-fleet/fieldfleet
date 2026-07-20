import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/workspace_provider.dart';
import '../../../theme/theme.dart';
import '../../../utils/project_terminology.dart';
import '../dashboard_edit_controller.dart';

/// Shared "Manage Widgets" bottom sheet used by the home dashboard and the
/// project Overview tab.
///
/// Widgets are split into a "Shown" and a "Hidden" section so it's obvious
/// where to find a card that was removed with the × button, and each row
/// carries the catalog's one-line description so users can decide what to
/// show without toggling things on and off to find out.
void showManageWidgetsSheet(
  BuildContext context,
  DashboardEditController controller,
) {
  showModalBottomSheet(
    context: context,
    // On desktop a full-width sheet puts the toggles a meter away from the
    // dashboard they affect; cap the width so it reads as a panel.
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (ctx) {
      return ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final hiddenSet = controller.config.hidden.toSet();
          final shown = controller.config.order
              .where((id) => !hiddenSet.contains(id))
              .toList(growable: false);
          final hidden = controller.config.order
              .where(hiddenSet.contains)
              .toList(growable: false);
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Text(
                        'Manage Widgets',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (shown.isNotEmpty)
                          _SectionHeader(label: 'Shown', count: shown.length),
                        for (final id in shown)
                          _WidgetToggleTile(
                            controller: controller,
                            widgetId: id,
                            isVisible: true,
                          ),
                        if (hidden.isNotEmpty)
                          _SectionHeader(
                            label: 'Hidden',
                            count: hidden.length,
                          ),
                        for (final id in hidden)
                          _WidgetToggleTile(
                            controller: controller,
                            widgetId: id,
                            isVisible: false,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      );
    },
  );
}

/// Shared reset-to-defaults confirmation dialog for dashboard grids.
void showResetDashboardConfirmation(
  BuildContext context,
  DashboardEditController controller, {
  String title = 'Reset Dashboard',
}) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: const Text(
        'This will restore all widgets and their positions to the defaults.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            controller.resetDefaults();
            Navigator.of(ctx).pop();
          },
          child: const Text('Reset'),
        ),
      ],
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;

  const _SectionHeader({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Row(
        children: [
          Text(
            '$label ($count)',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(child: Divider(height: 1)),
        ],
      ),
    );
  }
}

class _WidgetToggleTile extends StatelessWidget {
  final DashboardEditController controller;
  final String widgetId;
  final bool isVisible;

  const _WidgetToggleTile({
    required this.controller,
    required this.widgetId,
    required this.isVisible,
  });

  @override
  Widget build(BuildContext context) {
    final meta = controller.catalog.metaFor(widgetId);
    final terminology =
        context.watch<WorkspaceProvider>().projectTerminology;
    final description = meta.description.isEmpty
        ? null
        : substituteProjectTerminology(meta.description, terminology);
    // Sizes are in grid cells (width × height). Surfacing the limits here
    // explains why a resize drag stops responding at some point. Max is
    // uncapped for most widgets, so it's only shown where a cap exists.
    final maxW = meta.maxW;
    final maxH = meta.maxH;
    final maxInfo = (maxW != null && maxH != null)
        ? ' · Max $maxW×$maxH'
        : maxW != null
            ? ' · Max width $maxW'
            : maxH != null
                ? ' · Max height $maxH'
                : '';
    // autoHeight cells track their content height until the user sets an
    // explicit height — worth naming, since it reads like a size cap.
    final autoInfo = meta.autoHeight ? ' · Height fits content' : '';
    final sizeInfo = 'Default ${meta.desktopDefaultW}×${meta.desktopDefaultH}'
        ' · Min ${meta.minW}×${meta.minH}$maxInfo$autoInfo';
    return SwitchListTile(
      secondary: CircleAvatar(
        backgroundColor:
            meta.accentColor.withValues(alpha: isVisible ? 0.1 : 0.05),
        child: Icon(
          meta.icon,
          color: isVisible
              ? meta.accentColor
              : meta.accentColor.withValues(alpha: 0.4),
          size: 20,
        ),
      ),
      title: Text(
        substituteProjectTerminology(meta.label, terminology),
        style: TextStyle(color: isVisible ? null : AppColors.textSecondary),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (description != null)
            Text(
              description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          Text(
            sizeInfo,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
      value: isVisible,
      onChanged: (_) {
        if (isVisible) {
          controller.hideWidget(widgetId);
        } else {
          controller.showWidget(widgetId);
        }
      },
    );
  }
}
