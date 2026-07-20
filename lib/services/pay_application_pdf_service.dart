import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/pay_application.dart';

/// Generates a printable PDF for an AIA G702/G703 payment application.
///
/// This is a **clean-room layout** containing the same data fields as the
/// official AIA G702/G703 forms. It does NOT reproduce the copyrighted AIA
/// form artwork — column labels, structure, and totals only.
class PayApplicationPdfService {
  static final _money = NumberFormat.currency(symbol: r'$', decimalDigits: 2);
  static final _pct = NumberFormat.decimalPercentPattern(decimalDigits: 1);
  static final _date = DateFormat.yMMMd();

  static Future<Uint8List> build(PayApplication app) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter.landscape,
        margin: const pw.EdgeInsets.all(28),
        header: (ctx) => _header(app),
        build: (ctx) => [
          _g702Block(app),
          pw.SizedBox(height: 14),
          _g703Title(),
          pw.SizedBox(height: 4),
          _g703Table(app),
          pw.SizedBox(height: 14),
          _certificationBlock(app),
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

  // ────────────────────────────────────────────────────────────────────

  static pw.Widget _header(PayApplication app) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Application and Certificate for Payment',
          style:
              pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          'AIA G702/G703 equivalent · Application No. ${app.applicationNumber} · '
          'Status: ${app.status.displayLabel}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
        pw.Divider(height: 8, thickness: 0.5),
      ],
    );
  }

  static pw.Widget _g702Block(PayApplication app) {
    pw.Widget kv(String k, String v) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1),
          child: pw.Row(children: [
            pw.SizedBox(
              width: 140,
              child: pw.Text(k,
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey700)),
            ),
            pw.Expanded(
                child: pw.Text(v, style: const pw.TextStyle(fontSize: 9))),
          ]),
        );

    pw.Widget line(String label, double value, {bool bold = false}) {
      final style = pw.TextStyle(
        fontSize: 9,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      );
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(children: [
          pw.Expanded(child: pw.Text(label, style: style)),
          pw.Text(_money.format(value), style: style),
        ]),
      );
    }

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Left: parties / period
        pw.Expanded(
          flex: 5,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              kv('To (Owner)', app.ownerName ?? ''),
              kv('From (Contractor)', app.contractorName ?? ''),
              kv('Architect', app.architectName ?? ''),
              kv('Contract For', app.contractFor ?? ''),
              kv('Period From',
                  app.periodFrom == null ? '' : _date.format(app.periodFrom!)),
              kv('Period To',
                  app.periodTo == null ? '' : _date.format(app.periodTo!)),
              kv('Date Issued',
                  app.dateIssued == null ? '' : _date.format(app.dateIssued!)),
            ],
          ),
        ),
        pw.SizedBox(width: 16),
        // Right: dollar lines
        pw.Expanded(
          flex: 6,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                line('1. Original Contract Sum', app.originalContractSum),
                line(
                    '2. Net Change by Change Orders', app.netChangeByChangeOrders),
                line('3. Contract Sum to Date (1 + 2)', app.contractSumToDate,
                    bold: true),
                line('4. Total Completed & Stored to Date',
                    app.totalCompletedAndStored),
                line('5. Retainage', app.totalRetainage),
                line('6. Total Earned Less Retainage (4 − 5)',
                    app.totalEarnedLessRetainage),
                line('7. Less Previous Certificates for Payment',
                    app.lessPreviousCertificates),
                pw.Divider(height: 6, thickness: 0.5),
                line('8. CURRENT PAYMENT DUE', app.currentPaymentDue,
                    bold: true),
                line('9. Balance to Finish, Plus Retainage',
                    app.balanceToFinish),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Retainage: ${_pct.format(app.retainagePctCompleted / 100)} on '
                  'completed work, ${_pct.format(app.retainagePctStored / 100)} on stored materials.',
                  style: const pw.TextStyle(
                      fontSize: 8, color: PdfColors.grey700),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _g703Title() => pw.Text(
        'Continuation Sheet (G703)',
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
      );

  static pw.Widget _g703Table(PayApplication app) {
    final headerStyle =
        pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);
    final cellStyle = const pw.TextStyle(fontSize: 8);

    final headers = [
      'A\nItem',
      'B\nDescription',
      'C\nScheduled Value',
      'D\nFrom Previous',
      'E\nThis Period',
      'F\nMaterials Stored',
      'G\nTotal Completed & Stored',
      '%\n(G/C)',
      'H\nBalance to Finish',
      'I\nRetainage',
    ];

    final rows = <List<String>>[];
    for (final l in app.lines) {
      rows.add([
        l.itemNo ?? '',
        l.description,
        _money.format(l.scheduledValue),
        _money.format(l.workCompletedPrevious),
        _money.format(l.workCompletedThisPeriod),
        _money.format(l.materialsStored),
        _money.format(l.totalCompletedAndStored),
        _pct.format(l.percentComplete / 100),
        _money.format(l.balanceToFinish),
        _money.format(_lineRetainage(l, app)),
      ]);
    }

    // Totals row
    rows.add([
      '',
      'TOTALS',
      _money.format(app.lines.fold<double>(0, (s, l) => s + l.scheduledValue)),
      _money.format(
          app.lines.fold<double>(0, (s, l) => s + l.workCompletedPrevious)),
      _money.format(
          app.lines.fold<double>(0, (s, l) => s + l.workCompletedThisPeriod)),
      _money.format(
          app.lines.fold<double>(0, (s, l) => s + l.materialsStored)),
      _money.format(app.totalCompletedAndStored),
      '',
      _money.format(app.lines.fold<double>(0, (s, l) => s + l.balanceToFinish)),
      _money.format(app.totalRetainage),
    ]);

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.4),
      columnWidths: const {
        0: pw.FixedColumnWidth(28),
        1: pw.FlexColumnWidth(3),
        2: pw.FlexColumnWidth(1.4),
        3: pw.FlexColumnWidth(1.3),
        4: pw.FlexColumnWidth(1.3),
        5: pw.FlexColumnWidth(1.3),
        6: pw.FlexColumnWidth(1.6),
        7: pw.FixedColumnWidth(36),
        8: pw.FlexColumnWidth(1.4),
        9: pw.FlexColumnWidth(1.2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: headers
              .map((h) => pw.Padding(
                    padding: const pw.EdgeInsets.all(3),
                    child: pw.Text(h, style: headerStyle),
                  ))
              .toList(),
        ),
        for (final r in rows)
          pw.TableRow(
            decoration: r[1] == 'TOTALS'
                ? const pw.BoxDecoration(color: PdfColors.grey100)
                : null,
            children: [
              for (var i = 0; i < r.length; i++)
                pw.Padding(
                  padding: const pw.EdgeInsets.all(3),
                  child: pw.Text(
                    r[i],
                    style: r[1] == 'TOTALS'
                        ? pw.TextStyle(
                            fontSize: 8, fontWeight: pw.FontWeight.bold)
                        : cellStyle,
                    textAlign: i >= 2 ? pw.TextAlign.right : pw.TextAlign.left,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  static double _lineRetainage(dynamic l, PayApplication app) {
    // Use override if present, otherwise apply header pct to (completed + stored).
    if (l.retainageOverride != null) return l.retainageOverride as double;
    final completedPortion =
        (l.workCompletedPrevious + l.workCompletedThisPeriod) as double;
    final storedPortion = l.materialsStored as double;
    return completedPortion * (app.retainagePctCompleted / 100) +
        storedPortion * (app.retainagePctStored / 100);
  }

  static pw.Widget _certificationBlock(PayApplication app) {
    pw.Widget sigBox(String title, String? name, DateTime? when,
        {double? amount}) {
      return pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey500, width: 0.5),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(title,
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 18),
              pw.Container(
                  height: 0.5,
                  width: double.infinity,
                  color: PdfColors.grey800),
              pw.SizedBox(height: 2),
              pw.Text('Signature',
                  style: const pw.TextStyle(
                      fontSize: 7, color: PdfColors.grey700)),
              pw.SizedBox(height: 6),
              pw.Text('By: ${name ?? ''}',
                  style: const pw.TextStyle(fontSize: 8)),
              pw.Text(
                  'Date: ${when == null ? '' : _date.format(when)}',
                  style: const pw.TextStyle(fontSize: 8)),
              if (amount != null)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 4),
                  child: pw.Text('Amount Certified: ${_money.format(amount)}',
                      style: pw.TextStyle(
                          fontSize: 9, fontWeight: pw.FontWeight.bold)),
                ),
            ],
          ),
        ),
      );
    }

    return pw.Row(children: [
      sigBox(
        "Contractor's Certification",
        app.contractorName,
        app.dateIssued,
      ),
      pw.SizedBox(width: 12),
      sigBox(
        "Architect's Certificate for Payment",
        app.certifiedBy,
        app.certifiedAt,
        amount: app.certifiedAmount,
      ),
    ]);
  }
}
