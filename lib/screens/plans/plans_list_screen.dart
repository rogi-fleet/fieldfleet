import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdfx/pdfx.dart';
import '../../utils/user_facing_error.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/construction_plan.dart';
import '../../models/plan_discipline.dart';
import '../../models/property.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/project_terminology.dart';
import '../../services/floorplan/ai_plan_to_scene.dart';
import '../../utils/app_logger.dart';
import '../../utils/floorplan/id_broker.dart';
import '../../widgets/common/add_entity_fab.dart';
import '../../widgets/common/list_skeleton.dart';
import '../../widgets/common/zero_items_action_empty_state.dart';
import '../../widgets/floorplan/ai_floorplan_dialog.dart';
import '../../widgets/floorplan/preset_picker_dialog.dart';

class PlansListScreen extends StatefulWidget {
  final String projectId;
  /// Pre-applied structure filter. Set when navigating in from a property's
  /// "View plans" action so the list opens already scoped.
  final String? initialPropertyId;

  const PlansListScreen({
    super.key,
    required this.projectId,
    this.initialPropertyId,
  });

  @override
  State<PlansListScreen> createState() => _PlansListScreenState();
}

class _PlansListScreenState extends State<PlansListScreen> {
  final _planService = ServiceLocator.planService;
  PlanDiscipline? _filterDiscipline;
  bool _showCurrentOnly = false;
  String _searchQuery = '';
  String? _filterPropertyId;

  // Bulk selection
  bool _selectionMode = false;
  Set<String> _selectedPlanIds = {};

  // Cache of structures keyed by id. Lets bulk operations + tile labels
  // resolve a property name without an extra fetch.
  Map<String, Property> _propertiesById = const {};

  // Tracks whether any plans exist. Used to hide filter chips on empty state.
  bool _hasAnyPlans = true;

  @override
  void initState() {
    super.initState();
    _filterPropertyId = widget.initialPropertyId;
  }

  bool get _hasActiveFilters =>
      _filterDiscipline != null ||
      _showCurrentOnly ||
      _filterPropertyId != null ||
      _searchQuery.trim().isNotEmpty;

  /// The "Add Plan" menu entries, shared by the FAB and the empty-state CTA.
  List<AddEntityAction> _addPlanActions(String workspaceId) => [
    AddEntityAction(
      label: 'Upload PDF',
      icon: Icons.upload_file,
      subtitle: 'Add an existing construction plan',
      onTap: () {
        if (!mounted) return;
        final query = _filterPropertyId != null
            ? '?property=$_filterPropertyId'
            : '';
        context.push('/projects/${widget.projectId}/plans/upload$query');
      },
    ),
    AddEntityAction(
      label: 'New Floorplan',
      icon: Icons.architecture,
      subtitle: 'Pick a starter — blank, preset, AI, or room scan',
      onTap: () {
        if (!mounted) return;
        _createEditorPlan(context, workspaceId);
      },
    ),
  ];

