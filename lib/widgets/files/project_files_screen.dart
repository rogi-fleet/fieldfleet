import 'dart:async';

import 'package:flutter/material.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../models/field_form_submission.dart';
import '../../models/field_form_template.dart';
import '../../models/file_attachment.dart';
import '../../models/file_folder.dart';
import '../../models/project.dart';
import '../../screens/projects/tabs/project_daily_logs_tab.dart';
import '../../screens/projects/tabs/project_inspections_tab.dart';
import '../../screens/projects/tabs/project_specifications_tab.dart';
import '../../screens/projects/tabs/project_punch_list_tab.dart';
import '../../screens/projects/tabs/project_warranties_tab.dart';
import '../../screens/plans/plans_list_screen.dart';
import '../../models/generated_document.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/budget_document_wizard.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../common/draggable_divider.dart';
import '../common/view_toolbar.dart';
import '../common/view_icon_button.dart';
import '../common/zero_items_action_empty_state.dart';
import '../documents/document_list_panel.dart';
import '../field_forms/field_form_submission_card.dart';
import '../../screens/files/file_markup_editor_screen.dart';
import '../../screens/documents/create_document_screen.dart';
import 'bulk_action_bar.dart';
import 'folder_tree_widget.dart';
import 'file_grid_view.dart';
import 'file_list_view.dart';
import 'file_viewer.dart';
import 'file_tag_input.dart';
import 'file_tags_quick_editor.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

/// The main Files tab widget with folder navigation and file display.
class ProjectFilesScreen extends StatefulWidget {
  final String projectId;
  final String workspaceId;
  // Optional full Project — required to render the project-module
  // virtual folders (Daily Logs / Inspections / Punch List / Warranties).
  // Workspace-level callers may pass null; those folders are then hidden.
  final Project? project;

  // One-time initial state — read once in initState(), ignored on rebuilds.
  // Used by ProjectDetailScreen to hand off a budget → create doc request.
  final String? initialVirtualFolder; // VirtualFolderType constant or null
  final String? initialSelectedDocumentId;
  final BudgetDocumentWizardResult? initialCreateDocumentData;

  const ProjectFilesScreen({
    super.key,
    required this.projectId,
    required this.workspaceId,
    this.project,
    this.initialVirtualFolder,
    this.initialSelectedDocumentId,
    this.initialCreateDocumentData,
  });

  @override
  State<ProjectFilesScreen> createState() => ProjectFilesScreenState();
}

// Public state class so ProjectDetailScreen can hold a GlobalKey<ProjectFilesScreenState>
// and call openDocumentCreate() imperatively from the budget tab.
class ProjectFilesScreenState extends State<ProjectFilesScreen> {
  final _folderService = ServiceLocator.folderService;
  final _storageService = ServiceLocator.storageService;
  final ImagePicker _imagePicker = ImagePicker();

  FileFolder? _selectedFolder;
  bool _foldersInitialized = false;
  List<String> _uploadTags = [];
  String? _selectedTagFilter; // For filtering files by tag
  String _fileSearchQuery = ''; // For searching files by name
  Stream<List<FileAttachment>>? _filesStream; // Cached to avoid rebuild flicker

  // Cached folder list — updated each time the folder stream emits.
  List<FileFolder> _lastKnownFolders = [];
  // Guards the one-time initial virtual folder selection.
  bool _initialFolderApplied = false;

  // Document create state.
  // _showCreateDocument: user tapped "Create" in DocumentListPanel (no template pre-selected).
  // _createDocumentData: budget → create handoff with a real templateId and line items.
  // Both are mutually exclusive; exactly one is true while CreateDocumentScreen is visible.
  bool _showCreateDocument = false;
  BudgetDocumentWizardResult? _createDocumentData;
  // Invoked when the embedded CreateDocumentScreen's Back arrow is tapped.
  // Set by openDocumentCreate() so the originating tab (e.g. Financials)
  // can be restored instead of leaving the user on the Files tab.
  VoidCallback? _onCreateDocumentClose;
  // Set when openDocumentCreate fires before the folder stream has emitted —
  // we defer selecting the Documents virtual folder until folders arrive.
  bool _pendingDocsFolderSelection = false;
  String? _viewingDocumentId;
  Stream<List<GeneratedDocument>>? _documentStream;

  // Field form submissions stream.
  Stream<List<FieldFormSubmission>>? _fieldFormStream;

  /// Files currently selected for bulk operations. Populated by long-press
  /// (grid) or checkbox (list). When non-empty, tap on unselected cards
  /// toggles selection instead of opening the viewer.
  final Set<String> _selectedIds = <String>{};

  /// Latest file list emitted by the stream — used so bulk operations have
  /// something to iterate without subscribing separately.
  List<FileAttachment> _lastKnownFiles = const [];

  /// All image files in the project, grouped by folder id (null bucket is
  /// unfiled). Maintained via [_allProjectFilesSub]; used by
  /// FolderTreeWidget to render the thumbnail strip next to each folder.
  final Map<String, List<FileAttachment>> _projectImagesByFolder =
      <String, List<FileAttachment>>{};
  StreamSubscription<List<FileAttachment>>? _allProjectFilesSub;

  /// Latest task/message file images for virtual-folder thumbnail strips.
  /// Kept separate so real-folder subscription can refresh independently
  /// without clobbering these.
  List<FileAttachment> _taskFileImages = const [];
  List<FileAttachment> _messageFileImages = const [];
  StreamSubscription<List<FileAttachment>>? _taskFilesSub;
  StreamSubscription<List<FileAttachment>>? _messageFilesSub;

  static const String _viewModePrefKey = 'filesView.mode';

  // Process-wide cache of the persisted view mode so navigating back to
  // the Files tab within a session doesn't flicker from grid to list while
  // SharedPreferences resolves. Nullable until the first async load.
  static bool? _cachedViewMode;

  bool _isListView = _cachedViewMode ?? false;

  /// userId → display name, used by FileListView for the "Uploaded By" column.
  Map<String, String> _userNames = const {};

  @override
  void initState() {
    super.initState();
    _initializeFolders();
    _updateFilesStream();
    _subscribeProjectFilesForThumbnails();
    _createDocumentData = widget.initialCreateDocumentData;
    _viewingDocumentId = widget.initialSelectedDocumentId;
    if (_cachedViewMode == null) _loadViewModePreference();
    _loadUserNames();
  }

  Future<void> _loadUserNames() async {
    final usersMap = await ServiceLocator.userService
        .getWorkspaceUsersMap(widget.workspaceId);
    if (!mounted) return;
    setState(() {
      _userNames = {
        for (final e in usersMap.entries)
          e.key: e.value.displayName ?? e.value.email,
      };
    });
  }

