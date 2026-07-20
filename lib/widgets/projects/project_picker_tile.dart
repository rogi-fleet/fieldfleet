import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../models/project.dart';
import '../../models/project_status_theme.dart';
import '../../theme/theme.dart';

/// A reusable project list-item used in project pickers (header dropdown,
/// clock-in bottom sheet, etc.).
class ProjectPickerTile extends StatelessWidget {
  final Project project;
  final bool isCurrent;
  final VoidCallback? onTap;

  const ProjectPickerTile({
    super.key,
    required this.project,
    this.isCurrent = false,
    this.onTap,
  });

  Color _statusColor(ProjectStatus status) {
    return ProjectStatusTheme.color(status);
  }

  @override
  Widget build(BuildContext context) {
    final serial = project.serialNumber?.trim();
    final hasSerial = serial != null && serial.isNotEmpty;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _statusColor(project.status),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.cardBorder,
                  width: 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: project.photoUrl != null
                  ? CachedNetworkImage(
                      imageUrl: project.photoUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        color: AppColors.surfaceAlt,
                        child: const Icon(
                          Icons.image,
                          size: 14,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    )
                  : Container(
                      color: AppColors.surfaceAlt,
                      child: const Icon(
                        Icons.image,
                        size: 14,
                        color: AppColors.textTertiary,
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          project.name,
                          style: TextStyle(
                            fontWeight:
                                isCurrent ? FontWeight.w600 : FontWeight.w400,
                            color: isCurrent
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasSerial) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.textTertiary
                                .withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(AppRadius.xs),
                          ),
                          child: Text(
                            '#$serial',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (project.customerName != null &&
                      project.customerName!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      project.customerName!,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (project.address.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      project.address,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor(project.status)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    child: Text(
                      project.status.displayName,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _statusColor(project.status),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (isCurrent) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.check,
                size: 14,
                color: AppColors.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
