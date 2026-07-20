import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Trigger a browser download of [bytes] as [fileName]. Used by the
/// floorplan editor's Export action on web; mobile/desktop go through
/// the share sheet variant.
Future<void> shareFloorplanFile(
  Uint8List bytes,
  String fileName, {
  String? mimeType,
}) async {
  final blob = html.Blob([bytes], mimeType ?? 'application/octet-stream');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
  html.Url.revokeObjectUrl(url);
}

Future<void> saveFloorplanFile(
  Uint8List bytes,
  String fileName, {
  String? mimeType,
}) =>
    shareFloorplanFile(bytes, fileName, mimeType: mimeType);
