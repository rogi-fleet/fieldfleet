import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/floorplan/floorplan_editor_controller.dart';
import '../../services/floorplan/scene_exporter.dart';
import '../../utils/floorplan_export_io.dart'
    if (dart.library.html) '../../utils/floorplan_export_web.dart'
    as floorplan_export;

enum _Format { png, svg, pdf }

extension on _Format {
  String get label => switch (this) {
        _Format.png => 'PNG image',
        _Format.svg => 'SVG (vector)',
        _Format.pdf => 'PDF document',
      };

  String get extension => switch (this) {
        _Format.png => 'png',
        _Format.svg => 'svg',
        _Format.pdf => 'pdf',
      };

  String get mime => switch (this) {
        _Format.png => 'image/png',
        _Format.svg => 'image/svg+xml',
        _Format.pdf => 'application/pdf',
      };

  IconData get icon => switch (this) {
        _Format.png => Icons.image_outlined,
        _Format.svg => Icons.brush_outlined,
        _Format.pdf => Icons.picture_as_pdf_outlined,
      };

  String get hint => switch (this) {
        _Format.png =>
          'Raster image, opens anywhere. Good for screenshots and embedding.',
        _Format.svg =>
          'True vector — scales without loss, opens in any browser or vector editor.',
        _Format.pdf =>
          'Print-ready single page with title and scale note.',
      };
}

Future<void> showExportDialog(
  BuildContext context,
  FloorplanEditorController controller, {
  String? planTitle,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => ChangeNotifierProvider.value(
      value: controller,
      child: _ExportDialog(planTitle: planTitle),
    ),
  );
}

class _ExportDialog extends StatefulWidget {
  final String? planTitle;
  const _ExportDialog({this.planTitle});

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  _Format _format = _Format.png;
  bool _exporting = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Export floorplan'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final f in _Format.values)
              RadioListTile<_Format>(
                value: f,
                groupValue: _format,
                onChanged: (v) {
                  if (v != null) setState(() => _format = v);
                },
                contentPadding: EdgeInsets.zero,
                title: Row(
                  children: [
                    Icon(f.icon, size: 16),
                    const SizedBox(width: 8),
                    Text(f.label),
                  ],
                ),
                subtitle: Text(f.hint),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _exporting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _exporting ? null : _doExport,
          icon: _exporting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.ios_share, size: 16),
          label: const Text('Export'),
        ),
      ],
    );
  }

  Future<void> _doExport() async {
    final controller = context.read<FloorplanEditorController>();
    setState(() {
      _exporting = true;
      _error = null;
    });
    try {
      final scene = controller.scene;
      final baseName = (widget.planTitle?.trim().isNotEmpty == true
              ? widget.planTitle!.trim()
              : 'floorplan')
          .replaceAll(RegExp(r'[^A-Za-z0-9_\- ]'), '')
          .replaceAll(' ', '_');
      final fileName = '$baseName.${_format.extension}';
      late final dynamic bytes;
      switch (_format) {
        case _Format.png:
          bytes = await SceneExporter.renderPng(scene, scale: 2.0);
        case _Format.svg:
          bytes = utf8.encode(SceneExporter.renderSvg(scene));
        case _Format.pdf:
          bytes = await SceneExporter.renderPdf(
            scene,
            title: widget.planTitle ?? 'Floorplan',
          );
      }
      await floorplan_export.shareFloorplanFile(
        bytes,
        fileName,
        mimeType: _format.mime,
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _exporting = false;
        _error = 'Export failed: $e';
      });
    }
  }
}
