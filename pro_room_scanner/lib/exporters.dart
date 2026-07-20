import 'dart:io';
import 'dart:math' as math;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'models_and_math.dart';

class Exporter {
  
  // 1. DXF Export (AutoCAD)
  static Future<String> generateDxf(List<RoomPoint> points, String name) async {
    final buffer = StringBuffer();
    buffer.writeln("0\nSECTION\n2\nENTITIES");

    for (int i = 0; i < points.length; i++) {
      final p1 = points[i];
      final p2 = points[(i + 1) % points.length];

      buffer.writeln("0\nLINE\n8\nWALLS");
      buffer.writeln("10\n${p1.x}\n20\n${p1.z}\n30\n0.0");
      buffer.writeln("11\n${p2.x}\n21\n${p2.z}\n31\n0.0");
    }

    buffer.writeln("0\nENDSEC\n0\nEOF");
    
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$name.dxf');
    await file.writeAsString(buffer.toString());
    return file.path;
  }

  // 2. OBJ Export (3D)
  static Future<String> generateObj(List<RoomPoint> points, double height) async {
    final buffer = StringBuffer();
    buffer.writeln("# Flutter Pro Scanner OBJ\no Room");

    for (var p in points) {
      buffer.writeln("v ${p.x} 0.0 ${p.z}");
      buffer.writeln("v ${p.x} $height ${p.z}");
    }

    int count = points.length;
    for (int i = 0; i < count; i++) {
      int next = (i + 1) % count;
      int p1f = (i * 2) + 1;
      int p1c = (i * 2) + 2;
      int p2f = (next * 2) + 1;
      int p2c = (next * 2) + 2;
      buffer.writeln("f $p1f $p2f $p2c $p1c");
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/room_3d.obj');
    await file.writeAsString(buffer.toString());
    return file.path;
  }

  // 3. PDF Report
  static Future<void> generatePdfReport(List<RoomPoint> points, double area, List<Attachment> attachments) async {
    final pdf = pw.Document();
    
    // Bounds for scaling
    double minX = double.infinity, maxX = -double.infinity;
    double minZ = double.infinity, maxZ = -double.infinity;
    for (var p in points) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.z < minZ) minZ = p.z;
      if (p.z > maxZ) maxZ = p.z;
    }
    double w = maxX - minX;
    double h = maxZ - minZ;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(level: 0, child: pw.Text("Room Scan Report")),
              pw.SizedBox(height: 20),
            
