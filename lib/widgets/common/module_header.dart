import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Standard top-of-screen header shown on every module index.
///
/// Renders an icon + title row, a short description, and optional trailing
/// actions (e.g. a refresh button) and a bottom slot (typically a `TabBar`).
class ModuleHeader extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String description;
  final List<Widget>? trailing;
  final Widget? bottom;

  const ModuleHeader({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    required this.description,
    this.trailing,
    this.bottom,
  }) : assert(icon != null || leading != null,
            'ModuleHeader requires either an icon or a leading widget');

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeColors.of(context);
    final theme = Theme.of(context);
    return Container(
      color: chrome.background,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              leading ?? Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: chrome.textActive,
                ),
              ),
              if (trailing != null && trailing!.isNotEmpty) ...[
                const Spacer(),
                ...trailing!,
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(color: chrome.text),
          ),
          const SizedBox(height: 8),
          if (bottom != null) bottom!,
        ],
      ),
    );
  }
}
