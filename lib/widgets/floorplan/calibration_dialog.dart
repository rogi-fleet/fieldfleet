import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/floorplan/editor_mode.dart';
import '../../services/floorplan/floorplan_editor_controller.dart';
import '../../utils/floorplan/units.dart';
import '../../theme/theme.dart';

/// Walks the user through scale calibration:
///   1. Click point A
///   2. Click point B
///   3. Enter the real-world distance between them
///   4. Apply — every coordinate in the scene scales by
///      `realDistance / currentPixelDistance`.
///
/// The dialog floats above the canvas. It listens to the controller's
/// mode so as the user clicks A and B (which the canvas captures), the
/// step text + length prompt advance automatically.
Future<void> showCalibrationDialog(
  BuildContext context,
  FloorplanEditorController controller,
) async {
  controller.beginCalibration();
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return ChangeNotifierProvider<FloorplanEditorController>.value(
        value: controller,
        child: const _CalibrationDialog(),
      );
    },
  );
  // If the user dismisses without applying, exit calibration mode.
  if (controller.mode is CalibratingMode) {
    controller.cancelCalibration();
  }
}

class _CalibrationDialog extends StatefulWidget {
  const _CalibrationDialog();

  @override
  State<_CalibrationDialog> createState() => _CalibrationDialogState();
}

class _CalibrationDialogState extends State<_CalibrationDialog> {
  final TextEditingController _lengthCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _lengthCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<FloorplanEditorController>();
    final mode = controller.mode;
    if (mode is! CalibratingMode) {
      // The user (or some other action) left calibration mode — close.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }
    final unit = controller.scene.unit;
    final hasFirst = mode.first != null;
    final hasSecond = mode.second != null;
    final pixelDistance = (hasFirst && hasSecond)
        ? (mode.second! - mode.first!).distance
        : 0.0;

    return AlertDialog(
      title: const Text('Calibrate scale'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Step(
            number: 1,
            done: hasFirst,
            text: 'Click the first reference point on the canvas',
          ),
          _Step(
            number: 2,
            done: hasSecond,
            text: 'Click the second reference point',
          ),
          _Step(
            number: 3,
            done: false,
            text: 'Enter the real-world distance and apply',
          ),
          if (hasSecond) ...[
            const SizedBox(height: 12),
            Text(
              'Reference distance on canvas: '
              '${formatLengthCm(pixelDistance, unit)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _lengthCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Real-world distance',
                suffixText: unit,
                border: const OutlineInputBorder(),
                isDense: true,
                errorText: _error,
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _apply(controller, pixelDistance),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            controller.cancelCalibration();
            Navigator.pop(context);
          },
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: hasSecond
              ? () => _apply(controller, pixelDistance)
              : null,
          child: const Text('Apply'),
        ),
      ],
    );
  }

  void _apply(FloorplanEditorController controller, double pixelDistance) {
    if (pixelDistance < 0.5) {
      setState(() => _error = 'The two points are too close together');
      return;
    }
    final realCm = parseLengthToCm(
      _lengthCtrl.text,
      controller.scene.unit,
    );
    if (realCm == null || realCm <= 0) {
      setState(() => _error = 'Enter a positive number');
      return;
    }
    final factor = realCm / pixelDistance;
    if (!factor.isFinite || factor <= 0 || factor.isNaN) {
      setState(() => _error = 'Could not compute scale factor');
      return;
    }
    controller.applyCalibration(factor);
    Navigator.pop(context);
  }
}

class _Step extends StatelessWidget {
  final int number;
  final bool done;
  final String text;

  const _Step({
    required this.number,
    required this.done,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.surfaceContainerHigh,
            ),
            alignment: Alignment.center,
            child: done
                ? const Icon(Icons.check, size: 12, color: Colors.white)
                : Text(
                    '$number',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

