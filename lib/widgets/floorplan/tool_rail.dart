import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/floorplan/editor_mode.dart';
import '../../services/floorplan/floorplan_editor_controller.dart';
import '../../theme/theme.dart';

/// Tool rail. Vertical by default (desktop / wide layouts), horizontal
/// when [horizontal] is true so it can sit at the bottom of a phone
/// viewport. The structural shift that turns the editor from
/// "AppBar of icons" into something that reads like a drawing tool.
///
/// Tools fall into two categories:
///   - direct: tap to switch to a single mode (Select, Pan, Wall, Door, …)
///   - menu:   tap to pick from a sub-list (Items, Annotations, …)
class ToolRail extends StatelessWidget {
  static const double width = 56;
  static const double height = 56;

  /// When true, lays the buttons out left-to-right and renders the rail
  /// as a horizontal strip — for the bottom of a narrow viewport.
  final bool horizontal;

  /// Extra "More" menu entries appended after Annotate. Used on the
  /// compact (mobile) rail to surface AppBar overflow items (AI
  /// regenerate / edit, Calibrate, Export) where users on phones can
  /// actually find them.
  final List<ToolRailMoreEntry>? more;

  const ToolRail({super.key, this.horizontal = false, this.more});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<FloorplanEditorController>();
    final mode = controller.mode;

    bool isDoorMode() =>
        mode is WaitingDrawingHoleMode &&
        (mode).holePrototype == 'door';
    bool isWindowMode() =>
        mode is WaitingDrawingHoleMode &&
        (mode).holePrototype == 'window';

    final children = <Widget>[
      SizedBox(width: horizontal ? 6 : 0, height: horizontal ? 0 : 6),
      _RailButton(
        icon: Icons.near_me_outlined,
        label: 'Select',
        shortcut: 'V',
        selected: mode is IdleMode,
        horizontal: horizontal,
        onTap: () => controller.setMode(const IdleMode()),
      ),
      _RailButton(
        icon: Icons.pan_tool_alt_outlined,
        label: 'Pan / zoom',
        shortcut: 'H',
        selected: mode is PanMode,
        horizontal: horizontal,
        onTap: () => controller.setMode(const PanMode()),
      ),
      _RailDivider(horizontal: horizontal),
      _RailButton(
        icon: Icons.architecture,
        label: 'Wall',
        shortcut: 'W',
        selected: mode is WaitingDrawingWallMode ||
            mode is DrawingWallMode,
        horizontal: horizontal,
        onTap: () =>
            controller.setMode(const WaitingDrawingWallMode()),
      ),
      _RailButton(
        icon: Icons.sensor_door_outlined,
        label: 'Door',
        shortcut: 'D',
        selected: isDoorMode(),
        horizontal: horizontal,
        onTap: () => controller.setMode(
          const WaitingDrawingHoleMode(holePrototype: 'door'),
        ),
      ),
      _RailButton(
        icon: Icons.window_outlined,
        label: 'Window',
        shortcut: 'N',
        selected: isWindowMode(),
        horizontal: horizontal,
        onTap: () => controller.setMode(
          const WaitingDrawingHoleMode(holePrototype: 'window'),
        ),
      ),
      _RailMenuButton(
        icon: Icons.crop_square_outlined,
        label: 'Room',
        selected: mode is DrawingRectangleRoomMode ||
            mode is TracingRoomMode,
        horizontal: horizontal,
        entries: [
          _MenuEntry(
            icon: Icons.crop_square_outlined,
            label: 'Rectangle room',
            onTap: () => controller
                .setMode(const DrawingRectangleRoomMode()),
          ),
          _MenuEntry(
            icon: Icons.gesture,
            label: 'Trace room',
            onTap: () =>
                controller.setMode(const TracingRoomMode()),
          ),
        ],
      ),
      _RailDivider(horizontal: horizontal),
      _RailMenuButton(
        icon: Icons.chair_outlined,
        label: 'Items',
        selected: mode is PlacingItemMode,
        horizontal: horizontal,
        entries: controller.catalog.all
            .map((e) => _MenuEntry(
                  icon: e.icon,
                  label: e.name,
                  onTap: () => controller.setMode(
                    PlacingItemMode(itemPrototype: e.prototype),
                  ),
                ))
            .toList(),
      ),
      _RailMenuButton(
        icon: Icons.text_fields,
        label: 'Annotate',
        selected: mode is AddingAnnotationMode,
        horizontal: horizontal,
        entries: [
          _MenuEntry(
            icon: Icons.text_fields,
            label: 'Text label',
            onTap: () => controller.setMode(
              const AddingAnnotationMode(annotationKind: 'text'),
            ),
          ),
          _MenuEntry(
            icon: Icons.arrow_forward,
            label: 'Arrow',
            onTap: () => controller.setMode(
              const AddingAnnotationMode(annotationKind: 'arrow'),
            ),
          ),
          _MenuEntry(
            icon: Icons.straighten,
            label: 'Dimension',
            onTap: () => controller.setMode(
              const AddingAnnotationMode(annotationKind: 'dimension'),
            ),
          ),
        ],
      ),
      if (more != null && more!.isNotEmpty) ...[
        _RailDivider(horizontal: horizontal),
        _RailMenuButton(
          icon: Icons.more_horiz,
          label: 'More',
          selected: false,
          horizontal: horizontal,
          entries: more!
              .map((e) => _MenuEntry(
                    icon: e.icon,
                    label: e.label,
                    onTap: e.onTap,
                  ))
              .toList(),
        ),
      ],
      SizedBox(width: horizontal ? 6 : 0, height: horizontal ? 0 : 6),
    ];

