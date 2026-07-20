import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Save bytes to a temp file and open the OS share sheet. Used by the
/// floorplan editor's Export action to hand the rendered file off to
/// whatever the user wants to do with it (Mail, Drive, AirDrop, …).
Future<void> shareFloorplanFile(
  Uint8List bytes,
  String fileName, {
  String? mimeType,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes);
  await Share.shareXFiles(
    [XFile(file.path, mimeType: mimeType)],
    subject: fileName,
  );
}

/// Same payload as [shareFloorplanFile] but written to a path the user
/// picks via the platform file picker. v1 just reuses the share sheet
/// since "Save to Files" is one of its options on iOS / Android /
/// macOS; a real Save-As dialog can come later.
Future<void> saveFloorplanFile(
  Uint8List bytes,
  String fileName, {
  String? mimeType,
}) =>
    shareFloorplanFile(bytes, fileName, mimeType: mimeType);
