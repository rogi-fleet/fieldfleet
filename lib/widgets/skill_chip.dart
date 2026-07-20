import 'package:flutter/material.dart';
import '../models/skill.dart';
import '../theme/theme.dart';

/// Widget to display a skill as a colored chip
class SkillChip extends StatelessWidget {
  final Skill skill;
  final bool showDelete;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;
  final bool isCompact;

  const SkillChip({
    super.key,
    required this.skill,
    this.showDelete = false,
    this.onDelete,
    this.onTap,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = skill.color;
    final textColor = _getContrastingTextColor(chipColor);

    if (isCompact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: chipColor.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(AppRadius.xs),
          border: Border.all(color: chipColor.withValues(alpha: 0.5), width: 1),
        ),
        child: Text(
          skill.name,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: chipColor,
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Chip(
        label: Text(
          skill.name,
          style: TextStyle(
            color: textColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: chipColor.withValues(alpha: 0.8),
        deleteIcon: showDelete
            ? Icon(Icons.close, size: 16, color: textColor)
            : null,
        onDeleted: showDelete ? onDelete : null,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        labelPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      ),
    );
  }

  Color _getContrastingTextColor(Color backgroundColor) {
    // Calculate luminance and return white or black
    final luminance = backgroundColor.computeLuminance();
    return luminance > 0.5 ? Colors.black87 : Colors.white;
  }
}

/// Widget to display skill match indicator (e.g., "2/3 skills")
class SkillMatchBadge extends StatelessWidget {
  final int matchingSkills;
  final int totalRequired;
  final bool isCompact;

  const SkillMatchBadge({
    super.key,
    required this.matchingSkills,
    required this.totalRequired,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (totalRequired == 0) return const SizedBox.shrink();

    final matchRatio = matchingSkills / totalRequired;
    final Color badgeColor;
    if (matchRatio >= 1.0) {
      badgeColor = AppColors.success;
    } else if (matchRatio >= 0.5) {
      badgeColor = AppColors.warning;
    } else {
      badgeColor = AppColors.textTertiary;
    }

    if (isCompact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 1),
        decoration: BoxDecoration(
          color: badgeColor.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        child: Text(
          '$matchingSkills/$totalRequired',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: badgeColor,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            matchRatio >= 1.0 ? Icons.check_circle : Icons.build,
            size: 12,
            color: badgeColor,
          ),
          const SizedBox(width: 3),
          Text(
            '$matchingSkills/$totalRequired skills',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: badgeColor,
            ),
          ),
        ],
      ),
    );
  }
}