  @override
  void dispose() {
    _allProjectFilesSub?.cancel();
    _taskFilesSub?.cancel();
    _messageFilesSub?.cancel();
    super.dispose();
  }

  /// Subscribe to every file in the project purely to feed the folder
  /// tree's thumbnail strips. This runs in parallel with the folder-
  /// scoped [_filesStream] so the tree can show thumbs for OTHER folders
  /// without re-fetching when the user navigates between them. Filtered
  /// to images that already have a thumbnail_url — legacy pre-097 uploads
  /// have no thumbnail, and loading their full-size bytes into an 18px
  /// tile wastes megabytes per folder row. Folder-less files bucket under
  /// '__root__'.
  void _subscribeProjectFilesForThumbnails() {
    _allProjectFilesSub?.cancel();
    _taskFilesSub?.cancel();
    _messageFilesSub?.cancel();
    _allProjectFilesSub = _storageService
        .getProjectFiles(widget.workspaceId, widget.projectId)
        .listen((files) {
      if (!mounted) return;
      final next = <String, List<FileAttachment>>{};
      for (final f in files) {
        if (!f.isImage) continue;
        if (f.thumbnailUrl == null || f.thumbnailUrl!.isEmpty) continue;
        final key = f.folderId ?? '__root__';
        (next[key] ??= <FileAttachment>[]).add(f);
      }
      for (final list in next.values) {
        list.sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
      }
      setState(() {
        _projectImagesByFolder
          ..clear()
          ..addAll(next);
      });
    });

    // Virtual folders (Tasks, Messages) host files tied to those entities,
    // not to real folder rows. Subscribe to the same underlying streams the
    // virtual browsers use and route filtered images into the thumbnail
    // map under the virtual folder's id (resolved lazily at paint time).
    _taskFilesSub = _storageService
        .getAllProjectTaskFiles(widget.workspaceId, widget.projectId)
        .listen((files) {
      if (!mounted) return;
      setState(() {
        _taskFileImages = _filterThumbableImages(files);
      });
    });
    _messageFilesSub = _storageService
        .getAllProjectMessageFiles(widget.workspaceId, widget.projectId)
        .listen((files) {
      if (!mounted) return;
      setState(() {
        _messageFileImages = _filterThumbableImages(files);
      });
    });
  }

  List<FileAttachment> _filterThumbableImages(List<FileAttachment> files) {
    final out = <FileAttachment>[];
    for (final f in files) {
      if (!f.isImage) continue;
      if (f.thumbnailUrl == null || f.thumbnailUrl!.isEmpty) continue;
      out.add(f);
    }
    out.sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
    return out;
  }

