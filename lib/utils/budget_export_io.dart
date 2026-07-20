import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Download/share a CSV file on mobile platforms
Future<void> exportCsv(String csvContent, String fileName, String subject) async {
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}/$fileName');
  await file.writeAsString(csvContent);

  await Share.shareXFiles(
    [XFile(file.path)],
    subject: subject,
  );
}

/// Download/share multiple CSV files on mobile platforms
Future<void> exportMultipleCsv(
  List<MapEntry<String, String>> files,
  String subject,
  String? text,
) async {
  final directory = await getTemporaryDirectory();
  final xFiles = <XFile>[];

  for (final file in files) {
    final ioFile = File('${directory.path}/${file.key}');
    await ioFile.writeAsString(file.value);
    xFiles.add(XFile(ioFile.path));
  }

  await Share.shareXFiles(
    xFiles,
    subject: subject,
    text: text,
  );
}
