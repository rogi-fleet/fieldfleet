/// Builds a printable Specifications PDF from a selection of project budget
/// items. Pricing is intentionally excluded; only description, quantity and
/// unit are emitted so the sheet can be shared with employees, vendors, and
/// other stakeholders.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../models/budget_item.dart';
import '../../../models/project.dart';
import '../../../theme/theme.dart';

Future<Uint8List> buildSpecsPdf({
  required Project project,
  required List<BudgetItem> allItems,
  required Set<String> selectedIds,
}) async {
  // Build parent → children map (sorted), and an id → item lookup.
  final byParent = <String?, List<BudgetItem>>{};
  for (final b in allItems) {
    byParent.putIfAbsent(b.parentId, () => []).add(b);
  }
  for (final list in byParent.values) {
    list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }
  final byId = {for (final b in allItems) b.id: b};

  // The PDF should include every selected leaf and the ancestor group chain
  // above it (so groups give context). Walk up from each selection.
  final include = <String>{};
  for (final id in selectedIds) {
    BudgetItem? cur = byId[id];
    while (cur != null) {
      include.add(cur.id);
      final pid = cur.parentId;
      cur = pid == null ? null : byId[pid];
    }
  }

  final doc = pw.Document(title: 'Specifications — ${project.name}');

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 36),
      header: (ctx) => ctx.pageNumber == 1
          ? pw.SizedBox()
          : pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(
                'Project Specifications — ${project.name}',
                style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
            ),
      footer: (ctx) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              _formatDate(DateTime.now()),
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey),
            ),
            pw.Text(
              'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey),
            ),
          ],
        ),
      ),
      build: (ctx) => [
        _headerBlock(project, selectedIds.length),
        pw.SizedBox(height: 16),
        _table(byParent, include, selectedIds),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _headerBlock(Project project, int selectedCount) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'Project Specifications',
        style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        project.name,
        style: pw.TextStyle(fontSize: 14, color: PdfColors.grey800),
      ),
      if (project.address != null && project.address!.isNotEmpty)
        pw.Text(
          project.address!,
          style: pw.TextStyle(fontSize: 11, color: PdfColors.grey600),
        ),
      pw.SizedBox(height: 4),
      pw.Text(
        'Generated ${_formatDate(DateTime.now())} · '
        '$selectedCount item${selectedCount == 1 ? '' : 's'}',
        style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        'Quantities and units are shown for scope reference. '
        'Pricing is intentionally omitted.',
        style: pw.TextStyle(
          fontSize: 10,
          color: PdfColors.grey700,
          fontStyle: pw.FontStyle.italic,
        ),
      ),
    ],
  );
}

pw.Widget _table(
  Map<String?, List<BudgetItem>> byParent,
  Set<String> include,
  Set<String> selectedIds,
) {
  final rows = <pw.TableRow>[];
  rows.add(
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      children: [
        _headerCell('Item / Description'),
        _headerCell('Qty', align: pw.TextAlign.right),
        _headerCell('Unit'),
      ],
    ),
  );

  void walk(BudgetItem node, int depth) {
    if (!include.contains(node.id)) return;
    if (node.itemType == BudgetItemType.group) {
      rows.add(_groupRow(node, depth));
    } else if (selectedIds.contains(node.id)) {
      rows.add(_itemRow(node, depth));
    }
    final children = byParent[node.id] ?? const <BudgetItem>[];
    for (final c in children) {
      walk(c, depth + 1);
    }
  }

  final roots = byParent[null] ?? const <BudgetItem>[];
  for (final r in roots) {
    walk(r, 0);
  }

  return pw.Table(
    columnWidths: const {
      0: pw.FlexColumnWidth(6),
      1: pw.FixedColumnWidth(60),
      2: pw.FixedColumnWidth(50),
    },
    border: pw.TableBorder(
      bottom: pw.BorderSide(color: PdfColors.grey400),
      horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
    ),
    children: rows,
  );
}

pw.TableRow _groupRow(BudgetItem node, int depth) {
  return pw.TableRow(
    decoration: const pw.BoxDecoration(color: PdfColors.grey100),
    children: [
      pw.Padding(
        padding: pw.EdgeInsets.only(
          left: 4.0 + depth * 12,
          top: 6,
          bottom: 6,
          right: 4,
        ),
        child: pw.Text(
          node.name,
          style: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: depth == 0 ? 12 : 11,
          ),
        ),
      ),
      pw.SizedBox(),
      pw.SizedBox(),
    ],
  );
}

pw.TableRow _itemRow(BudgetItem node, int depth) {
  return pw.TableRow(
    children: [
      pw.Padding(
        padding: pw.EdgeInsets.only(
          left: 4.0 + depth * 12,
          top: 6,
          bottom: 6,
          right: 8,
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              node.name,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            if (node.description != null && node.description!.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 2),
                child: pw.Text(
                  node.description!,
                  style: pw.TextStyle(fontSize: 10, color: PdfColors.grey800),
                ),
              ),
            if (node.notes != null && node.notes!.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 2),
                child: pw.Text(
                  'Note: ${node.notes!}',
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey700,
                    fontStyle: pw.FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: AppSpacing.xs),
        child: pw.Text(
          _fmtQty(node.quantity),
          textAlign: pw.TextAlign.right,
          style: pw.TextStyle(fontSize: 11),
        ),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: AppSpacing.xs),
        child: pw.Text(
          node.unit ?? '',
          style: pw.TextStyle(fontSize: 11),
        ),
      ),
    ],
  );
}

pw.Widget _headerCell(String text, {pw.TextAlign align = pw.TextAlign.left}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: AppSpacing.xs),
    child: pw.Text(
      text,
      textAlign: align,
      style: pw.TextStyle(
        fontSize: 11,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.grey800,
      ),
    ),
  );
}

String _fmtQty(double q) {
  if (q == q.roundToDouble()) return q.toInt().toString();
  return q.toStringAsFixed(2);
}

String _formatDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}
