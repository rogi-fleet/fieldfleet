import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../models/floorplan/scan/floor_plan_scan_result.dart';
import '../../../models/floorplan/scan/room_scan_capabilities.dart';
import '../../../models/floorplan/scene.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/floorplan/ai_edit_to_scene.dart';
import '../../../services/floorplan/scan/room_scan_controller.dart';
import '../../../services/floorplan/scan/scan_to_scene.dart';
import '../../../services/service_locator.dart';
import '../../../utils/floorplan/id_broker.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/floorplan/ai_floorplan_dialog.dart';
import '../../../widgets/floorplan/scan/room_scan_overlay.dart';
import '../../../widgets/floorplan/scan/room_scan_platform_view.dart';
import '../../../widgets/floorplan/scan/scan_review_sheet.dart';
import 'room_scan_unsupported_screen.dart';
import '../../../theme/theme.dart';

/// Full-screen room scan flow, scoped to a project.
///
/// Two modes:
///
///   * **Create mode** (the default): when [appendToPlanId] is null, the
///     scan creates a new plan via `SupabasePlanService.createEditorPlan`,
///     upserts the converted [Scene], and pushes into the editor.
///   * **Append mode**: when [appendToPlanId] is non-null, the scan
///     loads the existing scene, appends the new room via
///     `ScanToScene.appendInto`, upserts, and returns to the editor.
///     Used when scanning room N of a plan started earlier.
class RoomScanScreen extends StatefulWidget {
  final String projectId;
  final String? propertyId;

  /// When set, append-into-plan mode. The screen loads this plan's scene
  /// on scan completion and merges the new room into its selected layer.
  final String? appendToPlanId;

  const RoomScanScreen({
    super.key,
    required this.projectId,
    this.propertyId,
    this.appendToPlanId,
  });

  bool get isAppendMode => appendToPlanId != null;

  @override
  State<RoomScanScreen> createState() => _RoomScanScreenState();
}