  Future<void> _loadViewModePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getString(_viewModePrefKey) == 'list';
    _cachedViewMode = list;
    if (!mounted || _isListView == list) return;
    setState(() => _isListView = list);
  }

  Future<void> _persistViewMode(bool list) async {
    _cachedViewMode = list;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_viewModePrefKey, list ? 'list' : 'grid');
  }

  @override
  void didUpdateWidget(covariant ProjectFilesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId ||
        oldWidget.workspaceId != widget.workspaceId) {
      // Reset project-specific cached data when the project changes.
      _showCreateDocument = false;
      _createDocumentData = null;
      _onCreateDocumentClose = null;
      _documentStream = null;
      _fieldFormStream = null;
      _lastKnownFolders = [];
      _fileSearchQuery = '';
      _projectImagesByFolder.clear();
      _taskFileImages = const [];
      _messageFileImages = const [];
      _updateFilesStream();
      // Re-subscribe so the folder tree's thumbnail strip reflects the
      // new project; otherwise stale thumbs from the previous project
      // linger until next full mount.
      _subscribeProjectFilesForThumbnails();
      // Re-apply the initial virtual folder for the new project.
      _initialFolderApplied = false;
      return;
    }

    // When the deep-link target changes for the same project (e.g. user
    // navigates from /?tab=plans to /?tab=specifications), re-arm the
    // one-shot guard so the new section is selected on the next build.
    if (widget.initialVirtualFolder != oldWidget.initialVirtualFolder &&
        widget.initialVirtualFolder != null) {
      final target = _lastKnownFolders
          .where(
            (f) =>
                f.isVirtual && f.virtualType == widget.initialVirtualFolder,
          )
          .firstOrNull;
      if (target != null) {
        // Folders are already loaded — apply directly.
        _initialFolderApplied = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _selectedFolder = target;
            _updateFilesStream();
          });
        });
      } else {
        // Folders not yet loaded — let the one-shot path in the
        // StreamBuilder apply when data arrives.
        _initialFolderApplied = false;
      }
    }
  }

  Future<void> _initializeFolders() async {
    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.appUser?.id ?? '';

    await _folderService.initializeDefaultFolders(
      workspaceId: widget.workspaceId,
      projectId: widget.projectId,
      createdBy: userId,
    );
    // Backfill any virtual folders added after this project was created
    // (Daily Logs / Inspections / Punch List / Warranties).
    await _folderService.ensureDefaultVirtualFolders(
      workspaceId: widget.workspaceId,
      projectId: widget.projectId,
      createdBy: userId,
    );

    if (!mounted) return;
    setState(() {
      _foldersInitialized = true;
    });
  }

  /// Renders the project-module sections (Daily Logs / Inspections /
  /// Punch List / Warranties) when their virtual folder is selected.
  /// These were previously top-level project tabs and are now hosted
  /// inside the Files tree.
  Widget _buildModuleContent() {
    final project = widget.project;
    final virtualType = _selectedFolder?.virtualType;
    if (project == null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Text(
          'Open this section from inside a project to see its content.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    switch (virtualType) {
      case VirtualFolderType.dailyLogs:
        return ProjectDailyLogsTab(project: project);
      case VirtualFolderType.inspections:
        return ProjectInspectionsTab(project: project);
      case VirtualFolderType.specifications:
        return ProjectSpecificationsTab(project: project);
      case VirtualFolderType.punchList:
        return ProjectPunchListTab(project: project);
      case VirtualFolderType.warranties:
        return ProjectWarrantiesTab(project: project);
      case VirtualFolderType.plans:
        return PlansListScreen(projectId: project.id);
      case VirtualFolderType.specifications:
        return ProjectSpecificationsTab(project: project);
      default:
        return const SizedBox.shrink();
    }
  }

  void _updateFilesStream() {
    if (_selectedFolder == null) {
      _filesStream = _storageService.getProjectFiles(
        widget.workspaceId,
        widget.projectId,
      );
      return;
    }

    if (_selectedFolder!.isVirtual) {
      switch (_selectedFolder!.virtualType) {
        case VirtualFolderType.tasks:
          _filesStream = _storageService.getAllProjectTaskFiles(
            widget.workspaceId,
            widget.projectId,
          );
          return;
        case VirtualFolderType.messages:
          _filesStream = _storageService.getAllProjectMessageFiles(
            widget.workspaceId,
            widget.projectId,
          );
          return;
        case VirtualFolderType.forms:
        case VirtualFolderType.documents:
        case VirtualFolderType.dailyLogs:
        case VirtualFolderType.inspections:
        case VirtualFolderType.specifications:
        case VirtualFolderType.punchList:
        case VirtualFolderType.warranties:
        case VirtualFolderType.plans:
        case VirtualFolderType.specifications:
          // Content is rendered directly; no file-attachment stream needed.
          _filesStream = Stream.value([]);
          return;
        default:
          _filesStream = Stream.value([]);
          return;
      }
    }

    _filesStream = _storageService.getFolderFiles(
      widget.workspaceId,
      widget.projectId,
      _selectedFolder!.id,
    );
  }

  bool get _isFormsFolder =>
      _selectedFolder?.isVirtual == true &&
      _selectedFolder?.virtualType == VirtualFolderType.forms;
  bool get _isDocumentsFolder =>
      _selectedFolder?.isVirtual == true &&
      _selectedFolder?.virtualType == VirtualFolderType.documents;
  bool get _isModuleFolder =>
      _selectedFolder?.isVirtual == true &&
      VirtualFolderType.moduleTypes
          .contains(_selectedFolder?.virtualType ?? '');

  IconData _getVirtualFolderIcon(String? virtualType) {
    switch (virtualType) {
      case VirtualFolderType.tasks:
        return Icons.check_circle_outline;
      case VirtualFolderType.messages:
        return Icons.message_outlined;
      case VirtualFolderType.forms:
        return Icons.dynamic_form_outlined;
      case VirtualFolderType.documents:
        return Icons.description_outlined;
      case VirtualFolderType.dailyLogs:
        return Icons.event_note_outlined;
      case VirtualFolderType.inspections:
        return Icons.checklist_rtl_outlined;
      case VirtualFolderType.specifications:
        return Icons.menu_book_outlined;
      case VirtualFolderType.punchList:
        return Icons.fact_check_outlined;
      case VirtualFolderType.warranties:
        return Icons.verified_outlined;
      case VirtualFolderType.plans:
        return Icons.map_outlined;
      case VirtualFolderType.specifications:
        return Icons.menu_book_outlined;
      default:
        return Icons.folder_special;
    }
  }

  Future<void> _createFolder(String name, String? parentId) async {
    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.appUser?.id ?? '';

    await _folderService.createFolder(
      workspaceId: widget.workspaceId,
      projectId: widget.projectId,
      name: name,
      parentFolderId: parentId,
      createdBy: userId,
    );

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Folder "$name" created')));
    }
  }

  Future<void> _openCreateFolderDialog() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final name = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New folder'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Folder name (e.g. Zone 1)',
            ),
            validator: (v) {
              final trimmed = v?.trim() ?? '';
              if (trimmed.isEmpty) return 'Please enter a folder name.';
              return null;
            },
            onFieldSubmitted: (_) {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(ctx).pop(controller.text);
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(ctx).pop(controller.text);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);

    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    await _createFolder(trimmed, null);
  }

  Future<void> _deleteFolder(String folderId) async {
    // Reset selection if deleting selected folder
    if (_selectedFolder?.id == folderId) {
      setState(() {
        _selectedFolder = null;
        _updateFilesStream();
      });
    }

    await _folderService.deleteFolder(folderId);

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Folder deleted')));
    }
  }

  Future<void> _renameFolder(String folderId, String newName) async {
    await _folderService.renameFolder(folderId, newName);

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Folder renamed to "$newName"')));
    }
  }

  void _showUploadDialog() {
    final content = Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _selectedFolder != null
                ? 'Upload to "${_selectedFolder!.displayName}"'
                : 'Upload Files',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _pickFileAndShowTagDialog();
                },
                icon: const Icon(Icons.attach_file),
                label: const Text('Choose Files'),
              ),
              if (!kIsWeb)
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _pickCameraAndShowTagDialog();
                  },
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Camera'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Max size: 10MB. Supported: JPG, PNG, PDF, DOC, XLS',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );

    showDialog(
      context: context,
      // Use the root navigator so the dialog overlays the app shell —
      // otherwise the bottom navigation bar floats above the dialog and
      // covers the "Choose Files" button on mobile.
      useRootNavigator: true,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: content,
        ),
      ),
    );
  }

  // Pick file then show tag dialog
  static const _allowedExtensions = {
    'jpg', 'jpeg', 'png', 'gif', 'webp',
    'pdf',
    'doc', 'docx',
    'xls', 'xlsx',
    'ppt', 'pptx',
    'mp4', 'mov', 'avi',
    'mp3', 'wav',
    'zip',
  };

  Future<void> _pickFileAndShowTagDialog() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _allowedExtensions.toList(),
        allowMultiple: true,
      );

      if (result == null || result.files.isEmpty) return;

      // Web browsers don't always honour the extension filter — validate here.
      final rejected = result.files
          .where((f) {
            final ext =
                f.name.contains('.') ? f.name.split('.').last.toLowerCase() : '';
            return !_allowedExtensions.contains(ext);
          })
          .map((f) => f.name)
          .toList();

      if (rejected.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Unsupported file type${rejected.length == 1 ? '' : 's'}: '
              '${rejected.join(', ')}',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }

      final valid = result.files
          .where((f) {
            final ext =
                f.name.contains('.') ? f.name.split('.').last.toLowerCase() : '';
            return _allowedExtensions.contains(ext);
          })
          .toList();

      if (valid.isNotEmpty) {
        await _showTagDialogAndUpload(valid);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.uiMessage(e, action: 'picking file')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _pickCameraAndShowTagDialog() async {
    if (kIsWeb) return;

    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2048,
        maxHeight: 2048,
      );

      if (photo != null) {
        final file = PlatformFile(
          name: photo.name,
          size: await photo.length(),
          path: photo.path,
          bytes: kIsWeb ? await photo.readAsBytes() : null,
        );
        await _showTagDialogAndUpload([file]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.uiMessage(e, action: 'taking photo')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // Show tag dialog after file is selected
  Future<void> _showTagDialogAndUpload(List<PlatformFile> files) async {
    if (files.isEmpty) return;

    _uploadTags = [];
    final totalSize = files.fold<int>(0, (sum, file) => sum + file.size);

    final shouldUpload = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Add Tags'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // File preview
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          files.length == 1
                              ? _getPreviewIcon(
                                  files.first.extension?.toLowerCase(),
                                )
                              : Icons.file_copy_outlined,
                          size: 32,
                          color: AppColors.textPrimary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                files.length == 1
                                    ? files.first.name
                                    : '${files.length} files selected',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                _formatBytes(totalSize),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              if (files.length > 1) ...[
                                const SizedBox(height: 8),
                                ...files
                                    .take(3)
                                    .map(
                                      (file) => Text(
                                        file.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                if (files.length > 3)
                                  Text(
                                    '+${files.length - 3} more',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Tag input
                  FileTagInput(
                    initialTags: _uploadTags,
                    onTagsChanged: (tags) {
                      _uploadTags = tags;
                    },
                    suggestedTags: const [
                      'project',
                      'document',
                      'photo',
                      'invoice',
                      'contract',
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.upload),
                label: const Text('Upload'),
              ),
            ],
          );
        },
      ),
    );

    if (shouldUpload == true) {
      await _uploadFiles(files);
    } else {
      _uploadTags = [];
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _getPreviewIcon(String? ext) {
    if (ext == 'pdf') return Icons.picture_as_pdf;
    if (ext == 'jpg' || ext == 'jpeg' || ext == 'png' || ext == 'gif') {
      return Icons.image;
    }
    if (ext == 'doc' || ext == 'docx') return Icons.description;
    if (ext == 'xls' || ext == 'xlsx') return Icons.table_chart;
    return Icons.insert_drive_file;
  }

  Future<void> _uploadFiles(List<PlatformFile> files) async {
    if (files.isEmpty) return;

    final tags = List<String>.from(_uploadTags);
    final failedUploads = <String>[];
    var successfulUploads = 0;

    for (final file in files) {
      try {
        await _uploadFile(file, tags: tags);
        successfulUploads++;
      } catch (e) {
        failedUploads.add('${file.name}: $e');
      }
    }

    if (!mounted) {
      _uploadTags = [];
      return;
    }

    if (failedUploads.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            successfulUploads == 1
                ? 'File uploaded successfully'
                : '$successfulUploads files uploaded successfully',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            successfulUploads == 0
                ? 'All ${files.length} uploads failed'
                : 'Uploaded $successfulUploads of ${files.length} files',
          ),
          backgroundColor: successfulUploads == 0
              ? AppColors.error
              : AppColors.warning,
        ),
      );
    }

    _uploadTags = [];
  }

  Future<void> _uploadFile(
    PlatformFile platformFile, {
    required List<String> tags,
  }) async {
    final authProvider = context.read<AuthProvider>();
    final uploadedBy = authProvider.appUser?.id ?? '';

    try {
      if (kIsWeb) {
        if (platformFile.bytes == null) {
          throw Exception('File bytes are null');
        }

        await _storageService.uploadFileBytes(
          bytes: platformFile.bytes!,
          fileName: platformFile.name,
          workspaceId: widget.workspaceId,
          projectId: widget.projectId,
          folderId: _selectedFolder?.isVirtual == false
              ? _selectedFolder?.id
              : null,
          tags: tags,
          uploadedBy: uploadedBy,
        );
      } else {
        if (platformFile.path == null) {
          throw Exception('File path is null');
        }

        final file = File(platformFile.path!);

        await _storageService.uploadFile(
          file: file,
          fileName: platformFile.name,
          workspaceId: widget.workspaceId,
          projectId: widget.projectId,
          folderId: _selectedFolder?.isVirtual == false
              ? _selectedFolder?.id
              : null,
          tags: tags,
          uploadedBy: uploadedBy,
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;

    if (!_foldersInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return ColoredBox(
      color: Colors.white,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (isMobile) {
            return _buildMobileLayout();
          }
          return _buildDesktopLayout();
        },
      ),
    );
  }

  static const double _dividerWidth = 8.0;
  static const double _sidebarMinWidth = 180.0;
  static const double _sidebarMaxWidth = 420.0;
  static const double _sidebarCollapsedWidth = 40.0;
  double _sidebarWidth = 280.0;
  bool _isSidebarCollapsed = false;

  Widget _buildDesktopLayout() {
    final effectiveWidth =
        _isSidebarCollapsed ? _sidebarCollapsedWidth : _sidebarWidth;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Folder sidebar
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          width: effectiveWidth,
          child: _buildFolderSidebar(),
        ),
        // Resizable divider — disabled while collapsed.
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragUpdate: _isSidebarCollapsed
              ? null
              : (d) {
                  setState(() {
                    _sidebarWidth = (_sidebarWidth + d.delta.dx).clamp(
                      _sidebarMinWidth,
                      _sidebarMaxWidth,
                    );
                  });
                },
          child: const DraggableDivider(width: _dividerWidth),
        ),
        // File content area
        Expanded(child: _buildFileContent()),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        // Folder bar with dropdown
        _buildMobileFolderBar(),
        // File content
        Expanded(child: _buildFileContent()),
      ],
    );
  }

  Widget _buildMobileFolderBar() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          // Folder selector
          Expanded(
            child: StreamBuilder<List<FileFolder>>(
              stream: _folderService.getProjectFolders(
                widget.workspaceId,
                widget.projectId,
              ),
              builder: (context, snapshot) {
                final folders = snapshot.data ?? [];

                return PopupMenuButton<FileFolder?>(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _selectedFolder != null ? Icons.folder : Icons.home,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _selectedFolder?.displayName ?? 'All Files',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down),
                      ],
                    ),
                  ),
                  itemBuilder: (context) => [
                    const PopupMenuItem<FileFolder?>(
                      value: null,
                      child: Row(
                        children: [
                          Icon(Icons.home, size: 20),
                          SizedBox(width: 8),
                          Text('All Files'),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    ...folders.map(
                      (folder) => PopupMenuItem<FileFolder?>(
                        value: folder,
                        child: Row(
                          children: [
                            Icon(
                              folder.isVirtual
                                  ? _getVirtualFolderIcon(folder.virtualType)
                                  : Icons.folder,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(folder.displayName),
                            if (folder.isVirtual) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.auto_awesome,
                                size: 14,
                                color: AppColors.secondaryDark,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                  onSelected: (folder) {
                    setState(() {
                      _selectedFolder = folder;
                      _fileSearchQuery = '';
                      _selectedTagFilter = null;
                      _updateFilesStream();
                    });
                  },
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          // Upload button
          if (_selectedFolder?.isVirtual != true)
            IconButton(
              onPressed: _showUploadDialog,
              icon: const Icon(Icons.add),
              tooltip: 'Upload file',
            ),
        ],
      ),
    );
  }

  Widget _buildSidebarToggle() {
    return Align(
      alignment: Alignment.centerRight,
      child: IconButton(
        icon: Icon(
          _isSidebarCollapsed ? Icons.chevron_right : Icons.chevron_left,
          size: 20,
        ),
        tooltip: _isSidebarCollapsed ? 'Expand folders' : 'Collapse folders',
        onPressed: () =>
            setState(() => _isSidebarCollapsed = !_isSidebarCollapsed),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildFolderSidebar() {
    if (_isSidebarCollapsed) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: _buildSidebarToggle(),
      );
    }
    return StreamBuilder<List<FileFolder>>(
      stream: _folderService.getProjectFolders(
        widget.workspaceId,
        widget.projectId,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final folders = snapshot.data ?? [];
        _lastKnownFolders = folders;

        // Apply the one-time initial virtual folder selection once data arrives.
        // Guard is checked before addPostFrameCallback to avoid registering
        // redundant callbacks on every stream emission.
        if (!_initialFolderApplied && widget.initialVirtualFolder != null) {
          final target = folders
              .where(
                (f) =>
                    f.isVirtual && f.virtualType == widget.initialVirtualFolder,
              )
              .firstOrNull;
          if (target != null) {
            _initialFolderApplied = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                _selectedFolder = target;
                _updateFilesStream();
              });
            });
          }
        }

        // Resolve a pending budget → document-create handoff that fired before
        // folders had loaded. Select the Documents virtual folder now.
        if (_pendingDocsFolderSelection) {
          final docsFolder = folders
              .where(
                (f) =>
                    f.isVirtual && f.virtualType == VirtualFolderType.documents,
              )
              .firstOrNull;
          if (docsFolder != null) {
            _pendingDocsFolderSelection = false;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                _selectedFolder = docsFolder;
                _updateFilesStream();
              });
            });
          }
        }

        // Up to 3 thumbnails per folder for the tree strip, newest-first.
        // The subscription already filtered to files with a thumbnail_url
        // so we can use it directly without a fileUrl fallback.
        final thumbs = <String, List<String>>{
          for (final entry in _projectImagesByFolder.entries)
            entry.key: entry.value
                .take(3)
                .map((f) => f.thumbnailUrl!)
                .toList(),
        };
        final counts = <String, int>{
          for (final entry in _projectImagesByFolder.entries)
            entry.key: entry.value.length,
        };

        // Merge virtual-folder (Tasks/Messages) images into the thumbnail
        // maps so those rows get the same visual preview as real folders.
        for (final folder in folders.where((f) => f.isVirtual)) {
          List<FileAttachment>? images;
          switch (folder.virtualType) {
            case VirtualFolderType.tasks:
              images = _taskFileImages;
              break;
            case VirtualFolderType.messages:
              images = _messageFileImages;
              break;
            default:
              images = null;
          }
          if (images != null && images.isNotEmpty) {
            thumbs[folder.id] =
                images.take(3).map((f) => f.thumbnailUrl!).toList();
            counts[folder.id] = images.length;
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 4),
              child: _buildSidebarToggle(),
            ),
            Expanded(
              child: FolderTreeWidget(
                folders: folders,
                selectedFolderId: _selectedFolder?.id,
                onFolderSelected: (folder) {
                  setState(() {
                    _selectedFolder = folder;
                    _fileSearchQuery = '';
                    _selectedTagFilter = null;
                    _showCreateDocument = false;
                    _createDocumentData = null;
                    _onCreateDocumentClose = null;
                    _pendingDocsFolderSelection = false;
                    _updateFilesStream();
                  });
                },
                onCreateFolder: _createFolder,
                onDeleteFolder: _deleteFolder,
                onRenameFolder: _renameFolder,
                thumbnailsByFolder: thumbs,
                imageCountByFolder: counts,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFileContent() {
    if (_isFormsFolder) return _buildFormsContent();
    if (_isDocumentsFolder) return _buildDocumentsContent();
    if (_isModuleFolder) return _buildModuleContent();

    return StreamBuilder<List<FileAttachment>>(
      stream: _filesStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final allFiles = snapshot.data ?? [];

        // Extract all unique tags from files (excluding internal system tags
        // like `property:<uuid>` so the filter dropdown only shows
        // user-facing labels).
        final allTags = <String>{};
        for (final file in allFiles) {
          allTags.addAll(file.displayLegacyTags);
        }
        final sortedTags = allTags.toList()..sort();

        // Filter files by selected tag and search query. Search matches
        // name, title, description, and any tag — users expect to find a
        // file by typing a tag they can see on the card.
        final query = _fileSearchQuery.trim().toLowerCase();
        final files = allFiles.where((f) {
          final matchesTag =
              _selectedTagFilter == null || f.tags.contains(_selectedTagFilter);
          if (!matchesTag) return false;
          if (query.isEmpty) return true;
          if (f.fileName.toLowerCase().contains(query)) return true;
          if ((f.title ?? '').toLowerCase().contains(query)) return true;
          if ((f.description ?? '').toLowerCase().contains(query)) return true;
          if (f.effectiveTagNames
              .any((t) => t.toLowerCase().contains(query))) {
            return true;
          }
          return false;
        }).toList();

        // Keep bulk ops in sync with the stream — drop selected ids that no
        // longer exist (e.g. another user deleted them). Done in the build
        // path to avoid a parallel listener; the set is mutated in place.
        _lastKnownFiles = files;
        if (_selectedIds.isNotEmpty) {
          final visibleIds = files.map((f) => f.id).toSet();
          _selectedIds.removeWhere((id) => !visibleIds.contains(id));
        }

        final isDesktop = MediaQuery.of(context).size.width >= 800;

        return Column(
          children: [
            BulkActionBar(
              selectedCount: _selectedIds.length,
              onClear: () => setState(() => _selectedIds.clear()),
              onMove: _selectedIds.isEmpty ? null : _bulkMove,
              onAddTag: _selectedIds.isEmpty ? null : _bulkAddTag,
              onRemoveTag: _selectedIds.isEmpty ? null : _bulkRemoveTag,
              onDelete: _selectedIds.isEmpty ? null : _bulkDelete,
            ),
            _buildBreadcrumbs(),
            _buildMultiZoneNudge(files),
            ViewToolbar(
              searchHint: 'Search files...',
              searchQuery: _fileSearchQuery,
              onSearch: (q) => setState(() => _fileSearchQuery = q),
              quickToggles: [
                ViewIconButton(
                  icon: Icons.grid_view,
                  tooltip: 'Grid view',
                  isSelected: !_isListView,
                  onTap: () {
                    if (_isListView) {
                      setState(() => _isListView = false);
                      _persistViewMode(false);
                    }
                  },
                ),
                ViewIconButton(
                  icon: Icons.view_list,
                  tooltip: 'List view',
                  isSelected: _isListView,
                  onTap: () {
                    if (!_isListView) {
                      setState(() => _isListView = true);
                      _persistViewMode(true);
                    }
                  },
                ),
                // Explicit select-mode button so bulk actions are
                // discoverable — long-press on the grid isn't obvious.
                if (_selectedFolder?.isVirtual != true && files.isNotEmpty)
                  ViewIconButton(
                    icon: _selectedIds.isEmpty
                        ? Icons.checklist
                        : Icons.checklist_rtl,
                    tooltip: _selectedIds.isEmpty
                        ? 'Select files'
                        : 'Clear selection',
                    isSelected: _selectedIds.isNotEmpty,
                    onTap: () {
                      setState(() {
                        if (_selectedIds.isEmpty) {
                          // Seed with the first file so the bulk bar and
                          // checkboxes become visible — tells the user
                          // they're now in select mode.
                          if (files.isNotEmpty) {
                            _selectedIds.add(files.first.id);
                          }
                        } else {
                          _selectedIds.clear();
                        }
                      });
                    },
                  ),
                if (isDesktop && _selectedFolder?.isVirtual != true)
                  ViewIconButton(
                    icon: Icons.upload,
                    tooltip: 'Upload',
                    isSelected: false,
                    onTap: _showUploadDialog,
                  ),
              ],
              filterCount:
                  sortedTags.isNotEmpty ? (_selectedTagFilter != null ? 1 : 0) : null,
              onFilterTap: sortedTags.isNotEmpty
                  ? () => _showTagFilterSheet(sortedTags)
                  : null,
            ),
            // File grid / list or empty state
            Expanded(
              child: files.isEmpty
                  ? _buildFilesEmptyState()
                  : _isListView
                      ? FileListView(
                          files: files,
                          folders: _lastKnownFolders,
                          onOpen: (f) => _openFile(files, files.indexOf(f)),
                          selectedIds: _selectedIds,
                          onToggleSelect: _toggleSelection,
                          onToggleAll: (selectAll) {
                            setState(() {
                              if (selectAll) {
                                _selectedIds.addAll(files.map((f) => f.id));
                              } else {
                                _selectedIds.clear();
                              }
                            });
                          },
                          userNames: _userNames,
                          onEditTags: (f) => showQuickTagEditor(
                            context: context,
                            file: f,
                            workspaceId: widget.workspaceId,
                          ),
                        )
                      : FileGridView(
                          files: files,
                          onOpen: (f) => _openFile(files, files.indexOf(f)),
                          selectedIds: _selectedIds,
                          onToggleSelect: _toggleSelection,
                          onDelete: _showDeleteFileDialog,
                        ),
            ),
          ],
        );
      },
    );
  }

  void _showTagFilterSheet(List<String> tags) {
    final isCompact = MediaQuery.of(context).size.width < AppBreakpoints.compact;

    final content = StatefulBuilder(
      builder: (context, setSheetState) {
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Filter by tag',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  if (_selectedTagFilter != null)
                    TextButton(
                      onPressed: () {
                        setState(() => _selectedTagFilter = null);
                        Navigator.pop(context);
                      },
                      child: const Text('Clear'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: tags
                    .map(
                      (tag) => FilterChip(
                        label: Text(tag),
                        selected: _selectedTagFilter == tag,
                        onSelected: (selected) {
                          setState(() {
                            _selectedTagFilter = selected ? tag : null;
                          });
                          Navigator.pop(context);
                        },
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (isCompact) {
      showModalBottomSheet(context: context, builder: (_) => content);
    } else {
      showDialog(
        context: context,
        useRootNavigator: false,
        builder: (dialogContext) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: content,
          ),
        ),
      );
    }
  }

  Widget _buildFilesEmptyState() {
    if (_fileSearchQuery.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxxl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off, size: 64, color: AppColors.textTertiary),
              const SizedBox(height: 16),
              Text(
                'No files matching "$_fileSearchQuery"',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    if (_selectedTagFilter != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxxl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.filter_alt_off,
                size: 64,
                color: AppColors.textTertiary,
              ),
              const SizedBox(height: 16),
              Text(
                'No files with tag "$_selectedTagFilter"',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  setState(() {
                    _selectedTagFilter = null;
                  });
                },
                child: const Text('Clear filter'),
              ),
            ],
          ),
        ),
      );
    }
    if (_selectedFolder?.isVirtual == true) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxxl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.auto_awesome,
                size: 64,
                color: AppColors.secondaryDark,
              ),
              const SizedBox(height: 16),
              Text(
                'No files ${_selectedFolder?.virtualType == VirtualFolderType.tasks ? 'attached to tasks' : 'attached to messages'} yet',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return ZeroItemsActionEmptyState(
      icon: Icons.folder_open,
      title: 'No files in this folder',
      subtitle: 'Upload files to get started',
      ctaLabel: 'Upload File',
      onTap: _showUploadDialog,
    );
  }

  // Build Forms content for the virtual Forms folder — shows field form submissions.
  Widget _buildFormsContent() {
    _fieldFormStream ??= ServiceLocator.fieldFormService.getSubmissions(
      widget.workspaceId,
      projectId: widget.projectId,
    );

    return StreamBuilder<List<FieldFormSubmission>>(
      stream: _fieldFormStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final submissions = snapshot.data ?? [];

        if (submissions.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.assignment_outlined,
                    size: 56,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No form submissions yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Form submissions linked to this project will appear here. '
                    'Fill a form from a task or the Templates screen to get started.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _showFieldFormTemplatePicker,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Fill a Form'),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Text(
                    '${submissions.length} submission${submissions.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _showFieldFormTemplatePicker,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Fill Form'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                itemCount: submissions.length,
                itemBuilder: (context, index) {
                  final sub = submissions[index];
                  return FieldFormSubmissionCard(
                    submission: sub,
                    onTap: () =>
                        context.push('/field-forms/submissions/${sub.id}'),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showFieldFormTemplatePicker() async {
    final templates = await ServiceLocator.fieldFormService
        .getTemplates(widget.workspaceId)
        .first;
    if (!mounted) return;

    final selected = await showDialog<FieldFormTemplate>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Select a Form'),
        children: templates.isEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.assignment_outlined,
                        size: 48,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No form templates yet',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Generate the default form templates to get started.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () async {
                          Navigator.of(dialogContext).pop();
                          await _generateDefaultFieldFormTemplates();
                        },
                        icon: const Icon(Icons.auto_fix_high, size: 18),
                        label: const Text('Generate Default Templates'),
                      ),
                    ],
                  ),
                ),
              ]
            : templates
                  .map(
                    (t) => SimpleDialogOption(
                      onPressed: () => Navigator.of(dialogContext).pop(t),
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          fieldFormCategoryIcon(t.category),
                          size: 20,
                          color: AppColors.primary,
                        ),
                        title: Text(t.name),
                        subtitle: t.description != null
                            ? Text(
                                t.description!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : null,
                      ),
                    ),
                  )
                  .toList(),
      ),
    );

    if (selected == null || !mounted) return;
    await context.push(
      '/field-forms/${selected.id}/fill?projectId=${widget.projectId}',
    );
    // Reset the stream so the list re-fetches when we return, in case
    // the Supabase subscription didn't receive the new submission in time.
    if (mounted) setState(() => _fieldFormStream = null);
  }

  Future<void> _generateDefaultFieldFormTemplates() async {
    final auth = context.read<AuthProvider>();
    final userId = auth.appUser?.id ?? '';

    try {
      await ServiceLocator.fieldFormService.generateDefaultTemplates(
        workspaceId: widget.workspaceId,
        createdBy: userId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Default field form templates created!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.uiMessage(e, action: 'creating templates'),
          ),
        ),
      );
    }
  }

  // DocumentListPanel activates its inline detail pane at ≥1200px content
  // width. With the 280px folder sidebar this requires ≥1480px total — fine.
  Widget _buildDocumentsContent() {
    if (_showCreateDocument || _createDocumentData != null) {
      final data = _createDocumentData;
      return CreateDocumentScreen(
        embedded: true,
        projectId: widget.projectId,
        templateId: data?.templateId,
        prePopulatedLineItems: data?.lineItems,
        preSelectedBudgetItemIds: data?.selectedBudgetItemIds,
        preSelectedBudgetItemAmounts: data?.budgetItemAmounts,
        onBack: () {
          final onClose = _onCreateDocumentClose;
          setState(() {
            _showCreateDocument = false;
            _createDocumentData = null;
            _onCreateDocumentClose = null;
          });
          onClose?.call();
        },
        onDocumentCreated: (documentId) {
          setState(() {
            _showCreateDocument = false;
            _createDocumentData = null;
            _onCreateDocumentClose = null;
            _viewingDocumentId = documentId;
          });
        },
      );
    }

    _documentStream ??= ServiceLocator.documentService.getDocuments(
      widget.workspaceId,
      projectId: widget.projectId,
    );

    return DocumentListPanel(
      documentStream: _documentStream!,
      projectId: widget.projectId,
      initialSelectedDocumentId: _viewingDocumentId,
      onCreateTap: () => setState(() => _showCreateDocument = true),
      onNavigateToDocument: (id) => context.push('/documents/$id'),
    );
  }

  /// Imperatively activates the Documents folder and opens the embedded create
  /// form. Called by [ProjectDetailScreen] via [GlobalKey] when the budget tab
  /// triggers document creation.
  void openDocumentCreate(
    BudgetDocumentWizardResult result, {
    VoidCallback? onClose,
  }) {
    final docsFolder = _lastKnownFolders
        .where(
          (f) => f.isVirtual && f.virtualType == VirtualFolderType.documents,
        )
        .firstOrNull;
    setState(() {
      if (docsFolder != null) {
        _selectedFolder = docsFolder;
        _updateFilesStream();
      } else {
        // Folder stream hasn't emitted yet (e.g. Files tab built lazily on
        // tab switch from Budget). Defer selection until folders load.
        _pendingDocsFolderSelection = true;
      }
      _createDocumentData = result;
      _onCreateDocumentClose = onClose;
    });
  }

  Future<void> _showDeleteFileDialog(FileAttachment file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete File'),
        content: Text(
          'Are you sure you want to delete "${file.fileName}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteFile(file);
    }
  }

  Future<void> _deleteFile(FileAttachment file) async {
    try {
      await _storageService.deleteFile(file);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File deleted'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// SharedPreferences key base for the per-project "don't show again"
  /// dismiss state on the multi-zone nudge.
  static const String _multiZoneNudgeDismissPrefix = 'filesView.nudge.dismissed.';
  static const int _multiZoneNudgeThreshold = 10;

  bool _multiZoneNudgeDismissed = false;
  bool _multiZoneNudgeDismissLoaded = false;

  Widget _buildMultiZoneNudge(List<FileAttachment> files) {
    // Gate: at root (no selected folder), plenty of files, no real folders.
    if (_selectedFolder != null) return const SizedBox.shrink();
    if (files.length < _multiZoneNudgeThreshold) return const SizedBox.shrink();
    final hasRealFolder = _lastKnownFolders.any((f) => !f.isVirtual);
    if (hasRealFolder) return const SizedBox.shrink();

    // Load the dismiss pref once, then respect it.
    if (!_multiZoneNudgeDismissLoaded) {
      _multiZoneNudgeDismissLoaded = true;
      SharedPreferences.getInstance().then((prefs) {
        final dismissed = prefs.getBool(
              '$_multiZoneNudgeDismissPrefix${widget.projectId}',
            ) ??
            false;
        if (dismissed && mounted) {
          setState(() => _multiZoneNudgeDismissed = true);
        }
      });
    }
    if (_multiZoneNudgeDismissed) return const SizedBox.shrink();

    return Material(
      color: AppColors.primarySurface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Icon(Icons.tips_and_updates, color: AppColors.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'This project has lots of photos — organize them into folders '
                '(one per zone/area) to keep things scannable.',
                style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
              ),
            ),
            TextButton(
              onPressed: _openCreateFolderDialog,
              child: const Text('Create folder'),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Dismiss',
              onPressed: _dismissMultiZoneNudge,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _dismissMultiZoneNudge() async {
    setState(() => _multiZoneNudgeDismissed = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      '$_multiZoneNudgeDismissPrefix${widget.projectId}',
      true,
    );
  }

  Widget _buildBreadcrumbs() {
    // Walks up parent_folder_id to produce a "Files ▸ Foo ▸ Bar" trail. Each
    // crumb is tappable; tapping "Files" resets the folder filter. Hidden on
    // the root view to avoid a lonely "Files" bar with no path to show.
    final current = _selectedFolder;
    if (current == null) return const SizedBox.shrink();

    final byId = {for (final f in _lastKnownFolders) f.id: f};
    final chain = <FileFolder>[];
    // Detect cycles (parent → child → parent) — if we've already walked
    // through a folder, data is corrupt and we stop rather than loop forever.
    final seen = <String>{};
    var hierarchyTruncated = false;
    const maxDepth = 32;
    FileFolder? cursor = current;
    while (cursor != null) {
      if (!seen.add(cursor.id)) {
        hierarchyTruncated = true;
        break;
      }
      if (chain.length >= maxDepth) {
        hierarchyTruncated = true;
        break;
      }
      chain.insert(0, cursor);
      final parentId = cursor.parentFolderId;
      cursor = parentId == null ? null : byId[parentId];
    }

    final crumbs = <Widget>[
      _BreadcrumbTile(
        label: 'Files',
        onTap: () => setState(() {
          _selectedFolder = null;
          _updateFilesStream();
        }),
      ),
    ];
    for (var i = 0; i < chain.length; i++) {
      final folder = chain[i];
      final isLast = i == chain.length - 1;
      crumbs.add(const _BreadcrumbSeparator());
      crumbs.add(
        _BreadcrumbTile(
          label: folder.displayName,
          isCurrent: isLast,
          onTap: isLast
              ? null
              : () => setState(() {
                    _selectedFolder = folder;
                    _updateFilesStream();
                  }),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: crumbs),
            ),
          ),
          if (hierarchyTruncated) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: 'Folder path is too deep or contains a cycle — '
                  'some parents are hidden.',
              child: Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: AppColors.warning,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Bulk selection ────────────────────────────────────────────────────
  void _toggleSelection(String id) {
    setState(() {
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
    });
  }

  Iterable<FileAttachment> get _selectedFiles =>
      _lastKnownFiles.where((f) => _selectedIds.contains(f.id));

  Future<void> _bulkMove() async {
    final real = _lastKnownFolders.where((f) => !f.isVirtual).toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final targetId = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        String? picked;
        return AlertDialog(
          title: Text('Move ${_selectedIds.length} file(s)'),
          content: StatefulBuilder(
            builder: (ctx, setSB) => DropdownButtonFormField<String?>(
              initialValue: picked,
              decoration: const InputDecoration(labelText: 'Destination'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('— Unfiled —'),
                ),
                ...real.map(
                  (f) => DropdownMenuItem<String?>(
                    value: f.id,
                    child: Text(f.displayName),
                  ),
                ),
              ],
              onChanged: (v) => setSB(() => picked = v),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(_kCancelSentinel),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(picked),
              child: const Text('Move'),
            ),
          ],
        );
      },
    );
    if (targetId == _kCancelSentinel) return;

    await _runBulk(
      label: 'Moving',
      task: (file) => _storageService.updateFileMetadata(
        fileId: file.id,
        folderId: targetId,
        clearFolder: targetId == null,
      ),
    );
  }

  Future<void> _bulkAddTag() async {
    final name = await _promptForTagName('Add tag');
    if (name == null || name.trim().isEmpty) return;
    final tag = await ServiceLocator.fileTagService.ensureTag(
      workspaceId: widget.workspaceId,
      name: name.trim(),
    );
    await _runBulk(
      label: 'Tagging',
      task: (file) async {
        final current = await ServiceLocator.fileTagService.getTagsForFile(file.id);
        final ids = current.map((t) => t.id).toSet()..add(tag.id);
        await _storageService.updateFileMetadata(
          fileId: file.id,
          tagIds: ids.toList(),
        );
      },
    );
  }

  Future<void> _bulkRemoveTag() async {
    final name = await _promptForTagName('Remove tag (case-insensitive)');
    if (name == null || name.trim().isEmpty) return;
    final target = name.trim().toLowerCase();
    await _runBulk(
      label: 'Untagging',
      task: (file) async {
        final current = await ServiceLocator.fileTagService.getTagsForFile(file.id);
        final ids = current
            .where((t) => t.name.toLowerCase() != target)
            .map((t) => t.id)
            .toList();
        if (ids.length == current.length) return;
        await _storageService.updateFileMetadata(
          fileId: file.id,
          tagIds: ids,
        );
      },
    );
  }

  Future<void> _bulkDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${_selectedIds.length} file(s)?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await _runBulk(
      label: 'Deleting',
      task: (file) => _storageService.deleteFile(file),
    );
  }

  Future<String?> _promptForTagName(String title) {
    final controller = TextEditingController();
    return showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Tag name'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _runBulk({
    required String label,
    required Future<void> Function(FileAttachment file) task,
  }) async {
    final targets = _selectedFiles.toList(); // snapshot
    final total = targets.length;
    if (total == 0) return;

    setState(() => _selectedIds.clear());
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text('$label $total file(s)…')),
    );

    var ok = 0;
    var failed = 0;
    for (final file in targets) {
      try {
        await task(file);
        ok++;
      } catch (_) {
        failed++;
      }
    }

    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? '$label done ($ok)'
              : '$label done: $ok succeeded, $failed failed',
        ),
        backgroundColor: failed == 0 ? AppColors.success : AppColors.warning,
      ),
    );
  }

  static const String _kCancelSentinel = '__cancel__';

  Future<void> _openFile(List<FileAttachment> files, int index) async {
    // If the user is in selection mode, tap toggles selection instead of
    // opening the viewer — matches the mobile gallery convention.
    if (_selectedIds.isNotEmpty) {
      _toggleSelection(files[index].id);
      return;
    }
    // Full-screen viewer with swipe next/prev across the filtered list.
    // The metadata-editing detail panel is reachable from the viewer's
    // "info" button (see FileViewer._openDetails).
    await openFileViewer(
      context: context,
      files: files,
      initialIndex: index,
      workspaceId: widget.workspaceId,
      onEditImage: (f) {
        // "Mark up" — non-destructive vector layer. The original image
        // bytes are never modified; the editor writes to file_markup_layers.
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FileMarkupEditorScreen(file: f),
          ),
        );
      },
    );
  }

}

class _BreadcrumbTile extends StatelessWidget {
  final String label;
  final bool isCurrent;
  final VoidCallback? onTap;

  const _BreadcrumbTile({
    required this.label,
    this.isCurrent = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 12,
      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
      color: isCurrent ? AppColors.textPrimary : AppColors.textSecondary,
    );
    if (onTap == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
        child: Text(label, style: style),
      );
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
        child: Text(label, style: style),
      ),
    );
  }
}

class _BreadcrumbSeparator extends StatelessWidget {
  const _BreadcrumbSeparator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Icon(
        Icons.chevron_right,
        size: 14,
        color: AppColors.textTertiary,
      ),
    );
  }
}
