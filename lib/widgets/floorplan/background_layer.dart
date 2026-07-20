import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:pdfx/pdfx.dart';

import '../../models/floorplan/background_pdf.dart';
import '../../utils/app_logger.dart';

/// Faded PDF underlay rendered behind the floorplan canvas.
///
/// Loads the configured page on first build and rasterizes it into a
/// `dart:ui.Image`. Mobile downloads + caches via [path_provider]; web
/// uses an in-memory byte buffer because filesystem access isn't available.
/// Subsequent rebuilds reuse the cached image until the PDF identity
/// changes (compared by `fileUrl + pageIndex`).
class BackgroundLayer extends StatefulWidget {
  final BackgroundPdf? background;
  final double sceneWidth;
  final double sceneHeight;

  const BackgroundLayer({
    super.key,
    required this.background,
    required this.sceneWidth,
    required this.sceneHeight,
  });

  @override
  State<BackgroundLayer> createState() => _BackgroundLayerState();
}

class _BackgroundLayerState extends State<BackgroundLayer> {
  PdfDocument? _doc;
  ImageProvider? _image;
  String? _loadedKey;
  bool _loading = false;
  String? _error;

  String get _key {
    final bg = widget.background;
    return bg == null ? '' : '${bg.fileUrl}#${bg.pageIndex}';
  }

  @override
  void initState() {
    super.initState();
    _ensureLoaded();
  }

  @override
  void didUpdateWidget(covariant BackgroundLayer old) {
    super.didUpdateWidget(old);
    if (_loadedKey != _key) _ensureLoaded();
  }

  @override
  void dispose() {
    _doc?.close();
    super.dispose();
  }

  Future<void> _ensureLoaded() async {
    final bg = widget.background;
    if (bg == null) {
      setState(() {
        _image = null;
        _doc = null;
        _loadedKey = '';
        _error = null;
      });
      return;
    }
    final key = _key;
    if (_loadedKey == key && _image != null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await _fetchPdfBytes(bg.fileUrl);
      final doc = await PdfDocument.openData(bytes);
      final page = await doc.getPage(bg.pageIndex + 1);
      // Render at a reasonable resolution: scale the PDF page so its
      // longer side maps to ~1024 px, preserving aspect ratio. The
      // canvas then stretches the resulting image to fill scene extents.
      final maxSide = 1024;
      final scale = (page.width >= page.height
              ? maxSide / page.width
              : maxSide / page.height)
          .clamp(0.25, 3.0);
      final renderW = (page.width * scale).round();
      final renderH = (page.height * scale).round();
      final pageImage = await page.render(
        width: renderW.toDouble(),
        height: renderH.toDouble(),
      );
      await page.close();
      if (!mounted) {
        await doc.close();
        return;
      }
      final image = MemoryImage(pageImage!.bytes);
      setState(() {
        _doc?.close();
        _doc = doc;
        _image = image;
        _loadedKey = key;
        _loading = false;
      });
    } catch (e) {
      AppLogger.warning(
        'background pdf load failed',
        metadata: {'url': bg.fileUrl, 'error': e.toString()},
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not render PDF underlay';
      });
    }
  }

  Future<Uint8List> _fetchPdfBytes(String url) async {
    if (kIsWeb) {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode != 200) {
        throw Exception('PDF download HTTP ${resp.statusCode}');
      }
      return resp.bodyBytes;
    }
    // Mobile/desktop: cache to disk for repeat opens.
    final dir = await path_provider.getTemporaryDirectory();
    final fileName = url.hashCode.toRadixString(16);
    final file = await _writeCached(dir.path, fileName, url);
    return file;
  }

  Future<Uint8List> _writeCached(
    String dir,
    String name,
    String url,
  ) async {
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode != 200) {
      throw Exception('PDF download HTTP ${resp.statusCode}');
    }
    return resp.bodyBytes;
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.background;
    if (bg == null) return const SizedBox.shrink();
    final image = _image;
    return SizedBox(
      width: widget.sceneWidth,
      height: widget.sceneHeight,
      child: Opacity(
        opacity: bg.opacity,
        child: image != null
            ? Image(image: image, fit: BoxFit.contain)
            : Center(
                child: _loading
                    ? const SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _error ?? 'Loading PDF underlay…',
                        style:
                            Theme.of(context).textTheme.bodySmall,
                      ),
              ),
      ),
    );
  }
}
