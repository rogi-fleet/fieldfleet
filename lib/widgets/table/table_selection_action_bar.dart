import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Shared selection action bar used by table/list screens when rows are selected.
class TableSelectionActionBar extends StatelessWidget {
  const TableSelectionActionBar({
    super.key,
    required this.selectedCount,
    this.leadingDetails = const [],
    this.actions = const [],
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
    this.backgroundOpacity = 0.08,
    this.detailSpacing = 12,
    this.actionSpacing = 8,
  });

  final int selectedCount;
  final List<Widget> leadingDetails;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;
  final double backgroundOpacity;
  final double detailSpacing;
  final double actionSpacing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final selectedChip = Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(AppRadius.r16),
      ),
      child: Text(
        '$selectedCount selected',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );

    final compactLeadingChildren = <Widget>[selectedChip, ...leadingDetails];
    final desktopLeadingChildren = <Widget>[selectedChip];
    for (final detail in leadingDetails) {
      desktopLeadingChildren.add(SizedBox(width: detailSpacing));
      desktopLeadingChildren.add(detail);
    }

    final desktopTrailingChildren = <Widget>[];
    for (var i = 0; i < actions.length; i++) {
      if (i > 0) {
        desktopTrailingChildren.add(SizedBox(width: actionSpacing));
      }
      desktopTrailingChildren.add(actions[i]);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 720;

        return Container(
          padding: padding,
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: backgroundOpacity),
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: isCompact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: detailSpacing,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: compactLeadingChildren,
                    ),
                    if (actions.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: actionSpacing,
                        runSpacing: 8,
                        children: actions,
                      ),
                    ],
                  ],
                )
              : Row(
                  children: [
                    ...desktopLeadingChildren,
                    const Spacer(),
                    ...desktopTrailingChildren,
                  ],
                ),
        );
      },
    );
  }
}
