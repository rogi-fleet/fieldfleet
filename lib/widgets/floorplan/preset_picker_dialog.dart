import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../services/floorplan/presets.dart';
import '../mobile_app/app_download_section.dart';
import '../../theme/theme.dart';

/// Modal grid picker shown before a new floorplan is created. Returns the
/// selected [FloorplanPreset], or null if the user cancels.
Future<FloorplanPreset?> showPresetPicker(BuildContext context) {
  return showDialog<FloorplanPreset>(
    context: context,
    builder: (dialogContext) => const _PresetPickerDialog(),
  );
}

class _PresetPickerDialog extends StatelessWidget {
  const _PresetPickerDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Start a new floorplan',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Pick a starting point. You can change anything afterwards.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: GridView.builder(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.05,
                  ),
                  itemCount: defaultPresets.length,
                  itemBuilder: (context, i) =>
                      _PresetCard(preset: defaultPresets[i]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  final FloorplanPreset preset;
  const _PresetCard({required this.preset});

  /// Some presets only work on certain platforms. Scan needs a real
  /// camera + AR runtime; the picker renders the tile as disabled
  /// (rather than hiding it) so users can see the feature exists.
  bool get _isMobileOnly => preset.id == 'scan';
  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  bool get _isAvailable => !_isMobileOnly || _isMobile;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final disabled = !_isAvailable;
    final iconColor = disabled ? colors.outline : colors.primary;
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: disabled
            ? () => showAppDownloadSheet(context)
            : () => Navigator.pop(context, preset),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(preset.icon, size: 36, color: iconColor),
                  const Spacer(),
                  if (_isMobileOnly)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: 2),
                      decoration: BoxDecoration(
                        color: _isMobile
                            ? colors.secondaryContainer
                            : colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppRadius.r12),
                      ),
                      child: Text(
                        'Mobile',
                        style: textTheme.labelSmall?.copyWith(
                          color: _isMobile
                              ? colors.onSecondaryContainer
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                preset.name,
                style: textTheme.titleMedium?.copyWith(
                  color: disabled ? colors.outline : null,
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  preset.description,
                  style: textTheme.bodySmall?.copyWith(
                    color: disabled ? colors.outline : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
