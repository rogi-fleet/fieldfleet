import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// A small icon button used inside segmented view toggle containers.
///
/// Renders a 34x34 rounded square with an icon. When [isSelected] is true,
/// the icon turns orange; unselected icons use the chrome text color.
class ViewIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isSelected;
  final VoidCallback onTap;

  const ViewIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeColors.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(
            icon,
            size: 20,
            color: isSelected ? AppColors.secondary : chrome.text,
          ),
        ),
      ),
    );
  }
}
