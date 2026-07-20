import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../models/workspace.dart';
import '../models/generated_document.dart';
import '../models/document_line_item.dart';
import '../models/file_attachment.dart';
import '../models/document_type.dart';
import '../models/field_form_submission.dart';
import '../models/field_form_template.dart';
import '../models/form_field_definition.dart';
import '../models/form_field_type.dart';
import '../models/project_note.dart';
import '../utils/currency_utils.dart';
import '../utils/pdf_export_io.dart'
    if (dart.library.html) '../utils/pdf_export_web.dart' as pdf_export;

class PDFService {
  // Generate invoice PDF
  Future<Uint8List> generateInvoicePDF({
    required GeneratedDocument invoice,
    required Workspace workspace,
    String? clientName,
    String? projectName,
    String projectLabel = 'Project',
  }) async {
    final pdf = pw.Document();
    final currencyFormat = CurrencyUtils.getFormatter(workspace.currencyCode);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return [
            // Header
            _buildInvoiceHeader(workspace, invoice),
            pw.SizedBox(height: 20),

            // Bill To Section
            _buildBillToSection(clientName, projectName, projectLabel),
            pw.SizedBox(height: 20),

            // Line Items Table
            _buildInvoiceLineItemsTable(invoice, currencyFormat),
            pw.SizedBox(height: 20),

            // Totals Section
            _buildInvoiceTotalsSection(invoice, currencyFormat),
            pw.SizedBox(height: 20),

            // Payment Terms
            _buildPaymentTerms(invoice),
          ];
        },
        footer: (pw.Context context) {
          return pw.Column(
            children: [
              _buildFooter(workspace),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text(
                    'Page ${context.pageNumber} of ${context.pagesCount}',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildInvoiceHeader(Workspace workspace, GeneratedDocument invoice) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Company Info
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              workspace.name,
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            if (workspace.fullCompanyAddress != null &&
                workspace.fullCompanyAddress!.isNotEmpty) ...[
              pw.SizedBox(height: 4),
              pw.Text(
                workspace.fullCompanyAddress!,
                style: const pw.TextStyle(fontSize: 10),
              ),
            ],
          ],
        ),
        // Invoice Info
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'INVOICE',
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              invoice.documentNumber ?? '',
              style: const pw.TextStyle(fontSize: 12),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Date: ${DateFormat('MM/dd/yyyy').format(invoice.createdAt)}',
              style: const pw.TextStyle(fontSize: 10),
            ),
            if (invoice.dueDate != null)
              pw.Text(
                'Due: ${DateFormat('MM/dd/yyyy').format(invoice.dueDate!)}',
                style: const pw.TextStyle(fontSize: 10),
              ),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildBillToSection(String? clientName, String? projectName, String projectLabel) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'BILL TO:',
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            clientName ?? 'Customer',
            style: const pw.TextStyle(fontSize: 11),
          ),
          if (projectName != null) ...[
            pw.SizedBox(height: 2),
            pw.Text(
              '$projectLabel: $projectName',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
          ],
        ],
      ),
    );
  }

  pw.Widget _buildInvoiceLineItemsTable(GeneratedDocument invoice, NumberFormat currencyFormat) {
    final visibleItems = invoice.lineItems.where((item) => item.isVisible && item.isItem).toList();
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      children: [
        // Header row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _buildTableCell('Description', isHeader: true),
            _buildTableCell('Quantity', isHeader: true, align: pw.TextAlign.right),
            _buildTableCell('Unit Price', isHeader: true, align: pw.TextAlign.right),
            _buildTableCell('Total', isHeader: true, align: pw.TextAlign.right),
          ],
        ),
        // Data rows
        ...visibleItems.map((item) => pw.TableRow(
              children: [
                _buildTableCell(item.name),
                _buildTableCell(item.formattedQuantity, align: pw.TextAlign.right),
                _buildTableCell(currencyFormat.format(item.unitPrice), align: pw.TextAlign.right),
                _buildTableCell(currencyFormat.format(item.total), align: pw.TextAlign.right),
              ],
            )),
      ],
    );
  }

  pw.Widget _buildTableCell(
    String text, {
    bool isHeader = false,
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 11 : 10,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: align,
      ),
    );
  }

  pw.Widget _buildInvoiceTotalsSection(GeneratedDocument invoice, NumberFormat currencyFormat) {
    final subtotal = invoice.lineItemsTotal;
    final taxAmount = invoice.computedTaxAmount; // honors per-line taxability [M002]
    final discount = invoice.discountAmount; // [M004]
    final total = invoice.computedGrandTotal;

    return pw.Container(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 200,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Column(
          children: [
            _buildTotalRow('Subtotal:', currencyFormat.format(subtotal)),
            if (discount > 0) ...[
              pw.SizedBox(height: 4),
              _buildTotalRow('Discount:', '-${currencyFormat.format(discount)}'),
            ],
            if (invoice.collectTax && invoice.taxRate > 0) ...[
              pw.SizedBox(height: 4),
              _buildTotalRow(
                'Tax (${invoice.taxRate.toStringAsFixed(1)}%):',
                currencyFormat.format(taxAmount),
              ),
            ],
            pw.Divider(thickness: 1),
            _buildTotalRow(
              'TOTAL:',
              currencyFormat.format(total),
              isBold: true,
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _buildTotalRow(String label, String amount, {bool isBold = false}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: isBold ? 12 : 10,
            fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
        pw.Text(
          amount,
          style: pw.TextStyle(
            fontSize: isBold ? 12 : 10,
            fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ],
    );
  }

  pw.Widget _buildPaymentTerms(GeneratedDocument invoice) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Payment Terms',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          if (invoice.dueDate != null)
            pw.Text(
              'Due Date: ${DateFormat('MM/dd/yyyy').format(invoice.dueDate!)}',
              style: const pw.TextStyle(fontSize: 10),
            ),
          if (invoice.renderedContent.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text(
              'Notes:',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              invoice.renderedContent,
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
        ],
      ),
    );
  }

  pw.Widget _buildFooter(Workspace workspace) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey300),
        ),
      ),
      child: pw.Center(
        child: pw.Text(
          'Thank you for your business!',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
        ),
      ),
    );
  }


  // Generate document PDF (generic documents from templates)
  Future<Uint8List> generateDocumentPDF({
    required GeneratedDocument document,
    required Workspace workspace,
    List<FileAttachment>? attachedPhotos,
    Uint8List? signatureImageBytes,
    Uint8List? logoBytes,
  }) async {
    final pdf = pw.Document();
    final currencyFormat = CurrencyUtils.getFormatter(workspace.currencyCode);

    // Convert logo bytes to image if provided
    pw.ImageProvider? logoImage;
    if (logoBytes != null && logoBytes.isNotEmpty) {
      try {
        logoImage = pw.MemoryImage(logoBytes);
      } catch (e) {
        // Ignore logo loading errors
      }
    }

    // Convert signature bytes to image if provided
    pw.ImageProvider? signatureImage;
    if (signatureImageBytes != null && signatureImageBytes.isNotEmpty) {
      try {
        signatureImage = pw.MemoryImage(signatureImageBytes);
      } catch (e) {
        // Ignore signature loading errors
      }
    }

    // Build line items widgets
    final visibleLineItems = document.visibleLineItems;

    // Download attached image bytes for embedding (cap at 20 images, 15s timeout each).
    // Non-image artifacts are listed in the PDF and attached to outbound emails.
    const maxPhotos = 20;
    final photoImages = <pw.MemoryImage>[];
    final attachedFiles = attachedPhotos ?? const <FileAttachment>[];
    final nonImageFiles = attachedFiles.where((file) => !file.isImage).toList();
    if (attachedPhotos != null) {
      final imagePhotos = attachedPhotos.where((p) => p.isImage).take(maxPhotos);
      final futures = imagePhotos.map((photo) async {
        try {
          final response = await http
              .get(Uri.parse(photo.fileUrl))
              .timeout(const Duration(seconds: 15));
          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            return pw.MemoryImage(response.bodyBytes);
          }
        } catch (_) {
          // Skip photos that fail to download
        }
        return null;
      });
      final results = await Future.wait(futures);
      photoImages.addAll(results.whereType<pw.MemoryImage>());
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return [
            // Header with logo
            _buildDocumentHeader(document, workspace, logoImage),
            pw.SizedBox(height: 20),

            // Prepared By / Prepared For
            if (document.preparedBy != null || document.preparedFor != null)
              _buildDocContactHeaders(document),

            // Gold divider line
            pw.Container(
              height: 3,
              margin: const pw.EdgeInsets.symmetric(vertical: 16),
              color: PdfColor.fromHex('#D4A843'),
            ),

            // Main content (rendered markdown)
            ...MarkdownToPdfConverter.convert(document.renderedContent),

            // Line items table
            if (visibleLineItems.isNotEmpty) ...[
              pw.SizedBox(height: 20),
              _buildDocLineItemsTable(visibleLineItems, document, currencyFormat),
            ],

            // Attached files
            if (photoImages.isNotEmpty || nonImageFiles.isNotEmpty) ...[
              pw.SizedBox(height: 20),
              pw.Text(
                'Attached Files',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 10),
              if (photoImages.isNotEmpty) ..._buildPhotoGrid(photoImages),
              if (nonImageFiles.isNotEmpty) ...[
                if (photoImages.isNotEmpty) pw.SizedBox(height: 8),
                ..._buildAttachmentList(nonImageFiles),
              ],
            ],

            // Signature section
            if (document.isSigned) ...[
              pw.SizedBox(height: 30),
              _buildDocSignatureSection(document, signatureImage),
            ],
          ];
        },
        footer: (pw.Context context) {
          return _buildDocumentFooter(document, workspace, context);
        },
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildDocumentHeader(
    GeneratedDocument document,
    Workspace workspace,
    pw.ImageProvider? logoImage,
  ) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Logo
        if (logoImage != null)
          pw.Container(
            width: 80,
            height: 80,
            margin: const pw.EdgeInsets.only(right: 16),
            child: pw.Image(logoImage, fit: pw.BoxFit.contain),
          ),
        // Document title and date
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                document.templateName,
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (document.documentNumber != null &&
                  document.documentNumber!.isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Text(
                  document.documentNumber!,
                  style: const pw.TextStyle(fontSize: 12),
                ),
              ],
              pw.SizedBox(height: 4),
              pw.Text(
                DateFormat('MMMM dd, yyyy').format(document.createdAt),
                style: const pw.TextStyle(
                  fontSize: 11,
                  color: PdfColors.grey700,
                ),
              ),
              if (document.dueDate != null && document.documentType.hasExpiryDate) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  '${document.documentType.expiryDateLabel}: ${DateFormat('MMMM dd, yyyy').format(document.dueDate!)}',
                  style: const pw.TextStyle(
                    fontSize: 11,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _buildDocContactHeaders(GeneratedDocument document) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (document.preparedBy != null && !document.preparedBy!.isEmpty)
          pw.Expanded(
            child: _buildDocContactColumn('FROM', document.preparedBy!),
          ),
        if (document.preparedFor != null && !document.preparedFor!.isEmpty)
          pw.Expanded(
            child: _buildDocContactColumn('TO', document.preparedFor!),
          ),
      ],
    );
  }

  pw.Widget _buildDocContactColumn(String title, DocumentContactInfo contact) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: 10,
          ),
        ),
        pw.SizedBox(height: 4),
        if (contact.name != null && contact.name!.isNotEmpty)
          pw.Text(
            contact.name!,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
          ),
        if (contact.organization != null && contact.organization!.isNotEmpty)
          pw.Text(
            contact.organization!,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
        if (contact.phone != null && contact.phone!.isNotEmpty)
          pw.Text(
            contact.phone!,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
        if (contact.email != null && contact.email!.isNotEmpty)
          pw.Text(
            contact.email!,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
        if (contact.address != null && contact.address!.isNotEmpty)
          pw.Text(
            contact.address!,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
      ],
    );
  }

  pw.Widget _buildDocLineItemsTable(
    List<DocumentLineItem> items,
    GeneratedDocument document,
    NumberFormat currencyFormat,
  ) {
    final topLevelItems = items.where((i) => i.parentId == null).toList();
    final subtotal = document.lineItemsTotal;
    final hasTax = document.collectTax && document.taxRate > 0;
    final taxAmount = document.computedTaxAmount; // per-line taxability [M002]
    final discount = document.discountAmount; // [M004]
    final grandTotal = document.computedGrandTotal;
    final depositAmount =
        (document.metadata['applied_deposit_amount'] as num?)?.toDouble() ?? 0.0;
    final retainageAmount = document.retainageAmount;
    final retainagePercent = document.retainagePercent;
    final hasHoldback = retainageAmount > 0;
    final hasDeposit = depositAmount > 0;
    final balanceDue =
        (grandTotal - depositAmount - retainageAmount).clamp(0.0, double.infinity);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Line Items',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300),
          columnWidths: {
            0: const pw.FlexColumnWidth(4),
            1: const pw.FlexColumnWidth(1),
            2: const pw.FlexColumnWidth(1.5),
            3: const pw.FlexColumnWidth(1.5),
          },
          children: [
            // Header row
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                _buildTableCell('Description', isHeader: true),
                _buildTableCell('Qty', isHeader: true, align: pw.TextAlign.right),
                _buildTableCell('Price', isHeader: true, align: pw.TextAlign.right),
                _buildTableCell('Total', isHeader: true, align: pw.TextAlign.right),
              ],
            ),
            // Data rows
            ...topLevelItems.expand((item) => _buildDocLineItemRows(item, items, currencyFormat)),
            // Subtotal row (only label it "Subtotal" if tax applies)
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey100),
              children: [
                _buildTableCell(hasTax || discount > 0 ? 'Subtotal' : 'Total', isHeader: true),
                _buildTableCell('', isHeader: false),
                _buildTableCell('', isHeader: false),
                _buildTableCell(currencyFormat.format(subtotal), isHeader: true, align: pw.TextAlign.right),
              ],
            ),
            // Discount row [M004]
            if (discount > 0)
              pw.TableRow(
                children: [
                  _buildTableCell('Discount', isHeader: false),
                  _buildTableCell('', isHeader: false),
                  _buildTableCell('', isHeader: false),
                  _buildTableCell(
                    '-${currencyFormat.format(discount)}',
                    align: pw.TextAlign.right,
                  ),
                ],
              ),
            // Tax row
            if (hasTax)
              pw.TableRow(
                children: [
                  _buildTableCell(
                    '${document.taxName ?? 'Tax'} (${document.taxRate.toStringAsFixed(1)}%)',
                    isHeader: false,
                  ),
                  _buildTableCell('', isHeader: false),
                  _buildTableCell('', isHeader: false),
                  _buildTableCell(currencyFormat.format(taxAmount), align: pw.TextAlign.right),
                ],
              ),
            // Grand total row (when there's a deduction/tax to net out)
            if (hasTax || discount > 0)
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                children: [
                  _buildTableCell('Total', isHeader: true),
                  _buildTableCell('', isHeader: false),
                  _buildTableCell('', isHeader: false),
                  _buildTableCell(currencyFormat.format(grandTotal), isHeader: true, align: pw.TextAlign.right),
                ],
              ),
            // Deposit deduction row
            if (hasDeposit)
              pw.TableRow(
                children: [
                  _buildTableCell('Less Deposit', isHeader: false),
                  _buildTableCell('', isHeader: false),
                  _buildTableCell('', isHeader: false),
                  _buildTableCell(
                    '-${currencyFormat.format(depositAmount)}',
                    align: pw.TextAlign.right,
                  ),
                ],
              ),
            // Holdback (retainage) withheld row
            if (hasHoldback)
              pw.TableRow(
                children: [
                  _buildTableCell(
                    'Less Holdback (${retainagePercent.toStringAsFixed(1)}%)',
                    isHeader: false,
                  ),
                  _buildTableCell('', isHeader: false),
                  _buildTableCell('', isHeader: false),
                  _buildTableCell(
                    '-${currencyFormat.format(retainageAmount)}',
                    align: pw.TextAlign.right,
                  ),
                ],
              ),
            // Balance due row when anything was deducted
            if (hasDeposit || hasHoldback)
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                children: [
                  _buildTableCell('Balance Due', isHeader: true),
                  _buildTableCell('', isHeader: false),
                  _buildTableCell('', isHeader: false),
                  _buildTableCell(
                    currencyFormat.format(balanceDue),
                    isHeader: true,
                    align: pw.TextAlign.right,
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  List<pw.TableRow> _buildDocLineItemRows(
    DocumentLineItem item,
    List<DocumentLineItem> allItems,
    NumberFormat currencyFormat, {
    int depth = 0,
  }) {
    final children = allItems.where((i) => i.parentId == item.id && i.isVisible).toList();
    final isGroup = item.isGroup;

    final List<pw.TableRow> rows = [
      pw.TableRow(
        children: [
          pw.Padding(
            padding: pw.EdgeInsets.only(left: 8 + (depth * 12.0), top: 6, bottom: 6, right: 8),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  item.name,
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: isGroup ? pw.FontWeight.bold : pw.FontWeight.normal,
                  ),
                ),
                if (item.description != null && item.description!.isNotEmpty)
                  pw.Text(
                    item.description!,
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                  ),
              ],
            ),
          ),
          _buildTableCell(
            isGroup ? '' : item.formattedQuantity,
            align: pw.TextAlign.right,
          ),
          _buildTableCell(
            isGroup ? '' : item.formattedUnitPrice,
            align: pw.TextAlign.right,
          ),
          _buildTableCell(
            isGroup
                ? currencyFormat.format(_calculateDocGroupTotal(item.id, allItems))
                : item.formattedTotal,
            isHeader: isGroup,
            align: pw.TextAlign.right,
          ),
        ],
      ),
    ];

    // Add children rows
    for (final child in children) {
      rows.addAll(_buildDocLineItemRows(child, allItems, currencyFormat, depth: depth + 1));
    }

    return rows;
  }

  double _calculateDocGroupTotal(String groupId, List<DocumentLineItem> allItems) {
    double total = 0;
    for (final child in allItems.where((i) => i.parentId == groupId)) {
      if (!child.isVisible) continue;
      if (child.isGroup) {
        total += _calculateDocGroupTotal(child.id, allItems);
      } else {
        total += child.total;
      }
    }
    return total;
  }

  /// Lay out photo images in a 2-column grid with consistent sizing.
  List<pw.Widget> _buildPhotoGrid(List<pw.MemoryImage> images) {
    final widgets = <pw.Widget>[];
    for (var i = 0; i < images.length; i += 2) {
      final row = <pw.Widget>[
        pw.Expanded(
          child: pw.Container(
            height: 200,
            child: pw.Image(images[i], fit: pw.BoxFit.contain),
          ),
        ),
      ];
      if (i + 1 < images.length) {
        row.add(pw.SizedBox(width: 10));
        row.add(
          pw.Expanded(
            child: pw.Container(
              height: 200,
              child: pw.Image(images[i + 1], fit: pw.BoxFit.contain),
            ),
          ),
        );
      } else {
        row.add(pw.SizedBox(width: 10));
        row.add(pw.Expanded(child: pw.SizedBox()));
      }
      widgets.add(pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: row,
      ));
      widgets.add(pw.SizedBox(height: 10));
    }
    return widgets;
  }

  List<pw.Widget> _buildAttachmentList(List<FileAttachment> files) {
    return files
        .map(
          (file) => pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 6),
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F8FAFC'),
              border: pw.Border.all(color: PdfColor.fromHex('#E5E7EB')),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Row(
              children: [
                pw.Container(
                  width: 44,
                  child: pw.Text(
                    file.fileExtension,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(file.fileName, style: const pw.TextStyle(fontSize: 10)),
                ),
                pw.Text(file.formattedSize, style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ),
        )
        .toList();
  }

  pw.Widget _buildDocSignatureSection(
    GeneratedDocument document,
    pw.ImageProvider? signatureImage,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F0FDF4'), // Light green background
        border: pw.Border.all(color: PdfColors.green300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(
                width: 16,
                height: 16,
                decoration: const pw.BoxDecoration(
                  color: PdfColors.green700,
                  shape: pw.BoxShape.circle,
                ),
                child: pw.Center(
                  child: pw.Text(
                    '\u2714',
                    style: const pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Text(
                'Document Signed',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 12,
                  color: PdfColors.green800,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Signed by:',
                      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                    ),
                    pw.Text(
                      document.signedByName ?? 'Unknown',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                    ),
                    if (document.signedByEmail != null)
                      pw.Text(
                        document.signedByEmail!,
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                      ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Date: ${document.formattedSignedAt}',
                      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                    ),
                  ],
                ),
              ),
              if (signatureImage != null)
                pw.Container(
                  width: 120,
                  height: 60,
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Image(signatureImage, fit: pw.BoxFit.contain),
                ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildDocumentFooter(
    GeneratedDocument document,
    Workspace workspace,
    pw.Context context,
  ) {
    return pw.Column(
      children: [
        if (document.footerContent != null && document.footerContent!.isNotEmpty) ...[
          pw.Container(
            padding: const pw.EdgeInsets.only(top: 10),
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300)),
            ),
            child: pw.Text(
              document.footerContent!,
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ),
        ],
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              workspace.name,
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
            ),
          ],
        ),
      ],
    );
  }

  /// Generate PDF for a list of notes belonging to an entity (project,
  /// customer, or vendor).
  Future<Uint8List> generateNotesPDF({
    required List<ProjectNote> notes,
    required Workspace workspace,
    required String entityType,
    String? entityTitle,
    String? filterTag,
    Uint8List? logoBytes,
  }) async {
    final pdf = pw.Document();

    pw.ImageProvider? logoImage;
    if (logoBytes != null && logoBytes.isNotEmpty) {
      try {
        logoImage = pw.MemoryImage(logoBytes);
      } catch (_) {}
    }

    final entityLabel = entityType.isEmpty
        ? 'Notes'
        : '${entityType[0].toUpperCase()}${entityType.substring(1)} Notes';
    final generatedAt = DateTime.now();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(40),
        build: (ctx) => [
          _buildNotesHeader(workspace, entityLabel, entityTitle, logoImage),
          pw.SizedBox(height: 16),
          _buildNotesMeta(
            generatedAt: generatedAt,
            count: notes.length,
            filterTag: filterTag,
          ),
          pw.SizedBox(height: 16),
          if (notes.isEmpty)
            pw.Text('No notes to display.',
                style: const pw.TextStyle(
                    fontSize: 11, color: PdfColors.grey600))
          else
            ..._buildNotesList(notes),
        ],
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(workspace.name,
                style: const pw.TextStyle(
                    fontSize: 8, color: PdfColors.grey500)),
            pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                style: const pw.TextStyle(
                    fontSize: 8, color: PdfColors.grey500)),
          ],
        ),
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildNotesHeader(
    Workspace workspace,
    String entityLabel,
    String? entityTitle,
    pw.ImageProvider? logoImage,
  ) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (logoImage != null) ...[
              pw.Container(
                width: 80,
                height: 40,
                child: pw.Image(logoImage, fit: pw.BoxFit.contain),
              ),
              pw.SizedBox(height: 6),
            ],
            pw.Text(workspace.name,
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(entityLabel,
                style: pw.TextStyle(
                    fontSize: 18, fontWeight: pw.FontWeight.bold)),
            if (entityTitle != null && entityTitle.isNotEmpty) ...[
              pw.SizedBox(height: 4),
              pw.Text(entityTitle,
                  style: const pw.TextStyle(
                      fontSize: 11, color: PdfColors.grey700)),
            ],
          ],
        ),
      ],
    );
  }

  pw.Widget _buildNotesMeta({
    required DateTime generatedAt,
    required int count,
    String? filterTag,
  }) {
    final rows = <List<String>>[
      ['Generated', DateFormat('MM/dd/yyyy hh:mm a').format(generatedAt)],
      ['Notes', '$count'],
    ];
    if (filterTag != null && filterTag.isNotEmpty) {
      rows.add(['Filter', filterTag]);
    }
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: rows
            .map((r) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(children: [
                    pw.SizedBox(
                      width: 80,
                      child: pw.Text(r[0],
                          style: const pw.TextStyle(
                              fontSize: 10, color: PdfColors.grey600)),
                    ),
                    pw.Expanded(
                      child: pw.Text(r[1],
                          style: pw.TextStyle(
                              fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    ),
                  ]),
                ))
            .toList(),
      ),
    );
  }

  List<pw.Widget> _buildNotesList(List<ProjectNote> notes) {
    final dateFormat = DateFormat('MMM d, y · h:mm a');
    final widgets = <pw.Widget>[];
    for (var i = 0; i < notes.length; i++) {
      final note = notes[i];
      widgets.add(
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 10),
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      dateFormat.format(note.createdAt),
                      style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey800),
                    ),
                  ),
                  if (note.tag != null && note.tag!.isNotEmpty)
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey200,
                        borderRadius:
                            const pw.BorderRadius.all(pw.Radius.circular(8)),
                      ),
                      child: pw.Text(
                        note.tag!,
                        style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey800),
                      ),
                    ),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                note.content,
                style: const pw.TextStyle(fontSize: 11, lineSpacing: 2),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                note.isEdited
                    ? '${note.authorName} · Edited'
                    : note.authorName,
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey600),
              ),
            ],
          ),
        ),
      );
    }
    return widgets;
  }

  /// Fetch image bytes from a URL
  static Future<Uint8List?> fetchImageBytes(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
    } catch (e) {
      // Ignore fetch errors
    }
    return null;
  }

  /// Generate PDF for a field-form submission (inspection / completion
  /// report / safety checklist, etc.).
  ///
  /// [imageBytesByFieldId] pre-fetched image bytes keyed by field id, for
  /// photo/file fields whose value points at an image URL. Same for
  /// signature bytes — pre-fetched by the caller.
  Future<Uint8List> generateFieldFormSubmissionPDF({
    required FieldFormSubmission submission,
    required FieldFormTemplate template,
    required Workspace workspace,
    String? taskTitle,
    String? projectName,
    Uint8List? logoBytes,
    Map<String, Uint8List>? imageBytesByFieldId,
    Uint8List? techSignatureBytes,
    Uint8List? supervisorSignatureBytes,
    Uint8List? customerSignatureBytes,
  }) async {
    final pdf = pw.Document();

    pw.ImageProvider? logoImage;
    if (logoBytes != null && logoBytes.isNotEmpty) {
      try {
        logoImage = pw.MemoryImage(logoBytes);
      } catch (_) {}
    }

    final images = <String, pw.ImageProvider>{};
    imageBytesByFieldId?.forEach((key, bytes) {
      try {
        images[key] = pw.MemoryImage(bytes);
      } catch (_) {}
    });

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(40),
        build: (ctx) => [
          _buildFieldFormHeader(workspace, template, submission, logoImage),
          pw.SizedBox(height: 16),
          _buildFieldFormMeta(submission, taskTitle, projectName),
          pw.SizedBox(height: 16),
          _buildFieldFormResponses(template, submission, images),
          pw.SizedBox(height: 16),
          _buildFieldFormSignatures(
            submission,
            techSignatureBytes,
            supervisorSignatureBytes,
            customerSignatureBytes,
          ),
          if (submission.notes != null && submission.notes!.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Text('Notes',
                style: pw.TextStyle(
                    fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(submission.notes!, style: const pw.TextStyle(fontSize: 10)),
          ],
        ],
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(workspace.name,
                style: const pw.TextStyle(
                    fontSize: 8, color: PdfColors.grey500)),
            pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                style: const pw.TextStyle(
                    fontSize: 8, color: PdfColors.grey500)),
          ],
        ),
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildFieldFormHeader(
    Workspace workspace,
    FieldFormTemplate template,
    FieldFormSubmission submission,
    pw.ImageProvider? logoImage,
  ) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (logoImage != null) ...[
              pw.Container(
                width: 80,
                height: 40,
                child: pw.Image(logoImage, fit: pw.BoxFit.contain),
              ),
              pw.SizedBox(height: 6),
            ],
            pw.Text(workspace.name,
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(template.name,
                style: pw.TextStyle(
                    fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(template.category.displayName.toUpperCase(),
                style: const pw.TextStyle(
                    fontSize: 10, color: PdfColors.grey600)),
            pw.SizedBox(height: 4),
            pw.Text('Status: ${submission.status.displayName}',
                style: const pw.TextStyle(fontSize: 10)),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildFieldFormMeta(
    FieldFormSubmission submission,
    String? taskTitle,
    String? projectName,
  ) {
    final rows = <List<String>>[];
    if (submission.filledByName != null) {
      rows.add(['Filled by', submission.filledByName!]);
    }
    if (submission.submittedAt != null) {
      rows.add([
        'Submitted',
        DateFormat('MM/dd/yyyy hh:mm a').format(submission.submittedAt!),
      ]);
    }
    if (projectName != null && projectName.isNotEmpty) {
      rows.add(['Project', projectName]);
    }
    if (taskTitle != null && taskTitle.isNotEmpty) {
      rows.add(['Task', taskTitle]);
    }
    if (rows.isEmpty) return pw.SizedBox.shrink();
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: rows
            .map((r) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(children: [
                    pw.SizedBox(
                      width: 80,
                      child: pw.Text(r[0],
                          style: const pw.TextStyle(
                              fontSize: 10, color: PdfColors.grey600)),
                    ),
                    pw.Expanded(
                      child: pw.Text(r[1],
                          style: pw.TextStyle(
                              fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    ),
                  ]),
                ))
            .toList(),
      ),
    );
  }

  pw.Widget _buildFieldFormResponses(
    FieldFormTemplate template,
    FieldFormSubmission submission,
    Map<String, pw.ImageProvider> images,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Responses',
            style: pw.TextStyle(
                fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        ...template.fields.map((field) => _buildFieldFormFieldRow(
              field,
              submission.data[field.id],
              images[field.id],
            )),
      ],
    );
  }

  pw.Widget _buildFieldFormFieldRow(
    FormFieldDefinition field,
    dynamic value,
    pw.ImageProvider? image,
  ) {
    if (field.type == FormFieldType.section) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8, bottom: 4),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Divider(height: 1, color: PdfColors.grey400),
            pw.SizedBox(height: 4),
            pw.Text(field.label,
                style: pw.TextStyle(
                    fontSize: 12, fontWeight: pw.FontWeight.bold)),
            if (field.description != null && field.description!.isNotEmpty)
              pw.Text(field.description!,
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey600)),
          ],
        ),
      );
    }

    if (field.type == FormFieldType.table) {
      final rows =
          (value as List?)?.cast<Map<String, dynamic>>() ?? [];
      final cols = field.columns ?? [];
      if (rows.isEmpty || cols.isEmpty) {
        return _pdfFieldLabelValue(field.label, '—');
      }
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(field.label,
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey600)),
            pw.SizedBox(height: 4),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              children: [
                pw.TableRow(
                  decoration:
                      const pw.BoxDecoration(color: PdfColors.grey200),
                  children: cols
                      .map((c) => pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text(c.label,
                                style: pw.TextStyle(
                                    fontSize: 9,
                                    fontWeight: pw.FontWeight.bold)),
                          ))
                      .toList(),
                ),
                ...rows.map((r) => pw.TableRow(
                      children: cols
                          .map((c) => pw.Padding(
                                padding: const pw.EdgeInsets.all(4),
                                child: pw.Text(
                                    r[c.key]?.toString() ?? '',
                                    style: const pw.TextStyle(fontSize: 9)),
                              ))
                          .toList(),
                    )),
              ],
            ),
          ],
        ),
      );
    }

    if ((field.type == FormFieldType.photo ||
            field.type == FormFieldType.file) &&
        image != null) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(field.label,
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey600)),
            pw.SizedBox(height: 4),
            pw.Container(
              height: 200,
              alignment: pw.Alignment.centerLeft,
              child: pw.Image(image, fit: pw.BoxFit.contain),
            ),
          ],
        ),
      );
    }

    return _pdfFieldLabelValue(
        field.label, _formatFieldValueForPdf(field, value));
  }

  pw.Widget _pdfFieldLabelValue(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label,
              style: const pw.TextStyle(
                  fontSize: 9, color: PdfColors.grey600)),
          pw.SizedBox(height: 2),
          pw.Text(value.isEmpty ? '—' : value,
              style: const pw.TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  String _formatFieldValueForPdf(FormFieldDefinition field, dynamic value) {
    if (value == null) return '';
    switch (field.type) {
      case FormFieldType.checkbox:
        return (value as bool? ?? false) ? 'Yes' : 'No';
      case FormFieldType.multiSelect:
        return ((value as List?)?.cast<String>() ?? []).join(', ');
      case FormFieldType.inspectionItem:
        switch (value as String?) {
          case 'pass':
            return 'Pass';
          case 'fail':
            return 'Fail';
          case 'na':
            return 'N/A';
          default:
            return '—';
        }
      case FormFieldType.rating:
        final r = (value as num?)?.toInt() ?? 0;
        return '$r / 5';
      case FormFieldType.file:
      case FormFieldType.photo:
        if (value is Map) return (value['fileName'] as String?) ?? 'File';
        return value.toString();
      default:
        return value.toString();
    }
  }

  pw.Widget _buildFieldFormSignatures(
    FieldFormSubmission sub,
    Uint8List? techBytes,
    Uint8List? supBytes,
    Uint8List? custBytes,
  ) {
    final slots = <pw.Widget>[];
    pw.Widget slot(String role, FormSignatureSlot s, Uint8List? bytes) {
      pw.ImageProvider? img;
      if (bytes != null && bytes.isNotEmpty) {
        try {
          img = pw.MemoryImage(bytes);
        } catch (_) {}
      }
      return pw.Container(
        width: 170,
        margin: const pw.EdgeInsets.only(right: 8, bottom: 8),
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(role,
                style: pw.TextStyle(
                    fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            if (img != null)
              pw.Container(
                  height: 50,
                  child: pw.Image(img, fit: pw.BoxFit.contain))
            else
              pw.Container(
                  height: 50,
                  alignment: pw.Alignment.center,
                  child: pw.Text('Not signed',
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.grey500))),
            pw.SizedBox(height: 4),
            if (s.isSigned) ...[
              pw.Text(s.signedByName ?? '',
                  style: const pw.TextStyle(fontSize: 9)),
              pw.Text(s.formattedSignedAt,
                  style: const pw.TextStyle(
                      fontSize: 8, color: PdfColors.grey600)),
            ],
          ],
        ),
      );
    }

    if (sub.techSignature.isSigned) {
      slots.add(slot('Technician', sub.techSignature, techBytes));
    }
    if (sub.supervisorSignature.isSigned) {
      slots.add(slot('Supervisor', sub.supervisorSignature, supBytes));
    }
    if (sub.customerSignature.isSigned) {
      slots.add(slot('Customer', sub.customerSignature, custBytes));
    }
    if (slots.isEmpty) return pw.SizedBox.shrink();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Signatures',
            style: pw.TextStyle(
                fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.Wrap(children: slots),
      ],
    );
  }

  // Share / download PDF (platform-aware)
  Future<void> sharePDF(Uint8List pdfBytes, String filename) async {
    await pdf_export.exportPdf(pdfBytes, filename);
  }
}

