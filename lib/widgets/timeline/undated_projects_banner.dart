import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Warning banner shown above timeline views when projects lack dates.
class UndatedProjectsBanner extends StatelessWidget {
  final int count;

  const UndatedProjectsBanner({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        border: Border(
          bottom: BorderSide(
            color: AppColors.warning.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: AppColors.warningDark),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$count project${count == 1 ? '' : 's'} not shown (no dates set)',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.warningDark,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
