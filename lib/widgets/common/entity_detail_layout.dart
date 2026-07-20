import 'package:flutter/material.dart';

import '../../theme/theme.dart';

class EntityDetailSectionHeader extends StatelessWidget {
  final String title;

  const EntityDetailSectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: ChromeColors.of(context).scaffoldText,
      ),
    );
  }
}

class EntityDetailCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const EntityDetailCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.all(AppSpacing.base),
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class EntityDetailInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final IconData? actionIcon;
  final String? actionTooltip;
  final int? maxLines;

  const EntityDetailInfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.actionIcon,
    this.actionTooltip,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isInteractive = onTap != null;
    final actionColor = isInteractive
        ? colorScheme.primary
        : colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: onTap,
                  child: Text(
                    value,
                    maxLines: maxLines,
                    overflow: maxLines != null
                        ? TextOverflow.ellipsis
                        : null,
                    style: TextStyle(
                      fontSize: 16,
                      color: actionColor,
                      decoration: isInteractive
                          ? TextDecoration.underline
                          : TextDecoration.none,
                      decorationColor: isInteractive ? actionColor : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (actionIcon != null && onTap != null) ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: onTap,
              icon: Icon(actionIcon, size: 18),
              tooltip: actionTooltip,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }
}

class EntityDetailResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double minCardWidth;
  final double spacing;

  const EntityDetailResponsiveGrid({
    super.key,
    required this.children,
    this.minCardWidth = 280,
    this.spacing = 16,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = ((width + spacing) / (minCardWidth + spacing))
            .floor()
            .clamp(1, children.length);

        final rows = <List<Widget>>[];
        for (var i = 0; i < children.length; i += columns) {
          rows.add(
            children.sublist(i, (i + columns).clamp(0, children.length)),
          );
        }

        return Column(
          children: rows
              .map(
                (row) => Padding(
                  padding: EdgeInsets.only(
                    bottom: row == rows.last ? 0 : spacing,
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < row.length; i++) ...[
                          if (i > 0) SizedBox(width: spacing),
                          Expanded(child: row[i]),
                        ],
                        for (var i = row.length; i < columns; i++) ...[
                          SizedBox(width: spacing),
                          const Expanded(child: SizedBox.shrink()),
                        ],
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}
