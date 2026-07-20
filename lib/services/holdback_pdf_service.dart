import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/holdback_release.dart';
import 'supabase/holdback_service.dart' show HoldbackSummary;

/// PDF templates for the holdback feature.
///
///  * [buildStatement]  — Statement of Holdback (per project): how much has
///    been withheld to date, how much released, how much outstanding.
///  * [buildRelease]    — Release of Holdback document: the formal release
///    notice for one [HoldbackRelease].
class HoldbackPdfService {
  static final _money = NumberFormat.currency(symbol: r'$', decimalDigits: 2);
  static final _pct = NumberFormat.decimalPercentPattern(decimalDigits: 1);
  static final _date = DateFormat.yMMMd();

  HoldbackPdfService._();

  // ─────────────────────────────────────────────────────────────────────
  // Statement of Holdback
  // ─────────────────────────────────────────────────────────────────────
  static Future<Uint8List> buildStatement({
    required String projectName,
    required String? customerName,
    required HoldbackSummary summary,
    String? notes,
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(36),
        header: (ctx) => _statementHeader(projectName, customerName),
        build: (ctx) => [
          _statementTotals(summary),
          pw.SizedBox(height: 16),
          _statementTable(summary),
          if (notes != null && notes.trim().isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Text('Notes',
                style: pw.TextStyle(
                    fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(notes.trim(),
                style: const pw.TextStyle(fontSize: 10)),
          ],
        ],
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ),
      ),
    );
    return doc.save();
  }

