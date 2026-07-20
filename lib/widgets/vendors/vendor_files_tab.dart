import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';
import '../../models/file_attachment.dart';
import '../../models/project.dart';
import '../../models/vendor.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/project_terminology.dart';
import '../common/zero_items_action_empty_state.dart';
import 'vendor_related_project_scope.dart';

class VendorFilesTab extends StatefulWidget {
  final Vendor vendor;

  const VendorFilesTab({super.key, required this.vendor});

  @override
  State<VendorFilesTab> createState() => _VendorFilesTabState();
}

class _VendorFilesTabState extends State<VendorFilesTab> {
  final dynamic _storageService = ServiceLocator.storageService;
  late final Future<VendorRelatedProjectScope> _scopeFuture;

  @override
  void initState() {
    super.initState();
    _scopeFuture = loadVendorRelatedProjectScope(widget.vendor);
  }

  @override
  Widget build(BuildContext context) {
    final pluralTerminology =
        context.watch<WorkspaceProvider>().projectTerminology;
    final singularTerminology =
        singularProjectTerminology(pluralTerminology);

    return FutureBuilder<VendorRelatedProjectScope>(
      future: _scopeFuture,
      builder: (context, scopeSnapshot) {
        if (scopeSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final scope = scopeSnapshot.data;
        if (scope == null || !scope.hasRelatedProjects) {
          return ZeroItemsActionEmptyState(
            icon: Icons.folder_open_outlined,
            title:
                'No vendor-linked ${singularTerminology.toLowerCase()} files yet',
            subtitle:
                'Once this vendor is tied to purchase orders, bills, or bid requests, related ${singularTerminology.toLowerCase()} files can be surfaced here.',
            ctaLabel: '',
            onTap: null,
            hintText:
                'Files will appear automatically once vendor-linked ${pluralTerminology.toLowerCase()} exist',
          );
        }

        return FutureBuilder<List<_ProjectFileSummary>>(
          future: _loadSummaries(scope.projects),
          builder: (context, summarySnapshot) {
            if (summarySnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final summaries =
                summarySnapshot.data ?? const <_ProjectFileSummary>[];
            final populated =
                summaries.where((summary) => summary.files.isNotEmpty).toList()
                  ..sort((a, b) {
                    final aTime = a.files.first.uploadedAt;
                    final bTime = b.files.first.uploadedAt;
                    return bTime.compareTo(aTime);
                  });
            final totalFileCount = populated.fold<int>(
              0,
              (sum, summary) => sum + summary.files.length,
            );

            if (totalFileCount == 0) {
              return ZeroItemsActionEmptyState(
                icon: Icons.insert_drive_file_outlined,
                title:
                    'No files on related ${pluralTerminology.toLowerCase()} yet',
                subtitle:
                    '$singularTerminology file uploads for work involving this vendor will appear here.',
                ctaLabel: '',
                onTap: null,
                hintText:
                    'Upload files on a related ${singularTerminology.toLowerCase()} to see them here',
              );
            }

            return ListView(
              padding: const EdgeInsets.all(AppSpacing.base),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.base),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppColors.infoLight,
                          child: Icon(
                            Icons.folder_open,
                            color: AppColors.info,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$totalFileCount file${totalFileCount == 1 ? '' : 's'} across ${populated.length} ${projectTerminologyForCount(populated.length, pluralTerminology).toLowerCase()}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Recent uploads from this vendor\'s related ${pluralTerminology.toLowerCase()}',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
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
                  onPressed: () =>
                      context.go('/projects/${summary.project.id}?tab=files'),
                  icon: const Icon(Icons.open_in_new),
                  label: Text('Open $singularTerminology'),
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

  Future<List<_ProjectFileSummary>> _loadSummaries(
    List<Project> projects,
  ) async {
    final summaries = await Future.wait(
      projects.map((project) async {
        final files = await _storageService
            .getProjectFiles(widget.vendor.workspaceId, project.id)
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