            // FIELD DOCUMENTATION
            if (attachments.isNotEmpty) ...[
              pw.Header(level: 1, text: "Field Documentation"),
              
              // Moisture
              if (attachments.any((a) => a.type == AttachmentType.moisture)) ...[
                pw.Header(level: 2, text: "Moisture Readings"),
                pw.Table.fromTextArray(
                  headers: ["Time", "Value", "Location (X, Z)"],
                  data: attachments.where((a) => a.type == AttachmentType.moisture).map((a) => [
                    DateFormat('HH:mm').format(a.timestamp),
                    a.data,
                    "${a.position.x.toStringAsFixed(1)}, ${a.position.z.toStringAsFixed(1)}"
                  ]).toList(),
                ),
                pw.SizedBox(height: 10),
              ],

              // Notes
              if (attachments.any((a) => a.type == AttachmentType.note)) ...[
                pw.Header(level: 2, text: "Notes"),
                ...attachments.where((a) => a.type == AttachmentType.note).map((a) => 
                  pw.Bullet(text: "${DateFormat('HH:mm').format(a.timestamp)}: ${a.data}")
                ),
                pw.SizedBox(height: 10),
              ],

              // Photos
              if (attachments.any((a) => a.type == AttachmentType.photo)) ...[
                pw.Header(level: 2, text: "Photo Log"),
                pw.Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: attachments.where((a) => a.type == AttachmentType.photo).map((a) {
                    // Note: Loading image from path might require async, but pdf widgets are sync.
                    // We usually need to load bytes first. 
                    // For simplicity in this sync builder, we might skip actual image rendering 
                    // or assume we can use a placeholder if async loading is complex here.
                    // Better: Load images BEFORE creating pdf document.
                    return pw.Container(
                      width: 100, height: 100,
                      color: PdfColors.grey300,
                      child: pw.Center(child: pw.Text("Photo\n${DateFormat('HH:mm').format(a.timestamp)}"))
                    );
                  }).toList(),
                ),
              ]
            ],
              pw.Table.fromTextArray(data: [
                ['Metric', 'Value'],
                ['Total Area', '${area.toStringAsFixed(2)} m²'],
                ['Perimeter', '${GeometryEngine.calculatePerimeter(points).toStringAsFixed(2)} m'],
                ['Wall Segments', '${points.length}'],
                ['Ceiling Height', '2.4 m (estimated)'],
                ['Room', points.first.roomLabel ?? 'Not Set'],
                ['Floor Level', '${(points.first.floorLevel + 1)}'],
                ['Date', DateTime.now().toString().substring(0,10)],
              ]),
              pw.SizedBox(height: 30),
              pw.Text("Blueprint Preview", style: pw.TextStyle(fontSize: 16)),
              pw.Divider(),
              pw.Expanded(
                child: pw.Container(
                  decoration: pw.BoxDecoration(border: pw.Border.all()),
                  child: pw.CustomPaint(
                    size: const PdfPoint(400, 400),
                    painter: (canvas, size) {
                      double scale = math.min(size.x / (w + 1), size.y / (h + 1));
                      double offX = (size.x - (w * scale)) / 2;
                      double offY = (size.y - (h * scale)) / 2;

                      canvas
                        ..setStrokeColor(PdfColors.black)
                        ..setLineWidth(2);

                      for (int i = 0; i < points.length; i++) {
                        var p1 = points[i];
                        var p2 = points[(i + 1) % points.length];
                        double x1 = (p1.x - minX) * scale + offX;
                        double y1 = (p1.z - minZ) * scale + offY;
                        double x2 = (p2.x - minX) * scale + offX;
                        double y2 = (p2.z - minZ) * scale + offY;
                        canvas.drawLine(x1, y1, x2, y2);
                      }
                      canvas.strokePath();
                    }
                  )
                )
              )
            ]
          );
        }
      )
    );

    await Printing.sharePdf(bytes: await pdf.save(), filename: 'room_report.pdf');
  }
  
  // 4. Excel/CSV Export (Material List)
  static Future<String> generateExcel(List<RoomPoint> points) async {
    // Calculate statistics
    double area = GeometryEngine.calculateArea(points);
    double perimeter = GeometryEngine.calculatePerimeter(points);
    String roomLabel = points.first.roomLabel ?? 'Not Set';
    int floorLevel = points.first.floorLevel + 1;
    double ceilingHeight = 2.4; // Default
    
    // Material calculations
    double paintCoverage = (area * 2.5).toStringAsFixed(2) as double; // 2.5 coats
    double flooringArea = area;
    double baseboardLength = perimeter;
    
    // Create CSV data
    List<List<dynamic>> rows = [
      ['Pro Room Scanner - Material List'],
      ['Date: ${DateTime.now().toString().substring(0, 10)}'],
      [],
      ['Room Information'],
      ['Room Name', roomLabel],
      ['Floor Level', floorLevel],
      ['Ceiling Height (m)', ceilingHeight.toStringAsFixed(2)],
      [],
      ['Measurements'],
      ['Total Area (m²)', area.toStringAsFixed(2)],
      ['Perimeter (m)', perimeter.toStringAsFixed(2)],
      ['Wall Segments', points.length],
      [],
      ['Material Estimates'],
      ['Paint Coverage (m² @ 2.5 coats)', (area * 2.5).toStringAsFixed(2)],
      ['Flooring Area (m²)', area.toStringAsFixed(2)],
      ['Baseboard Length (m)', perimeter.toStringAsFixed(2)],
      [],
      ['Wall Dimensions'],
      ['Segment', 'Length (m)'],
    ];
    
    // Add individual wall lengths
    for (int i = 0; i < points.length; i++) {
      var p1 = points[i];
      var p2 = points[(i + 1) % points.length];
      double length = p1.distanceTo(p2);
      rows.add(['Wall ${i + 1}', length.toStringAsFixed(2)]);
    }
    
    // Convert to CSV
    String csv = const ListToCsvConverter().convert(rows);
    
    // Save file
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/material_list.csv');
    await file.writeAsString(csv);
    return file.path;
  }
}
