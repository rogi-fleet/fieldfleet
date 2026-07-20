import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../models/form_template.dart';
import '../../../models/project.dart';
import '../../../providers/workspace_provider.dart';
import '../../../services/service_locator.dart';
import '../../../theme/theme.dart';
import '../../../utils/project_terminology.dart';

/// Shows form templates from the user's active projects that may need filling.
class PendingFormsWidget extends StatelessWidget {
  final String workspaceId;
  final String userId;
  final List<Project>? allProjects;

  const PendingFormsWidget({
    super.key,
    required this.workspaceId,
    required this.userId,
    this.allProjects,
  });

  @override
  Widget build(BuildContext context) {
    final singularTerminology = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: AppSpacing.base),
            StreamBuilder<List<FormTemplate>>(
              stream: ServiceLocator.formService.getFormTemplates(workspaceId),
              builder: (context, snapshot) {
                if (snapshot.hasError) return _buildErrorState();
                if (!snapshot.hasData) return _buildLoadingState();

                // Filter to forms linked to active projects assigned to this user.
                final activeProjectIds = (allProjects ?? <Project>[])
                    .where((p) =>
                        p.status == ProjectStatus.active &&
                        p.teamMemberIds.contains(userId))
                    .map((p) => p.id)
                    .toSet();

                final relevantForms = snapshot.data!.where((form) {
                  if (form.projectId == null) return false;
                  return activeProjectIds.contains(form.projectId);
                }).toList();

                if (relevantForms.isEmpty) return _buildEmptyState();

                final displayForms = relevantForms.take(5).toList();

                return Column(
                  children: displayForms.map((form) {
                    final projectName = allProjects
                            ?.cast<Project?>()
                            .firstWhere(
                              (p) => p!.id == form.projectId,
                              orElse: () => null,
                            )
                            ?.name ??
                        'Unknown $singularTerminology';

                    return _FormRow(
                      form: form,
                      projectName: projectName,
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.warningDark.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: const Icon(
            Icons.assignment,
            color: AppColors.warningDark,
            size: 20,
          ),
        ),
        const SizedBox(width: AppSpacing.iconGap),
        const Expanded(
          child: Text(
            'Pending Forms',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        TextButton(
          onPressed: () => context.go('/forms'),
          child: const Text('View All'),
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return const SizedBox(
      height: 100,
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }

  Widget _buildErrorState() {
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.base),
      child: Text(
        'Unable to load forms',
        style: TextStyle(color: AppColors.textTertiary),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sectionGap),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.assignment_turned_in, size: 48, color: AppColors.cardBorder),
            const SizedBox(height: AppSpacing.iconGap),
            const Text(
              'No pending forms',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 4),
            const Text(
              'All forms are up to date',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormRow extends StatelessWidget {
  final FormTemplate form;
  final String projectName;

  const _FormRow({required this.form, required this.projectName});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => context.go('/forms/${form.id}'),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.iconGap),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.description,
                color: AppColors.warningDark,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.iconGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      form.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      projectName,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.warningDark.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  '${form.fieldCount} fields',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.warningDark,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Icon(
                Icons.chevron_right,
                color: AppColors.textTertiary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
