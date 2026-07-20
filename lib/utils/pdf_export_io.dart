import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Share/save a PDF file on mobile/desktop platforms
Future<void> exportPdf(Uint8List pdfBytes, String fileName) async {
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}/$fileName');
  await file.writeAsBytes(pdfBytes);

  await Share.shareXFiles(
    [XFile(file.path)],
    subject: fileName,
  );
}
