import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/budget_item.dart';
import '../models/project.dart';
import '../services/service_locator.dart';
import 'currency_utils.dart';

// Platform-specific exports (uses IO on mobile, web APIs on browser)
import 'budget_export_io.dart'
    if (dart.library.html) 'budget_export_web.dart'
    as platform_export;
import 'pdf_export_io.dart'
    if (dart.library.html) 'pdf_export_web.dart'
    as pdf_platform_export;

enum BudgetExportFormat { standard, pdf, quickbooks }

class BudgetExport {
  static final _generatedDateFormat = DateFormat('MMM d, yyyy h:mm a');

  dynamic get _budgetService => ServiceLocator.budgetService;

  /// Export budget to CSV file
  Future<void> exportBudgetToCSV({
    required String projectId,
    required String workspaceId,
    required Project project,
  }) async {
    try {
      // Get all budget items
      final budgetItems = await _budgetService
          .getBudgetItems(projectId, workspaceId: workspaceId)
          .first;

      if (budgetItems.isEmpty) {
        throw Exception('No budget items to export');
      }

      // Build hierarchy tree
      final topLevelItems = budgetItems
          .where((item) => item.parentId == null)
          .toList();

      // Fetch all actual costs in one bulk query
      final actualCosts = await _budgetService.getActualCostsForProject(
        projectId,
        workspaceId,
      );

      // Create CSV data
      final List<List<dynamic>> rows = [];

      // Header row
      rows.add([
        'Level',
        'Name',
        'Description',
        'Approved Price',
        'Projected Cost',
        'Actual Cost',
        'Final Cost',
        'Projected Profit',
        'Projected Margin %',
        'Status',
      ]);

      // Add items recursively
      for (final item in topLevelItems) {
        _addItemToCSV(rows, item, budgetItems, 0, actualCosts);
      }

      // Convert to CSV string
      final csv = const ListToCsvConverter().convert(rows);
      final fileName =
          'budget_${_safeFileName(project.name)}_${DateTime.now().millisecondsSinceEpoch}.csv';

      // Use platform-specific export
      await platform_export.exportCsv(
        csv,
        fileName,
        'Budget Export - ${project.name}',
      );
    } catch (e) {
      throw Exception('Error exporting budget to CSV: $e');
    }
  }

  /// Recursively add item and children to CSV
  void _addItemToCSV(
    List<List<dynamic>> rows,
    BudgetItem item,
    List<BudgetItem> allItems,
    int indentLevel,
    Map<String, double> actualCosts,
  ) {
    final actualCost = actualCosts[item.id] ?? 0.0;

    // Add indentation to name
    final indent = '  ' * indentLevel;

    rows.add([
      item.hierarchyLevel, // Level number
      '$indent${item.name}', // Indented name
      item.description ?? '',
      item.approvedPrice.toStringAsFixed(2),
      item.projectedCost.toStringAsFixed(2),
      actualCost.toStringAsFixed(2),
      item.isComplete ? item.finalCost.toStringAsFixed(2) : '',
      item.projectedProfit.toStringAsFixed(2),
      item.projectedMargin.toStringAsFixed(1),
      item.isComplete ? 'Complete' : 'In Progress',
    ]);

    // Add children recursively
    final children = allItems.where((i) => i.parentId == item.id).toList();
    for (final child in children) {
      _addItemToCSV(rows, child, allItems, indentLevel + 1, actualCosts);
    }
  }

