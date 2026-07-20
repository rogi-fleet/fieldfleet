import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';
import '../../models/customer.dart';
import '../../models/file_attachment.dart';
import '../../models/project.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/project_terminology.dart';
import '../common/zero_items_action_empty_state.dart';
import '../project_form_popup.dart';

class CustomerFilesTab extends StatefulWidget {
  final Customer customer;

  const CustomerFilesTab({super.key, required this.customer});

  @override
  State<CustomerFilesTab> createState() => _CustomerFilesTabState();
}

class _CustomerFilesTabState extends State<CustomerFilesTab> {
  dynamic get _customerService => ServiceLocator.customerService;
  final dynamic _storageService = ServiceLocator.storageService;

  @override
  Widget build(BuildContext context) {
    final pluralTerminology =
        context.watch<WorkspaceProvider>().projectTerminology;
    final singularTerminology =
        singularProjectTerminology(pluralTerminology);

    return StreamBuilder<List<Project>>(
      stream: _customerService.getCustomerProjects(widget.customer.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final projects = snapshot.data ?? [];
        if (projects.isEmpty) {
          return _buildNoProjectsState(
            context,
            pluralTerminology,
            singularTerminology,
          );
        }

        return FutureBuilder<List<_ProjectFileSummary>>(
          future: _loadSummaries(projects),
          builder: (context, summarySnapshot) {
            if (summarySnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final summaries =
                summarySnapshot.data ?? const <_ProjectFileSummary>[];
            final totalFileCount = summaries.fold<int>(
              0,
              (sum, summary) => sum + summary.files.length,
            );
            final populated =
                summaries.where((summary) => summary.files.isNotEmpty).toList()
                  ..sort((a, b) {
                    final aTime = a.files.first.uploadedAt;
                    final bTime = b.files.first.uploadedAt;
                    return bTime.compareTo(aTime);
                  });

            if (totalFileCount == 0) {
              return _buildNoFilesState(
                context,
                projects,
                singularTerminology,
              );
            }

            return ListView(
              padding: const EdgeInsets.all(AppSpacing.base),
              children: [
                _buildHeader(
                  totalFileCount,
                  populated.length,
                  pluralTerminology,
                ),
                const SizedBox(height: 16),
                ...populated.map(
                  (summary) =>
                      _buildProjectCard(summary, singularTerminology),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildHeader(
    int totalFileCount,
    int projectCount,
    String pluralTerminology,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.infoLight,
              child: Icon(Icons.folder_open, color: AppColors.info),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$totalFileCount file${totalFileCount == 1 ? '' : 's'} across $projectCount ${projectTerminologyForCount(projectCount, pluralTerminology).toLowerCase()}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Recent uploads from this customer\'s ${pluralTerminology.toLowerCase()}',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectCard(
    _ProjectFileSummary summary,
    String singularTerminology,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary.project.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${summary.files.length} file${summary.files.length == 1 ? '' : 's'}',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    context.go('/projects/${summary.project.id}?tab=files');
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: Text('Open $singularTerminology Files'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...summary.files.take(3).map(_buildFileTile),
          ],
        ),
      ),
    );
  }

  Widget _buildFileTile(FileAttachment file) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: AppColors.surfaceAlt,
        child: Icon(_iconForFile(file), color: AppColors.textSecondary),
      ),
      title: Text(file.fileName, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${file.formattedSize} • ${timeago.format(file.uploadedAt)}',
      ),
      trailing: IconButton(
        icon: const Icon(Icons.open_in_new),
        tooltip: 'Open file',
        onPressed: () => _openFile(file),
      ),
      onTap: () => _openFile(file),
    );
  }

  Widget _buildNoProjectsState(
    BuildContext context,
    String pluralTerminology,
    String singularTerminology,
  ) {
    return ZeroItemsActionEmptyState(
      icon: Icons.work_outline,
      title: 'No ${pluralTerminology.toLowerCase()} yet',
      subtitle:
          'Create a ${singularTerminology.toLowerCase()} for ${widget.customer.name} to start uploading files.',
      ctaLabel: 'Create $singularTerminology',
      onTap: () => showProjectFormPopup(
        context,
        initialCustomerId: widget.customer.id,
      ),
    );
  }

  Widget _buildNoFilesState(
    BuildContext context,
    List<Project> projects,
    String singularTerminology,
  ) {
    return ZeroItemsActionEmptyState(
      icon: Icons.insert_drive_file_outlined,
      title: 'No ${singularTerminology.toLowerCase()} files uploaded yet',
      subtitle:
          'Use a ${singularTerminology.toLowerCase()}\'s Files tab to upload and organize customer files.',
      ctaLabel: 'Open $singularTerminology Files',
      onTap: () {
        context.go('/projects/${projects.first.id}?tab=files');
      },
    );
  }

  Future<List<_ProjectFileSummary>> _loadSummaries(
    List<Project> projects,
  ) async {
    final summaries = await Future.wait(
      projects.map((project) async {
        final files = await _storageService
            .getProjectFiles(widget.customer.workspaceId, project.id)
            .first;
        files.sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
        return _ProjectFileSummary(project: project, files: files);
      }),
    );

    return summaries;
  }

  IconData _iconForFile(FileAttachment file) {
    if (file.isImage) return Icons.image_outlined;
    if (file.isPDF) return Icons.picture_as_pdf_outlined;
    if (file.isDocument) return Icons.description_outlined;
    return Icons.attach_file;
  }

  Future<void> _openFile(FileAttachment file) async {
    final uri = Uri.tryParse(file.fileUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _ProjectFileSummary {
  final Project project;
  final List<FileAttachment> files;

  const _ProjectFileSummary({required this.project, required this.files});
}
