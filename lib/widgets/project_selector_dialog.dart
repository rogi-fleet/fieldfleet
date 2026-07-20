import 'package:flutter/material.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_header.dart';
import 'package:go_router/go_router.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:provider/provider.dart';
import '../models/project.dart';
import '../models/project_status_theme.dart';
import '../providers/workspace_provider.dart';
import '../services/service_locator.dart';
import '../theme/theme.dart';
import '../utils/address_formatter.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

class ProjectSelectorDialog extends StatefulWidget {
  final String workspaceId;
  final String? currentProjectId;

  const ProjectSelectorDialog({
    super.key,
    required this.workspaceId,
    this.currentProjectId,
  });

  @override
  State<ProjectSelectorDialog> createState() => _ProjectSelectorDialogState();
}

class _ProjectSelectorDialogState extends State<ProjectSelectorDialog> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final projectService = ServiceLocator.projectService;
    final projectTerminology = context
        .watch<WorkspaceProvider>()
        .projectTerminology;
    final singularTerminology = _getSingularTerminology(projectTerminology);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r16)),
      child: Container(
        width: 640,
        height: 680,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.r16),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.r16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FormPopupHeader(
                icon: Icons.search,
                title: 'Select $singularTerminology',
                onClose: () => Navigator.pop(context),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
            StackedField(
              label: 'Search ${projectTerminology.toLowerCase()}',
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Name, serial, address, customer, contact, or PO',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() => _searchQuery = value.toLowerCase());
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Search by name, serial number, address, customer, primary contact, or PO.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<List<Project>>(
                stream: projectService.getProjects(widget.workspaceId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: SelectableText(
                        UserFacingError.uiMessage(
                          snapshot.error,
                          action: 'load data',
                        ),
                      ),
                    );
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    // First-run dead-end: invoking +New > Invoice / Task in
                    // an empty workspace landed users here with no way out.
                    // Give them a one-click path to create the first record
                    // and resume what they were doing.
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.folder_open,
                            size: 56,
                            color: AppColors.textTertiary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No ${projectTerminology.toLowerCase()} yet',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'You need to create a '
                            '${_getSingularTerminology(projectTerminology).toLowerCase()} '
                            'first.',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            icon: const Icon(Icons.add),
                            label: Text(
                              'Create '
                              '${_getSingularTerminology(projectTerminology)}',
                            ),
                            onPressed: () {
                              Navigator.pop(context);
                              context.go('/projects/new');
                            },
                          ),
                        ],
                      ),
                    );
                  }

                  final projects = snapshot.data!
                      .where(_matchesProjectSearch)
                      .toList();

                  if (projects.isEmpty) {
                    return Center(
                      child: Text(
                        'No matching ${projectTerminology.toLowerCase()}',
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: projects.length,
                    itemBuilder: (context, index) {
                      final project = projects[index];
                      final isSelected = project.id == widget.currentProjectId;

                      return _buildProjectTile(
                        context,
                        project: project,
                        isSelected: isSelected,
                      );
                    },
                  );
                },
              ),
            ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getSingularTerminology(String plural) {
    if (plural.endsWith('s') && plural.length > 1) {
      return plural.substring(0, plural.length - 1);
    }
    return plural;
  }

  bool _matchesProjectSearch(Project project) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return true;

    final normalizedQuery = _normalizeIdentifier(query);
    final fallbackShortId = project.id.length > 6
        ? project.id.substring(0, 6)
        : project.id;

    final textMatches =
        project.name.toLowerCase().contains(query) ||
        project.address.toLowerCase().contains(query) ||
        (project.description?.toLowerCase().contains(query) ?? false) ||
        (project.customerName?.toLowerCase().contains(query) ?? false) ||
        (project.primaryContactName?.toLowerCase().contains(query) ?? false) ||
        (project.purchaseOrderNumber?.toLowerCase().contains(query) ?? false) ||
        (project.serialNumber?.toLowerCase().contains(query) ?? false);

    if (textMatches) return true;
    if (normalizedQuery.isEmpty) return false;

    final identifierCandidates = <String>{
      if (project.serialNumber?.trim().isNotEmpty ?? false)
        project.serialNumber!.trim(),
      if (project.serialNumber?.trim().isNotEmpty ?? false)
        '#${project.serialNumber!.trim().replaceFirst(RegExp(r'^#'), '')}',
      fallbackShortId,
      '#$fallbackShortId',
    };

    return identifierCandidates.any(
      (candidate) => _normalizeIdentifier(candidate).contains(normalizedQuery),
    );
  }

  String _normalizeIdentifier(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  Widget _buildProjectTile(
    BuildContext context, {
    required Project project,
    required bool isSelected,
  }) {
    final serialLabel = _projectSerialLabel(project);
    final condensedAddress = AddressFormatter.condense(project.address);
    final customerName = project.customerName?.trim();
    final poNumber = project.purchaseOrderNumber?.trim();
    final teamCount = project.teamMemberIds.length;
    final statusColor = _getProjectColor(project.status);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.r16),
          onTap: () => Navigator.pop(context, project),
          child: Ink(
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.08)
                  : Theme.of(context).colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppRadius.r16),
              border: Border.all(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.28)
                    : AppColors.cardBorder,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: ProjectStatusTheme.colorLight(project.status),
                      borderRadius: BorderRadius.circular(AppRadius.r12),
                    ),
                    child: Icon(
                      _getProjectIcon(project.status),
                      color: statusColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                project.name,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            if (serialLabel != null) ...[
                              const SizedBox(width: 8),
                              _buildMetaChip(
                                label: serialLabel,
                                icon: Icons.tag_outlined,
                                backgroundColor: AppColors.surfaceAlt
                                    .withValues(alpha: 0.8),
                                foregroundColor: AppColors.textSecondary,
                              ),
                            ],
                          ],
                        ),
                        if (condensedAddress.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            condensedAddress,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildMetaChip(
                              label: project.status.displayName,
                              icon: _getProjectIcon(project.status),
                              backgroundColor: ProjectStatusTheme.colorLight(
                                project.status,
                              ),
                              foregroundColor: ProjectStatusTheme.colorDark(
                                project.status,
                              ),
                            ),
                            if (customerName != null && customerName.isNotEmpty)
                              _buildMetaChip(
                                label: _truncate(customerName),
                                icon: Icons.person_outline,
                              ),
                            if (teamCount > 0)
                              _buildMetaChip(
                                label: '$teamCount team',
                                icon: Icons.group_outlined,
                              ),
                            if (poNumber != null && poNumber.isNotEmpty)
                              _buildMetaChip(
                                label: 'PO ${_truncate(poNumber, max: 18)}',
                                icon: Icons.confirmation_number_outlined,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: 12),
                    const Icon(Icons.check_circle, color: AppColors.success),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetaChip({
    required String label,
    required IconData icon,
    Color? backgroundColor,
    Color? foregroundColor,
  }) {
    final chipBackground =
        backgroundColor ?? AppColors.surfaceAlt.withValues(alpha: 0.8);
    final chipForeground = foregroundColor ?? AppColors.textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: chipBackground,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: chipForeground),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: chipForeground,
            ),
          ),
        ],
      ),
    );
  }

  String _truncate(String value, {int max = 28}) {
    if (value.length <= max) return value;
    return '${value.substring(0, max - 1)}...';
  }

  String? _projectSerialLabel(Project project) {
    final serial = project.serialNumber?.trim();
    if (serial == null || serial.isEmpty) return null;
    return '#${serial.replaceFirst(RegExp(r'^#'), '')}';
  }

  IconData _getProjectIcon(ProjectStatus status) {
    return ProjectStatusTheme.icon(status);
  }

  Color _getProjectColor(ProjectStatus status) {
    return ProjectStatusTheme.color(status);
  }
}
