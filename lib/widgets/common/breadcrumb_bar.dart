import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// A breadcrumb item representing one level in the navigation hierarchy.
class BreadcrumbItem {
  final String label;
  final VoidCallback? onTap;

  const BreadcrumbItem({required this.label, this.onTap});
}

/// A lightweight breadcrumb bar for showing navigation context.
///
/// Items are rendered left-to-right with chevron separators.
/// All items except the last are tappable links.
class BreadcrumbBar extends StatelessWidget {
  final List<BreadcrumbItem> items;
  final EdgeInsetsGeometry padding;

  const BreadcrumbBar({
    super.key,
    required this.items,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
  });

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeColors.of(context);

    return Padding(
      padding: padding,
      child: Row(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: chrome.scaffoldTextSecondary,
                ),
              ),
            if (i < items.length - 1 && items[i].onTap != null)
              InkWell(
                onTap: items[i].onTap,
                borderRadius: BorderRadius.circular(AppRadius.xs),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: 2,
                  ),
                  child: Text(
                    items[i].label,
                    style: TextStyle(
                      fontSize: 13,
                      color: chrome.scaffoldAccent,
                    ),
                  ),
                ),
              )
            else
              Text(
                items[i].label,
                style: TextStyle(
                  fontSize: 13,
                  color: chrome.scaffoldTextSecondary,
                  fontWeight: i == items.length - 1
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
