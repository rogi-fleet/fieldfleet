import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/construction_plan.dart';
import '../../models/floorplan/editor_mode.dart';
import '../../providers/auth_provider.dart';
import '../../services/floorplan/floorplan_editor_controller.dart';
import '../../services/floorplan/scene_io.dart';
import '../../services/floorplan/thumbnail_renderer.dart';
import '../../services/service_locator.dart';
import '../../utils/user_facing_error.dart';
import '../../services/floorplan/ai_plan_to_scene.dart';
import '../../services/supabase/floorplan_generation_service.dart';
import '../../utils/floorplan/id_broker.dart';
import '../../widgets/floorplan/ai_floorplan_dialog.dart';
import '../../widgets/floorplan/calibration_dialog.dart';
import '../../widgets/floorplan/canvas_hint.dart';
import '../../widgets/floorplan/export_dialog.dart';
import '../../widgets/floorplan/floorplan_canvas.dart';
import '../../widgets/floorplan/generating_overlay.dart';
import '../../widgets/floorplan/grid_panel.dart';
import '../../widgets/floorplan/layer_panel.dart';
import '../../widgets/floorplan/property_inspector.dart';
import '../../widgets/floorplan/status_bar.dart';
import '../../widgets/floorplan/tool_rail.dart';
import '../../widgets/floorplan/viewport_controller.dart';
import '../../utils/text_selection_utils.dart';
import '../../theme/theme.dart';

/// Phase 1 floorplan editor: blank canvas, wall drawing, undo/redo, save.
///
/// Loads the plan + (optional) saved scene from Supabase, hands them to a
/// [FloorplanEditorController] that owns the in-memory state, and renders
/// the canvas + a top toolbar. Saving uploads a thumbnail and upserts the
/// scene JSON.
class FloorplanEditorScreen extends StatefulWidget {
  final String projectId;
  final String planId;

  /// When true, the editor renders without a Scaffold AppBar — the
  /// route is at the top level (outside the project ShellRoute) so the
  /// canvas can use the full window. When false (default), the editor
  /// is mounted inside the project shell with the project nav visible.
  final bool fullscreen;

  const FloorplanEditorScreen({
    super.key,
    required this.projectId,
    required this.planId,
    this.fullscreen = false,
  });

  @override
  State<FloorplanEditorScreen> createState() => _FloorplanEditorScreenState();
}

class _FloorplanEditorScreenState extends State<FloorplanEditorScreen> {
  final _planService = ServiceLocator.planService;
  final _sceneService = ServiceLocator.floorplanSceneService;
  final _generationService = ServiceLocator.floorplanGenerationService;

  FloorplanEditorController? _controller;
  final FloorplanViewportController _viewport = FloorplanViewportController();
  ConstructionPlan? _plan;
  int _serverVersion = 0;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  /// Latest AI generation row state for this plan, watched via realtime.
  /// `null` = no generation has ever run; otherwise the editor either
  /// shows a generating spinner (status='generating') or an error
  /// overlay (status='failed'). On 'ready' we re-pull the scene and
  /// dismiss the overlay.
  ({String status, String prompt, String? error})? _generation;
  StreamSubscription<({String status, String prompt, String? error})?>?
      _generationSub;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _generationSub?.cancel();
    _controller?.dispose();
    _viewport.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final auth = context.read<AuthProvider>();
      final workspaceId = auth.appUser?.currentWorkspaceId;
      if (workspaceId == null) {
        throw Exception('No workspace selected');
      }

      final plan = await _planService.getPlan(widget.planId, workspaceId);
      if (plan == null) {
        throw Exception('Plan not found');
      }

      final loaded = await _sceneService.getScene(widget.planId);
      final scene = loaded?.scene ?? buildEmptyScene(name: plan.name);
      final version = loaded?.version ?? 0;

      setState(() {
        _plan = plan;
        _serverVersion = version;
        _controller = FloorplanEditorController(scene: scene);
        _loading = false;
      });