  Future<void> _createEditorPlan(
    BuildContext context,
    String workspaceId,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final auth = context.read<AuthProvider>();
    final user = auth.appUser;
    if (user == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Not signed in')));
      return;
    }
    // Pick a starter layout up front so users don't face a blank canvas.
    final preset = await showPresetPicker(context);
    if (preset == null || !context.mounted) return;

    // The Scan preset opens the native room-scan screen, which creates
    // its own plan + scene. Short-circuit before touching the plan
    // service.
    if (preset.id == 'scan') {
      final query = _filterPropertyId != null
          ? '?property=$_filterPropertyId'
          : '';
      context.push('/projects/${widget.projectId}/plans/scan$query');
      return;
    }

    // The "Generate from text/photo/PDF" presets are special — collect
    // a prompt first, then dispatch an AI generation. Failure to get a
    // prompt bails out before creating the plan. Photo and PDF go
    // through a vision describe step (multimodal endpoint) and let the
    // user review/edit the resulting brief before generation.
    String? aiPrompt;
    if (preset.id == 'ai') {
      aiPrompt = await showAiFloorplanDialog(context);
      if (aiPrompt == null || !context.mounted) return;
    } else if (preset.id == 'ai_image') {
      aiPrompt = await _pickImageAndDescribe(context);
      if (aiPrompt == null || !context.mounted) return;
    } else if (preset.id == 'ai_pdf') {
      aiPrompt = await _pickPdfAndDescribe(context);
      if (aiPrompt == null || !context.mounted) return;
    }

    try {
      final plan = await _planService.createEditorPlan(
        projectId: widget.projectId,
        workspaceId: workspaceId,
        propertyId: _filterPropertyId,
        name: aiPrompt != null
            ? 'AI floorplan ${DateTime.now().month}/${DateTime.now().day}'
            : preset.name,
        createdBy: user.id,
      );
      if (aiPrompt != null) {
        // Dispatch the generation via the standard fire-and-forget
        // pattern. The editor screen subscribes to the generation row
        // and shows a spinner overlay until status flips to ready.
        await _dispatchAiGeneration(
          plan.id,
          plan.workspaceId,
          plan.projectId,
          aiPrompt,
          user.id,
        );
      } else if (preset.id != 'blank') {
        final scene = preset.build(IdBroker(), preset.name);
        await ServiceLocator.floorplanSceneService.upsertScene(
          planId: plan.id,
          workspaceId: plan.workspaceId,
          projectId: plan.projectId,
          scene: scene,
          lastEditedBy: user.id,
        );
      }
      if (!context.mounted) return;
      context.push(
        '/projects/${widget.projectId}/plans/${plan.id}/edit',
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.uiMessage(e, action: 'create floorplan'),
          ),
        ),
      );
    }
  }

  /// Insert the generation row, then kick off the AI call without
  /// blocking the UI. We don't await the LLM here — the editor opens
  /// immediately and the realtime subscription on
  /// floorplan_generations drives the spinner and the eventual scene
  /// load.
  Future<void> _dispatchAiGeneration(
    String planId,
    String workspaceId,
    String projectId,
    String prompt,
    String userId,
  ) async {
    final genService = ServiceLocator.floorplanGenerationService;
    final aiService = ServiceLocator.aiFloorplanService;
    final sceneService = ServiceLocator.floorplanSceneService;
    final generationId = await genService.beginGeneration(
      planId: planId,
      workspaceId: workspaceId,
      projectId: projectId,
      prompt: prompt,
      userId: userId,
    );
    unawaited(() async {
      try {
        final aiPlan = await aiService.generate(prompt: prompt);
        final scene = aiPlanToScene(aiPlan, IdBroker());
        await sceneService.upsertScene(
          planId: planId,
          workspaceId: workspaceId,
          projectId: projectId,
          scene: scene,
          lastEditedBy: userId,
        );
        await genService.markReady(
          generationId,
          aiPlanJson: {
            'rooms': aiPlan.rooms.map((r) => {
                  'name': r.name,
                  'x': r.x,
                  'y': r.y,
                  'width': r.width,
                  'height': r.height,
                }).toList(),
            'doors': aiPlan.doors.length,
            'windows': aiPlan.windows.length,
            'items': aiPlan.items.length,
          },
        );
      } catch (e, stack) {
        AppLogger.warning(
          'AI floorplan generation failed',
          metadata: {'planId': planId, 'error': e.toString()},
        );
        await genService.markFailed(
          generationId,
          errorMessage: e.toString(),
        );
        // Re-throw to surface in dev console; UI gets the failure via
        // the realtime subscription.
        if (kDebugMode) debugPrintStack(stackTrace: stack);
      }
    }());
  }

  /// Photo flow: pick an image from the device, send it to the
  /// multimodal endpoint for description, then let the user review/
  /// edit the prose before it becomes a generation prompt.
  Future<String?> _pickImageAndDescribe(BuildContext context) async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: ImageSource.gallery,
      // Keep base64 payloads sane — vision models don't benefit from
      // pixel-perfect detail and the request body would balloon.
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 85,
    );
    if (picked == null || !context.mounted) return null;
    final bytes = await picked.readAsBytes();
    if (!context.mounted) return null;
    return _describeAndConfirm(context, bytes);
  }

  /// PDF flow: pick a PDF, rasterize page 1 to PNG via pdfx, then
  /// reuse the same describe-and-confirm path as the photo flow.
  Future<String?> _pickPdfAndDescribe(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    final pdfBytes = result?.files.firstOrNull?.bytes;
    if (pdfBytes == null || !context.mounted) return null;

    Uint8List pageBytes;
    try {
      final doc = await PdfDocument.openData(pdfBytes);
      final page = await doc.getPage(1);
      // Render at ~1024 px on the longer side — same heuristic as the
      // background-layer renderer; enough resolution for the vision
      // model to read room labels without bloating the request body.
      const maxSide = 1024;
      final scale = (page.width >= page.height
              ? maxSide / page.width
              : maxSide / page.height)
          .clamp(0.25, 3.0);
      final rendered = await page.render(
        width: (page.width * scale),
        height: (page.height * scale),
      );
      await page.close();
      await doc.close();
      if (rendered == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not render PDF page.')),
          );
        }
        return null;
      }
      pageBytes = rendered.bytes;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read PDF: $e')),
        );
      }
      return null;
    }
    if (!context.mounted) return null;
    return _describeAndConfirm(context, pageBytes);
  }

  /// Shared tail for the photo and PDF flows: show a spinner, run the
  /// vision describe step, then open the existing prompt dialog with
  /// the AI's prose as the initial value so the user can review and
  /// correct it before generation.
  Future<String?> _describeAndConfirm(
    BuildContext context,
    Uint8List bytes,
  ) async {
    final descriptionFuture =
        ServiceLocator.aiFloorplanService.describeImage(bytes: bytes);

    // Fire-and-forget the spinner dialog; we pop it ourselves once
    // the future settles. Awaiting `showDialog` would block until the
    // dialog closes, which is the opposite of what we need here.
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: SizedBox(
            width: 280,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                SizedBox(width: 16),
                Expanded(child: Text('AI is reading your image…')),
              ],
            ),
          ),
        ),
      ),
    );

    String description;
    try {
      description = await descriptionFuture;
    } catch (e) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not analyse image: $e')),
        );
      }
      return null;
    }
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    if (!context.mounted) return null;

    return showAiFloorplanDialog(
      context,
      initialPrompt: description.trim(),
      confirmLabel: 'Generate from this',
      warning: 'Edit the description if the AI got something wrong.',
    );
  }

  Stream<List<ConstructionPlan>> _plansStream(String workspaceId) {
    if (_showCurrentOnly) {
      return _planService.getCurrentPlans(widget.projectId, workspaceId);
    }
    if (_filterDiscipline != null) {
      return _planService.getPlansByDiscipline(
        widget.projectId,
        workspaceId,
        _filterDiscipline!,
      );
    }
    return _planService.getPlans(widget.projectId, workspaceId);
  }

  // ---- Selection ----------------------------------------------------------

  void _enterSelectionMode(String planId) {
    setState(() {
      _selectionMode = true;
      _selectedPlanIds = {planId};
    });
  }

  void _toggleSelection(String planId) {
    setState(() {
      if (_selectedPlanIds.contains(planId)) {
        _selectedPlanIds.remove(planId);
        if (_selectedPlanIds.isEmpty) _selectionMode = false;
      } else {
        _selectedPlanIds.add(planId);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedPlanIds.clear();
    });
  }

  Future<void> _runBulk(
    Future<void> Function() action,
    String successMsg,
  ) async {
    try {
      await action();
      if (!mounted) return;
      _exitSelectionMode();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMsg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.uiMessage(e, action: 'complete this action'),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _bulkMoveToProperty(String workspaceId) async {
    final ids = _selectedPlanIds.toList();
    final newPropertyId = await _showPropertyPicker(
      context,
      currentValue: null,
      includeProjectWide: true,
    );
    if (newPropertyId == _PropertyPickerResult.cancelled) return;
    final value = newPropertyId == _PropertyPickerResult.projectWide
        ? null
        : newPropertyId.propertyId;
    final label = value == null
        ? 'project-wide'
        : (_propertiesById[value]?.displayLabel ?? 'structure');
    await _runBulk(
      () => _planService.bulkSetProperty(ids, workspaceId, value),
      'Moved ${ids.length} plan(s) to $label',
    );
  }

  Future<void> _bulkChangeDiscipline(
    String workspaceId,
    PlanDiscipline discipline,
  ) async {
    final ids = _selectedPlanIds.toList();
    await _runBulk(
      () => _planService.bulkSetDiscipline(ids, workspaceId, discipline),
      'Updated ${ids.length} plan(s) to ${discipline.displayName}',
    );
  }

  Future<void> _bulkDelete(String workspaceId) async {
    final ids = _selectedPlanIds.toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete plans?'),
        content: Text(
          '${ids.length} plan(s) and their attached PDFs will be removed. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runBulk(
      () => _planService.bulkDeletePlans(ids, workspaceId),
      'Deleted ${ids.length} plan(s)',
    );
  }

  Future<_PropertyPickerResult> _showPropertyPicker(
    BuildContext context, {
    String? currentValue,
    bool includeProjectWide = true,
  }) async {
    final properties = _propertiesById.values.toList()
      ..sort((a, b) => a.displayLabel.compareTo(b.displayLabel));
    final projectTerm = singularProjectTerminology(
      context.read<WorkspaceProvider>().projectTerminology,
    );
    final result = await showDialog<_PropertyPickerResult>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Choose structure'),
        children: [
          if (includeProjectWide)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(
                ctx,
                _PropertyPickerResult.projectWide,
              ),
              child: Row(
                children: [
                  const Icon(Icons.public, size: 18),
                  const SizedBox(width: 12),
                  Text('$projectTerm-wide (no structure)'),
                ],
              ),
            ),
          if (properties.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.base),
              child: Text(
                'No structures defined for this project yet.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            )
          else
            ...properties.map(
              (p) => SimpleDialogOption(
                onPressed: () => Navigator.pop(
                  ctx,
                  _PropertyPickerResult.forProperty(p.id),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.apartment, size: 18),
                    const SizedBox(width: 12),
                    Expanded(child: Text(p.displayLabel)),
                    if (p.id == currentValue)
                      const Icon(
                        Icons.check,
                        size: 16,
                        color: AppColors.success,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    return result ?? _PropertyPickerResult.cancelled;
  }

  // ---- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final workspaceId = authProvider.appUser?.currentWorkspaceId ?? '';

    return Scaffold(
      appBar: _buildAppBar(context, workspaceId),
      body: StreamBuilder<List<Property>>(
        stream: ServiceLocator.propertyService.getProperties(widget.projectId),
        builder: (context, propertySnapshot) {
          // Cache properties for resolution in tiles + dialogs.
          final properties = propertySnapshot.data ?? const <Property>[];
          _propertiesById = {for (final p in properties) p.id: p};
          // Drop a stale property filter if the structure no longer exists.
          if (_filterPropertyId != null &&
              propertySnapshot.hasData &&
              !_propertiesById.containsKey(_filterPropertyId)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _filterPropertyId = null);
            });
          }

          return Column(
            children: [
              if (_selectionMode && _selectedPlanIds.isNotEmpty)
                _buildBulkActionBar(context, workspaceId),
              _buildQuickFilterChips(context),
              Expanded(child: _buildPlansList(context, workspaceId)),
            ],
          );
        },
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom + 78,
        ),
        child: _buildAnimatedFab(context, workspaceId),
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context, String workspaceId) {
    if (_selectionMode && _selectedPlanIds.isNotEmpty) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _exitSelectionMode,
        ),
        title: Text('${_selectedPlanIds.length} selected'),
      );
    }
    return AppBar(
      automaticallyImplyLeading: false,
      title: _searchQuery.isEmpty
          ? null
          : TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search plans...',
                border: InputBorder.none,
                hintStyle: TextStyle(color: Colors.white70),
              ),
              style: const TextStyle(color: Colors.white),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
      actions: [
        if (_searchQuery.isEmpty)
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              setState(() {
                _searchQuery = ' '; // Set to space to trigger search mode
              });
            },
            tooltip: 'Search',
          )
        else
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              setState(() {
                _searchQuery = '';
              });
            },
            tooltip: 'Clear search',
          ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.filter_list),
          onSelected: (value) async {
            if (value == 'current') {
              setState(() => _showCurrentOnly = !_showCurrentOnly);
            } else if (value == 'clear') {
              setState(() {
                _filterDiscipline = null;
                _showCurrentOnly = false;
                _filterPropertyId = null;
                _searchQuery = '';
              });
            } else if (value == 'pick_property') {
              final result = await _showPropertyPicker(
                context,
                currentValue: _filterPropertyId,
                includeProjectWide: false,
              );
              if (!mounted) return;
              if (result == _PropertyPickerResult.cancelled) return;
              setState(() {
                _filterPropertyId =
                    result.propertyId; // null when "Project-wide" picked
              });
            } else {
              setState(() {
                _filterDiscipline = PlanDiscipline.fromString(value);
              });
            }
          },
          itemBuilder: (context) => [
            CheckedPopupMenuItem(
              checked: _showCurrentOnly,
              value: 'current',
              child: const Text('Current Versions Only'),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              enabled: false,
              child: Text(
                'Filter by Discipline',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ...PlanDiscipline.values.map((discipline) {
              return CheckedPopupMenuItem(
                checked: _filterDiscipline == discipline,
                value: discipline.toString(),
                child: Row(
                  children: [
                    Icon(discipline.icon, size: 18, color: discipline.color),
                    const SizedBox(width: 8),
                    Text(discipline.displayName),
                  ],
                ),
              );
            }),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'pick_property',
              child: Row(
                children: [
                  const Icon(Icons.apartment, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _filterPropertyId == null
                          ? 'Filter by Structure…'
                          : 'Structure: ${_propertiesById[_filterPropertyId]?.displayLabel ?? 'Loading…'}',
                    ),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'clear', child: Text('Clear Filters')),
          ],
        ),
      ],
    );
  }

  /// Quick-filter chips above the list. Hidden in selection mode or when the
  /// list is empty (filters serve no purpose with no content).
  Widget _buildQuickFilterChips(BuildContext context) {
    if (_selectionMode || (!_hasAnyPlans && !_hasActiveFilters)) {
      return const SizedBox.shrink();
    }
    final chips = <Widget>[
      FilterChip(
        label: const Text('All'),
        selected: _filterDiscipline == null && !_showCurrentOnly,
        onSelected: (_) {
          setState(() {
            _filterDiscipline = null;
            _showCurrentOnly = false;
          });
        },
      ),
      FilterChip(
        avatar: const Icon(Icons.check_circle_outline, size: 16),
        label: const Text('Current only'),
        selected: _showCurrentOnly,
        onSelected: (selected) {
          setState(() => _showCurrentOnly = selected);
        },
      ),
      ...PlanDiscipline.values.map((discipline) {
        final selected = _filterDiscipline == discipline;
        return FilterChip(
          avatar: Icon(discipline.icon, size: 16, color: discipline.color),
          label: Text(discipline.displayName),
          selected: selected,
          onSelected: (sel) {
            setState(() {
              _filterDiscipline = sel ? discipline : null;
            });
          },
        );
      }),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Scrollbar(
            thumbVisibility: kIsWeb,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final c in chips) ...[c, const SizedBox(width: 8)],
                ],
              ),
            ),
          ),
          if (_filterPropertyId != null) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                InputChip(
                  avatar: const Icon(Icons.apartment, size: 16),
                  label: Text(
                    'Structure: ${_propertiesById[_filterPropertyId]?.displayLabel ?? '…'}',
                  ),
                  onDeleted: () =>
                      setState(() => _filterPropertyId = null),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBulkActionBar(BuildContext context, String workspaceId) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Text(
              '${_selectedPlanIds.length} selected',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: _exitSelectionMode,
              child: const Text('Clear'),
            ),
            const SizedBox(width: 8),
            ActionChip(
              avatar: const Icon(Icons.apartment, size: 16),
              label: const Text('Move to structure'),
              visualDensity: VisualDensity.compact,
              onPressed: () => _bulkMoveToProperty(workspaceId),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<PlanDiscipline>(
              tooltip: 'Change discipline',
              child: Chip(
                avatar: const Icon(Icons.category, size: 16),
                label: const Text('Discipline'),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
              itemBuilder: (context) => PlanDiscipline.values
                  .map(
                    (d) => PopupMenuItem(
                      value: d,
                      child: Row(
                        children: [
                          Icon(d.icon, size: 16, color: d.color),
                          const SizedBox(width: 8),
                          Text(d.displayName),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onSelected: (d) => _bulkChangeDiscipline(workspaceId, d),
            ),
            const SizedBox(width: 8),
            ActionChip(
              avatar: const Icon(
                Icons.delete_outline,
                size: 16,
                color: AppColors.error,
              ),
              label: const Text(
                'Delete',
                style: TextStyle(color: AppColors.error),
              ),
              visualDensity: VisualDensity.compact,
              onPressed: () => _bulkDelete(workspaceId),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlansList(BuildContext context, String workspaceId) {
    return StreamBuilder<List<ConstructionPlan>>(
      stream: _plansStream(workspaceId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              UserFacingError.uiMessage(snapshot.error, action: 'load data'),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const ListSkeleton();
        }

        final allPlans = snapshot.data ?? const <ConstructionPlan>[];

        // Keep _hasAnyPlans in sync so _buildQuickFilterChips can hide itself
        // when there are no plans to filter.
        if (_hasAnyPlans != allPlans.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _hasAnyPlans = allPlans.isNotEmpty);
          });
        }

        var plans = allPlans;

        // Property pre-filter (applied client-side because the upstream
        // streams are scoped to project, not property).
        if (_filterPropertyId != null) {
          plans = plans
              .where((p) => p.propertyId == _filterPropertyId)
              .toList();
        }

        // Search filter
        if (_searchQuery.trim().isNotEmpty) {
          final query = _searchQuery.toLowerCase();
          plans = plans.where((plan) {
            return plan.name.toLowerCase().contains(query) ||
                (plan.sheetNumber?.toLowerCase().contains(query) ?? false) ||
                (plan.version?.toLowerCase().contains(query) ?? false) ||
                (plan.notes?.toLowerCase().contains(query) ?? false) ||
                plan.discipline.displayName.toLowerCase().contains(query);
          }).toList();
        }

        if (plans.isEmpty) {
          if (!_hasActiveFilters && allPlans.isEmpty) {
            return ZeroItemsActionEmptyState(
              icon: Icons.architecture,
              title: 'No plans yet',
              subtitle: 'Upload a PDF or draw a new floorplan',
              ctaLabel: 'Add Plan',
              onTap: () => AddEntityFab.showActionsSheet(
                context,
                _addPlanActions(workspaceId),
              ),
            );
          }
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.architecture,
                  size: 80,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(height: 16),
                Text(
                  'No plans match your filters',
                  style: TextStyle(
                    fontSize: 18,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }

        // Group plans by discipline
        final groupedPlans = <PlanDiscipline, List<ConstructionPlan>>{};
        for (final plan in plans) {
          groupedPlans.putIfAbsent(plan.discipline, () => []).add(plan);
        }

        return ListView.builder(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            MediaQuery.paddingOf(context).bottom + 90,
          ),
          itemCount: groupedPlans.length,
          itemBuilder: (context, index) {
            final discipline = groupedPlans.keys.elementAt(index);
            final disciplinePlans = groupedPlans[discipline]!;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (index > 0) const SizedBox(height: 24),
                Row(
                  children: [
                    Icon(discipline.icon, color: discipline.color),
                    const SizedBox(width: 8),
                    Text(
                      discipline.displayName,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: discipline.color,
                          ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: discipline.color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(AppRadius.r12),
                      ),
                      child: Text(
                        '${disciplinePlans.length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: discipline.color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...disciplinePlans.map(
                  (plan) => PlanListTile(
                    plan: plan,
                    propertyLabel: plan.propertyId == null
                        ? null
                        : _propertiesById[plan.propertyId!]?.displayLabel,
                    selectionMode: _selectionMode,
                    selected: _selectedPlanIds.contains(plan.id),
                    onLongPress: () => _enterSelectionMode(plan.id),
                    onTapInSelectionMode: () => _toggleSelection(plan.id),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget? _buildAnimatedFab(BuildContext context, String workspaceId) {
    if (_selectionMode) return null;
    return StreamBuilder<List<ConstructionPlan>>(
      stream: _plansStream(workspaceId),
      builder: (context, snapshot) {
        final allPlans = snapshot.data ?? const <ConstructionPlan>[];
        final hideFab = !_hasActiveFilters && allPlans.isEmpty;
        if (hideFab) return const SizedBox.shrink();

        // Pulse only on empty-no-filters (AddEntityFab policy); the
        // filters-active case renders at rest, same rule as before.
        return AddEntityFab(
          label: 'Add Plan',
          actions: _addPlanActions(workspaceId),
          isEmpty: allPlans.isEmpty,
          filtersActive: _hasActiveFilters,
        );
      },
    );
  }
}

/// Result wrapper for the property picker. Distinguishes:
/// - cancelled (user dismissed dialog)
/// - projectWide (user picked the "no structure" option)
/// - a specific property id
class _PropertyPickerResult {
  final String? propertyId;
  final bool isCancelled;
  final bool isProjectWide;

  const _PropertyPickerResult._({
    this.propertyId,
    this.isCancelled = false,
    this.isProjectWide = false,
  });

  static const cancelled = _PropertyPickerResult._(isCancelled: true);
  static const projectWide = _PropertyPickerResult._(isProjectWide: true);

  factory _PropertyPickerResult.forProperty(String id) =>
      _PropertyPickerResult._(propertyId: id);
}

class PlanListTile extends StatelessWidget {
  final ConstructionPlan plan;
  final String? propertyLabel;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onLongPress;
  final VoidCallback? onTapInSelectionMode;

  const PlanListTile({
    super.key,
    required this.plan,
    this.propertyLabel,
    this.selectionMode = false,
    this.selected = false,
    this.onLongPress,
    this.onTapInSelectionMode,
  });

  Future<void> _openPdf(BuildContext context) async {
    final pdfUrl = plan.fileUrl;
    if (pdfUrl == null || pdfUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This plan has no PDF attached')),
      );
      return;
    }
    final url = Uri.parse(pdfUrl);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open PDF'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _showVersionsDialog(BuildContext context) async {
    if (plan.sheetNumber == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No sheet number assigned to view versions'),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Versions of ${plan.sheetNumber}'),
        content: StreamBuilder<List<ConstructionPlan>>(
          stream: ServiceLocator.planService.getPlanVersions(
            plan.projectId,
            plan.workspaceId,
            plan.sheetNumber!,
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final versions = snapshot.data ?? [];

            return SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: versions.length,
                itemBuilder: (context, index) {
                  final version = versions[index];
                  return ListTile(
                    leading: Icon(
                      version.isCurrentVersion
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      color: version.isCurrentVersion
                          ? AppColors.success
                          : AppColors.textTertiary,
                    ),
                    title: Text(version.version ?? 'Unnamed Version'),
                    subtitle: Text(
                      'Uploaded ${version.uploadedAt.month}/${version.uploadedAt.day}/${version.uploadedAt.year}',
                    ),
                    trailing: version.isCurrentVersion
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: AppSpacing.xs,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.success.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(AppRadius.r12),
                            ),
                            child: Text(
                              'CURRENT',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.success,
                              ),
                            ),
                          )
                        : null,
                  );
                },
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: selected
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
          : null,
      child: ListTile(
        contentPadding: const EdgeInsets.all(AppSpacing.md),
        onTap: selectionMode
            ? onTapInSelectionMode
            : () {
                // Editor-only plans go straight to the editor; PDF plans go
                // to the detail viewer where the editor is one menu item
                // away.
                final route = plan.hasPdf
                    ? '/projects/${plan.projectId}/plans/${plan.id}'
                    : '/projects/${plan.projectId}/plans/${plan.id}/edit';
                context.push(route);
              },
        onLongPress: onLongPress,
        leading: selectionMode
            ? Checkbox(
                value: selected,
                onChanged: (_) => onTapInSelectionMode?.call(),
              )
            : CircleAvatar(
                backgroundColor: plan.discipline.color.withValues(alpha: 0.2),
                child: Icon(
                  plan.hasPdf ? Icons.picture_as_pdf : Icons.architecture,
                  color: plan.discipline.color,
                ),
              ),
        title: Row(
          children: [
            if (plan.sheetNumber != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.cardBorder,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text(
                  plan.sheetNumber!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                plan.name,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            if (plan.isCurrentVersion)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text(
                  'CURRENT',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.success,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                if (plan.version != null) ...[
                  Text(plan.version!),
                  const Text(' • '),
                ],
                Text(plan.fileSizeFormatted),
                const Text(' • '),
                Text(
                  'Uploaded ${plan.uploadedAt.month}/${plan.uploadedAt.day}/${plan.uploadedAt.year}',
                ),
              ],
            ),
            if (propertyLabel != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.apartment,
                    size: 12,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      propertyLabel!,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (plan.notes != null) ...[
              const SizedBox(height: 4),
              Text(
                plan.notes!,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        trailing: selectionMode
            ? null
            : PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'open') {
                    _openPdf(context);
                  } else if (value == 'edit') {
                    context.push(
                      '/projects/${plan.projectId}/plans/${plan.id}/edit',
                    );
                  } else if (value == 'versions') {
                    _showVersionsDialog(context);
                  }
                },
                itemBuilder: (context) => [
                  if (plan.hasPdf)
                    const PopupMenuItem(
                      value: 'open',
                      child: Row(
                        children: [
                          Icon(Icons.open_in_new),
                          SizedBox(width: 8),
                          Text('Open PDF'),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.architecture),
                        SizedBox(width: 8),
                        Text('Open in Editor'),
                      ],
                    ),
                  ),
                  if (plan.sheetNumber != null)
                    const PopupMenuItem(
                      value: 'versions',
                      child: Row(
                        children: [
                          Icon(Icons.history),
                          SizedBox(width: 8),
                          Text('View Versions'),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
