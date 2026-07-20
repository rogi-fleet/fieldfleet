import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Download a CSV file on web platform
Future<void> exportCsv(String csvContent, String fileName, String subject) async {
  final bytes = utf8.encode(csvContent);
  final blob = html.Blob([bytes], 'text/csv');
  final url = html.Url.createObjectUrlFromBlob(blob);

  html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();

  html.Url.revokeObjectUrl(url);
}

/// Download multiple CSV files on web platform
Future<void> exportMultipleCsv(
  List<MapEntry<String, String>> files,
  String subject,
  String? text,
) async {
  // Small delay between downloads to ensure browser handles them
  for (final file in files) {
    await exportCsv(file.value, file.key, subject);
    await Future.delayed(const Duration(milliseconds: 500));
  }
}
