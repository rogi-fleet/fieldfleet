import 'package:flutter/material.dart';
import '../../models/customer_tag.dart';
import '../../theme/theme.dart';

class CustomerTagChip extends StatelessWidget {
  final CustomerTag tag;
  final VoidCallback? onDeleted;
  final bool small;

  const CustomerTagChip({
    super.key,
    required this.tag,
    this.onDeleted,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final tagColor = _parseColor(tag.color);

    if (small) {
      // Compact version without delete button
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: tagColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: tagColor.withOpacity(0.4),
            width: 1,
          ),
        ),
        child: Text(
          tag.name,
          style: TextStyle(
            color: tagColor,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    // Full version with optional delete
    return Chip(
      label: Text(
        tag.name,
        style: TextStyle(
          color: tagColor,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      backgroundColor: tagColor.withOpacity(0.1),
      side: BorderSide(
        color: tagColor.withOpacity(0.3),
        width: 1,
      ),
      deleteIcon: onDeleted != null
          ? Icon(Icons.close, size: 16, color: tagColor)
          : null,
      onDeleted: onDeleted,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Color _parseColor(String hexColor) {
    try {
      String colorStr = hexColor.replaceAll('#', '');
      
      // Handle RGB format (#RGB -> #RRGGBB)
      if (colorStr.length == 3) {
        colorStr = colorStr.split('').map((c) => c + c).join();
      }
      
      // Handle RRGGBB format
      if (colorStr.length == 6) {
        return Color(int.parse('FF$colorStr', radix: 16));
      }
      
      // Handle AARRGGBB format
      if (colorStr.length == 8) {
        return Color(int.parse(colorStr, radix: 16));
      }
      
      // Default to blue if parsing fails
      return AppColors.primary;
    } catch (e) {
      return AppColors.primary;
    }
  }
}