  /// Export budget to a printable PDF file.
  Future<void> exportBudgetToPDF({
    required String projectId,
    required String workspaceId,
    required Project project,
    String currencyCode = 'USD',
  }) async {
    try {
      final budgetItems = await _budgetService
          .getBudgetItems(projectId, workspaceId: workspaceId)
          .first;

      if (budgetItems.isEmpty) {
        throw Exception('No budget items to export');
      }

      final topLevelItems = budgetItems
          .where((item) => item.parentId == null)
          .toList();
      final actualCosts = await _budgetService.getActualCostsForProject(
        projectId,
        workspaceId,
      );
      final rows = <pw.TableRow>[];

      rows.add(
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: [
            _pdfCell('Level', isHeader: true),
            _pdfCell('Name', isHeader: true),
            _pdfCell('Approved', isHeader: true),
            _pdfCell('Projected', isHeader: true),
            _pdfCell('Actual', isHeader: true),
            _pdfCell('Final', isHeader: true),
            _pdfCell('Profit', isHeader: true),
            _pdfCell('Margin', isHeader: true),
            _pdfCell('Status', isHeader: true),
          ],
        ),
      );

      for (final item in topLevelItems) {
        _addItemToPdfRows(
          rows,
          item,
          budgetItems,
          0,
          actualCosts,
          currencyCode,
        );
      }

      final totals = _calculatePdfTotals(budgetItems, actualCosts);
      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.letter.landscape,
          margin: const pw.EdgeInsets.all(28),
          build: (context) => [
            pw.Header(
              level: 0,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Budget Export',
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    project.name,
                    style: const pw.TextStyle(fontSize: 15),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Generated: ${_generatedDateFormat.format(DateTime.now())}',
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey600,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _pdfSummaryColumn([
                    'Budget Items: ${totals.itemCount}',
                    'Approved Price: ${_formatMoney(totals.approvedPrice, currencyCode)}',
                    'Projected Cost: ${_formatMoney(totals.projectedCost, currencyCode)}',
                  ]),
                  _pdfSummaryColumn([
                    'Actual Cost: ${_formatMoney(totals.actualCost, currencyCode)}',
                    'Projected Profit: ${_formatMoney(totals.projectedProfit, currencyCode)}',
                    'Projected Margin: ${totals.projectedMargin.toStringAsFixed(1)}%',
                  ], alignEnd: true),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400),
              columnWidths: const {
                0: pw.FlexColumnWidth(0.6),
                1: pw.FlexColumnWidth(2.7),
                2: pw.FlexColumnWidth(1.0),
                3: pw.FlexColumnWidth(1.0),
                4: pw.FlexColumnWidth(1.0),
                5: pw.FlexColumnWidth(1.0),
                6: pw.FlexColumnWidth(1.0),
                7: pw.FlexColumnWidth(0.8),
                8: pw.FlexColumnWidth(0.9),
              },
              children: rows,
            ),
          ],
        ),
      );

      final fileName =
          'budget_${_safeFileName(project.name)}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      await pdf_platform_export.exportPdf(await pdf.save(), fileName);
    } catch (e) {
      throw Exception('Error exporting budget to PDF: $e');
    }
  }

  void _addItemToPdfRows(
    List<pw.TableRow> rows,
    BudgetItem item,
    List<BudgetItem> allItems,
    int indentLevel,
    Map<String, double> actualCosts,
    String currencyCode,
  ) {
    final actualCost = actualCosts[item.id] ?? 0.0;
    final indent = '  ' * indentLevel;
    final isGroup = item.itemType == BudgetItemType.group;

    rows.add(
      pw.TableRow(
        decoration: isGroup
            ? const pw.BoxDecoration(color: PdfColors.grey100)
            : null,
        children: [
          _pdfCell('${item.hierarchyLevel}'),
          _pdfCell('$indent${item.name}', isStrong: isGroup),
          _pdfCell(_formatMoney(item.approvedPrice, currencyCode)),
          _pdfCell(_formatMoney(item.projectedCost, currencyCode)),
          _pdfCell(_formatMoney(actualCost, currencyCode)),
          _pdfCell(
            item.isComplete ? _formatMoney(item.finalCost, currencyCode) : '-',
          ),
          _pdfCell(_formatMoney(item.projectedProfit, currencyCode)),
          _pdfCell('${item.projectedMargin.toStringAsFixed(1)}%'),
          _pdfCell(item.isComplete ? 'Complete' : 'In Progress'),
        ],
      ),
    );

    final children = allItems.where((i) => i.parentId == item.id).toList();
    for (final child in children) {
      _addItemToPdfRows(
        rows,
        child,
        allItems,
        indentLevel + 1,
        actualCosts,
        currencyCode,
      );
    }
  }

  ({
    int itemCount,
    double approvedPrice,
    double projectedCost,
    double actualCost,
    double projectedProfit,
    double projectedMargin,
  })
  _calculatePdfTotals(
    List<BudgetItem> budgetItems,
    Map<String, double> actualCosts,
  ) {
    final parentIds = budgetItems
        .map((item) => item.parentId)
        .whereType<String>()
        .toSet();
    final leafItems = budgetItems
        .where(
          (item) =>
              item.itemType == BudgetItemType.item &&
              !parentIds.contains(item.id),
        )
        .toList();

    final approvedPrice = leafItems.fold<double>(
      0,
      (sum, item) => sum + item.approvedPrice,
    );
    final projectedCost = leafItems.fold<double>(
      0,
      (sum, item) => sum + item.projectedCost,
    );
    final actualCost = leafItems.fold<double>(
      0,
      (sum, item) => sum + (actualCosts[item.id] ?? 0.0),
    );
    final projectedProfit = approvedPrice - projectedCost;
    final projectedMargin = approvedPrice == 0
        ? 0.0
        : (projectedProfit / approvedPrice) * 100;

    return (
      itemCount: leafItems.length,
      approvedPrice: approvedPrice,
      projectedCost: projectedCost,
      actualCost: actualCost,
      projectedProfit: projectedProfit,
      projectedMargin: projectedMargin,
    );
  }

  pw.Widget _pdfSummaryColumn(List<String> lines, {bool alignEnd = false}) {
    return pw.Column(
      crossAxisAlignment: alignEnd
          ? pw.CrossAxisAlignment.end
          : pw.CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          pw.Text(line, style: const pw.TextStyle(fontSize: 11)),
      ],
    );
  }

  pw.Widget _pdfCell(
    String text, {
    bool isHeader = false,
    bool isStrong = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 8 : 7,
          fontWeight: isHeader || isStrong
              ? pw.FontWeight.bold
              : pw.FontWeight.normal,
        ),
      ),
    );
  }

  /// Export budget to QuickBooks-compatible CSV format
  /// This creates two sheets:
  /// 1. Products/Services format for importing items into QBO
  /// 2. Estimate line items format for reference when creating estimates
  /// Returns the number of product names that were truncated to fit QBO's 100-char limit.
  Future<int> exportBudgetToQuickBooks({
    required String projectId,
    required String workspaceId,
    required Project project,
  }) async {
    try {
      // Get all budget items
      final budgetItems = await _budgetService
          .getBudgetItems(projectId, workspaceId: workspaceId)
          .first;

      if (budgetItems.isEmpty) {
        throw Exception('No budget items to export');
      }

      // Create Products/Services CSV (for importing items into QBO)
      final (productsCSV, productsTruncated) = _createQuickBooksProductsCSV(
        budgetItems,
        project,
      );

      // Create Estimate CSV (for reference when creating estimates)
      final (estimateCSV, estimateTruncated) =
          await _createQuickBooksEstimateCSV(budgetItems, project);
      final truncatedCount = productsTruncated + estimateTruncated;

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final projectName = _safeFileName(project.name);

      final productsFileName = 'qbo_products_${projectName}_$timestamp.csv';
      final estimateFileName = 'qbo_estimate_${projectName}_$timestamp.csv';

      // Use platform-specific export for multiple files
      await platform_export.exportMultipleCsv(
        [
          MapEntry(productsFileName, productsCSV),
          MapEntry(estimateFileName, estimateCSV),
        ],
        'QuickBooks Export - ${project.name}',
        'QuickBooks export files:\n'
            '• Products/Services - Import into QBO Products and Services\n'
            '• Estimate - Reference for creating estimates in QBO',
      );
      return truncatedCount;
    } catch (e) {
      throw Exception('Error exporting budget to QuickBooks format: $e');
    }
  }

  /// Create QuickBooks Products/Services import CSV.
  /// Returns (csv, truncatedCount) where truncatedCount is the number of
  /// product names that were cut to fit QBO's 100-character limit.
  (String, int) _createQuickBooksProductsCSV(
    List<BudgetItem> budgetItems,
    Project project,
  ) {
    final List<List<dynamic>> rows = [];

    // Header row - QBO Products/Services format
    rows.add([
      'Name',
      'Type',
      'SKU',
      'Price/Rate',
      'Sales Description',
      'Taxable',
      'Cost',
      'Purchase Description',
      'Income Account',
      'Expense Account',
    ]);

    // Only export leaf items (items with no children) as products/services
    // Use parent hierarchy for naming
    final leafItems = budgetItems
        .where((item) => !budgetItems.any((other) => other.parentId == item.id))
        .toList();

    int truncatedCount = 0;
    for (final item in leafItems) {
      // Build hierarchical name (Package > Section > Item)
      final parentNames = _getParentNames(item, budgetItems);
      final fullName = [...parentNames, item.name].join(':');

      // Truncate to 100 chars (QBO limit)
      final wasTruncated = fullName.length > 100;
      if (wasTruncated) truncatedCount++;
      final name = wasTruncated ? fullName.substring(0, 100) : fullName;

      rows.add([
        name,
        'Service', // Most construction items are services
        '', // SKU - empty
        item.approvedPrice.toStringAsFixed(2),
        item.description ?? item.name,
        'Y', // Taxable
        item.projectedCost.toStringAsFixed(2),
        item.description ?? item.name,
        'Construction Income', // Default income account
        'Cost of Goods Sold', // Default expense account
      ]);
    }

    return (const ListToCsvConverter().convert(rows), truncatedCount);
  }

  /// Create QuickBooks Estimate reference CSV.
  /// Returns (csv, truncatedCount) where truncatedCount is the number of
  /// product names that were cut to fit QBO's 100-character limit.
  Future<(String, int)> _createQuickBooksEstimateCSV(
    List<BudgetItem> budgetItems,
    Project project,
  ) async {
    final List<List<dynamic>> rows = [];
    final dateFormat = DateFormat('MM/dd/yyyy');

    // Header row - Estimate format
    rows.add([
      'Customer',
      'Estimate Date',
      'Expiration Date',
      'Product/Service',
      'Description',
      'Quantity',
      'Rate',
      'Amount',
      'Tax',
      'Category',
    ]);

    // Get customer name from project (use primary contact or project name)
    final customerName = project.primaryContactName ?? project.name;
    final estimateDate = dateFormat.format(DateTime.now());
    final expirationDate = dateFormat.format(
      DateTime.now().add(const Duration(days: 30)),
    );

    // Export all items with hierarchy context
    final topLevelItems = budgetItems
        .where((item) => item.parentId == null)
        .toList();

    int truncatedCount = 0;
    for (final topItem in topLevelItems) {
      truncatedCount += await _addEstimateRows(
        rows,
        topItem,
        budgetItems,
        customerName,
        estimateDate,
        expirationDate,
      );
    }

    // Add totals row - sum leaf items (items with no children)
    final totalApproved = budgetItems
        .where((i) => !budgetItems.any((other) => other.parentId == i.id))
        .fold(0.0, (sum, item) => sum + item.approvedPrice);

    rows.add([]);
    rows.add([
      '',
      '',
      '',
      'TOTAL',
      '',
      '',
      '',
      totalApproved.toStringAsFixed(2),
      '',
      '',
    ]);

    return (const ListToCsvConverter().convert(rows), truncatedCount);
  }

  /// Add estimate rows recursively. Returns the number of truncated product names.
  Future<int> _addEstimateRows(
    List<List<dynamic>> rows,
    BudgetItem item,
    List<BudgetItem> allItems,
    String customerName,
    String estimateDate,
    String expirationDate,
  ) async {
    final children = allItems.where((i) => i.parentId == item.id).toList();
    final hasChildren = children.isNotEmpty;

    if (hasChildren) {
      // Add section header for packages/sections
      rows.add([
        customerName,
        estimateDate,
        expirationDate,
        '--- ${item.name} ---',
        item.description ?? '',
        '',
        '',
        '',
        '',
        item.hierarchyLevelName,
      ]);

      // Add children
      int truncated = 0;
      for (final child in children) {
        truncated += await _addEstimateRows(
          rows,
          child,
          allItems,
          customerName,
          estimateDate,
          expirationDate,
        );
      }
      return truncated;
    } else {
      // Leaf item - add as line item
      final parentNames = _getParentNames(item, allItems);
      final productName = [...parentNames, item.name].join(':');
      final wasTruncated = productName.length > 100;

      rows.add([
        customerName,
        estimateDate,
        expirationDate,
        wasTruncated ? productName.substring(0, 100) : productName,
        item.description ?? '',
        '1', // Quantity
        item.approvedPrice.toStringAsFixed(2),
        item.approvedPrice.toStringAsFixed(2),
        'Y',
        parentNames.isNotEmpty ? parentNames.first : '',
      ]);
      return wasTruncated ? 1 : 0;
    }
  }

  /// Get parent names for an item (for building hierarchical product names)
  List<String> _getParentNames(BudgetItem item, List<BudgetItem> allItems) {
    final names = <String>[];
    String? parentId = item.parentId;

    while (parentId != null) {
      final parent = allItems.firstWhere(
        (i) => i.id == parentId,
        orElse: () => item,
      );
      if (parent.id != item.id) {
        names.insert(0, parent.name);
        parentId = parent.parentId;
      } else {
        break;
      }
    }

    return names;
  }

  String _safeFileName(String value) {
    final normalized = value.trim().replaceAll(' ', '_');
    final safe = normalized.replaceAll(RegExp(r'[^\w]'), '');
    return safe.isEmpty ? 'budget' : safe;
  }

  String _formatMoney(double amount, String currencyCode) {
    return CurrencyUtils.formatCurrency(amount, currencyCode);
  }
}
