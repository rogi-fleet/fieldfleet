import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Shared chrome for the sticky column-header row used in list/table views.
///
/// Provides consistent height (40px), tinted background, and a border-bottom
/// divider. Pass domain-specific column cells as [children].
class TableHeaderRow extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  /// When true, render an Excel/spreadsheet-style header: denser height,
  /// neutral light-grey background, a stronger bottom rule, and a faint
  /// top rule so the header reads as a structural band rather than a
  /// soft surface tint.
  final bool excelStyle;

  const TableHeaderRow({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    this.excelStyle = false,
  });

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeColors.of(context);
    // Spreadsheet-style header colors. In dark mode we keep the same
    // structural treatment but use the existing dark card surface so the
    // header still reads as a band on a dark scaffold instead of a glaring
    // light strip.
    final Color bg;
    final Color rule;
    if (excelStyle) {
      if (chrome.isDark) {
        bg = const Color(0xFF2A2F36);
        rule = const Color(0xFF3A4047);
      } else {
        bg = const Color(0xFFEDEFF2);
        rule = const Color(0xFFB6BCC4);
      }
    } else {
      bg = chrome.isDark
          ? const Color(0xFFF1F5F9)
          : Theme.of(context).colorScheme.surfaceContainerLowest;
      rule = chrome.isDark
          ? AppColors.cardBorder
          : Theme.of(context).dividerColor.withValues(alpha: 0.6);
    }
    return Container(
      height: excelStyle ? 30 : 40,
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          top: excelStyle ? BorderSide(color: rule) : BorderSide.none,
          bottom: BorderSide(color: rule),
        ),
      ),
      child: Row(children: children),
    );
  }
}
