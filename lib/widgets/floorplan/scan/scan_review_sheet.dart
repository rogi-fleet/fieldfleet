import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../models/floorplan/scan/floor_plan_scan_result.dart';
import '../../../theme/theme.dart';

/// Bottom sheet shown after a successful capture. Lists what was detected
/// and offers the primary action — open it in the floorplan editor.
class ScanReviewSheet extends StatelessWidget {
  final FloorPlanScanResult result;
  final VoidCallback onOpenInEditor;
  final VoidCallback? onRefineWithAi;
  final VoidCallback onRescan;
  final VoidCallback onDiscard;
  final bool busy;

  const ScanReviewSheet({
    super.key,
    required this.result,
    required this.onOpenInEditor,
    this.onRefineWithAi,
    required this.onRescan,
    required this.onDiscard,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Scan ready',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  _EnginePill(engine: result.engine, confidence: result.confidence),
                ],
              ),
              const SizedBox(height: 12),
              if (result.thumbnailPngBase64 != null)
                _ThumbnailPreview(base64Png: result.thumbnailPngBase64!),
              const SizedBox(height: 12),
              _SummaryGrid(result: result),
              if (result.confidence < 0.5) ...[
                const SizedBox(height: 12),
                _LowConfidenceBanner(confidence: result.confidence),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: busy ? null : onOpenInEditor,
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.edit_outlined),
                  label: const Text('Open in editor'),
                ),
              ),
              if (onRefineWithAi != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onRefineWithAi,
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('Refine with AI…'),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : onRescan,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Rescan'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : onDiscard,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Discard'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnginePill extends StatelessWidget {
  final ScanSourceEngine engine;
  final double confidence;
  const _EnginePill({required this.engine, required this.confidence});

  @override
  Widget build(BuildContext context) {
    final label = switch (engine) {
      ScanSourceEngine.roomPlan => 'RoomPlan',
      ScanSourceEngine.arKitPlaneTap => 'iOS tap',
      ScanSourceEngine.arCoreDepth => 'ARCore depth',
      ScanSourceEngine.arCorePlaneTap => 'ARCore tap',
    };
    final pct = (confidence * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Text(
        '$label · $pct%',
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  final FloorPlanScanResult result;
  const _SummaryGrid({required this.result});

  @override
  Widget build(BuildContext context) {
    final rooms = result.rooms.length;
    final doors =
        result.openings.where((o) => o.kind == OpeningKind.door).length;
    final windows =
        result.openings.where((o) => o.kind == OpeningKind.window).length;
    final objects = result.objects.length;
    final ceiling = result.ceilingHeightMeters;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _StatTile(icon: Icons.home_outlined, label: 'Rooms', value: '$rooms'),
        _StatTile(
            icon: Icons.door_front_door_outlined,
            label: 'Doors',
            value: '$doors'),
        _StatTile(
            icon: Icons.window_outlined, label: 'Windows', value: '$windows'),
        if (objects > 0)
          _StatTile(
              icon: Icons.chair_outlined, label: 'Objects', value: '$objects'),
        if (ceiling != null)
          _StatTile(
            icon: Icons.height,
            label: 'Ceiling',
            value: '${ceiling.toStringAsFixed(2)} m',
          ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Amber-on-amber warning ribbon shown when the bridge couldn't form a
/// confident polygon (typically: convex-hull fallback fired on iOS, or
/// the user only tapped a few corners on Android). The user can still
/// open the scene in the editor — the warning just primes them to
/// double-check dimensions before relying on the result.
class _LowConfidenceBanner extends StatelessWidget {
  final double confidence;
  const _LowConfidenceBanner({required this.confidence});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final pct = (confidence * 100).round();
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.error.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: colors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Low-confidence scan · $pct%',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colors.error,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  'The scanner couldn\'t form a confident room shape. '
                  'Verify the dimensions in the editor before sharing.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThumbnailPreview extends StatelessWidget {
  final String base64Png;
  const _ThumbnailPreview({required this.base64Png});

  @override
  Widget build(BuildContext context) {
    Uint8List? bytes;
    try {
      bytes = base64Decode(base64Png);
    } catch (_) {
      bytes = null;
    }
    if (bytes == null) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.r12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Image.memory(bytes, fit: BoxFit.contain),
      ),
    );
  }
}