  static pw.Widget _statementHeader(String projectName, String? customerName) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Statement of Holdback',
            style:
                pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('Project: $projectName',
            style: const pw.TextStyle(fontSize: 11)),
        if (customerName != null && customerName.isNotEmpty)
          pw.Text('Customer: $customerName',
              style: const pw.TextStyle(fontSize: 11)),
        pw.Text('Statement date: ${_date.format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.Divider(),
      ],
    );
  }

  static pw.Widget _statementTotals(HoldbackSummary s) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(2),
        1: pw.FlexColumnWidth(1),
      },
      children: [
        _kv('Total invoiced (with holdback)',
            _money.format(s.totalInvoicedWithHoldback)),
        _kv('Total holdback withheld', _money.format(s.totalHeld), bold: true),
        _kv('Released to date', _money.format(s.totalReleased)),
        _kv('Outstanding to be released',
            _money.format(s.totalOutstanding), bold: true),
        _kv('% released',
            s.totalHeld == 0 ? '—' : _pct.format(s.totalReleased / s.totalHeld)),
      ],
    );
  }

  static pw.Widget _statementTable(HoldbackSummary s) {
    if (s.outstandingInvoices.isEmpty) {
      return pw.Text('No outstanding holdback to display.',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700));
    }
    final headerStyle = pw.TextStyle(
        fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white);
    final cellStyle = const pw.TextStyle(fontSize: 9);
    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
        children: [
          _cell('Invoice #', headerStyle, pad: 4),
          _cell('Date', headerStyle, pad: 4),
          _cell('Invoice total', headerStyle, align: pw.TextAlign.right, pad: 4),
          _cell('Holdback %', headerStyle, align: pw.TextAlign.right, pad: 4),
          _cell('Held', headerStyle, align: pw.TextAlign.right, pad: 4),
        ],
      ),
      for (final o in s.outstandingInvoices)
        pw.TableRow(children: [
          _cell(o.documentNumber ?? '—', cellStyle, pad: 3),
          _cell(_date.format(o.createdAt), cellStyle, pad: 3),
          _cell(_money.format(o.invoiceTotal), cellStyle,
              align: pw.TextAlign.right, pad: 3),
          _cell('${o.retainagePercent.toStringAsFixed(1)}%', cellStyle,
              align: pw.TextAlign.right, pad: 3),
          _cell(_money.format(o.retainageAmount), cellStyle,
              align: pw.TextAlign.right, pad: 3),
        ]),
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          _cell('TOTAL OUTSTANDING',
              pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              pad: 4),
          _cell('', cellStyle),
          _cell('', cellStyle),
          _cell('', cellStyle),
          _cell(_money.format(s.totalOutstanding),
              pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              align: pw.TextAlign.right, pad: 4),
        ],
      ),
    ];
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(2),
        1: pw.FlexColumnWidth(2),
        2: pw.FlexColumnWidth(2),
        3: pw.FlexColumnWidth(1.2),
        4: pw.FlexColumnWidth(2),
      },
      children: rows,
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Release of Holdback
  // ─────────────────────────────────────────────────────────────────────
  static Future<Uint8List> buildRelease({
    required String projectName,
    required String? customerName,
    required HoldbackRelease release,
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(36),
        header: (ctx) => _releaseHeader(release, projectName, customerName),
        build: (ctx) => [
          _releaseSummary(release),
          pw.SizedBox(height: 16),
          _releaseLines(release),
          pw.SizedBox(height: 24),
          _releaseSignature(),
          if (release.notes != null && release.notes!.trim().isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Text('Notes',
                style: pw.TextStyle(
                    fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(release.notes!.trim(),
                style: const pw.TextStyle(fontSize: 10)),
          ],
        ],
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ),
      ),
    );
    return doc.save();
  }

  static pw.Widget _releaseHeader(
      HoldbackRelease r, String projectName, String? customerName) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Release of Holdback',
            style:
                pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('Release No. ${r.releaseNumber} · ${_date.format(r.releaseDate)}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.SizedBox(height: 6),
        pw.Text('Project: $projectName',
            style: const pw.TextStyle(fontSize: 11)),
        if (customerName != null && customerName.isNotEmpty)
          pw.Text('Customer: $customerName',
              style: const pw.TextStyle(fontSize: 11)),
        pw.Divider(),
      ],
    );
  }

  static pw.Widget _releaseSummary(HoldbackRelease r) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Total released this statement',
              style: pw.TextStyle(
                  fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.Text(_money.format(r.totalAmount),
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  static pw.Widget _releaseLines(HoldbackRelease r) {
    final headerStyle = pw.TextStyle(
        fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white);
    final cellStyle = const pw.TextStyle(fontSize: 9);
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(4),
        1: pw.FlexColumnWidth(2),
        2: pw.FlexColumnWidth(2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
          children: [
            _cell('Description', headerStyle, pad: 4),
            _cell('Amount held', headerStyle,
                align: pw.TextAlign.right, pad: 4),
            _cell('Released', headerStyle,
                align: pw.TextAlign.right, pad: 4),
          ],
        ),
        for (final l in r.lines)
          pw.TableRow(children: [
            _cell(l.description.isEmpty ? '—' : l.description, cellStyle,
                pad: 3),
            _cell(_money.format(l.amountHeld), cellStyle,
                align: pw.TextAlign.right, pad: 3),
            _cell(_money.format(l.amountReleased), cellStyle,
                align: pw.TextAlign.right, pad: 3),
          ]),
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _cell('TOTAL',
                pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                pad: 4),
            _cell('', cellStyle),
            _cell(_money.format(r.totalAmount),
                pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                align: pw.TextAlign.right, pad: 4),
          ],
        ),
      ],
    );
  }

  static pw.Widget _releaseSignature() {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: _sigBlock('Approved by (Owner / Customer)')),
        pw.SizedBox(width: 24),
        pw.Expanded(child: _sigBlock('Issued by (Contractor)')),
      ],
    );
  }

  static pw.Widget _sigBlock(String label) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          height: 36,
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom:
                  pw.BorderSide(color: PdfColors.grey700, width: 0.5),
            ),
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(label,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        pw.SizedBox(height: 6),
        pw.Row(children: [
          pw.Expanded(
            child: pw.Container(
              height: 22,
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom:
                      pw.BorderSide(color: PdfColors.grey700, width: 0.5),
                ),
              ),
            ),
          ),
          pw.SizedBox(width: 8),
          pw.SizedBox(
            width: 80,
            child: pw.Container(
              height: 22,
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom:
                      pw.BorderSide(color: PdfColors.grey700, width: 0.5),
                ),
              ),
            ),
          ),
        ]),
        pw.SizedBox(height: 2),
        pw.Row(children: [
          pw.Expanded(
              child: pw.Text('Printed name',
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey700))),
          pw.SizedBox(width: 8),
          pw.SizedBox(
            width: 80,
            child: pw.Text('Date',
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey700)),
          ),
        ]),
      ],
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────
  static pw.TableRow _kv(String k, String v, {bool bold = false}) {
    return pw.TableRow(children: [
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: pw.Text(k, style: const pw.TextStyle(fontSize: 10)),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: pw.Text(v,
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            )),
      ),
    ]);
  }

  static pw.Widget _cell(String text, pw.TextStyle style,
      {pw.TextAlign align = pw.TextAlign.left, double pad = 2}) {
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(horizontal: pad, vertical: pad),
      child: pw.Text(text, style: style, textAlign: align),
    );
  }
}