    final scrollable = SingleChildScrollView(
      scrollDirection: horizontal ? Axis.horizontal : Axis.vertical,
      child: horizontal
          ? Row(mainAxisSize: MainAxisSize.min, children: children)
          : Column(mainAxisSize: MainAxisSize.min, children: children),
    );

    return Container(
      width: horizontal ? null : width,
      height: horizontal ? height : null,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          right: horizontal
              ? BorderSide.none
              : BorderSide(color: Theme.of(context).dividerColor),
          top: horizontal
              ? BorderSide(color: Theme.of(context).dividerColor)
              : BorderSide.none,
        ),
      ),
      child: scrollable,
    );
  }
}

class _RailButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? shortcut;
  final bool selected;
  final bool horizontal;
  final VoidCallback onTap;

  const _RailButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.horizontal,
    required this.onTap,
    this.shortcut,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurface;
    final accent = selected
        ? Theme.of(context).colorScheme.primary
        : Colors.transparent;
    return Tooltip(
      message: shortcut == null ? label : '$label ($shortcut)',
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: horizontal ? 44 : null,
          height: horizontal ? null : 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              left: horizontal
                  ? BorderSide.none
                  : BorderSide(color: accent, width: 2),
              top: horizontal
                  ? BorderSide(color: accent, width: 2)
                  : BorderSide.none,
            ),
            color: selected
                ? Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.08)
                : null,
          ),
          child: Icon(icon, size: 22, color: color),
        ),
      ),
    );
  }
}

class _RailMenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool horizontal;
  final List<_MenuEntry> entries;

  const _RailMenuButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.horizontal,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurface;
    final accent = selected
        ? Theme.of(context).colorScheme.primary
        : Colors.transparent;
    return PopupMenuButton<int>(
      tooltip: label,
      position: horizontal ? PopupMenuPosition.over : PopupMenuPosition.under,
      onSelected: (i) => entries[i].onTap(),
      itemBuilder: (_) => [
        for (var i = 0; i < entries.length; i++)
          PopupMenuItem<int>(
            value: i,
            child: Row(
              children: [
                Icon(entries[i].icon, size: 16),
                const SizedBox(width: 8),
                Text(entries[i].label),
              ],
            ),
          ),
      ],
      child: Container(
        width: horizontal ? 44 : null,
        height: horizontal ? null : 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            left: horizontal
                ? BorderSide.none
                : BorderSide(color: accent, width: 2),
            top: horizontal
                ? BorderSide(color: accent, width: 2)
                : BorderSide.none,
          ),
          color: selected
              ? Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.08)
              : null,
        ),
        child: Icon(icon, size: 22, color: color),
      ),
    );
  }
}

class _RailDivider extends StatelessWidget {
  final bool horizontal;
  const _RailDivider({required this.horizontal});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: horizontal
          ? const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: 6)
          : const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      child: Container(
        width: horizontal ? 1 : null,
        height: horizontal ? null : 1,
        color: Theme.of(context).dividerColor,
      ),
    );
  }
}

class _MenuEntry {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MenuEntry({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

/// One entry in [ToolRail.more] — used to surface editor-screen
/// actions (AI regenerate, Edit with AI, Calibrate, Export) on the
/// compact rail.
class ToolRailMoreEntry {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const ToolRailMoreEntry({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}
