import 'package:flutter/material.dart';

import '../../theme/theme.dart';

class EntityArchivedBadge extends StatelessWidget {
  final EdgeInsetsGeometry? margin;

  const EntityArchivedBadge({super.key, this.margin});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.errorLight,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: const Text(
        'Archived',
        style: TextStyle(
          fontSize: 11,
          color: AppColors.errorDark,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
