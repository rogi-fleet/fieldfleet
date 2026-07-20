import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/theme.dart';

class ProjectActionButtons extends StatelessWidget {
  final String projectId;

  const ProjectActionButtons({
    super.key,
    required this.projectId,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ActionButton(
          icon: Icons.receipt_long,
          label: 'Invoices',
          onPressed: () => context.push('/projects/$projectId?tab=financials'),
        ),
        _ActionButton(
          icon: Icons.auto_awesome,
          label: 'AI Schedule',
          isAi: true,
          onPressed: () => context.push('/projects/$projectId/schedule'),
        ),
        _ActionButton(
          icon: Icons.access_time,
          label: 'Time',
          onPressed: () => context.push('/time-tracking?projectId=$projectId'),
        ),
        _ActionButton(
          icon: Icons.attach_money,
          label: 'Budget',
          onPressed: () => context.push('/projects/$projectId/budget'),
        ),
        _ActionButton(
          icon: Icons.architecture,
          label: 'Plans',
          onPressed: () => context.push('/projects/$projectId/plans'),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool isAi;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isAi = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isAi) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: FilledButton.styleFrom(
          foregroundColor: AppColors.secondaryDark,
          backgroundColor: AppColors.secondarySurface,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          minimumSize: const Size(0, 36),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        minimumSize: const Size(0, 36),
      ),
    );
  }
}
