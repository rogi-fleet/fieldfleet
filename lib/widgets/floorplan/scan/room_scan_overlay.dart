import 'package:flutter/material.dart';

import '../../../models/floorplan/scan/floor_plan_scan_result.dart';
import '../../../services/floorplan/scan/room_scan_channel.dart';
import '../../../services/floorplan/scan/room_scan_controller.dart';
import '../../../theme/theme.dart';

/// Floating HUD over the native AR view: guidance pill, live counts,
/// finish / cancel buttons.
class RoomScanOverlay extends StatelessWidget {
  final RoomScanController controller;
  final VoidCallback onCancel;
  final VoidCallback onFinish;
  final Future<void> Function() onUndoTap;

  const RoomScanOverlay({
    super.key,
    required this.controller,
    required this.onCancel,
    required this.onFinish,
    required this.onUndoTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: 12,
                left: 12,
                child: _CancelButton(onTap: onCancel),
              ),
              Positioned(
                top: 16,
                left: 0,
                right: 0,
                child: Center(child: _GuidancePill(controller: controller)),
              ),
              Positioned(
                bottom: 32,
                left: 0,
                right: 0,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                  child: Row(
                    children: [
                      Expanded(child: _ProgressChips(controller: controller)),
                      const SizedBox(width: 12),
                      if (_engineSupportsUndo(controller))
                        _UndoButton(
                          enabled: controller.progress.walls > 0 &&
                              controller.phase == RoomScanPhase.capturing,
                          onTap: onUndoTap,
                        ),
                      const SizedBox(width: 12),
                      _FinishButton(
                        enabled:
                            controller.phase == RoomScanPhase.capturing,
                        loading:
                            controller.phase == RoomScanPhase.finishing,
                        onTap: onFinish,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CancelButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CancelButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Icon(Icons.close, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _GuidancePill extends StatelessWidget {
  final RoomScanController controller;
  const _GuidancePill({required this.controller});

  @override
  Widget build(BuildContext context) {
    final guidance = controller.guidance;
    final phase = controller.phase;
    final (icon, text, color) = _resolve(guidance, phase);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  (IconData, String, Color) _resolve(
    RoomScanGuidanceEvent? g,
    RoomScanPhase phase,
  ) {
    if (g != null) {
      switch (g.severity) {
        case GuidanceSeverity.info:
          return (Icons.info_outline, g.message, Colors.lightBlueAccent);
        case GuidanceSeverity.warn:
          return (Icons.warning_amber, g.message, Colors.amberAccent);
        case GuidanceSeverity.error:
          return (Icons.error_outline, g.message, Colors.redAccent);
      }
    }
    switch (phase) {
      case RoomScanPhase.capturing:
        return (
          Icons.camera_rear_outlined,
          'Walk around the room — keep the camera level',
          Colors.white,
        );
      case RoomScanPhase.finishing:
        return (
          Icons.hourglass_top,
          'Processing scan…',
          Colors.lightGreenAccent,
        );
      default:
        return (Icons.info_outline, 'Hold still while we initialise', Colors.white);
    }
  }
}

class _ProgressChips extends StatelessWidget {
  final RoomScanController controller;
  const _ProgressChips({required this.controller});

  @override
  Widget build(BuildContext context) {
    final p = controller.progress;
    final chips = <Widget>[
      _chip(Icons.crop_square, '${p.walls} walls'),
      if (p.openings > 0)
        _chip(Icons.door_front_door_outlined, '${p.openings} openings'),
      if (p.objects > 0) _chip(Icons.chair_outlined, '${p.objects} objects'),
    ];
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  Widget _chip(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 16),
            const SizedBox(width: 6),
            Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      );
}

bool _engineSupportsUndo(RoomScanController controller) {
  final engine = controller.capabilities?.engine;
  return engine == ScanSourceEngine.arKitPlaneTap ||
      engine == ScanSourceEngine.arCoreDepth ||
      engine == ScanSourceEngine.arCorePlaneTap;
}

class _UndoButton extends StatelessWidget {
  final bool enabled;
  final Future<void> Function() onTap;
  const _UndoButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: enabled ? Colors.black.withValues(alpha: 0.7) : Colors.black38,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? () => onTap() : null,
          child: const Icon(Icons.undo_rounded, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}

class _FinishButton extends StatelessWidget {
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;
  const _FinishButton({
    required this.enabled,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: Material(
        color: enabled ? Colors.green.shade600 : Colors.grey.shade700,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled && !loading ? onTap : null,
          child: loading
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                )
              : const Icon(Icons.check, color: Colors.white, size: 32),
        ),
      ),
    );
  }
}