      // Subscribe to AI generation status for this plan. When status
      // flips to 'ready', re-pull the scene — but if the user has
      // dirty edits or undo history we ask first instead of silently
      // blowing them away (replaceScene clears the undo stack).
      _generationSub =
          _generationService.streamLatestForPlan(widget.planId).listen(
        (g) async {
          if (!mounted) return;
          final wasGenerating = _generation?.status == 'generating';
          setState(() => _generation = g);
          if (g != null && g.status == 'ready' && wasGenerating) {
            await _onGenerationReady();
          }
        },
      );
    } catch (e) {
      setState(() {
        _loading = false;
        _error = UserFacingError.uiMessage(e, action: 'open editor');
      });
    }
  }

  /// True when an AI generation row exists in either of the two
  /// states the editor reacts to (in flight or failed). 'ready' rows
  /// don't show an overlay — the scene has already been swapped in.
  bool get _shouldShowGenerationOverlay {
    final g = _generation;
    if (g == null) return false;
    return g.status == 'generating' || g.status == 'failed';
  }

  /// Invoked when a generation flips to 'ready'. If the user hasn't
  /// touched anything since regeneration started, swap in the new
  /// scene silently. If they have unsaved edits or undo history we'd
  /// be wiping out, prompt first — replaceScene clears the undo stack
  /// so this is irreversible without an explicit choice.
  Future<void> _onGenerationReady() async {
    final controller = _controller;
    if (controller == null) return;
    final loaded = await _sceneService.getScene(widget.planId);
    if (!mounted || loaded == null) return;
    final hasLocalWork = controller.dirty || controller.canUndo;
    if (hasLocalWork) {
      final messenger = ScaffoldMessenger.of(context);
      final accept = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('AI generation ready'),
          content: const Text(
            'You\'ve made changes since regeneration started. Loading '
            'the new scene will replace your work and clear the undo '
            'stack. Discard your changes?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep my work'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Use AI scene'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (accept != true) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'AI scene saved to history; current edits preserved.',
            ),
          ),
        );
        return;
      }
    }
    _serverVersion = loaded.version;
    controller.replaceScene(loaded.scene);
  }

  /// Modify the current scene from a free-text prompt. Unlike the
  /// regenerate flow, this preserves everything the AI doesn't touch
  /// — single undo entry restores the pre-edit scene.
  Future<void> _editWithAi() async {
    final controller = _controller;
    if (controller == null) return;
    final prompt = await showAiFloorplanDialog(
      context,
      confirmLabel: 'Apply',
    );
    if (prompt == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final batch = await ServiceLocator.aiFloorplanService.generateEdit(
        scene: controller.scene,
        prompt: prompt,
      );
      if (!mounted) return;
      if (batch.operations.isEmpty) {
        messenger.showSnackBar(const SnackBar(
          content: Text(
            'AI returned no operations — try a more specific request.',
          ),
        ));
        return;
      }
      final warnings = controller.applyAiEditBatch(batch);
      final base = 'Applied ${batch.operations.length} '
          'AI edit${batch.operations.length == 1 ? '' : 's'} '
          '(use Undo to revert)';
      messenger.showSnackBar(SnackBar(
        content: Text(
          warnings.isEmpty
              ? base
              : '$base\n${warnings.length} op'
                  '${warnings.length == 1 ? '' : 's'} skipped — '
                  '${warnings.first}',
        ),
        duration: warnings.isEmpty
            ? const Duration(seconds: 3)
            : const Duration(seconds: 6),
      ));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(
          UserFacingError.uiMessage(e, action: 'apply AI edits'),
        ),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Show the AI dialog and dispatch a regeneration on the existing
  /// plan. Warns the user that it will replace the current scene.
  Future<void> _regenerateFromText() async {
    final plan = _plan;
    final controller = _controller;
    if (plan == null || controller == null) return;
    final auth = context.read<AuthProvider>();
    final user = auth.appUser;
    if (user == null) return;
    final prompt = await showAiFloorplanDialog(
      context,
      confirmLabel: 'Regenerate',
      warning: 'This will replace your current scene. The previous version '
          'is recoverable via Undo after the new scene loads.',
    );
    if (prompt == null || !mounted) return;
    try {
      final genService = _generationService;
      final aiService = ServiceLocator.aiFloorplanService;
      final sceneService = _sceneService;
      final generationId = await genService.beginGeneration(
        planId: plan.id,
        workspaceId: plan.workspaceId,
        projectId: plan.projectId,
        prompt: prompt,
        userId: user.id,
      );
      unawaited(() async {
        try {
          final aiPlan = await aiService.generate(prompt: prompt);
          final scene = aiPlanToScene(aiPlan, IdBroker());
          await sceneService.upsertScene(
            planId: plan.id,
            workspaceId: plan.workspaceId,
            projectId: plan.projectId,
            scene: scene,
            lastEditedBy: user.id,
          );
          await genService.markReady(
            generationId,
            aiPlanJson: {
              'rooms': aiPlan.rooms.length,
              'doors': aiPlan.doors.length,
              'windows': aiPlan.windows.length,
              'items': aiPlan.items.length,
            },
          );
        } catch (e) {
          await genService.markFailed(
            generationId,
            errorMessage: e.toString(),
          );
        }
      }());
    } on FloorplanGenerationConflict catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.uiMessage(e, action: 'regenerate floorplan'),
          ),
        ),
      );
    }
  }

  Future<void> _save() async {
    final controller = _controller;
    final plan = _plan;
    if (controller == null || plan == null || _saving) return;

    setState(() => _saving = true);
    try {
      final auth = context.read<AuthProvider>();
      final user = auth.appUser;
      if (user == null) throw Exception('Not signed in');

      final pngBytes = await ThumbnailRenderer.renderPng(controller.scene);
      final thumbUrl = await _sceneService.uploadThumbnail(
        workspaceId: plan.workspaceId,
        projectId: plan.projectId,
        planId: plan.id,
        bytes: pngBytes,
      );

      final result = await _sceneService.upsertScene(
        planId: plan.id,
        workspaceId: plan.workspaceId,
        projectId: plan.projectId,
        scene: controller.scene,
        thumbnailUrl: thumbUrl,
        lastEditedBy: user.id,
        expectedVersion: _serverVersion,
      );

      if (!mounted) return;
      _serverVersion = result.version;
      controller.markSaved();
      if (result.conflictDetected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Saved, but a newer version existed on the server — '
              'your changes overwrote them. Reload to compare.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserFacingError.uiMessage(e, action: 'save scene')),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final controller = _controller;
    if (controller == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Floorplan Editor')),
        body: Center(child: Text(_error ?? 'Unable to open editor')),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<FloorplanEditorController>.value(
          value: controller,
        ),
        Provider<FloorplanViewportController>.value(value: _viewport),
      ],
      child: _ShortcutScope(
        controller: controller,
        child: PopScope(
          canPop: !controller.dirty,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            _confirmDiscardOrSave();
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Below this width the rail moves to the bottom and the
              // inspector becomes a slide-up sheet. 700px keeps a
              // typical 7" tablet in the desktop layout while phones
              // and split-screen tablets get the compact one.
              final isCompact = constraints.maxWidth < AppBreakpoints.compact;
              return Scaffold(
                appBar: _buildAppBar(),
                body: isCompact
                    ? _buildCompactBody(controller)
                    : _buildWideBody(controller),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildWideBody(FloorplanEditorController controller) {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              const ToolRail(),
              Expanded(
                child: Stack(
                  children: [
                    const Positioned.fill(child: FloorplanCanvas()),
                    const Positioned(
                      left: 16,
                      bottom: 16,
                      child: GridPanel(),
                    ),
                    const Positioned(
                      right: 16,
                      bottom: 16,
                      child: LayerPanel(),
                    ),
                    const Positioned(
                      left: 0,
                      right: 0,
                      top: 12,
                      child: Center(child: CanvasHint()),
                    ),
                    if (controller.scene.background != null)
                      Positioned(
                        left: 16,
                        top: 56,
                        child: _BackgroundOpacityPanel(controller: controller),
                      ),
                    if (_shouldShowGenerationOverlay)
                      GeneratingOverlay(
                        prompt: _generation!.prompt,
                        error: _generation!.status == 'failed'
                            ? (_generation!.error ?? 'Unknown error')
                            : null,
                        onRetry: _generation!.status == 'failed'
                            ? _regenerateFromText
                            : null,
                        onDismiss: _generation!.status == 'failed'
                            ? () => setState(() => _generation = null)
                            : null,
                      ),
                  ],
                ),
              ),
              const PropertyInspector(),
            ],
          ),
        ),
        const StatusBar(),
      ],
    );
  }

  Widget _buildCompactBody(FloorplanEditorController controller) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              const Positioned.fill(child: FloorplanCanvas()),
              const Positioned(
                left: 0,
                right: 0,
                top: 8,
                child: Center(child: CanvasHint()),
              ),
              if (controller.scene.background != null)
                Positioned(
                  left: 12,
                  top: 48,
                  child: _BackgroundOpacityPanel(controller: controller),
                ),
              // FAB cluster — compact layouts replace the wide-only
              // GridPanel + LayerPanel + PropertyInspector with three
              // bottom sheets.
              Positioned(
                right: 12,
                bottom: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FloatingActionButton.small(
                      heroTag: 'fp-grid-fab',
                      tooltip: 'Grid & units',
                      onPressed: () => _openGridSheet(context),
                      child: const Icon(Icons.grid_4x4),
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton.small(
                      heroTag: 'fp-layers-fab',
                      tooltip: 'Layers',
                      onPressed: () => _openLayersSheet(context),
                      child: const Icon(Icons.layers_outlined),
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton.small(
                      heroTag: 'fp-inspector-fab',
                      tooltip: 'Properties',
                      onPressed: () => _openInspectorSheet(context),
                      child: const Icon(Icons.tune),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const StatusBar(compact: true),
        ToolRail(horizontal: true, more: _compactMoreEntries(controller)),
      ],
    );
  }

  bool get _isMobilePlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  List<ToolRailMoreEntry> _compactMoreEntries(
    FloorplanEditorController controller,
  ) =>
      [
        ToolRailMoreEntry(
          icon: Icons.auto_fix_high,
          label: 'Edit with AI…',
          onTap: _editWithAi,
        ),
        ToolRailMoreEntry(
          icon: Icons.auto_awesome,
          label: 'Regenerate from text…',
          onTap: _regenerateFromText,
        ),
        if (_isMobilePlatform)
          ToolRailMoreEntry(
            icon: Icons.view_in_ar_outlined,
            label: 'Add scanned room…',
            onTap: _addScannedRoom,
          ),
        ToolRailMoreEntry(
          icon: Icons.straighten,
          label: 'Calibrate scale…',
          onTap: () => showCalibrationDialog(context, controller),
        ),
        ToolRailMoreEntry(
          icon: Icons.ios_share,
          label: 'Export…',
          onTap: () => showExportDialog(
            context,
            controller,
            planTitle: _plan?.name,
          ),
        ),
      ];

  /// Push into the room-scan screen in "append" mode. If the user has
  /// unsaved edits we save first — the append flow re-loads the scene
  /// from Supabase and would clobber in-memory work otherwise.
  Future<void> _addScannedRoom() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.dirty) {
      final messenger = ScaffoldMessenger.of(context);
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Save before scanning?'),
          content: const Text(
            'A room scan re-loads the scene from the server, which would '
            'discard your unsaved edits. Save first?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save and scan'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
      await _save();
      if (!mounted || controller.dirty) {
        // _save() flips dirty back to clean on success; still-dirty
        // means the save failed and a snackbar is already up.
        messenger.showSnackBar(
          const SnackBar(
              content: Text('Save failed — fix the error and try again.')),
        );
        return;
      }
    }
    if (!mounted) return;
    context.push(
      '/projects/${widget.projectId}/plans/${widget.planId}/scan',
    );
  }

  Future<void> _openLayersSheet(BuildContext context) async {
    final controller = _controller;
    if (controller == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return ChangeNotifierProvider<FloorplanEditorController>.value(
          value: controller,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: LayerPanel(width: null, bare: true),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openGridSheet(BuildContext context) async {
    final controller = _controller;
    if (controller == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return ChangeNotifierProvider<FloorplanEditorController>.value(
          value: controller,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: GridPanel(bare: true),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openInspectorSheet(BuildContext context) async {
    final controller = _controller;
    if (controller == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return ChangeNotifierProvider<FloorplanEditorController>.value(
          value: controller,
          child: DraggableScrollableSheet(
            initialChildSize: 0.5,
            minChildSize: 0.25,
            maxChildSize: 0.9,
            expand: false,
            builder: (_, scrollController) {
              return SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(AppSpacing.base),
                child: const PropertyInspector(),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _renamePlan(String name) async {
    final plan = _plan;
    if (plan == null) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == plan.name) return;
    try {
      await _planService.renamePlan(
        planId: plan.id,
        workspaceId: plan.workspaceId,
        name: trimmed,
      );
      if (!mounted) return;
      setState(() => _plan = plan.copyWith(name: trimmed));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserFacingError.uiMessage(e, action: 'rename plan')),
        ),
      );
    }
  }

  /// Triggered by [PopScope] when the user tries to leave with unsaved
  /// edits. Asks Save / Discard / Cancel; on Save we await and pop, on
  /// Discard we pop, on Cancel we stay.
  Future<void> _confirmDiscardOrSave() async {
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text(
          'You have unsaved changes. What would you like to do?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'discard'),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'save') {
      await _save();
      if (!mounted) return;
      if (!_controller!.dirty) context.pop();
    } else if (choice == 'discard') {
      _controller?.markSaved(); // disarm the dirty flag
      if (mounted) context.pop();
    }
    // 'cancel' or null: stay on the editor.
  }

  PreferredSizeWidget _buildAppBar() {
    final controller = _controller!;
    return AppBar(
      title: Row(
        children: [
          _InlineTitle(
            initial: _plan?.name ?? 'Floorplan',
            onCommit: _renamePlan,
          ),
          const SizedBox(width: 8),
          AnimatedBuilder(
            animation: controller,
            builder: (ctx, __) => controller.dirty
                ? const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.circle, size: 8, color: Colors.orange),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      actions: [
        AnimatedBuilder(
          animation: controller,
          builder: (ctx2, __) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete selection (Del)',
                onPressed: controller.scene.selectedLayer.selected.isNotEmpty
                    ? controller.deleteSelected
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.undo),
                tooltip: 'Undo',
                onPressed: controller.canUndo ? controller.undo : null,
              ),
              IconButton(
                icon: const Icon(Icons.redo),
                tooltip: 'Redo',
                onPressed: controller.canRedo ? controller.redo : null,
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  switch (value) {
                    case 'calibrate':
                      showCalibrationDialog(context, controller);
                    case 'ai':
                      _regenerateFromText();
                    case 'edit_ai':
                      _editWithAi();
                    case 'scan':
                      if (_isMobilePlatform) {
                        _addScannedRoom();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Room scanning is only available on the '
                              'FieldFleet mobile app.',
                            ),
                          ),
                        );
                      }
                    case 'export':
                      showExportDialog(
                        context,
                        controller,
                        planTitle: _plan?.name,
                      );
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit_ai',
                    child: Row(
                      children: [
                        Icon(Icons.auto_fix_high, size: 18),
                        SizedBox(width: 8),
                        Text('Edit with AI…'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'ai',
                    child: Row(
                      children: [
                        Icon(Icons.auto_awesome, size: 18),
                        SizedBox(width: 8),
                        Text('Regenerate from text…'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'scan',
                    enabled: _isMobilePlatform,
                    child: Row(
                      children: [
                        Icon(
                          Icons.view_in_ar_outlined,
                          size: 18,
                          color: _isMobilePlatform
                              ? null
                              : Theme.of(context).disabledColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isMobilePlatform
                              ? 'Add scanned room…'
                              : 'Add scanned room (mobile only)',
                          style: _isMobilePlatform
                              ? null
                              : TextStyle(
                                  color: Theme.of(context).disabledColor,
                                ),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'calibrate',
                    child: Row(
                      children: [
                        Icon(Icons.straighten, size: 18),
                        SizedBox(width: 8),
                        Text('Calibrate scale…'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'export',
                    child: Row(
                      children: [
                        Icon(Icons.ios_share, size: 18),
                        SizedBox(width: 8),
                        Text('Export…'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: const Text('Save'),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(
                  widget.fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                ),
                tooltip: widget.fullscreen ? 'Exit fullscreen' : 'Fullscreen',
                onPressed: () {
                  if (widget.fullscreen) {
                    context.go(
                      '/projects/${widget.projectId}/plans/${widget.planId}/edit',
                    );
                  } else {
                    context.go(
                      '/projects/${widget.projectId}/plans/${widget.planId}/edit/fullscreen',
                    );
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Close',
                onPressed: () => context.pop(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tap-to-edit text replacing the static plan title in the toolbar.
/// Reverts to read-only on commit (Enter / blur). The pencil icon hint
/// only shows on hover so the toolbar isn't cluttered when not editing.
class _InlineTitle extends StatefulWidget {
  final String initial;
  final ValueChanged<String> onCommit;

  const _InlineTitle({required this.initial, required this.onCommit});

  @override
  State<_InlineTitle> createState() => _InlineTitleState();
}

class _InlineTitleState extends State<_InlineTitle> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial);
  final FocusNode _focus = FocusNode();
  bool _editing = false;
  bool _hovering = false;

  @override
  void didUpdateWidget(covariant _InlineTitle old) {
    super.didUpdateWidget(old);
    if (!_editing && widget.initial != _ctrl.text) {
      _ctrl.text = widget.initial;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _start() {
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      selectAllText(_ctrl);
    });
  }

  void _commit() {
    if (!_editing) return;
    setState(() => _editing = false);
    widget.onCommit(_ctrl.text);
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return SizedBox(
        width: 240,
        child: TextField(
          controller: _ctrl,
          focusNode: _focus,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            contentPadding:
                EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _commit(),
          onTapOutside: (_) => _commit(),
        ),
      );
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.text,
      child: GestureDetector(
        onTap: _start,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_ctrl.text),
            if (_hovering)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.edit, size: 14),
              ),
          ],
        ),
      ),
    );
  }
}

/// Wraps the editor in a [Shortcuts]/[Actions] pair so single-letter tool
/// keys and Ctrl+Z/Y undo work regardless of focus inside the canvas.
class _ShortcutScope extends StatelessWidget {
  final FloorplanEditorController controller;
  final Widget child;

  const _ShortcutScope({required this.controller, required this.child});

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.escape): const _CancelIntent(),
        const SingleActivator(LogicalKeyboardKey.keyV): const _ModeIntent('v'),
        const SingleActivator(LogicalKeyboardKey.keyH): const _ModeIntent('h'),
        const SingleActivator(LogicalKeyboardKey.keyW): const _ModeIntent('w'),
        const SingleActivator(LogicalKeyboardKey.keyD): const _ModeIntent('d'),
        const SingleActivator(LogicalKeyboardKey.keyN): const _ModeIntent('n'),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            const _UndoIntent(),
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
            const _UndoIntent(),
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): const _RedoIntent(),
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          meta: true,
          shift: true,
        ): const _RedoIntent(),
        const SingleActivator(LogicalKeyboardKey.keyY, control: true):
            const _RedoIntent(),
        const SingleActivator(LogicalKeyboardKey.delete): const _DeleteIntent(),
        const SingleActivator(LogicalKeyboardKey.backspace):
            const _DeleteIntent(),
        const SingleActivator(LogicalKeyboardKey.keyR): const _FlipDoorIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _CancelIntent: CallbackAction<_CancelIntent>(
            onInvoke: (_) {
              controller.cancelDrawing();
              if (controller.mode is! IdleMode) {
                controller.setMode(const IdleMode());
              }
              return null;
            },
          ),
          _UndoIntent: CallbackAction<_UndoIntent>(
            onInvoke: (_) {
              if (controller.canUndo) controller.undo();
              return null;
            },
          ),
          _RedoIntent: CallbackAction<_RedoIntent>(
            onInvoke: (_) {
              if (controller.canRedo) controller.redo();
              return null;
            },
          ),
          _DeleteIntent: CallbackAction<_DeleteIntent>(
            onInvoke: (_) {
              controller.deleteSelected();
              return null;
            },
          ),
          _FlipDoorIntent: CallbackAction<_FlipDoorIntent>(
            onInvoke: (_) {
              controller.flipSelectedDoor();
              return null;
            },
          ),
          _ModeIntent: CallbackAction<_ModeIntent>(
            onInvoke: (intent) {
              switch (intent.key) {
                case 'v':
                  controller.setMode(const IdleMode());
                case 'h':
                  controller.setMode(const PanMode());
                case 'w':
                  controller.setMode(const WaitingDrawingWallMode());
                case 'd':
                  controller.setMode(
                    const WaitingDrawingHoleMode(holePrototype: 'door'),
                  );
                case 'n':
                  controller.setMode(
                    const WaitingDrawingHoleMode(holePrototype: 'window'),
                  );
              }
              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}

class _CancelIntent extends Intent {
  const _CancelIntent();
}

class _UndoIntent extends Intent {
  const _UndoIntent();
}

class _RedoIntent extends Intent {
  const _RedoIntent();
}

class _DeleteIntent extends Intent {
  const _DeleteIntent();
}

class _FlipDoorIntent extends Intent {
  const _FlipDoorIntent();
}

class _ModeIntent extends Intent {
  final String key;
  const _ModeIntent(this.key);
}

class _BackgroundOpacityPanel extends StatelessWidget {
  final FloorplanEditorController controller;

  const _BackgroundOpacityPanel({required this.controller});

  @override
  Widget build(BuildContext context) {
    final bg = controller.scene.background;
    if (bg == null) return const SizedBox.shrink();
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.layers_outlined, size: 16),
          const SizedBox(width: 8),
          Text(
            'PDF underlay',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 140,
            child: Slider(
              value: bg.opacity.clamp(0, 1),
              min: 0,
              max: 1,
              onChanged: controller.setBackgroundOpacity,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            tooltip: 'Remove underlay',
            onPressed: controller.clearBackground,
          ),
        ],
      ),
    );
  }
}

// _CatalogMenuButton, _AnnotationMenuButton and _ToolToggle moved to
// lib/widgets/floorplan/tool_rail.dart in Phase 6 — the editor's AppBar
// no longer hosts tool buttons.