class _RoomScanScreenState extends State<RoomScanScreen>
    with WidgetsBindingObserver {
  final RoomScanController _controller = RoomScanController();
  bool _persisting = false;

  /// AI refinement is allowed once per scan result — repeated refinements
  /// on the same scan tend to amplify the model's biases (it'll keep
  /// renaming rooms or moving doors around). After the first refine the
  /// button hides and the user opens the editor where Edit-with-AI is
  /// the right tool for further iteration.
  bool _refined = false;

  /// Holds the scene after a Refine-with-AI pass. Subsequent
  /// "Open in editor" persists this instead of re-converting the raw
  /// scan, so the AI cleanup actually lands.
  Scene? _refinedScene;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // App leaving the foreground — pause the AR session so the OS
        // doesn't kill it for using the camera in the background.
        _controller.pauseCapture();
      case AppLifecycleState.resumed:
        // User came back. Try to resume; if the OS reclaimed the AR
        // session the controller transitions to failed and the
        // unsupported screen explains.
        _controller.resumeCapture();
      case AppLifecycleState.detached:
        // Process detach — controller.dispose will run on its own.
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final phase = _controller.phase;

        if (phase == RoomScanPhase.unsupported ||
            phase == RoomScanPhase.failed) {
          final reason = _controller.failure?.message ??
              _controller.capabilities?.unsupportedReason ??
              'This device cannot run a room scan.';
          return RoomScanUnsupportedScreen(
            reason: reason,
            failureKind: _controller.failure?.kind,
            backRoute: '/projects/${widget.projectId}/plans',
          );
        }

        return Scaffold(
          backgroundColor: Colors.black,
          body: SizedBox.expand(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_canShowNativeView(phase)) const RoomScanPlatformView(),
                if (phase == RoomScanPhase.requestingPermission ||
                    phase == RoomScanPhase.checkingCapabilities)
                  const _BootstrapOverlay(),
                if (phase == RoomScanPhase.ready) _ReadyOverlay(
                  capabilities: _controller.capabilities,
                  multiRoomEnabled: _controller.multiRoomEnabled,
                  onToggleMultiRoom: _controller.setMultiRoomEnabled,
                  onStart: _controller.startCapture,
                  onCancel: () => _exit(),
                ),
                if (phase == RoomScanPhase.capturing ||
                    phase == RoomScanPhase.finishing)
                  RoomScanOverlay(
                    controller: _controller,
                    onCancel: _confirmCancel,
                    onFinish: _controller.finishCapture,
                    onUndoTap: _controller.undoLastTap,
                  ),
                if (phase == RoomScanPhase.paused)
                  _PausedOverlay(
                    onResume: _controller.resumeCapture,
                    onCancel: () async {
                      await _controller.cancelCapture();
                      if (mounted) _exit();
                    },
                  ),
                if (phase == RoomScanPhase.betweenRooms)
                  _BetweenRoomsOverlay(
                    completedRoomCount: _controller.completedRoomCount,
                    onScanNext: _controller.startCapture,
                    onFinishAll: _controller.finishAllRooms,
                    onCancel: () async {
                      final confirmed = await _confirmDiscard();
                      if (confirmed && mounted) {
                        await _controller.cancelCapture();
                        if (mounted) _exit();
                      }
                    },
                  ),
              ],
            ),
          ),
          bottomSheet: phase == RoomScanPhase.reviewing &&
                  _controller.result != null
              ? ScanReviewSheet(
                  result: _controller.result!,
                  busy: _persisting,
                  onOpenInEditor: _openInEditor,
                  // Refine-with-AI is create-mode only. In append mode
                  // the user gets refinement via the editor's existing
                  // "Edit with AI…" action after appending.
                  onRefineWithAi: widget.isAppendMode || _refined
                      ? null
                      : _refineWithAi,
                  onRescan: _rescan,
                  onDiscard: _discard,
                )
              : null,
        );
      },
    );
  }

  bool _canShowNativeView(RoomScanPhase phase) {
    return phase == RoomScanPhase.ready ||
        phase == RoomScanPhase.capturing ||
        phase == RoomScanPhase.finishing ||
        phase == RoomScanPhase.reviewing ||
        phase == RoomScanPhase.betweenRooms ||
        phase == RoomScanPhase.paused;
  }

  Future<bool> _confirmDiscard() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard scan?'),
        content: const Text(
          'You\'ll lose every room captured so far. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep scanning'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _confirmCancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard scan?'),
        content: const Text(
          'The current scan will be lost. You can start a new one any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep scanning'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _controller.cancelCapture();
      if (mounted) _exit();
    }
  }

  void _exit() {
    if (!mounted) return;
    final canPop = Navigator.of(context).canPop();
    if (canPop) {
      Navigator.of(context).pop();
    } else {
      context.go('/projects/${widget.projectId}/plans');
    }
  }

  Future<void> _openInEditor() async {
    final result = _controller.result;
    if (result == null) return;
    final auth = context.read<AuthProvider>();
    final user = auth.appUser;
    final workspaceId = user?.currentWorkspaceId;
    if (user == null || workspaceId == null) {
      _showSnack('Not signed in');
      return;
    }
    setState(() => _persisting = true);
    try {
      if (widget.isAppendMode) {
        await _appendIntoExistingPlan(
          result: result,
          workspaceId: workspaceId,
          userId: user.id,
        );
      } else {
        await _createPlanFromScan(
          result: result,
          workspaceId: workspaceId,
          userId: user.id,
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnack(UserFacingError.uiMessage(e, action: 'save scan'));
      }
    } finally {
      if (mounted) setState(() => _persisting = false);
    }
  }

  Future<void> _createPlanFromScan({
    required FloorPlanScanResult result,
    required String workspaceId,
    required String userId,
  }) async {
    final scene = _refinedScene ?? ScanToScene.convert(result, ids: IdBroker());
    final plan = await ServiceLocator.planService.createEditorPlan(
      projectId: widget.projectId,
      workspaceId: workspaceId,
      propertyId: widget.propertyId,
      name: scene.name,
      createdBy: userId,
    );
    await ServiceLocator.floorplanSceneService.upsertScene(
      planId: plan.id,
      workspaceId: workspaceId,
      projectId: widget.projectId,
      scene: scene,
      lastEditedBy: userId,
      // Archive the raw scan so we can re-process this plan later with
      // a better wall-graph algorithm without a re-capture from the user.
      scanMetadata: result.toJson(),
    );
    if (!mounted) return;
    context.go('/projects/${widget.projectId}/plans/${plan.id}/edit');
  }

  Future<void> _appendIntoExistingPlan({
    required FloorPlanScanResult result,
    required String workspaceId,
    required String userId,
  }) async {
    final planId = widget.appendToPlanId!;
    final sceneService = ServiceLocator.floorplanSceneService;
    // Load the latest version of the scene. If the user has unsaved
    // edits in the editor we'll necessarily clobber them — the editor
    // ought to have saved before launching the append flow.
    final loaded = await sceneService.getScene(planId);
    if (loaded == null) {
      _showSnack(
          'Scene not found — open the plan in the editor and save first.');
      return;
    }
    final merged = ScanToScene.appendInto(loaded.scene, result);
    await sceneService.upsertScene(
      planId: planId,
      workspaceId: workspaceId,
      projectId: widget.projectId,
      scene: merged,
      lastEditedBy: userId,
      expectedVersion: loaded.version,
    );
    if (!mounted) return;
    context.go('/projects/${widget.projectId}/plans/$planId/edit');
  }

  /// Pre-editor AI cleanup pass. Asks the user for an instruction (the
  /// dialog defaults to a useful starter), runs the existing
  /// `generateEdit` pipeline against the scan's converted scene, applies
  /// the resulting batch, and stashes the cleaned scene so the next
  /// "Open in editor" persists it instead of the raw conversion.
  Future<void> _refineWithAi() async {
    final result = _controller.result;
    if (result == null) return;

    final prompt = await showAiFloorplanDialog(
      context,
      confirmLabel: 'Refine',
      warning:
          'AI will rewrite the scan — squaring walls, labelling rooms, '
          'or whatever you describe. You can still undo every change '
          'in the editor afterwards.',
    );
    if (prompt == null || !mounted) return;

    setState(() => _persisting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final baseScene =
          _refinedScene ?? ScanToScene.convert(result, ids: IdBroker());
      final batch = await ServiceLocator.aiFloorplanService.generateEdit(
        scene: baseScene,
        prompt: prompt,
      );
      if (!mounted) return;
      if (batch.operations.isEmpty) {
        messenger.showSnackBar(const SnackBar(
          content:
              Text('AI returned no operations — try a more specific request.'),
        ));
        return;
      }
      final refinedResult = applyAiEditsWithReport(
        baseScene,
        batch.operations,
        IdBroker(),
      );
      setState(() {
        _refinedScene = refinedResult.scene;
        _refined = true;
      });
      messenger.showSnackBar(SnackBar(
        content: Text(
          'Applied ${batch.operations.length} AI edit'
          '${batch.operations.length == 1 ? '' : 's'}'
          '${refinedResult.warnings.isEmpty ? '' : ' (${refinedResult.warnings.length} skipped)'}',
        ),
      ));
    } catch (e) {
      if (mounted) {
        _showSnack(UserFacingError.uiMessage(e, action: 'refine scan'));
      }
    } finally {
      if (mounted) setState(() => _persisting = false);
    }
  }

  void _rescan() {
    _controller.discardResult();
    _refinedScene = null;
    _refined = false;
    _controller.startCapture();
  }

  void _discard() {
    _controller.discardResult();
    _exit();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _PausedOverlay extends StatelessWidget {
  final VoidCallback onResume;
  final VoidCallback onCancel;
  const _PausedOverlay({required this.onResume, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.55),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.pause_circle_outline,
                    size: 64, color: Colors.white),
                const SizedBox(height: 12),
                const Text(
                  'Scan paused',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'The AR session paused while the app was in the '
                  'background. Tap resume to keep scanning.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onResume,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Resume scanning'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onCancel,
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BetweenRoomsOverlay extends StatelessWidget {
  final int completedRoomCount;
  final VoidCallback onScanNext;
  final VoidCallback onFinishAll;
  final VoidCallback onCancel;

  const _BetweenRoomsOverlay({
    required this.completedRoomCount,
    required this.onScanNext,
    required this.onFinishAll,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.55),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline,
                    size: 64, color: Colors.lightGreenAccent),
                const SizedBox(height: 12),
                Text(
                  'Room $completedRoomCount captured',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Walk to the next room and start scanning, or merge '
                  'everything you\'ve captured so far.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onScanNext,
                    icon: const Icon(Icons.add_circle_outline),
                    label: Text('Scan room ${completedRoomCount + 1}'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onFinishAll,
                    icon: const Icon(Icons.merge_type),
                    label: const Text('Finish all rooms'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onCancel,
                  child: const Text(
                    'Discard all',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BootstrapOverlay extends StatelessWidget {
  const _BootstrapOverlay();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 16),
          Text(
            'Preparing room scanner…',
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _ReadyOverlay extends StatelessWidget {
  final RoomScanCapabilities? capabilities;
  final bool multiRoomEnabled;
  final ValueChanged<bool> onToggleMultiRoom;
  final VoidCallback onStart;
  final VoidCallback onCancel;

  const _ReadyOverlay({
    required this.capabilities,
    required this.multiRoomEnabled,
    required this.onToggleMultiRoom,
    required this.onStart,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final engine = capabilities?.engine;
    final hasDepth = capabilities?.hasDepthSensor ?? false;
    final blurb = switch (engine) {
      ScanSourceEngine.roomPlan =>
        'Slowly walk around the room — RoomPlan will detect walls, doors, '
            'windows, and furniture as you go.',
      ScanSourceEngine.arCoreDepth =>
        'Tap each corner of the room. Depth-aware hit-testing keeps the '
            'taps accurate on walls and the floor.',
      ScanSourceEngine.arCorePlaneTap ||
      ScanSourceEngine.arKitPlaneTap =>
        'Stand at one corner, tap to drop a marker, then walk to the next '
            'corner. Tap each corner of the room.',
      null => 'Tap to begin the scan.',
    };
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                onPressed: onCancel,
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(AppSpacing.base),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(AppRadius.r16),
              ),
              child: Column(
                children: [
                  Text(
                    hasDepth ? 'Ready to scan with depth' : 'Ready to scan',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    blurb,
                    style: const TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  if (capabilities?.supportsMultiRoom == true) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppRadius.r12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.holiday_village_outlined,
                              color: Colors.white70, size: 18),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Scan multiple rooms',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                          Switch(
                            value: multiRoomEnabled,
                            onChanged: onToggleMultiRoom,
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onStart,
                      icon: const Icon(Icons.play_arrow),
                      label: Text(multiRoomEnabled
                          ? 'Start first room'
                          : 'Start scanning'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