/// Helper class to convert markdown text to PDF widgets
class MarkdownToPdfConverter {
  static List<pw.Widget> convert(String markdown) {
    final widgets = <pw.Widget>[];
    final lines = markdown.split('\n');

    for (var line in lines) {
      line = line.trim();

      if (line.isEmpty) {
        widgets.add(pw.SizedBox(height: 8));
        continue;
      }

      // Handle headers
      if (line.startsWith('### ')) {
        widgets.add(pw.Text(
          line.substring(4),
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ));
        widgets.add(pw.SizedBox(height: 4));
      } else if (line.startsWith('## ')) {
        widgets.add(pw.Text(
          line.substring(3),
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ));
        widgets.add(pw.SizedBox(height: 6));
      } else if (line.startsWith('# ')) {
        widgets.add(pw.Text(
          line.substring(2),
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ));
        widgets.add(pw.SizedBox(height: 8));
      }
      // Handle unordered lists
      else if (line.startsWith('- ') || line.startsWith('* ')) {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(left: 16),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('\u2022 ', style: const pw.TextStyle(fontSize: 10)),
              pw.Expanded(
                child: _buildRichText(line.substring(2), 10),
              ),
            ],
          ),
        ));
      }
      // Handle ordered lists
      else if (RegExp(r'^\d+\. ').hasMatch(line)) {
        final match = RegExp(r'^(\d+)\. (.*)').firstMatch(line);
        if (match != null) {
          widgets.add(pw.Padding(
            padding: const pw.EdgeInsets.only(left: 16),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('${match.group(1)}. ', style: const pw.TextStyle(fontSize: 10)),
                pw.Expanded(
                  child: _buildRichText(match.group(2)!, 10),
                ),
              ],
            ),
          ));
        }
      }
      // Handle horizontal rules
      else if (line == '---' || line == '***' || line == '___') {
        widgets.add(pw.Divider(thickness: 1, color: PdfColors.grey300));
      }
      // Handle blockquotes
      else if (line.startsWith('> ')) {
        widgets.add(pw.Container(
          padding: const pw.EdgeInsets.all(8),
          margin: const pw.EdgeInsets.symmetric(vertical: 4),
          decoration: const pw.BoxDecoration(
            border: pw.Border(left: pw.BorderSide(color: PdfColors.grey400, width: 3)),
            color: PdfColors.grey100,
          ),
          child: _buildRichText(line.substring(2), 10, color: PdfColors.grey700),
        ));
      }
      // Regular paragraph
      else {
        widgets.add(_buildRichText(line, 10));
      }
    }

    return widgets;
  }

  /// Build a [pw.RichText] widget that renders inline bold, italic,
  /// bold-italic, and code spans from markdown text.
  static pw.Widget _buildRichText(String text, double fontSize,
      {PdfColor? color}) {
    final spans = _parseInlineSpans(text, fontSize, color: color);
    if (spans.length == 1) {
      // Single span — use simple Text for efficiency
      final s = spans.first;
      return pw.Text(s.text ?? '', style: s.style);
    }
    return pw.RichText(text: pw.TextSpan(children: spans));
  }

  /// Parse markdown inline formatting into [pw.TextSpan] list.
  ///
  /// Supports: **bold**, __bold__, *italic*, _italic_, ***bold italic***,
  /// ___bold italic___, and `code`.
  static List<pw.TextSpan> _parseInlineSpans(String text, double fontSize,
      {PdfColor? color}) {
    final baseStyle = pw.TextStyle(fontSize: fontSize, color: color);
    final boldStyle = pw.TextStyle(
        fontSize: fontSize, fontWeight: pw.FontWeight.bold, color: color);
    final italicStyle = pw.TextStyle(
        fontSize: fontSize, fontStyle: pw.FontStyle.italic, color: color);
    final boldItalicStyle = pw.TextStyle(
      fontSize: fontSize,
      fontWeight: pw.FontWeight.bold,
      fontStyle: pw.FontStyle.italic,
      color: color,
    );
    final codeStyle = pw.TextStyle(
      fontSize: fontSize * 0.9,
      font: pw.Font.courier(),
      color: color ?? PdfColors.grey800,
    );

    final spans = <pw.TextSpan>[];

    // Regex matches bold-italic (*** or ___), bold (** or __),
    // italic (* or _), or code (`) markers.
    final regex = RegExp(
      r'(\*\*\*|___)(.+?)\1'   // bold italic
      r'|(\*\*|__)(.+?)\3'     // bold
      r'|(\*|_)(.+?)\5'        // italic
      r'|`([^`]+)`',           // code
    );

    var lastEnd = 0;
    for (final match in regex.allMatches(text)) {
      // Add any plain text before this match
      if (match.start > lastEnd) {
        spans.add(pw.TextSpan(
          text: text.substring(lastEnd, match.start),
          style: baseStyle,
        ));
      }

      if (match.group(2) != null) {
        // Bold italic
        spans.add(pw.TextSpan(text: match.group(2), style: boldItalicStyle));
      } else if (match.group(4) != null) {
        // Bold
        spans.add(pw.TextSpan(text: match.group(4), style: boldStyle));
      } else if (match.group(6) != null) {
        // Italic
        spans.add(pw.TextSpan(text: match.group(6), style: italicStyle));
      } else if (match.group(7) != null) {
        // Code
        spans.add(pw.TextSpan(text: match.group(7), style: codeStyle));
      }
      lastEnd = match.end;
    }

    // Add remaining plain text
    if (lastEnd < text.length) {
      spans.add(pw.TextSpan(
        text: text.substring(lastEnd),
        style: baseStyle,
      ));
    }

    if (spans.isEmpty) {
      spans.add(pw.TextSpan(text: text, style: baseStyle));
    }

    return spans;
  }
}
