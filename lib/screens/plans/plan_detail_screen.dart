import 'dart:io';
import '../../utils/user_facing_error.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/construction_plan.dart';
import '../../models/floorplan/background_pdf.dart';
import '../../models/task.dart';
import '../../services/floorplan/scene_io.dart';
import '../../services/service_locator.dart';
import '../../providers/auth_provider.dart';
import '../plans/plan_upload_screen.dart';
import '../../theme/theme.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

class PlanDetailScreen extends StatefulWidget {
  final String planId;
  final String projectId;

  const PlanDetailScreen({
    super.key,
    required this.planId,
    required this.projectId,
  });

  @override
  State<PlanDetailScreen> createState() => _PlanDetailScreenState();
}

class _PlanDetailScreenState extends State<PlanDetailScreen> {
  final _planService = ServiceLocator.planService;
  final _taskService = ServiceLocator.taskService;
  PdfController? _pdfController;
  bool _isLoadingPdf = true;
  String? _pdfError;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  Future<void> _loadPdf() async {
    setState(() {
      _isLoadingPdf = true;
      _pdfError = null;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      final workspaceId = authProvider.appUser?.currentWorkspaceId;

      if (workspaceId == null) {
        throw Exception('No workspace found');
      }

      final plan = await _planService.getPlan(widget.planId, workspaceId);
      if (plan == null) {
        throw Exception('Plan not found');
      }

      // Editor-only plans (no PDF) skip the PDF load — the editor screen
      // is the right place to view them.
      final pdfUrl = plan.fileUrl;
      final pdfName = plan.fileName;
      if (pdfUrl == null || pdfUrl.isEmpty) {
        setState(() {
          _isLoadingPdf = false;
        });
        return;
      }

      // Load PDF from URL
      if (kIsWeb) {
        final pdfData = await _downloadPdfData(pdfUrl);
        _pdfController = PdfController(document: PdfDocument.openData(pdfData));
      } else {
        final file = await _downloadAndCachePdf(
          pdfUrl,
          pdfName ?? 'plan.pdf',
        );
        _pdfController = PdfController(
          document: PdfDocument.openFile(file.path),
        );
      }

      setState(() {
        _isLoadingPdf = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingPdf = false;
        _pdfError = UserFacingError.uiMessage(e, action: 'load PDF');
      });
    }
  }

  Future<Uint8List> _downloadPdfData(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return response.bodyBytes;
    } else {
      throw Exception('Failed to download PDF: ${response.statusCode}');
    }
  }

  Future<File> _downloadAndCachePdf(String url, String fileName) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');

    // Check if already cached
    if (await file.exists()) {
      return file;
    }

    // Download and cache
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      await file.writeAsBytes(response.bodyBytes);
      return file;
    } else {
      throw Exception('Failed to download PDF: ${response.statusCode}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    if (workspaceId == null) {
      return const Scaffold(
        body: Center(child: Text('Error: No workspace found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Construction Plan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () => _downloadPlan(),
            tooltip: 'Download',
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'edit_in_planner':
                  context.push(
                    '/projects/${widget.projectId}/plans/${widget.planId}/edit',
                  );
                  break;
                case 'overlay_in_planner':
                  await _startEditorOverlay();
                  break;
                case 'upload_version':
                  await _uploadNewVersion();
                  break;
                case 'make_current':
                  await _makeCurrentVersion();
                  break;
                case 'delete':
                  await _deletePlan();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit_in_planner',
                child: Row(
                  children: [
                    Icon(Icons.architecture),
                    SizedBox(width: 8),
                    Text('Edit in Planner'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'overlay_in_planner',
                child: Row(
                  children: [
                    Icon(Icons.layers_outlined),
                    SizedBox(width: 8),
                    Text('Trace over PDF in Planner'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'upload_version',
                child: Row(
                  children: [
                    Icon(Icons.upload_file),
                    SizedBox(width: 8),
                    Text('Upload New Version'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'make_current',
                child: Row(
                  children: [
                    Icon(Icons.check_circle),
                    SizedBox(width: 8),
                    Text('Make Current Version'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: AppColors.error),
                    SizedBox(width: 8),
                    Text('Delete', style: TextStyle(color: AppColors.error)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: StreamBuilder<ConstructionPlan?>(
        stream: _planService.getPlanStream(widget.planId, workspaceId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: SelectableText(
                UserFacingError.uiMessage(snapshot.error, action: 'load data'),
              ),
            );
          }

          final plan = snapshot.data;
          if (plan == null) {
            return const Center(child: Text('Plan not found'));
          }

          return Row(
            children: [
              // PDF Viewer
              Expanded(flex: 3, child: _buildPdfViewer()),

              // Metadata Sidebar
              Container(
                width: 350,
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: AppColors.cardBorder)),
                ),
                child: _buildMetadataSidebar(plan, workspaceId),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPdfViewer() {
    if (_isLoadingPdf) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading PDF...'),
          ],
        ),
      );
    }

    if (_pdfError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              _pdfError!,
              style: TextStyle(color: AppColors.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadPdf,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_pdfController == null) {
      return const Center(child: Text('No PDF loaded'));
    }

    return Column(
      children: [
        // PDF Controls
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.cardBorder,
            border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.zoom_out),
                onPressed: () {
                  // Zoom out functionality
                },
              ),
              IconButton(
                icon: const Icon(Icons.zoom_in),
                onPressed: () {
                  // Zoom in functionality
                },
              ),
              const SizedBox(width: 24),
              IconButton(
                icon: const Icon(Icons.navigate_before),
                onPressed: () {
                  // Previous page
                },
              ),
              const Text('Page control'),
              IconButton(
                icon: const Icon(Icons.navigate_next),
                onPressed: () {
                  // Next page
                },
              ),
            ],
          ),
        ),

        // PDF View
        Expanded(
          child: PdfView(
            controller: _pdfController!,
            scrollDirection: Axis.vertical,
            pageSnapping: false,
            physics: const BouncingScrollPhysics(),
          ),
        ),
      ],
    );
  }

  Widget _buildMetadataSidebar(ConstructionPlan plan, String workspaceId) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Plan Info Section
          _buildSection(
            title: 'Plan Information',
            children: [
              _buildInfoRow('Name', plan.name),
              _buildInfoRow('Discipline', plan.discipline.displayName),
              if (plan.sheetNumber != null)
                _buildInfoRow('Sheet Number', plan.sheetNumber!),
              if (plan.version != null) _buildInfoRow('Version', plan.version!),
              _buildInfoRow(
                'Status',
                plan.isCurrentVersion ? 'Current Version' : 'Outdated',
                valueColor: plan.isCurrentVersion
                    ? AppColors.success
                    : AppColors.warning,
              ),
              if (plan.drawingDate != null)
                _buildInfoRow(
                  'Drawing Date',
                  DateFormat('MMM d, yyyy').format(plan.drawingDate!),
                ),
            ],
          ),

          const Divider(),

          // File Info Section
          _buildSection(
            title: 'File Information',
            children: [
              _buildInfoRow('File Name', plan.fileName ?? '—'),
              _buildInfoRow('File Size', plan.fileSizeFormatted),
              _buildInfoRow(
                'Uploaded',
                DateFormat('MMM d, yyyy h:mm a').format(plan.uploadedAt),
              ),
            ],
          ),

          const Divider(),

          // Notes Section
          if (plan.notes != null && plan.notes!.isNotEmpty) ...[
            _buildSection(
              title: 'Notes',
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Text(plan.notes!),
                ),
              ],
            ),
            const Divider(),
          ],

          // Linked Tasks Section
          _buildSection(
            title: 'Linked Tasks',
            children: [
              if (plan.linkedTaskIds.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.sm),
                  child: Text(
                    'No tasks linked',
                    style: TextStyle(color: AppColors.textTertiary),
                  ),
                )
              else
                ...plan.linkedTaskIds.map(
                  (taskId) => FutureBuilder<Task?>(
                    future: _taskService.getTask(taskId),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const SizedBox.shrink();
                      }
                      final task = snapshot.data!;
                      return ListTile(
                        leading: Icon(
                          task.isComplete
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color: task.isComplete
                              ? AppColors.success
                              : AppColors.textTertiary,
                          size: 20,
                        ),
                        title: Text(task.title),
                        subtitle: task.description != null
                            ? Text(
                                task.description!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              )
                            : null,
                        dense: true,
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () => _unlinkTask(plan, taskId),
                          tooltip: 'Unlink',
                        ),
                        onTap: () {
                          // Navigate to task detail
                        },
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: OutlinedButton.icon(
                  onPressed: () => _linkTask(plan),
                  icon: const Icon(Icons.add_link, size: 18),
                  label: const Text('Link to Task'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(40),
                  ),
                ),
              ),
            ],
          ),

          const Divider(),

          // Version History Section
          _buildSection(
            title: 'Version History',
            children: [
              FutureBuilder<List<ConstructionPlan>>(
                future: _planService.getVersionHistory(
                  widget.projectId,
                  workspaceId,
                  plan.name,
                  plan.sheetNumber,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.base),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  final versions = snapshot.data ?? [];
                  if (versions.length <= 1) {
                    return Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Text(
                        'No previous versions',
                        style: TextStyle(color: AppColors.textTertiary),
                      ),
                    );
                  }

                  return Column(
                    children: versions.map((version) {
                      final isCurrent = version.id == plan.id;
                      return ListTile(
                        leading: Icon(
                          version.isCurrentVersion
                              ? Icons.check_circle
                              : Icons.history,
                          color: version.isCurrentVersion
                              ? AppColors.success
                              : AppColors.textTertiary,
                          size: 20,
                        ),
                        title: Text(
                          version.version ?? 'Unknown',
                          style: TextStyle(
                            fontWeight: isCurrent ? FontWeight.bold : null,
                          ),
                        ),
                        subtitle: Text(
                          DateFormat('MMM d, yyyy').format(version.uploadedAt),
                          style: const TextStyle(fontSize: 12),
                        ),
                        dense: true,
                        selected: isCurrent,
                        onTap: isCurrent
                            ? null
                            : () {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => PlanDetailScreen(
                                      planId: version.id,
                                      projectId: widget.projectId,
                                    ),
                                  ),
                                );
                              },
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        ...children,
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadPlan() async {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    if (workspaceId == null) return;

    try {
      final plan = await _planService.getPlan(widget.planId, workspaceId);
      if (plan == null) {
        throw Exception('Plan not found');
      }

      final pdfUrl = plan.fileUrl;
      if (pdfUrl == null || pdfUrl.isEmpty) {
        throw Exception('This plan has no PDF to download');
      }
      final uri = Uri.parse(pdfUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Could not open PDF');
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Opening PDF...')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'downloading plan'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _startEditorOverlay() async {
    final messenger = ScaffoldMessenger.of(context);
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    final user = authProvider.appUser;
    if (workspaceId == null || user == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Not signed in')));
      return;
    }
    final plan = await _planService.getPlan(widget.planId, workspaceId);
    if (plan == null) return;
    final pdfUrl = plan.fileUrl;
    if (pdfUrl == null || pdfUrl.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('This plan has no PDF to trace')),
      );
      return;
    }

    try {
      final sceneService = ServiceLocator.floorplanSceneService;
      final existing = await sceneService.getScene(widget.planId);
      if (existing == null) {
        // Bootstrap a fresh scene with the PDF as background.
        final scene = buildEmptyScene(name: plan.name).copyWith(
          background: BackgroundPdf(
            fileUrl: pdfUrl,
            opacity: 0.35,
          ),
        );
        await sceneService.upsertScene(
          planId: plan.id,
          workspaceId: plan.workspaceId,
          projectId: plan.projectId,
          scene: scene,
          lastEditedBy: user.id,
        );
      }
      if (!mounted) return;
      context.push(
        '/projects/${widget.projectId}/plans/${widget.planId}/edit',
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.uiMessage(e, action: 'start editor overlay'),
          ),
        ),
      );
    }
  }

  Future<void> _uploadNewVersion() async {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    if (workspaceId == null) return;

    final plan = await _planService.getPlan(widget.planId, workspaceId);
    if (plan == null) return;

    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PlanUploadScreen(projectId: widget.projectId),
        ),
      );
    }
  }

  Future<void> _makeCurrentVersion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Make Current Version'),
        content: const Text(
          'This will mark this plan as the current version and mark all other versions as outdated. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Make Current'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final authProvider = context.read<AuthProvider>();
      final workspaceId = authProvider.appUser?.currentWorkspaceId;

      if (workspaceId == null) return;

      final plan = await _planService.getPlan(widget.planId, workspaceId);
      if (plan == null) return;

      await _planService.setCurrentVersion(
        widget.planId,
        widget.projectId,
        workspaceId,
        plan.name,
        plan.sheetNumber,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Version updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'updating version'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _deletePlan() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Plan'),
        content: const Text(
          'Are you sure you want to delete this plan? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final authProvider = context.read<AuthProvider>();
      final workspaceId = authProvider.appUser?.currentWorkspaceId;

      if (workspaceId == null) return;

      await _planService.deletePlan(widget.planId, workspaceId);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Plan deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'deleting plan'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _linkTask(ConstructionPlan plan) async {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    if (workspaceId == null) return;

    // Get all tasks for this project
    final tasks = await _taskService
        .getTasks(widget.projectId, workspaceId: workspaceId)
        .first;

    // Filter out already linked tasks
    final availableTasks = tasks
        .where((task) => !plan.linkedTaskIds.contains(task.id))
        .toList();

    if (mounted) {
      final selectedTask = await showDialog<Task>(
        context: context,
        builder: (context) => _TaskLinkDialog(tasks: availableTasks),
      );

      if (selectedTask != null) {
        try {
          await _planService.linkPlanToTask(plan.id, selectedTask.id);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Linked to task: ${selectedTask.title}')),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  UserFacingError.uiMessage(e, action: 'linking task'),
                ),
                backgroundColor: AppColors.error,
              ),
            );
          }
        }
      }
    }
  }

  Future<void> _unlinkTask(ConstructionPlan plan, String taskId) async {
    try {
      await _planService.unlinkPlanFromTask(plan.id, taskId);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Task unlinked')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'unlinking task'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}

class _TaskLinkDialog extends StatefulWidget {
  final List<Task> tasks;

  const _TaskLinkDialog({required this.tasks});

  @override
  State<_TaskLinkDialog> createState() => _TaskLinkDialogState();
}

class _TaskLinkDialogState extends State<_TaskLinkDialog> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final filteredTasks = widget.tasks.where((task) {
      return task.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (task.description?.toLowerCase().contains(
                _searchQuery.toLowerCase(),
              ) ??
              false);
    }).toList();

    return AlertDialog(
      title: const Text('Link to Task'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            StackedField(
              label: 'Search tasks',
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: filteredTasks.isEmpty
                  ? const Center(
                      child: Text(
                        'No tasks available',
                        style: TextStyle(color: AppColors.textTertiary),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filteredTasks.length,
                      itemBuilder: (context, index) {
                        final task = filteredTasks[index];
                        return ListTile(
                          leading: Icon(
                            task.isComplete
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: task.isComplete
                                ? AppColors.success
                                : AppColors.textTertiary,
                          ),
                          title: Text(task.title),
                          subtitle: task.description != null
                              ? Text(
                                  task.description!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : null,
                          onTap: () => Navigator.pop(context, task),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
